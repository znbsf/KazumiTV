package org.kazumi.tv

import android.content.Context
import kotlinx.coroutines.*
import org.json.JSONObject
import org.kazumi.tv.playback.WebMediaResolver
import org.kazumi.tv.rules.SourceRule
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.concurrent.thread

/** Real localhost HTTP probes; no source page, CAPTCHA, or external media. */
object MediaProbeFallbackRegression {
    fun run(context: Context): String = runBlocking {
        for (mode in listOf("recover", "redirect", "explicit", "repeat400", "html", "401", "403", "429")) {
            val server = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
            val base = "http://127.0.0.1:${server.localPort}"
            val received = CopyOnWriteArrayList<Map<String, String>>()
            val acceptor = thread(isDaemon = true) {
                while (!server.isClosed) {
                    val socket = try { server.accept() } catch (_: Exception) { break }
                    thread(isDaemon = true) {
                        try { socket.use {
                            it.soTimeout = 3000
                            val reader = it.getInputStream().bufferedReader()
                            val path = reader.readLine().orEmpty().split(' ').getOrNull(1)
                            val headers = mutableMapOf<String, String>()
                            while (true) {
                                val line = reader.readLine() ?: break
                                if (line.isEmpty()) break
                                headers[line.substringBefore(':').lowercase()] = line.substringAfter(':').trim()
                            }
                            if (mode == "redirect" && path == "/media.mp4") {
                                it.getOutputStream().write("HTTP/1.1 302 Found\r\nLocation: /final.mp4\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray())
                            } else {
                                received.add(headers)
                                val hasReferer = headers["referer"].orEmpty().isNotEmpty()
                                val code = mode.toIntOrNull() ?: if (hasReferer || mode == "repeat400") 400 else 200
                                val bytes = if (code == 200 && mode != "html") byteArrayOf(0, 0, 0, 16, 102, 116, 121, 112, 105, 115, 111, 109, 0, 0, 0, 0)
                                    else "<html>fixture failure</html>".toByteArray()
                                val type = if (code == 200 && mode != "html") "video/mp4" else "text/html"
                                it.getOutputStream().write(("HTTP/1.1 $code Fixture\r\nContent-Type: $type\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n").toByteArray() + bytes)
                            }
                        } } catch (_: Exception) { }
                    }
                }
            }
            try {
                val rule = SourceRule(JSONObject().put("name", "probe fixture").put("baseURL", "$base/")
                    .put("referer", if (mode == "explicit") "$base/configured" else ""))
                val result = runCatching { withTimeout(12000) { WebMediaResolver(context).resolve("$base/media.mp4", rule, "fixture") } }
                val succeeds = mode in listOf("recover", "redirect")
                check(result.isSuccess == succeeds) { "probe result mismatch $mode" }
                val expectedCount = if (mode in listOf("explicit", "401", "403", "429")) 1 else 2
                check(received.size == expectedCount) { "probe request budget $mode count=${received.size}" }
                check(received.first()["referer"].orEmpty().isNotEmpty())
                check(received.all { it["range"] == "bytes=0-1023" && it["user-agent"] == rule.userAgent })
                if (received.size == 2) check(received.last().keys.none { it == "referer" || it == "origin" })
                if (succeeds) {
                    val playback = result.getOrThrow()
                    check(playback.mimeType == "video/mp4")
                    check(playback.headers.keys.none { it.equals("Referer", true) || it.equals("Origin", true) })
                    check(playback.headers["User-Agent"] == rule.userAgent)
                }
            } finally { server.close(); acceptor.join(1000) }
        }
        "media_probe_fallback=PASS cases=8 bounded_retry=true configured_referer_preserved=true nonmedia_rejected=true"
    }
}
