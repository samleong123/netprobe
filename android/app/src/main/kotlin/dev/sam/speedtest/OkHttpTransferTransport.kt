package dev.sam.speedtest

import java.net.URL
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response
import okio.BufferedSink

/** Call.cancel() aborts the exchange/socket, including a blocked body write. */
class OkHttpTransferTransport(private val client: OkHttpClient) : TransferHttpTransport {
    override fun newCall(request: TransferHttpRequest): TransferHttpCall {
        val builder = Request.Builder().url(request.url)
            .header("Cache-Control", "no-cache, no-store")
            .header("Accept-Encoding", "identity")
            .header("User-Agent", "NetProbe-Android/1.0")
        request.bodySize?.let { size ->
            builder.post(object : RequestBody() {
                override fun contentType() = "application/octet-stream".toMediaType()
                override fun contentLength() = size.toLong()
                override fun isOneShot() = true
                override fun writeTo(sink: BufferedSink) { request.writeBody(sink.outputStream()) }
            })
        }
        val call = client.newCall(builder.build())
        return object : TransferHttpCall {
            private var response: Response? = null
            override val url: URL = call.request().url.toUrl()
            override fun execute(): TransferHttpResponse {
                val result = call.execute()
                response = result
                return object : TransferHttpResponse {
                    override val code = result.code
                    override val contentType: String? get() = result.header("Content-Type")
                    override val body get() = checkNotNull(result.body).byteStream()
                    override fun header(name: String) = result.header(name)
                    override fun close() { result.close() }
                }
            }
            override fun cancel() { call.cancel() }
            override fun close() { response?.close() }
        }
    }
}
