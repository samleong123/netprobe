package dev.sam.speedtest

import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.io.ByteArrayOutputStream
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.min

/** A shared reservation prevents up to 64 workers from overrunning a payload cap. */
class TransferBudget(val limit: Long?) {
    private val reservedAndCommitted = AtomicLong(0)
    val transferred = AtomicLong(0)

    fun reserve(requested: Int): Int {
        require(requested > 0)
        while (true) {
            val current = reservedAndCommitted.get()
            val available = limit?.let { (it - current).coerceAtLeast(0) } ?: requested.toLong()
            val count = min(requested.toLong(), available).toInt()
            if (count == 0) return 0
            if (reservedAndCommitted.compareAndSet(current, current + count)) return count
        }
    }

    fun commit(reserved: Int, actual: Int) {
        require(actual in 0..reserved)
        transferred.addAndGet(actual.toLong())
        reservedAndCommitted.addAndGet(-(reserved - actual).toLong())
    }

    fun exhausted(): Boolean = limit?.let { transferred.get() >= it } ?: false
}

data class TransferConfig(
    val id: String,
    val mode: String,
    val threads: Int,
    val serverName: String,
    val downloadUrl: String?,
    val uploadUrl: String?,
    val latencyUrl: String?,
    val durationSeconds: Long?,
    val maxBytes: Long?,
    val unit: String,
    val customServer: Boolean = false,
) {
    init {
        require(mode in listOf("normal", "download", "upload")) { "Choose a transfer mode." }
        require(threads in 1..64) { "Threads must be between 1 and 64." }
        require(durationSeconds == null || durationSeconds in 1..86400) { "Duration must be 1–86400 seconds." }
        require(maxBytes == null || maxBytes in 1..9_000_000_000_000_000L) { "Enter a positive data limit." }
        require(mode == "upload" || validUrl(downloadUrl)) { "This mode needs a download URL." }
        require(mode == "download" || validUrl(uploadUrl)) { "This mode needs an upload URL." }
        require(latencyUrl == null || validUrl(latencyUrl)) { "Invalid latency URL." }
    }

    companion object {
        fun validUrl(value: String?): Boolean = try {
            val uri = URI(value ?: "")
            uri.scheme in listOf("http", "https") && !uri.host.isNullOrBlank() && uri.userInfo == null && uri.fragment == null
        } catch (_: Exception) { false }
    }
}

