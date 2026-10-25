package dev.sam.speedtest

import java.io.Closeable
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL

data class TransferHttpRequest(
    val url: String,
    val bodySize: Int? = null,
    val writeBody: (OutputStream) -> Unit = {},
)

interface TransferHttpResponse : Closeable {
    val code: Int
    val contentType: String?
    val body: InputStream
    fun header(name: String): String?
}

interface TransferHttpCall : Closeable {
    val url: URL
    fun execute(): TransferHttpResponse
    fun cancel()
}

fun interface TransferHttpTransport {
    fun newCall(request: TransferHttpRequest): TransferHttpCall
}

/** Adapter for the existing deterministic URLConnection engine checks. */
class UrlConnectionTransport(private val open: (URL) -> HttpURLConnection) : TransferHttpTransport {
    override fun newCall(request: TransferHttpRequest): TransferHttpCall {
        val c = open(URI(request.url).toURL())
        c.connectTimeout = 5000
        c.readTimeout = 5000
        c.useCaches = false
        c.instanceFollowRedirects = false
        c.setRequestProperty("Cache-Control", "no-cache, no-store")
        c.setRequestProperty("Accept-Encoding", "identity")
        c.setRequestProperty("User-Agent", "NetProbe-Android/1.0")
        request.bodySize?.let {
            c.requestMethod = "POST"
            c.doOutput = true
            c.setRequestProperty("Content-Type", "application/octet-stream")
            c.setFixedLengthStreamingMode(it)
        }
        return object : TransferHttpCall {
            override val url: URL = c.url
            override fun execute(): TransferHttpResponse {
                if (request.bodySize != null) c.outputStream.use(request.writeBody)
                val code = c.responseCode
                return object : TransferHttpResponse {
                    override val code = code
                    override val contentType: String? get() = c.contentType
                    override val body: InputStream get() = c.inputStream
                    override fun header(name: String): String? = c.getHeaderField(name)
                    override fun close() { c.disconnect() }
                }
            }
            override fun cancel() { c.disconnect() }
            override fun close() { c.disconnect() }
        }
    }
}
