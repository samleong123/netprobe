package dev.sam.speedtest

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

private class FakeConnection(url: URL, private val outgoing: AtomicLong, private val rejected: Boolean = false) : HttpURLConnection(url) {
    @Volatile private var closed = false
    private val received = AtomicLong()
    override fun connect() {}
    override fun disconnect() { closed = true }
    override fun usingProxy() = false
    override fun getResponseCode() = if (rejected) 403 else 200
    override fun getContentType() = "application/octet-stream"
    override fun getInputStream(): InputStream = if (requestMethod == "POST") ByteArrayInputStream("size=${received.get()}".toByteArray()) else object : InputStream() {
        override fun read(): Int = 42
        override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
            if (closed) throw java.io.IOException("closed")
            Thread.sleep(2)
            return minOf(length, 1024)
        }
    }
    override fun getOutputStream(): OutputStream = object : OutputStream() {
        override fun write(b: Int) { outgoing.incrementAndGet(); received.incrementAndGet() }
        override fun write(b: ByteArray, off: Int, len: Int) {
            if (closed) throw java.io.IOException("closed")
            Thread.sleep(2)
            outgoing.addAndGet(len.toLong())
            received.addAndGet(len.toLong())
        }
    }
}

private class UploadReplyConnection(
    url: URL,
    private val code: (Int) -> Int = { 200 },
    private val location: String? = null,
    private val reply: (Int) -> InputStream = { ByteArrayInputStream("size=$it".toByteArray()) },
    private val finished: (ByteArray) -> Unit = {},
) : HttpURLConnection(url) {
    private val body = ByteArrayOutputStream()
    override fun connect() {}
    override fun disconnect() {}
    override fun usingProxy() = false
    override fun getResponseCode(): Int {
        finished(body.toByteArray())
        return code(body.size())
    }
    override fun getHeaderField(name: String): String? = if (name == "Location") location else null
    override fun getInputStream() = reply(body.size())
    override fun getOutputStream(): OutputStream {
        check(requestMethod == "POST" && doOutput)
        check(getRequestProperty("Content-Type") == "application/octet-stream")
        return body
    }
}

