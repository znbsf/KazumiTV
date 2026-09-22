package org.kazumi.tv

import androidx.media3.common.C
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.okhttp.OkHttpDataSource
import kotlinx.coroutines.*
import okhttp3.OkHttpClient
import org.kazumi.tv.data.AppHttp
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

/** Continuous local response across the 30-second boundary; no real media or user downloads. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object StreamingTimeoutRegression {
    private data class ReadResult(val bytes: Int, val elapsedMs: Long, val failure: IOException?)

    fun run(): String = runBlocking {
        val text = AppHttp.client
        val streaming = AppHttp.streamingClient
        check(text.callTimeoutMillis == 30000 && streaming.callTimeoutMillis == 0)
        check(streaming.connectTimeoutMillis == 12000 && streaming.readTimeoutMillis == 15000)
        check(streaming.cookieJar === text.cookieJar && streaming.connectionPool === text.connectionPool)
        check(streaming.followRedirects == text.followRedirects && streaming.followSslRedirects == text.followSslRedirects)
        val server = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
        val base = "http://127.0.0.1:${server.localPort}"
        val sockets = ConcurrentHashMap.newKeySet<Socket>()
        val counts = ConcurrentHashMap<String, AtomicInteger>()
        val acceptor = thread(isDaemon = true) {
            while (!server.isClosed) {
                val socket = try { server.accept() } catch (_: IOException) { break }
                sockets.add(socket)
                thread(isDaemon = true) {
                    try { socket.use {
                        it.soTimeout = 3000
                        val reader = it.getInputStream().bufferedReader()
                        val path = reader.readLine().orEmpty().split(' ').getOrNull(1).orEmpty()
                        while (true) { val line = reader.readLine() ?: break; if (line.isEmpty()) break }
                        counts.computeIfAbsent(path) { AtomicInteger() }.incrementAndGet()
                        val output = it.getOutputStream()
                        output.write("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: 36\r\nConnection: close\r\n\r\n".toByteArray())
                        output.flush()
                        if (path == "/stall") Thread.sleep(1500)
                        repeat(36) { index ->
                            output.write(index); output.flush()
                            if (index != 35) Thread.sleep(1000)
                        }
                    } } catch (_: Exception) { } finally { sockets.remove(socket) }
                }
            }
        }
        suspend fun read(client: OkHttpClient, path: String): ReadResult = withContext(Dispatchers.IO) {
            val source = OkHttpDataSource.Factory(client).createDataSource()
            val start = System.nanoTime()
            var count = 0
            var failure: IOException? = null
            try {
                source.open(DataSpec.Builder().setUri(base + path).build())
                val buffer = ByteArray(8)
                while (true) {
                    val read = source.read(buffer, 0, buffer.size)
                    if (read == C.RESULT_END_OF_INPUT) break
                    for (index in 0 until read) check((buffer[index].toInt() and 255) == count + index) { "stream content corrupted" }
                    count += read
                }
            } catch (error: IOException) { failure = error }
            finally { source.close() }
            ReadResult(count, (System.nanoTime() - start) / 1_000_000, failure)
        }
        try {
            val results = withTimeout(46000) {
                coroutineScope {
                    val baseline = async { read(text, "/baseline") }
                    val continuous = async { read(streaming, "/streaming") }
                    val stalled = async { read(streaming.newBuilder().readTimeout(250, TimeUnit.MILLISECONDS).build(), "/stall") }
                    Triple(baseline.await(), continuous.await(), stalled.await())
                }
            }
            val baseline = results.first
            val continuous = results.second
            val stalled = results.third
            fun timedOut(failure: IOException?) = generateSequence<Throwable>(failure) { it.cause }.any { it is java.io.InterruptedIOException }
            check(timedOut(baseline.failure) && baseline.bytes in 1..35 && baseline.elapsedMs in 28000L..34000L) { "baseline did not expose whole-call timeout" }
            check(continuous.failure == null && continuous.bytes == 36 && continuous.elapsedMs >= 34500) { "streaming did not reach complete EOF" }
            check(timedOut(stalled.failure) && stalled.bytes == 0 && stalled.elapsedMs < 5000) { "per-read timeout lost" }
            check(listOf("/baseline", "/streaming", "/stall").all { counts[it]?.get() == 1 }) { "reconnect hid timeout" }
            "streaming_timeout=PASS baseline_ms=${baseline.elapsedMs} streaming_ms=${continuous.elapsedMs} streaming_bytes=36 single_request=true read_timeout_preserved=true"
        } finally {
            server.close()
            sockets.forEach { runCatching { it.close() } }
            acceptor.join(1000)
        }
    }
}
