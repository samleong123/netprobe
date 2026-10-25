package dev.sam.speedtest

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager

class NetworkDetails(private val context: Context) {
    fun read(capabilities: NetworkCapabilities? = null, fiveGOverride: Boolean = false): Map<String, Any?> {
        val cm = context.getSystemService(ConnectivityManager::class.java)
        val network = cm.activeNetwork
        val caps = capabilities ?: network?.let { cm.getNetworkCapabilities(it) }
        val wifi = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        val mobile = caps?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true
        val phone = context.getSystemService(TelephonyManager::class.java)?.let { manager ->
            val subscription = SubscriptionManager.getDefaultDataSubscriptionId()
            if (SubscriptionManager.isValidSubscriptionId(subscription)) manager.createForSubscriptionId(subscription) else manager
        }
        fun <T> safe(block: () -> T): T? = runCatching(block).getOrNull()
        val phoneGranted = context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED
        val locationGranted = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        @Suppress("DEPRECATION")
        val wifiInfo = (if (Build.VERSION.SDK_INT >= 29) caps?.transportInfo as? WifiInfo else null)
            ?: if (wifi) safe { context.applicationContext.getSystemService(WifiManager::class.java).connectionInfo } else null
        val ssid = wifiInfo?.ssid?.removeSurrounding("\"")?.takeUnless { it == WifiManager.UNKNOWN_SSID || it.isBlank() }
        val dataType = if (phoneGranted && phone != null) safe { phone.dataNetworkType } else null
        val voiceType = if (phoneGranted && phone != null) safe { phone.voiceNetworkType } else null
        val radio = if (dataType != null && dataType != TelephonyManager.NETWORK_TYPE_UNKNOWN) dataType else voiceType
        val manufacturer = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
        val model = Build.MODEL
        val device = if (model.startsWith(manufacturer, ignoreCase = true)) model else "$manufacturer $model"
        return mapOf(
            "connected" to (network != null),
            "validated" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true),
            "transport" to when {
                caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true -> "VPN"
                wifi -> "Wi-Fi"; mobile -> "Mobile"
                caps?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true -> "Ethernet"
                network != null -> "Other"; else -> "Offline"
            },
            "ssid" to ssid,
            "operator" to phone?.let { safe { it.networkOperatorName } }?.takeIf { it.isNotBlank() },
            "networkCountryCode" to phone?.let { safe { it.networkCountryIso.uppercase(java.util.Locale.ROOT) } }?.takeIf { it.isNotBlank() },
            "simOperator" to phone?.let { safe { it.simOperatorName } }?.takeIf { it.isNotBlank() },
            "roaming" to phone?.let { safe { it.isNetworkRoaming } },
            "networkType" to if (fiveGOverride && radio == TelephonyManager.NETWORK_TYPE_LTE) "5G NSA (LTE anchor)" else radioName(radio),
            "localAddresses" to network?.let { cm.getLinkProperties(it)?.linkAddresses?.mapNotNull { address ->
                address.address.takeUnless { it.isLoopbackAddress || it.isLinkLocalAddress }?.hostAddress
            } }.orEmpty(),
            "metered" to cm.isActiveNetworkMetered,
            "manufacturer" to manufacturer, "model" to model, "device" to device,
            "phonePermission" to phoneGranted, "locationPermission" to locationGranted,
            "locationEnabled" to context.getSystemService(LocationManager::class.java).let {
                if (Build.VERSION.SDK_INT >= 28) it.isLocationEnabled
                else it.isProviderEnabled(LocationManager.GPS_PROVIDER) || it.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
            },
        )
    }

    private fun radioName(type: Int?): String? = when (type) {
        null -> null
        TelephonyManager.NETWORK_TYPE_GPRS -> "GPRS"
        TelephonyManager.NETWORK_TYPE_EDGE -> "EDGE"
        TelephonyManager.NETWORK_TYPE_UMTS -> "UMTS"
        TelephonyManager.NETWORK_TYPE_CDMA -> "CDMA"
        TelephonyManager.NETWORK_TYPE_EVDO_0 -> "EVDO 0"
        TelephonyManager.NETWORK_TYPE_EVDO_A -> "EVDO A"
        TelephonyManager.NETWORK_TYPE_EVDO_B -> "EVDO B"
        TelephonyManager.NETWORK_TYPE_1xRTT -> "1xRTT"
        TelephonyManager.NETWORK_TYPE_HSDPA -> "HSDPA"
        TelephonyManager.NETWORK_TYPE_HSUPA -> "HSUPA"
        TelephonyManager.NETWORK_TYPE_HSPA -> "HSPA"
        TelephonyManager.NETWORK_TYPE_IDEN -> "iDEN"
        TelephonyManager.NETWORK_TYPE_LTE -> "LTE"
        TelephonyManager.NETWORK_TYPE_EHRPD -> "eHRPD"
        TelephonyManager.NETWORK_TYPE_HSPAP -> "HSPA+"
        TelephonyManager.NETWORK_TYPE_GSM -> "GSM"
        TelephonyManager.NETWORK_TYPE_TD_SCDMA -> "TD-SCDMA"
        TelephonyManager.NETWORK_TYPE_IWLAN -> "IWLAN"
        TelephonyManager.NETWORK_TYPE_NR -> "NR (5G)"
        else -> "Unknown"
    }
}