fun main(args: Array<String>) {
    var passed = 0
    fun test(name: String, run: () -> Unit) { run(); passed++; println("PASS $name") }
    fun config(mode: String, threads: Int = 8, seconds: Long? = 1, cap: Long? = null) = TransferConfig(
        "test", mode, threads, "Local test", "http://example.test/download", "http://example.test/upload", null, seconds, cap, "Mbps")

    test("64 concurrent workers cannot exceed the shared budget") {
        val budget = TransferBudget(1_234_567)
        val pool = Executors.newFixedThreadPool(64)
        val start = CountDownLatch(1)
        val futures = (1..64).map { pool.submit {
            start.await()
            while (!budget.exhausted()) {
                val count = budget.reserve(65536)
                if (count > 0) budget.commit(count, count) else Thread.yield()
            }
        } }
        start.countDown(); futures.forEach { it.get(5, TimeUnit.SECONDS) }; pool.shutdownNow()
        check(budget.transferred.get() == 1_234_567L)
    }
    test("EOF and failed I/O refund unused reservations") {
        val budget = TransferBudget(100)
        val first = budget.reserve(80)
        budget.commit(first, 10)
        check(budget.reserve(100) == 90)
        check(budget.transferred.get() == 10L)
    }
    test("download stops at an exact non-aligned cap with 64 workers") {
        val engine = TransferEngine(config("download", 64, null, 1_234_567)) { FakeConnection(it, AtomicLong()) }
        engine.run()
        val result = engine.snapshot()
        check(result["status"] == "complete") { result }
        check(result["totalBytes"] == 1_234_567L) { result }
        check(result["message"] == "Data limit reached")
    }
    test("upload payload and engine accounting agree at the cap") {
        val sent = AtomicLong()
        val engine = TransferEngine(config("upload", 64, null, 1_234_567)) { FakeConnection(it, sent) }
        engine.run()
        val result = engine.snapshot()
        check(result["status"] == "complete") { result }
        check(result["totalBytes"] == 1_234_567L) { result }
        check(sent.get() == 1_234_567L)
    }
    test("upload posts to the configured PHP URL without substituting the download host") {
        val uploadUrl = "http://upload.example.test:8080/speedtest/upload.php?region=MY&nonce=one%2Ftwo"
        val sent = AtomicLong()
        val engine = TransferEngine(config("upload", 4, null, 123456).copy(uploadUrl = uploadUrl)) {
            check(it.toString() == uploadUrl) { "Upload went to $it" }
            object : HttpURLConnection(it) {
                private var received = 0
                override fun connect() {}
                override fun disconnect() {}
                override fun usingProxy() = false
                override fun getResponseCode() = 200
                override fun getInputStream() = ByteArrayInputStream("size=$received".toByteArray())
                override fun getOutputStream(): OutputStream {
                    check(requestMethod == "POST")
                    return object : OutputStream() {
                        override fun write(b: Int) { sent.incrementAndGet(); received++ }
                        override fun write(b: ByteArray, offset: Int, length: Int) { sent.addAndGet(length.toLong()); received += length }
                    }
                }
            }
        }
        engine.run()
        check(engine.snapshot()["status"] == "complete") { engine.snapshot() }
        check(sent.get() == 123456L)
    }
    test("307 upgrades to HTTPS before any payload and 64 workers count acknowledged sizes") {
        val initial = "http://upload.example.test:8080/speedtest/upload.php?region=MY"
        val target = "https://upload.example.test:8443/speedtest/upload.php?nonce=one%2Ftwo"
        val probes = AtomicLong()
        val sent = AtomicLong()
        val engine = TransferEngine(config("upload", 64, null, 1_234_567).copy(uploadUrl = initial)) { url ->
            if (url.toString() == initial) {
                UploadReplyConnection(url, code = { 307 }, location = target, finished = {
                    check(it.isEmpty()) { "Payload was sent before resolving the HTTPS redirect" }
                    probes.incrementAndGet()
                })
            } else {
                check(url.toString() == target) { url }
                UploadReplyConnection(url, finished = { sent.addAndGet(it.size.toLong()) })
            }
        }
        engine.run()
        val result = engine.snapshot()
        check(result["status"] == "complete") { result }
        check(result["totalBytes"] == 1_234_567L) { result }
        check(sent.get() == 1_234_567L)
        check(probes.get() == 1L)
    }
    test("relative 308 preserves POST and the redirected path and encoded query") {
        val target = "http://example.test/tls/upload.php?nonce=one%2Ftwo"
        val engine = TransferEngine(config("upload", 1, null, 1001)) { url ->
            if (url.path == "/upload") UploadReplyConnection(url, code = { 308 }, location = "/tls/upload.php?nonce=one%2Ftwo")
            else {
                check(url.toString() == target) { url }
                UploadReplyConnection(url)
            }
        }
        engine.run()
        check(engine.snapshot()["totalBytes"] == 1001L) { engine.snapshot() }
        check(engine.snapshot()["status"] == "complete") { engine.snapshot() }
    }
    test("a body-only 307 replays identical binary payload without counting it twice") {
        var original: ByteArray? = null
        var replay: ByteArray? = null
        val engine = TransferEngine(config("upload", 1, null, 100001)) { url ->
            if (url.protocol == "http") UploadReplyConnection(url,
                code = { if (it == 0) 200 else 307 }, location = "https://example.test/upload",
                finished = { if (it.isNotEmpty()) original = it })
            else UploadReplyConnection(url, finished = { if (it.isNotEmpty()) replay = it })
        }
        engine.run()
        val result = engine.snapshot()
        check(result["status"] == "complete" && result["totalBytes"] == 100001L) { result }
        val offered = checkNotNull(original)
        check(offered.contentEquals(replay))
        check(offered.any { it.toInt() != 0 })
    }
    test("upload totals and rate use received size rather than bytes offered") {
        val confirmed = AtomicLong()
        val sent = AtomicLong()
        val engine = TransferEngine(config("upload", 1, 1)) { url ->
            UploadReplyConnection(url, reply = { size ->
                Thread.sleep(20)
                val accepted = size / 2
                confirmed.addAndGet(accepted.toLong())
                sent.addAndGet(size.toLong())
                ByteArrayInputStream("size=$accepted\r\n".toByteArray())
            })
        }
        engine.run()
        val result = engine.snapshot()
        check(result["status"] == "complete") { result }
        check(result["totalBytes"] == confirmed.get()) { result }
        check(confirmed.get().toDouble() / sent.get() in 0.49..0.5)
        val expected = confirmed.get() * 8.0 / (result["phaseSeconds"] as Double) / 1e6
        check(kotlin.math.abs((result["uploadMbps"] as Double) - expected) < expected * 0.01) { result }
    }
    test("reaching an in-flight upload reservation does not stop its acknowledgement") {
        val waiting = CountDownLatch(1)
        val acknowledge = CountDownLatch(1)
        val engine = TransferEngine(config("upload", 1, null, 100001)) { url ->
            UploadReplyConnection(url, reply = { size ->
                waiting.countDown()
                check(acknowledge.await(3, TimeUnit.SECONDS))
                ByteArrayInputStream("size=$size".toByteArray())
            })
        }
        val thread = Thread { engine.run() }.apply { start() }
        try {
            check(waiting.await(3, TimeUnit.SECONDS))
            check(engine.snapshot()["totalBytes"] == 0L) { engine.snapshot() }
            check(engine.snapshot()["status"] == "running")
            acknowledge.countDown()
            thread.join(5000)
            check(!thread.isAlive)
            check(engine.snapshot()["totalBytes"] == 100001L) { engine.snapshot() }
            check(engine.snapshot()["message"] == "Data limit reached") { engine.snapshot() }
        } finally { acknowledge.countDown(); engine.cancel(); thread.join(5000) }
    }
    test("the final timed POST gets a bounded chance to return its received size") {
        val engine = TransferEngine(config("upload", 1, 1)) { url ->
            UploadReplyConnection(url, reply = { size ->
                Thread.sleep(1200)
                ByteArrayInputStream("size=$size".toByteArray())
            })
        }
        engine.run()
        val result = engine.snapshot()
        check(result["status"] == "complete") { result }
        check(result["totalBytes"] == 256L * 1024) { result }
        check(result["message"] == "Time limit reached")
    }
    test("Stop cancels a pending acknowledgement without counting unconfirmed payload") {
        val waiting = CountDownLatch(1)
        val acknowledge = CountDownLatch(1)
        val engine = TransferEngine(config("upload", 1, null, 100001)) { url ->
            UploadReplyConnection(url, reply = { size ->
                waiting.countDown()
                check(acknowledge.await(3, TimeUnit.SECONDS))
                ByteArrayInputStream("size=$size".toByteArray())
            })
        }
        val thread = Thread { engine.run() }.apply { start() }
        try {
            check(waiting.await(3, TimeUnit.SECONDS))
            engine.cancel()
            acknowledge.countDown()
            thread.join(5000)
            check(!thread.isAlive)
            check(engine.snapshot()["status"] == "stopped") { engine.snapshot() }
            check(engine.snapshot()["totalBytes"] == 0L) { engine.snapshot() }
        } finally { acknowledge.countDown(); engine.cancel(); thread.join(5000) }
    }
    test("fragmented acknowledgements are read completely") {
        val engine = TransferEngine(config("upload", 1, null, 98765)) { url ->
            UploadReplyConnection(url, reply = { size ->
                object : ByteArrayInputStream("size=$size\n".toByteArray()) {
                    override fun read(bytes: ByteArray, offset: Int, length: Int) = super.read(bytes, offset, minOf(length, 1))
                }
            })
        }
        engine.run()
        check(engine.snapshot()["totalBytes"] == 98765L) { engine.snapshot() }
    }
    test("invalid or missing size acknowledgement cannot fabricate upload results") {
        for (reply in listOf("", "ok", "size=0", "size=-1", "size=999999", "size=999999999999999999999999999", "size=10&size=20", "x".repeat(4097))) {
            val engine = TransferEngine(config("upload", 1, null, 1234)) { url ->
                UploadReplyConnection(url, reply = { ByteArrayInputStream(reply.toByteArray()) })
            }
            engine.run()
            check(engine.snapshot()["status"] == "error") { engine.snapshot() }
            check(engine.snapshot()["totalBytes"] == 0L) { engine.snapshot() }
        }
    }
    test("custom HTTP 200 uploads count the full payload without reading any response body") {
        val sent = AtomicLong()
        val engine = TransferEngine(config("upload", 64, null, 1_234_567).copy(customServer = true)) { url ->
            UploadReplyConnection(url,
                reply = { error("Custom upload success must not depend on its response body") },
                finished = { sent.addAndGet(it.size.toLong()) })
        }
        engine.run()
        val result = engine.snapshot()
        check(result["status"] == "complete") { result }
        check(result["totalBytes"] == 1_234_567L && sent.get() == 1_234_567L) { result }
        check(result["message"] == "Data limit reached") { result }
        check((result["uploadMbps"] as Double) > 0) { result }
    }
    test("custom upload rejection cannot count the sent payload as successful") {
        val engine = TransferEngine(config("upload", 1, null, 1234).copy(customServer = true)) { url ->
            UploadReplyConnection(url, code = { 403 })
        }
        engine.run()
        val result = engine.snapshot()
        check(result["status"] == "error" && result["totalBytes"] == 0L) { result }
        check((result["message"] as String).contains("HTTP 403")) { result }
    }
    test("redirect loops and missing or invalid Locations fail before sending payload") {
        for (location in listOf(null, "/upload", "file:///tmp/upload", "https://user:pass@example.test/upload")) {
            val engine = TransferEngine(config("upload", 1, 1)) { url ->
                UploadReplyConnection(url, code = { 307 }, location = location, finished = { check(it.isEmpty()) })
            }
            engine.run()
            check(engine.snapshot()["status"] == "error") { engine.snapshot() }
            check(engine.snapshot()["totalBytes"] == 0L)
        }
    }
    test("normal test runs both phases for their own duration") {
        val engine = TransferEngine(config("normal")) { FakeConnection(it, AtomicLong()) }
        val start = System.nanoTime()
        engine.run()
        val seconds = (System.nanoTime() - start) / 1e9
        val result = engine.snapshot()
        check(result["downloadMbps"] is Double && result["uploadMbps"] is Double) { result }
        check(seconds in 1.9..4.0) { seconds }
    }
    test("earlier time limit wins over a large budget") {
        val engine = TransferEngine(config("download", 1, 1, 1_000_000_000)) { FakeConnection(it, AtomicLong()) }
        engine.run()
        val result = engine.snapshot()
        check(result["message"] == "Time limit reached") { result }
        check((result["totalBytes"] as Long) < 1_000_000_000)
    }
    test("manual cancellation stops all workers and freezes totals") {
        val engine = TransferEngine(config("download", 64, 60)) { FakeConnection(it, AtomicLong()) }
        val thread = Thread { engine.run() }.apply { start() }
        Thread.sleep(100)
        engine.cancel("Network disconnected")
        thread.join(5000)
        check(!thread.isAlive)
        val result = engine.snapshot()
        check(result["status"] == "stopped") { result }
        check(result["message"] == "Network disconnected")
        Thread.sleep(100)
        check(engine.snapshot()["totalBytes"] == result["totalBytes"])
    }
    test("rejected download returns an error rather than fabricated speed") {
        val engine = TransferEngine(config("download")) { FakeConnection(it, AtomicLong(), true) }
        engine.run()
        check(engine.snapshot()["status"] == "error") { engine.snapshot() }
    }
    test("upload rejected after writing a body is still reported as an error") {
        val engine = TransferEngine(config("upload", 1, 10)) { FakeConnection(it, AtomicLong(), true) }
        engine.run()
        check(engine.snapshot()["status"] == "error") { engine.snapshot() }
        check((engine.snapshot()["message"] as String).contains("403"))
    }
    test("empty limits keep download and upload running until explicit stop") {
        for (mode in listOf("download", "upload")) {
            val engine = TransferEngine(config(mode, 2, null, null)) { FakeConnection(it, AtomicLong()) }
            val thread = Thread { engine.run() }.apply { start() }
            try {
                Thread.sleep(1200)
                check(thread.isAlive) { "$mode ended without a limit or stop" }
                check(engine.snapshot()["status"] == "running")
                check((engine.snapshot()["totalBytes"] as Long) > 0)
            } finally {
                engine.cancel()
                thread.join(5000)
            }
            check(!thread.isAlive)
            check(engine.snapshot()["status"] == "stopped") { engine.snapshot() }
        }
    }
    test("upload displays live non-zero speed while chunks are actively written before acknowledgement arrives") {
        val waiting = CountDownLatch(1)
        val release = CountDownLatch(1)
        val engine = TransferEngine(config("upload", 1, null, null)) { url ->
            UploadReplyConnection(url, reply = { size ->
                waiting.countDown()
                release.await(3, TimeUnit.SECONDS)
                ByteArrayInputStream("size=$size".toByteArray())
            })
        }
        val thread = Thread { engine.run() }.apply { start() }
        try {
            check(waiting.await(3, TimeUnit.SECONDS))
            Thread.sleep(250)
            val snapshot = engine.snapshot()
            check(snapshot["status"] == "running")
            check((snapshot["speedMbps"] as Double) > 0.0) { "Live upload speed should be > 0 while transmitting data: $snapshot" }
        } finally {
            release.countDown()
            engine.cancel()
            thread.join(5000)
        }
    }
    test("stop during continuous upload immediately halts socket writes and terminates without lingering") {
        val writesAfterStop = AtomicLong(0)
        val startedWriting = CountDownLatch(1)
        val engine = TransferEngine(config("upload", 2, null, null)) { url ->
            object : HttpURLConnection(url) {
                @Volatile private var disconnected = false
                override fun connect() {}
                override fun disconnect() { disconnected = true }
                override fun usingProxy() = false
                override fun getResponseCode() = 200
                override fun getInputStream() = ByteArrayInputStream("size=65536".toByteArray())
                override fun getOutputStream() = object : OutputStream() {
                    override fun write(b: Int) { write(byteArrayOf(b.toByte()), 0, 1) }
                    override fun write(b: ByteArray, off: Int, len: Int) {
                        startedWriting.countDown()
                        if (disconnected) writesAfterStop.incrementAndGet()
                        Thread.sleep(20)
                    }
                }
            }
        }
        val thread = Thread { engine.run() }.apply { start() }
        check(startedWriting.await(3, TimeUnit.SECONDS))
        val stopStart = System.nanoTime()
        engine.cancel()
        thread.join(1500)
        val stopDurationMs = (System.nanoTime() - stopStart) / 1_000_000.0
        check(!thread.isAlive) { "Engine thread did not stop in time" }
        check(engine.snapshot()["status"] == "stopped")
        check(stopDurationMs < 1200) { "Stop took too long: ${stopDurationMs}ms" }
        check(writesAfterStop.get() == 0L) { "Writes occurred after disconnect/cancel: ${writesAfterStop.get()}" }
    }
    test("invalid thread counts and endpoints are rejected") {
        check(runCatching { config("download", 65) }.isFailure)
        check(runCatching { config("download", 0) }.isFailure)
        check(!TransferConfig.validUrl("file:///tmp/data"))
        check(!TransferConfig.validUrl("http://user:pass@example.test/upload"))
    }
    if (args.isNotEmpty()) {
        val baseUrl = args.single().trimEnd('/')
        fun httpUpload(path: String, custom: Boolean): Map<String, Any?> {
            val engine = TransferEngine(config("upload", 4, null, 123456).copy(
                uploadUrl = "$baseUrl/$path", customServer = custom))
            engine.run()
            return engine.snapshot()
        }
        for (path in listOf("empty", "json", "invalid-size", "redirect")) {
            test("real HTTP custom $path upload accepts 200 without a size acknowledgement") {
                val result = httpUpload(path, true)
                check(result["status"] == "complete" && result["totalBytes"] == 123456L) { result }
                check((result["uploadMbps"] as Double) > 0) { result }
            }
        }
        test("real HTTP Speedtest upload still requires a valid received size") {
            val result = httpUpload("size", false)
            check(result["status"] == "complete" && result["totalBytes"] == 123456L) { result }
            for (path in listOf("empty", "json", "invalid-size")) {
                val rejected = httpUpload(path, false)
                check(rejected["status"] == "error" && rejected["totalBytes"] == 0L) { rejected }
            }
        }
        test("real HTTP custom upload still rejects HTTP errors") {
            val result = httpUpload("rejected", true)
            check(result["status"] == "error" && result["totalBytes"] == 0L) { result }
            check((result["message"] as String).contains("HTTP 403")) { result }
        }
    }
    println("$passed native engine checks passed")
}
