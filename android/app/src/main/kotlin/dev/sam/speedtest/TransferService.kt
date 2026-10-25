package dev.sam.speedtest

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.util.Locale
import java.util.concurrent.Executors

class TransferService : Service() {
    companion object {
        const val STOP = "dev.sam.speedtest.STOP"
        const val CHANNEL = "transfers"
        private const val NOTIFICATION_ID = 10
        private val stateLock = Any()
        @Volatile var latest: Map<String, Any?>? = null
            private set
        @Volatile var active = false
            private set
        @Volatile var pending = false
            private set
        var listener: ((Map<String, Any?>) -> Unit)? = null

        fun tryStart(): Boolean = synchronized(stateLock) {
            if (active || pending) {
                false
            } else {
                pending = true
                true
            }
        }

        fun markActive() = synchronized(stateLock) {
            active = true
            pending = false
        }

        fun markInactive() = synchronized(stateLock) {
            active = false
            pending = false
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val coordinator = Executors.newSingleThreadExecutor()
    private var engine: TransferEngine? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var notificationTick = 0
    private var unit = "Mbps"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, getString(R.string.channel_name), NotificationManager.IMPORTANCE_LOW).apply {
                description = getString(R.string.channel_description)
                setShowBadge(false)
            }
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            cancel("Stopped by you")
            if (!active) {
                markInactive()
                stopSelf()
            }
            return START_NOT_STICKY
        }
        if (active) return START_NOT_STICKY
        val raw = intent?.getStringExtra("config") ?: run { markInactive(); stopSelf(); return START_NOT_STICKY }
        try {
            val j = JSONObject(raw)
            fun string(key: String) = if (j.isNull(key)) null else j.optString(key).takeIf { it.isNotBlank() }
            fun number(key: String) = if (j.isNull(key)) null else j.getLong(key)
            val config = TransferConfig(j.getString("id"), j.getString("mode"), j.getInt("threads"),
                j.getString("serverName"), string("downloadUrl"), string("uploadUrl"), string("latencyUrl"),
                number("durationSeconds"), number("maxBytes"), j.optString("unit", "Mbps"))
            unit = config.unit
            val connectivity = getSystemService(ConnectivityManager::class.java)
            val network = connectivity.activeNetwork ?: error("No connected network")
            engine = TransferEngine(config) { network.openConnection(it) as HttpURLConnection }
            markActive()
            publish(engine!!.snapshot())
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION_ID, notification(latest!!), ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            else startForeground(NOTIFICATION_ID, notification(latest!!))
            wakeLock = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "speedtest:transfer").apply {
                setReferenceCounted(false)
                acquire(6 * 60 * 60 * 1000L)
            }
            networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onLost(lost: Network) { if (lost == network) cancel("Network disconnected") }
                override fun onAvailable(available: Network) {
                    if (available != network) cancel("Network changed. Start a new test on the current connection.")
                }
            }.also { connectivity.registerDefaultNetworkCallback(it) }
            handler.post(ticker)
            coordinator.execute {
                engine!!.run()
                val result = engine!!.snapshot()
                saveResult(result)
                handler.post {
                    publish(result)
                    markInactive()
                    releaseResources()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
        } catch (e: Exception) {
            markInactive()
            publish(mapOf("id" to runCatching { JSONObject(raw).optString("id") }.getOrDefault(""),
                "status" to "error", "phase" to "finished", "message" to (e.message ?: "Unable to start transfer")))
            releaseResources()
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private val ticker = object : Runnable {
        override fun run() {
            if (!active) return
            val snapshot = engine?.snapshot() ?: return
            if (snapshot["status"] == "running") publish(snapshot)
            if (++notificationTick % 4 == 0) getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification(snapshot))
            handler.postDelayed(this, 250)
        }
    }

    private fun publish(snapshot: Map<String, Any?>) {
        latest = snapshot
        handler.post { listener?.invoke(snapshot) }
    }

    private fun cancel(reason: String) {
        // Disconnect can touch socket I/O; keep it off the main thread and the busy coordinator.
        Thread({
            engine?.cancel(reason)
            engine?.snapshot()?.let { publish(it) }
        }, "speedtest-stop").start()
    }

    private fun notification(s: Map<String, Any?>): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, TransferService::class.java).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val phaseName = getString(when (s["phase"]) {
            "download" -> R.string.phase_download; "upload" -> R.string.phase_upload
            "latency" -> R.string.phase_latency; else -> R.string.phase_starting
        })
        val mbps = (s["speedMbps"] as? Number)?.toDouble() ?: 0.0
        val speed = String.format(Locale.getDefault(), "%.1f %s", if (unit == "MB/s") mbps / 8 else mbps, unit)
        val bytes = (s["totalBytes"] as? Number)?.toLong() ?: 0
        val usage = if (bytes >= 1_000_000_000) String.format(Locale.getDefault(), "%.2f GB", bytes / 1e9)
            else String.format(Locale.getDefault(), "%.1f MB", bytes / 1e6)
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_speed).setContentTitle(getString(R.string.notification_title, phaseName, s["serverName"] ?: ""))
            .setContentText(getString(R.string.notification_detail, speed, usage)).setContentIntent(open)
            .setOnlyAlertOnce(true).setOngoing(true).setCategory(Notification.CATEGORY_PROGRESS)
            .addAction(Notification.Action.Builder(null, getString(R.string.stop), stop).build()).build()
    }

    private fun saveResult(snapshot: Map<String, Any?>) {
        val prefs = getSharedPreferences("speedtest", MODE_PRIVATE)
        val old = runCatching { JSONArray(prefs.getString("history", "[]")) }.getOrDefault(JSONArray())
        val updated = JSONArray().put(JSONObject(snapshot).put("timestamp", System.currentTimeMillis()))
        for (i in 0 until minOf(old.length(), 49)) updated.put(old.get(i))
        prefs.edit().putString("history", updated.toString()).commit()
    }

    private fun releaseResources() {
        handler.removeCallbacks(ticker)
        networkCallback?.let { runCatching { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(it) } }
        networkCallback = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.VANILLA_ICE_CREAM)
    override fun onTimeout(startId: Int, fgsType: Int) {
        cancel("Android background transfer time limit reached")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        cancel("Transfer service stopped")
        releaseResources()
        markInactive()
        coordinator.shutdown()
        super.onDestroy()
    }
}
