package org.kazumi.tv

import android.content.Context
import android.os.SystemClock
import android.webkit.WebView
import kotlinx.coroutines.*
import org.json.JSONObject
import org.json.JSONTokener
import org.kazumi.tv.playback.InlinePlayerMetadata
import org.kazumi.tv.playback.MediaResolutionFailure
import org.kazumi.tv.playback.WebMediaResolver
import org.kazumi.tv.rules.SourceRule
import org.kazumi.tv.rules.VerificationSession
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

/** Local resolution/probe only: deliberately absent Artplayer, no media playback or user storage. */
object InlinePlayerMetadataRegression {
    fun run(context:Context):String=runBlocking {
        val server=ServerSocket(0,16,InetAddress.getByName("127.0.0.1"))
        val base="http://127.0.0.1:${server.localPort}"
        val media="$base/media.m3u8"
        val mediaRequests=AtomicInteger()
        val pageLoads=AtomicInteger()
        val delayedProbes=AtomicInteger()
        val replacementLoads=AtomicInteger()
        val replacementDuringProbe=AtomicInteger()
        val delayedPending=java.util.concurrent.atomic.AtomicBoolean()
        val stalePlayerScript="var Isios=navigator.userAgent.match(/iPad|Android/i);var Vurl='$base/delayed.m3u8';var art=new Artplayer({url:Vurl});"
        val acceptor=thread(isDaemon=true) {
            while(!server.isClosed)try {
                val socket=server.accept()
                thread(isDaemon=true) {
                    socket.use {
                        runCatching {
                            it.soTimeout=3000
                            val input=it.getInputStream().bufferedReader()
                            val path=input.readLine()?.split(' ')?.getOrNull(1).orEmpty()
                            while(!input.readLine().isNullOrEmpty()) { }
                            val body=when(path) {
                                "/media.m3u8" -> { mediaRequests.incrementAndGet();"#EXTM3U\n#EXT-X-ENDLIST\n" }
                                "/delayed.m3u8" -> { delayedPending.set(true);delayedProbes.incrementAndGet();Thread.sleep(1500);delayedPending.set(false);"#EXTM3U\n#EXT-X-ENDLIST\n" }
                                "/probe-status" -> if(delayedProbes.get()>0)"1" else "0"
                                "/replacement" -> { replacementLoads.incrementAndGet();if(delayedPending.get())replacementDuringProbe.incrementAndGet();"<html><body>replacement</body></html>" }
                                "/stale" -> "<html><body><script>setInterval(function(){var x=new XMLHttpRequest();x.open('GET','/probe-status');x.onload=function(){if(x.responseText==='1')location.replace('/replacement');};x.send();},100);</script><script>$stalePlayerScript</script></body></html>"
                                "/parent" -> "<html><body><iframe id='video-player' width='640' height='360' src='http://localhost:${server.localPort}/player'></iframe></body></html>"
                                "/player", "/snapshot" -> "<html><head></head><body><script>window.fixtureLoad=${pageLoads.incrementAndGet()};var Isios=navigator.userAgent.match(/iPad|Android/i);var Vurl='$media';var art=new Artplayer({url:Vurl});</script></body></html>"
                                else -> "<html></html>"
                            }.toByteArray()
                            val type=if(path=="/media.m3u8"||path=="/delayed.m3u8")"application/vnd.apple.mpegurl" else if(path=="/probe-status")"text/plain" else "text/html"
                            it.getOutputStream().write("HTTP/1.1 200 OK\r\nContent-Type: $type\r\nCache-Control: no-store\r\nContent-Length: ${body.size}\r\nConnection: close\r\n\r\n".toByteArray()+body)
                        }
                    }
                }
            }catch(_:Exception){if(server.isClosed)break}
        }
        try {
            val rule=SourceRule(JSONObject().put("name","inline-fixture").put("baseURL",base))
            for(path in listOf("/player","/parent")) {
                val diagnostics=mutableListOf<String>()
                val before=mediaRequests.get()
                val started=SystemClock.elapsedRealtime()
                val resolved=withTimeout(23000) {
                    WebMediaResolver(context,timeoutMs=20000,diagnostic={diagnostics.add(it)},forceCompatibility=true)
                        .resolve(base+path,rule,"local inline fixture")
                }
                check(resolved.url==media && resolved.mimeType?.contains("mpegurl",ignoreCase=true)==true) { "inline resolver failed HLS identity/type for $path" }
                check(SystemClock.elapsedRealtime()-started>=7800) { "inline fixture bypassed eight-second live-document gate for $path" }
                check(diagnostics.any { it.startsWith("inline_player_reference") }) { "inline fixture resolved without live reference for $path" }
                check(mediaRequests.get()==before+1) { "inline fixture unexpected media probe count for $path" }
                if(path=="/parent")check(diagnostics.any { it.startsWith("iframe_fallback") }) { "cross-origin compatibility fixture did not promote player" }
            }
            check(InlinePlayerMetadata.reference(org.json.JSONArray().put(stalePlayerScript))==("Vurl" to "$base/delayed.m3u8")) {
                "stale fixture reference was rejected before live resolution"
            }
            val staleDiagnostics=mutableListOf<String>()
            val staleFailure=try {
                withTimeout(19000) {
                    WebMediaResolver(context,timeoutMs=15000,diagnostic={staleDiagnostics.add(it)},forceCompatibility=true)
                        .resolve("$base/stale",rule,"local stale inline fixture")
                }
                false
            }catch(_:MediaResolutionFailure){true}
            check(staleFailure) { "navigation during probe returned obsolete media" }
            check(staleDiagnostics.any { it.startsWith("inline_player_reference") }) { "stale fixture never queued live reference" }
            check(delayedProbes.get()==1 && replacementLoads.get()>0 && replacementDuringProbe.get()>0) {
                "stale fixture did not navigate during its single probe: probes=${delayedProbes.get()} replacements=${replacementLoads.get()} during=${replacementDuringProbe.get()}"
            }
            withContext(Dispatchers.Main) {
                val web=WebView(context)
                try {
                    web.settings.javaScriptEnabled=true
                    suspend fun evaluate(script:String)=VerificationSession.evaluate(web,script)
                    suspend fun load(previous:Int=0):Int {
                        web.loadUrl("$base/snapshot")
                        return withTimeout(6000) {
                            var token=0
                            while(token<=previous) {
                                token=evaluate("document.readyState==='complete' ? window.fixtureLoad || 0 : 0").toIntOrNull() ?: 0
                                if(token<=previous)delay(50)
                            }
                            token
                        }
                    }
                    val first=load()
                    val snapshot=JSONObject(JSONTokener(evaluate(InlinePlayerMetadata.snapshotScript)).nextValue().toString())
                    val reference=InlinePlayerMetadata.reference(snapshot.getJSONArray("scripts"))
                    check(reference==("Vurl" to media)) { "inline snapshot failed static variable reference" }
                    val match=InlinePlayerMetadata.matchesCurrentScript("Vurl",media,snapshot.getString("page"))
                    check(evaluate(match)=="true") { "live own data did not match" }
                    evaluate("window.Vurl='changed';void 0;")
                    check(evaluate(match)=="false") { "changed live value was accepted" }
                    // A separate configurable field proves descriptor reads do not invoke a getter.
                    evaluate("window.getterCalls=0;Object.defineProperty(window,'GuardedValue',{configurable:true,get:function(){window.getterCalls++;return '$media';}});void 0;")
                    check(evaluate(InlinePlayerMetadata.matchesCurrentScript("GuardedValue",media,snapshot.getString("page")))=="false") { "getter field was accepted" }
                    check(evaluate("window.getterCalls")=="0") { "live matching invoked getter" }
                    load(first)
                    check(evaluate(match)=="false") { "same URL new document reused previous snapshot marker" }
                } finally { web.stopLoading();web.destroy() }
            }
            "inline_player_metadata=PASS compatibility_top=true compatibility_cross_origin=true hls_probe=true probe_navigation_rejected=true changed_value_rejected=true getter_calls=0 new_document_rejected=true playback=false"
        } finally { server.close();acceptor.join(1000) }
    }
}