/** No Flutter isolate or Activity owns the workers. The foreground service owns this engine. */
class TransferEngine(
    val config: TransferConfig,
    private val open: (URL) -> HttpURLConnection = { it.openConnection() as HttpURLConnection },
) {
    companion object {
        private const val MAX_UPLOAD_BYTES = 4 * 1024 * 1024
        private const val UPLOAD_DRAIN_NANOS = 5_000_000_000L
        private const val MAX_REDIRECTS = 5
    }

    private val budget = TransferBudget(config.maxBytes)
    private val stopped = AtomicBoolean(false)
    private val stopReason = AtomicReference<String?>(null)
    private val connections = ConcurrentHashMap.newKeySet<HttpURLConnection>()
    private val phaseOpen = AtomicBoolean(false)
    private val phaseBytes = AtomicLong(0)
    private val wireBytes = AtomicLong(0)
    private val workerError = AtomicReference<String?>(null)
    private val fatalError = AtomicReference<String?>(null)
    private val uploadEndpoint = AtomicReference(config.uploadUrl)
    private val workers = Executors.newFixedThreadPool(config.threads)
    @Volatile private var phase = "starting"
    @Volatile private var status = "running"
    @Volatile private var started = System.nanoTime()
    @Volatile private var phaseStarted = started
    @Volatile private var phaseDeadline = Long.MAX_VALUE
    @Volatile private var finished = 0L
    @Volatile private var downloadMbps: Double? = null
    @Volatile private var uploadMbps: Double? = null
    @Volatile private var latencyMs: Double? = null
    @Volatile private var message: String? = null
    private var sampleTime = started
    private var sampleBytes = 0L
    private var speedMbps = 0.0

    fun cancel(reason: String = "Stopped by you") {
        if (!stopped.compareAndSet(false, true)) return
        stopReason.compareAndSet(null, reason)
        phaseOpen.set(false)
        status = "stopped"
        message = stopReason.get()
        disconnectAll()
        workers.shutdownNow()
    }

    private fun disconnectAll() {
        connections.forEach { runCatching { it.disconnect() } }
    }

    fun run() {
        started = System.nanoTime()
        val watchdog = Executors.newSingleThreadScheduledExecutor()
        watchdog.scheduleAtFixedRate({
            // At an upload deadline, stop starting requests but let bounded
            // in-flight POSTs finish and report their received size.
            val deadline = if (phase == "upload") uploadDrainDeadline() else phaseDeadline
            if (phaseOpen.get() && (System.nanoTime() >= deadline || budget.exhausted() || stopped.get())) {
                phaseOpen.set(false)
                disconnectAll()
            }
        }, 50, 50, TimeUnit.MILLISECONDS)
        try {
            if (config.mode == "normal" && !stopped.get()) measureLatency()
            val phases = if (config.mode == "normal") listOf("download", "upload") else listOf(config.mode)
            for (next in phases) {
                if (stopped.get() || budget.exhausted()) break
                runPhase(next)
            }
            if (message == null) {
                message = when {
                    stopped.get() -> stopReason.get()
                    budget.exhausted() -> "Data limit reached"
                    else -> "Time limit reached"
                }
            }
            if (status == "running") {
                status = if (stopped.get()) "stopped" else "complete"
            }
        } catch (e: Exception) {
            message = if (stopped.get()) stopReason.get() else e.message ?: "Transfer failed"
            status = if (stopped.get()) "stopped" else "error"
        } finally {
            phaseOpen.set(false)
            disconnectAll()
            workers.shutdownNow()
            watchdog.shutdownNow()
            // No reservation or late worker write can survive the final snapshot.
            workers.awaitTermination(1, TimeUnit.SECONDS)
            finished = System.nanoTime()
            phase = "finished"
        }
    }

    private fun connection(url: String): HttpURLConnection {
        if (stopped.get()) throw java.io.IOException("Transfer stopped")
        val c = open(URI(url).toURL())
        c.connectTimeout = 5000
        c.readTimeout = 5000
        c.useCaches = false
        c.instanceFollowRedirects = false
        c.setRequestProperty("Cache-Control", "no-cache, no-store")
        c.setRequestProperty("Accept-Encoding", "identity")
        c.setRequestProperty("User-Agent", "NetProbe-Android/1.0")
        connections.add(c)
        if (stopped.get()) {
            connections.remove(c)
            runCatching { c.disconnect() }
            throw java.io.IOException("Transfer stopped")
        }
        return c
    }

    private fun measureLatency() {
        val url = config.latencyUrl ?: return
        phase = "latency"
        val samples = mutableListOf<Double>()
        repeat(3) {
            if (stopped.get()) return
            val c = connection(url)
            try {
                val start = System.nanoTime()
                if (c.responseCode in 200..299) {
                    c.inputStream.use { it.read(ByteArray(64)) }
                    samples.add((System.nanoTime() - start) / 1_000_000.0)
                }
            } catch (_: Exception) {
                // Optional HTTP latency must not make an otherwise usable server fail.
            } finally { connections.remove(c); c.disconnect() }
        }
        latencyMs = samples.sorted().let { if (it.isEmpty()) null else it[it.size / 2] }
    }

    private fun runPhase(direction: String) {
        phaseBytes.set(0)
        workerError.set(null)
        if (direction == "upload") {
            phase = "upload"
            uploadEndpoint.set(resolveUploadEndpoint(uploadEndpoint.get()!!))
            if (stopped.get()) return
        }
        phaseStarted = System.nanoTime()
        sampleTime = phaseStarted
        sampleBytes = if (direction == "upload") wireBytes.get() else budget.transferred.get()
        speedMbps = 0.0
        val seconds = config.durationSeconds ?: if (config.mode == "normal") 15L else null
        phaseDeadline = seconds?.let { phaseStarted + it * 1_000_000_000L } ?: Long.MAX_VALUE
        phase = direction
        phaseOpen.set(true)
        val futures = (1..config.threads).map {
            workers.submit { transferWorker(direction) }
        }
        for (f in futures) {
            try {
                f.get()
            } catch (_: Exception) {
                if (stopped.get()) break
            }
        }
        phaseOpen.set(false)
        fatalError.get()?.let { throw IllegalStateException(it) }
        val elapsed = (System.nanoTime() - phaseStarted) / 1_000_000_000.0
        val bytes = phaseBytes.get()
        if (bytes == 0L && !stopped.get()) {
            throw IllegalStateException(workerError.get() ?: "The server transferred no data. Choose another server.")
        }
        // If all workers fail before the timer/cap, don't label a partial transfer as complete.
        if (!stopped.get() && !budget.exhausted() && System.nanoTime() < phaseDeadline && workerError.get() != null) {
            throw IllegalStateException(workerError.get())
        }
        val rate = bytes * 8.0 / elapsed.coerceAtLeast(0.001) / 1_000_000.0
        if (direction == "download") downloadMbps = rate else uploadMbps = rate
    }

    private fun active() = phaseOpen.get() && !stopped.get() && !budget.exhausted() && System.nanoTime() < phaseDeadline

    private fun uploadDrainDeadline() = if (phaseDeadline == Long.MAX_VALUE) Long.MAX_VALUE else phaseDeadline + UPLOAD_DRAIN_NANOS

    private fun finishingUpload() = phaseOpen.get() && !stopped.get() && System.nanoTime() < uploadDrainDeadline()

    private fun transferWorker(direction: String) {
        val buffer = ByteArray(64 * 1024)
        if (direction == "upload") SecureRandom().nextBytes(buffer)
        var failures = 0
        var uploadBytes = 256 * 1024
        while (active()) {
            val url = if (direction == "download") config.downloadUrl!! else config.uploadUrl!!
            var c: HttpURLConnection? = null
            val before = phaseBytes.get()
            try {
                if (direction == "download") {
                    c = connection(url)
                    if (!active()) return
                    download(c, buffer)
                } else {
                    val start = System.nanoTime()
                    val acknowledged = upload(buffer, uploadBytes)
                    // Keep requests near 250 ms so live acknowledged speed is
                    // useful on both slow links and fast single-thread tests.
                    val elapsed = (System.nanoTime() - start) / 1e9
                    if (acknowledged > 0) {
                        uploadBytes = (acknowledged * 0.25 / elapsed.coerceAtLeast(0.001))
                            .toInt().coerceIn(buffer.size, MAX_UPLOAD_BYTES)
                    }
                }
                failures = 0
                // A tiny/empty custom endpoint should not become an unbounded request loop.
                if (phaseBytes.get() == before && active()) throw IllegalStateException("The endpoint returned no transfer data.")
            } catch (e: Exception) {
                if (stopped.get()) return
                if (e is ServerRejectedException) {
                    fatalError.compareAndSet(null, e.message)
                    phaseOpen.set(false)
                    disconnectAll()
                    return
                }
                if (!active()) return
                failures++
                if (failures >= 3) {
                    workerError.set("Server transfer failed: ${e.message ?: "connection closed"}. Try another server.")
                    return
                }
                Thread.sleep(100L * failures)
            } finally {
                if (c != null) { connections.remove(c); runCatching { c.disconnect() } }
            }
        }
    }

    private fun nextReservation(buffer: ByteArray): Int {
        while (active()) {
            val count = budget.reserve(buffer.size)
            if (count > 0) return count
            // Other workers may refund an unused reservation after an EOF or failed request.
            Thread.sleep(5)
        }
        return 0
    }

    private fun download(c: HttpURLConnection, buffer: ByteArray) {
        checkResponse(c)
        val type = c.contentType.orEmpty().lowercase()
        require(!type.contains("text/html") && !type.contains("application/json")) { "Endpoint returned a page instead of download data" }
        c.inputStream.use { input ->
            while (active()) {
                val reserved = nextReservation(buffer)
                if (reserved == 0) break
                var actual = 0
                val count: Int
                try {
                    count = input.read(buffer, 0, reserved)
                    actual = count.coerceAtLeast(0)
                } finally {
                    budget.commit(reserved, actual)
                    phaseBytes.addAndGet(actual.toLong())
                    wireBytes.addAndGet(actual.toLong())
                }
                if (count < 0) break
            }
        }
    }

    private fun preparePost(c: HttpURLConnection, size: Int) {
        c.requestMethod = "POST"
        c.doOutput = true
        c.setRequestProperty("Content-Type", "application/octet-stream")
        c.setFixedLengthStreamingMode(size)
    }

    private fun redirect(c: HttpURLConnection, visited: MutableSet<String>): String {
        val location = c.getHeaderField("Location")
            ?: throw ServerRejectedException("The upload redirect has no Location header.")
        val next = try { c.url.toURI().resolve(location).toString() } catch (_: Exception) {
            throw ServerRejectedException("The server returned an invalid upload redirect.")
        }
        if (!TransferConfig.validUrl(next) || (c.url.protocol == "https" && URI(next).scheme != "https")) {
            throw ServerRejectedException("The server returned an invalid upload redirect.")
        }
        if (!visited.add(next) || visited.size > MAX_REDIRECTS + 1) {
            throw ServerRejectedException("The upload server redirected too many times.")
        }
        return next
    }

    private fun release(c: HttpURLConnection) {
        connections.remove(c)
        runCatching { c.disconnect() }
    }

    private fun resolveUploadEndpoint(initial: String): String {
        var url = initial
        val visited = mutableSetOf(url)
        // Resolve the HTTP-to-HTTPS redirect before spending any payload.
        // An empty POST also preserves POST semantics at every redirect hop.
        while (!stopped.get()) {
            val c = try { connection(url) } catch (_: Exception) { return url }
            try {
                if (stopped.get()) return url
                preparePost(c, 0)
                c.outputStream.use { }
                if (stopped.get()) return url
                val code = c.responseCode
                if (stopped.get()) return url
                if (code == 307 || code == 308) {
                    url = redirect(c, visited)
                } else {
                    // Some custom servers reject empty POSTs. Validate the
                    // response to the actual payload rather than this probe.
                    if (code in 300..399) checkResponse(c, code)
                    return url
                }
            } finally { release(c) }
        }
        return url
    }

    private fun upload(buffer: ByteArray, requested: Int): Int {
        var reserved = 0
        while (active() && reserved == 0) {
            reserved = budget.reserve(requested)
            if (reserved == 0) Thread.sleep(5)
        }
        if (reserved == 0) return 0
        var acknowledged = 0
        try {
            if (!active()) return 0
            var url = uploadEndpoint.get()!!
            val visited = mutableSetOf(url)
            while (finishingUpload()) {
                val c = try { connection(url) } catch (_: Exception) { return 0 }
                try {
                    if (!finishingUpload()) return 0
                    preparePost(c, reserved)
                    c.outputStream.use { output ->
                        var remaining = reserved
                        while (remaining > 0) {
                            if (stopped.get() || !finishingUpload()) throw java.io.IOException("Transfer stopped")
                            val count = min(buffer.size, remaining)
                            output.write(buffer, 0, count)
                            remaining -= count
                            wireBytes.addAndGet(count.toLong())
                        }
                        output.flush()
                    }
                    if (stopped.get()) throw java.io.IOException("Transfer stopped")
                    val code = c.responseCode
                    if (stopped.get()) throw java.io.IOException("Transfer stopped")
                    if (code == 307 || code == 308) {
                        // Handle redirects that occur only on a non-empty
                        // body too, replaying the exact POST payload once per hop.
                        url = redirect(c, visited)
                        uploadEndpoint.set(url)
                        continue
                    }
                    checkResponse(c, code)
                    // Custom endpoints confirm the POST through HTTP success;
                    // only Speedtest servers provide a received-size contract.
                    val size = if (config.customServer) reserved else readUploadSize(c, reserved)
                    if (finishingUpload()) acknowledged = size
                    return acknowledged
                } finally { release(c) }
            }
            return 0
        } finally {
            // Reserve the whole request until its acknowledgement arrives;
            // 64 workers cannot start more payload than the shared cap allows.
            budget.commit(reserved, acknowledged)
            phaseBytes.addAndGet(acknowledged.toLong())
        }
    }

    private fun readUploadSize(c: HttpURLConnection, sent: Int): Int {
        val reply = ByteArrayOutputStream()
        c.inputStream.use { input ->
            val bytes = ByteArray(256)
            while (true) {
                val count = input.read(bytes)
                if (count < 0) break
                if (reply.size() + count > 4096) {
                    throw ServerRejectedException("The upload server returned an invalid size acknowledgement.")
                }
                reply.write(bytes, 0, count)
            }
        }
        val match = Regex("size=([0-9]+)").matchEntire(reply.toString("UTF-8").trim())
        val size = match?.groupValues?.get(1)?.toLongOrNull()
        if (size == null || size <= 0 || size > sent) {
            throw ServerRejectedException("The upload server did not acknowledge a valid received size.")
        }
        return size.toInt()
    }

    private class ServerRejectedException(message: String) : IllegalStateException(message)

    private fun checkResponse(connection: HttpURLConnection, code: Int = connection.responseCode) {
        if (code !in 200..299) throw ServerRejectedException("The server rejected the transfer (HTTP $code). Choose another server.")
    }

    @Synchronized fun snapshot(): Map<String, Any?> {
        val now = if (finished != 0L) finished else System.nanoTime()
        val bytes = budget.transferred.get()
        val wire = wireBytes.get()
        val delta = (now - sampleTime) / 1_000_000_000.0
        if (delta >= 0.2) {
            val sampleCount = if (phase == "upload") wire else bytes
            speedMbps = (sampleCount - sampleBytes).coerceAtLeast(0) * 8.0 / delta / 1_000_000.0
            sampleTime = now
            sampleBytes = sampleCount
        }
        val elapsed = (now - started) / 1_000_000_000.0
        val phaseElapsed = (now - phaseStarted).coerceAtLeast(0) / 1_000_000_000.0
        return mapOf(
            "id" to config.id, "status" to status, "phase" to phase, "mode" to config.mode,
            "serverName" to config.serverName, "threads" to config.threads,
            "totalBytes" to bytes, "speedMbps" to if (status == "running") speedMbps else 0.0,
            "downloadMbps" to downloadMbps, "uploadMbps" to uploadMbps, "latencyMs" to latencyMs,
            "elapsedSeconds" to elapsed, "phaseSeconds" to phaseElapsed,
            "durationSeconds" to config.durationSeconds, "maxBytes" to config.maxBytes,
            "message" to message,
        )
    }
}
