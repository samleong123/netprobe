package dev.sam.speedtest

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SubscriptionManager
import android.telephony.TelephonyCallback
import android.telephony.TelephonyDisplayInfo
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private val io = Executors.newFixedThreadPool(3)
    private var eventSink: EventChannel.EventSink? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var currentCaps: NetworkCapabilities? = null
    private var displayCallback: TelephonyCallback? = null
    private var displayManager: TelephonyManager? = null
    private var fiveG = false
    private var permissionResult: MethodChannel.Result? = null
    private val details by lazy { NetworkDetails(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.sam.speedtest/control").setMethodCallHandler(::handle)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.sam.speedtest/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                eventSink = events
                TransferService.listener = { emit("transfer", it) }
                emitNetwork()
                TransferService.latest?.let { emit("transfer", it) }
            }
            override fun onCancel(arguments: Any?) { eventSink = null; TransferService.listener = null }
        })
        registerNetwork()
        registerDisplayInfo()
    }

    private fun emit(type: String, data: Map<String, Any?>) {
        handler.post { eventSink?.success(mapOf("type" to type, "data" to data)) }
    }

    private fun emitNetwork() { emit("network", details.read(currentCaps, fiveG)) }

    private fun registerNetwork() {
        networkCallback?.let { runCatching { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(it) } }
        val callback = if (Build.VERSION.SDK_INT >= 31) object : ConnectivityManager.NetworkCallback(FLAG_INCLUDE_LOCATION_INFO) {
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) { currentCaps = caps; emitNetwork() }
            override fun onLost(network: Network) { currentCaps = null; fiveG = false; emitNetwork() }
            override fun onLinkPropertiesChanged(network: Network, properties: android.net.LinkProperties) { emitNetwork() }
        } else object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) { currentCaps = caps; emitNetwork() }
            override fun onLost(network: Network) { currentCaps = null; emitNetwork() }
            override fun onLinkPropertiesChanged(network: Network, properties: android.net.LinkProperties) { emitNetwork() }
        }
        getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(callback)
        networkCallback = callback
    }

    private fun registerDisplayInfo() {
        if (Build.VERSION.SDK_INT < 31 || checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) return
        displayCallback?.let { displayManager?.unregisterTelephonyCallback(it) }
        val manager = getSystemService(TelephonyManager::class.java) ?: return
        val subscription = SubscriptionManager.getDefaultDataSubscriptionId()
        displayManager = if (SubscriptionManager.isValidSubscriptionId(subscription)) manager.createForSubscriptionId(subscription) else manager
        displayCallback = object : TelephonyCallback(), TelephonyCallback.DisplayInfoListener {
            override fun onDisplayInfoChanged(info: TelephonyDisplayInfo) {
                fiveG = info.overrideNetworkType == TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_NSA ||
                    info.overrideNetworkType == TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_ADVANCED
                emitNetwork()
            }
        }.also { runCatching { displayManager?.registerTelephonyCallback(mainExecutor, it) } }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "network" -> result.success(details.read(currentCaps, fiveG))
                "snapshot" -> result.success(TransferService.latest)
                "fetchConfig" -> io.execute {
                    try {
                        val uri = Uri.parse("https://www.speedtest.net/api/js/config-sdk").buildUpon()
                            .appendQueryParameter("engine", "js")
                            .appendQueryParameter("search", call.argument<String>("search") ?: "")
                            .appendQueryParameter("https_functional", "true").appendQueryParameter("limit", "100").build()
                        val connectivity = getSystemService(ConnectivityManager::class.java)
                        val network = connectivity.activeNetwork ?: error("No internet connection. Connect and try again.")
                        val c = network.openConnection(URL(uri.toString())) as HttpURLConnection
                        val body = try {
                            c.connectTimeout = 10000; c.readTimeout = 10000; c.useCaches = false
                            c.setRequestProperty("Accept", "application/json")
                            c.setRequestProperty("User-Agent", "NetProbe-Android/1.0")
                            if (c.responseCode !in 200..299) error("Server discovery returned HTTP ${c.responseCode}. Try again later.")
                            c.inputStream.bufferedReader().use { reader ->
                                val buffer = CharArray(8192)
                                val text = StringBuilder()
                                while (true) {
                                    val count = reader.read(buffer)
                                    if (count < 0) break
                                    text.append(buffer, 0, count)
                                    require(text.length <= 2_000_000) { "Discovery response was too large" }
                                }
                                text.toString()
                            }
                        } finally { c.disconnect() }
                        // Do not persist or forward the short-lived clientAuth token.
                        val payload = JSONObject(body).apply { remove("clientAuth"); remove("guid") }
                        handler.post { result.success(payload.toString()) }
                    } catch (e: Exception) { handler.post { result.error("discovery", e.message ?: "Unable to discover servers", null) } }
                }
                "start" -> {
                    check(TransferService.tryStart()) { "A transfer is already running" }
                    try {
                        val arguments = call.arguments as? Map<*, *> ?: error("Missing transfer configuration")
                        val json = JSONObject(arguments).toString()
                        // Validate before asking Android to launch a foreground service.
                        val j = JSONObject(json)
                        fun str(k: String) = if (j.isNull(k)) null else j.optString(k).takeIf { it.isNotBlank() }
                        fun num(k: String) = if (j.isNull(k)) null else j.getLong(k)
                        TransferConfig(j.getString("id"), j.getString("mode"), j.getInt("threads"), j.getString("serverName"),
                            str("downloadUrl"), str("uploadUrl"), str("latencyUrl"), num("durationSeconds"), num("maxBytes"), j.optString("unit", "Mbps"), j.optBoolean("customServer", false))
                        startForegroundService(Intent(this, TransferService::class.java).putExtra("config", json))
                        result.success(null)
                    } catch (e: Exception) {
                        TransferService.markInactive()
                        throw e
                    }
                }
                "stop" -> {
                    if (TransferService.active || TransferService.pending) startService(Intent(this, TransferService::class.java).setAction(TransferService.STOP))
                    result.success(null)
                }
                "load" -> {
                    val prefs = getSharedPreferences("speedtest", MODE_PRIVATE)
                    result.success(mapOf("settings" to prefs.getString("settings", null), "servers" to prefs.getString("servers", "[]"), "history" to prefs.getString("history", "[]")))
                }
                "save" -> {
                    val key = call.argument<String>("key") ?: error("Missing storage key")
                    require(key in listOf("settings", "servers", "history"))
                    val value = call.argument<String>("value") ?: error("Missing storage value")
                    io.execute {
                        val ok = getSharedPreferences("speedtest", MODE_PRIVATE).edit().putString(key, value).commit()
                        handler.post { if (ok) result.success(null) else result.error("storage", "Unable to save on this device", null) }
                    }
                }
                "requestStartupPermissions" -> {
                    val permissions = mutableListOf(Manifest.permission.READ_PHONE_STATE,
                        Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)
                    if (Build.VERSION.SDK_INT >= 33) permissions.add(Manifest.permission.POST_NOTIFICATIONS)
                    requestPermission(permissions.toTypedArray(), 22, result)
                }
                "requestDetails" -> requestPermission(arrayOf(Manifest.permission.READ_PHONE_STATE, Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION), 20, result)
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33) requestPermission(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 21, result)
                    else result.success(true)
                }
                "locationSettings" -> { startActivity(Intent(android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS)); result.success(null) }
                "appSettings" -> { startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))); result.success(null) }
                "openUrl" -> {
                    val url = call.argument<String>("url") ?: error("Missing url")
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) { result.error("android", e.message ?: "Android operation failed", null) }
    }

    private fun requestPermission(permissions: Array<String>, code: Int, result: MethodChannel.Result) {
        val missing = permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }.toMutableList()
        if (missing.isEmpty()) { result.success(true); return }
        // Android 12+ requires coarse and fine location to be requested together,
        // including an upgrade from an already-granted approximate permission.
        if (Manifest.permission.ACCESS_FINE_LOCATION in missing &&
            Manifest.permission.ACCESS_COARSE_LOCATION in permissions &&
            Manifest.permission.ACCESS_COARSE_LOCATION !in missing) {
            missing.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
        check(permissionResult == null) { "A permission request is already open" }
        permissionResult = result
        requestPermissions(missing.toTypedArray(), code)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode in 20..22) {
            permissionResult?.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
            permissionResult = null
            registerNetwork()
            registerDisplayInfo()
            emitNetwork()
        }
    }

    override fun onResume() {
        super.onResume()
        currentCaps = null
        if (networkCallback != null) { registerNetwork(); registerDisplayInfo(); emitNetwork() }
    }

    override fun onDestroy() {
        TransferService.listener = null
        eventSink = null
        networkCallback?.let { runCatching { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(it) } }
        if (Build.VERSION.SDK_INT >= 31) displayCallback?.let { runCatching { displayManager?.unregisterTelephonyCallback(it) } }
        io.shutdown()
        super.onDestroy()
    }
}
