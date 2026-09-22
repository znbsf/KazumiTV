package org.kazumi.tv

import android.annotation.SuppressLint
import android.content.Context
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import org.kazumi.tv.playback.WebMediaResolver
import androidx.webkit.WebViewFeature
import kotlinx.coroutines.*
import org.json.JSONObject
import org.json.JSONTokener
import org.kazumi.tv.playback.MediaDiscoveryScript
import org.kazumi.tv.playback.WebDiscoveryCapabilities
import java.net.InetAddress
import java.net.ServerSocket
import kotlin.concurrent.thread
import kotlin.coroutines.resume

/** Tests real provider script timing; modern coverage is explicitly skipped on old providers. */
object WebDiscoveryRegression {
    @SuppressLint("SetJavaScriptEnabled")
    fun run(context: Context): String = runBlocking {
        val server = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
        val base = "http://127.0.0.1:${server.localPort}"
        val redirectRequests=java.util.concurrent.atomic.AtomicInteger()
        val wrongContextRequests=java.util.concurrent.atomic.AtomicInteger()
        val rightContextRequests=java.util.concurrent.atomic.AtomicInteger()
        val acceptor = thread(isDaemon = true) {
            while (!server.isClosed) try {
                val socket = server.accept()
                thread(isDaemon = true) {
                    socket.use {
                        it.soTimeout = 3000
                        val input = it.getInputStream().bufferedReader()
                        val path = input.readLine()?.split(' ')?.getOrNull(1).orEmpty()
                        if(path=="/candidate-redirect")redirectRequests.incrementAndGet()
                        val headers=mutableMapOf<String,String>()
                        while(true) { val line=input.readLine();if(line.isNullOrEmpty())break
                            headers[line.substringBefore(':').lowercase()]=line.substringAfter(':').trim() }
                        val contextMedia=path=="/context-manifest.m3u8"
                        val rightContext=headers["referer"].orEmpty().endsWith("/context-child")
                        if(contextMedia) { if(rightContext)rightContextRequests.incrementAndGet() else wrongContextRequests.incrementAndGet() }
                        val body = when (path) {
                            "/early" -> "<html><script>window.earlyInstalled=!!window.__kazumiMedia;var x=new XMLHttpRequest();x.open('GET','/manifest');x.send();</script></html>"
                            "/range-parent" -> "<html><body><iframe id=player src=\"\"></iframe><script>setTimeout(function(){document.getElementById(\"player\").src=\"http://localhost:${server.localPort}/range-child\";},250);</script></body></html>"
                            "/range-child" -> "<html><script>var x=new XMLHttpRequest();x.open(\"GET\",\"/opaque-stream\");x.setRequestHeader(\"Range\",\"bytes=0-1023\");x.send();var j=new XMLHttpRequest();j.open(\"GET\",\"/code.js\");j.setRequestHeader(\"Range\",\"bytes=0-1023\");j.send();</script></html>"
                            "/opaque-stream" -> "#EXTM3U\n#EXT-X-ENDLIST\n"
                            "/code.js" -> "/* non-media Range response */"
                            "/parent" -> "<html><iframe src='http://localhost:${server.localPort}/early'></iframe></html>"
                            "/no-range-parent" -> "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'><style>html,body{margin:0;width:100%;height:100%}#video-player{width:100%;height:80%;border:0}</style></head><body><script src='/code.js'></script><img src='/tiny.png'><iframe id='ad-player' width='1' height='1' src='http://localhost:${server.localPort}/tracker'></iframe><iframe id='video-player' src='http://localhost:${server.localPort}/no-range-child'></iframe></body></html>"
                            "/broken-player-parent" -> "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'><style>html,body{margin:0;width:100%;height:100%}#main-player{width:100%;height:80%;border:0}</style></head><body><iframe id='ad-player' width='1' height='1' src='http://localhost:${server.localPort}/broken-player?url=http%3A%2F%2Flocalhost%3A${server.localPort}%2Fad-manifest.m3u8'></iframe><iframe id='hidden-player' style='visibility:hidden;position:absolute;width:640px;height:360px' src='http://localhost:${server.localPort}/broken-player?url=http%3A%2F%2Flocalhost%3A${server.localPort}%2Fad-manifest.m3u8'></iframe><iframe id='main-player' src='http://localhost:${server.localPort}/broken-player?url=http%3A%2F%2Flocalhost%3A${server.localPort}%2Fmanifest.m3u8'></iframe></body></html>"
                            "/bad-frame-parent" -> "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'><style>html,body{margin:0;width:100%;height:100%}iframe{width:100%;height:40%;border:0}</style></head><body><iframe id='bad-video-player' src='http://localhost:${server.localPort}/missing-player'></iframe><iframe id='good-video-player' src='http://localhost:${server.localPort}/no-range-child'></iframe></body></html>"
                            "/embedded-parent", "/cancel-parent" -> "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'><style>html,body{margin:0;width:100%;height:100%}#video-player{width:100%;height:80%;border:0}</style></head><body><iframe id='video-player' src='http://localhost:${server.localPort}/${if(path=="/embedded-parent") "embedded-child" else "never-child"}'></iframe></body></html>"
                            "/embedded-child" -> "<html><script>if(window.self===window.top){location.href='$base/candidate-redirect';}else{setTimeout(function(){var x=new XMLHttpRequest();x.open('GET','/delayed-embedded.m3u8');x.send();},5500);}</script></html>"
                            "/context-parent" -> "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'><style>html,body{margin:0;width:100%;height:100%}#video-player{width:100%;height:80%;border:0}</style></head><body><iframe id='video-player' src='http://localhost:${server.localPort}/context-child'></iframe><script>setTimeout(function(){var x=new XMLHttpRequest();x.open('GET','/context-manifest.m3u8');x.send();},200);</script></body></html>"
                            "/context-child" -> "<html><head><meta name='referrer' content='unsafe-url'></head><script>if(window.self===window.top){setTimeout(function(){var x=new XMLHttpRequest();x.open('GET','$base/context-manifest.m3u8');x.send();},200);}</script></html>"
                            "/challenge-parent", "/challenge-delay-parent", "/challenge-redirect-parent" -> "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'><style>html,body{margin:0;width:100%;height:100%}#video-player{width:100%;height:80%;border:0}</style></head><body><iframe id='video-player' src='http://localhost:${server.localPort}/${if(path=="/challenge-redirect-parent") "challenge-redirect-child" else "challenge-child"}'></iframe><script>setTimeout(function(){var x=new XMLHttpRequest();x.open('GET','/denied.m3u8');x.send();},200);${if(path=="/challenge-delay-parent") "setTimeout(function(){var x=new XMLHttpRequest();x.open('GET','/manifest.m3u8');x.send();},5500);" else ""}</script></body></html>"
                            "/challenge-child" -> "<html><head><title>安全验证</title></head><body>fixture requires verification</body></html>"
                            "/challenge-redirect-child" -> "<html><head><title>安全验证</title></head><body><script>if(window.self===window.top)setTimeout(function(){location.href='/candidate-normal';},1200);</script>fixture challenge</body></html>"
                            "/no-range-child" -> "<html><script>var x=new XMLHttpRequest();x.open('GET','/manifest');x.send();</script></html>"
                            "/viewport-verification" -> "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'><style>html,body{margin:0;width:100%;height:100%}</style></head><body><button id='verify' onclick=\"if(document.documentElement.clientWidth>=160&amp;&amp;document.documentElement.clientHeight>=90){this.parentNode.removeChild(this);}\">Verify</button><p>Fixture</p></body></html>"
                            "/noise-parent" -> "<html><script>for(var i=0;i<40;i++)(function(n){setTimeout(function(){var x=new XMLHttpRequest();x.open('GET','/noise/'+n);x.send();},n*45);})(i);setTimeout(function(){var x=new XMLHttpRequest();x.open('GET','/manifest');x.send();},2200);</script></html>"
                            "/late" -> "<html><body><script>setTimeout(function(){var x=new XMLHttpRequest();x.open('GET','/manifest');x.send();},1200);</script></body></html>"
                            "/manifest", "/manifest.m3u8", "/ad-manifest.m3u8", "/delayed-embedded.m3u8", "/context-manifest.m3u8" -> "#EXTM3U\n#EXT-X-ENDLIST\n"
                            else -> if(path.startsWith("/broken-player?")) "<html><body><script>var brokenBundle = ;</script><script>new Artplayer({});</script></body></html>" else if(path.startsWith("/noise/")) "{\"ok\":true}" else "<html></html>"
                        }.toByteArray()
                        val type = if (path == "/manifest") "text/plain" else if(path.startsWith("/noise/")) "application/json" else "text/html"
                        val status=if(path=="/missing-player") "404 Not Found" else if(path=="/denied.m3u8"||contextMedia&&!rightContext) "403 Forbidden" else "200 OK"
                        runCatching { it.getOutputStream().write("HTTP/1.1 $status\r\nContent-Type: $type\r\nContent-Length: ${body.size}\r\nConnection: close\r\n\r\n".toByteArray() + body) }
                    }
                }
            } catch (_: Exception) { if (server.isClosed) break }
        }
        try {
            withContext(Dispatchers.Main) {
                suspend fun checkPage(path: String, early: Boolean) {
                    val web = WebView(context)
                    var handle: androidx.webkit.ScriptHandler? = null
                    try {
                        web.settings.javaScriptEnabled = true
                        if (early) handle = WebDiscoveryCapabilities.install(web)
                        if (early) check(handle != null) { "Advertised modern provider did not install script" }
                        web.loadUrl(base + path)
                        withTimeout(6000) {
                            while (true) {
                                val raw = suspendCancellableCoroutine<String> { continuation ->
                                    web.evaluateJavascript(MediaDiscoveryScript.poll) { if (continuation.isActive) continuation.resume(it) }
                                }
                                val snapshot = runCatching { JSONObject(JSONTokener(raw).nextValue().toString()) }.getOrNull()
                                if ((snapshot?.optJSONArray("urls")?.length() ?: 0) > 0) {
                                    val candidate = snapshot!!.getJSONArray("urls").getJSONObject(0)
                                    check(candidate.getString("url").endsWith("/manifest"))
                                    if (path == "/parent") check(candidate.getString("referer").contains("localhost:"))
                                    if (path == "/early") {
                                        val installed = suspendCancellableCoroutine<String> { continuation ->
                                            web.evaluateJavascript("window.earlyInstalled===true") { if (continuation.isActive) continuation.resume(it) }
                                        }
                                        check(installed == "true") { "Hook was not present before inline site script" }
                                    }
                                    break
                                }
                                delay(100)
                            }
                        }
                    } finally {
                        handle?.remove()
                        web.stopLoading()
                        web.destroy()
                    }
                }
                suspend fun checkCompatibilityCrossOriginRange() {
                    val web = WebView(context)
                    val media = java.util.concurrent.atomic.AtomicReference<WebResourceRequest?>()
                    val rejectedScript = java.util.concurrent.atomic.AtomicBoolean()
                    try {
                        web.settings.javaScriptEnabled = true
                        // Deliberately no WebDiscoveryCapabilities.install: force the old-provider path.
                        web.webViewClient = object : WebViewClient() {
                            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                                val url = request.url.toString()
                                if (request.url.path == "/opaque-stream" && WebMediaResolver.isMediaCandidate(url, request.requestHeaders)) media.set(request)
                                if (request.url.path == "/code.js") rejectedScript.set(!WebMediaResolver.isMediaCandidate(url, request.requestHeaders))
                                return null
                            }
                        }
                        web.loadUrl(base + "/range-parent")
                        withTimeout(7000) {
                            while (true) {
                                val raw = suspendCancellableCoroutine<String> { continuation ->
                                    web.evaluateJavascript(MediaDiscoveryScript.poll) { if (continuation.isActive) continuation.resume(it) }
                                }
                                val snapshot = runCatching { JSONObject(JSONTokener(raw).nextValue().toString()) }.getOrNull()
                                if (media.get() != null && rejectedScript.get() && (snapshot?.optInt("inaccessibleFrames") ?: 0) > 0) {
                                    val request = media.get()!!
                                    check(request.url.host == "localhost")
                                    check(request.requestHeaders.entries.any { it.key.equals("Range", true) && it.value.startsWith("bytes=") })
                                    check(request.requestHeaders.entries.any { it.key.equals("Referer", true) && it.value.contains("localhost:") })
                                    // No document-start bridge and inaccessible child: the media cannot
                                    // have been discovered through its DOM/XHR hooks in the parent.
                                    check(snapshot!!.optJSONArray("urls")?.length() == 0)
                                    check(snapshot.getJSONArray("frames").length() == 1)
                                    break
                                }
                                delay(100)
                            }
                        }
                    } finally {
                        web.stopLoading()
                        web.webViewClient = WebViewClient()
                        web.destroy()
                    }
                }
                checkCompatibilityCrossOriginRange()
                // A parent-only old-provider hook cannot see this cross-origin, extensionless,
                // no-Range early XHR. Probe the frame separately, preserving the original embedding.
                val baseline=WebView(context)
                try {
                    baseline.settings.javaScriptEnabled=true
                    org.kazumi.tv.rules.HeadlessWebViewport.prepare(baseline)
                    baseline.loadUrl(base+"/no-range-parent")
                    withTimeout(5000) {
                        while(true) {
                            val raw=suspendCancellableCoroutine<String> { continuation -> baseline.evaluateJavascript(MediaDiscoveryScript.poll) { if(continuation.isActive)continuation.resume(it) } }
                            val snapshot=runCatching { JSONObject(JSONTokener(raw).nextValue().toString()) }.getOrNull()
                            if((snapshot?.optInt("inaccessibleFrames") ?: 0)>0) {
                                check(snapshot!!.getJSONArray("urls").length()==0)
                                val frames=snapshot.getJSONArray("frames")
                                val tracker=(0 until frames.length()).map { frames.getJSONObject(it) }.first { it.getString("url").endsWith("/tracker") }
                                check(!tracker.optBoolean("playerLike")) { "Tiny advertising frame became a player fallback" }
                                val player=(0 until frames.length()).map { frames.getJSONObject(it) }.firstOrNull { it.getString("url").endsWith("/no-range-child") }
                                if(player==null||!player.optBoolean("crossOrigin")) { delay(100);continue }
                                check(player.optBoolean("playerLike")) { "Responsive player has no usable headless viewport" }
                                break
                            }
                            delay(100)
                        }
                    }
                } finally { baseline.stopLoading();baseline.destroy() }
                val fallbackEvents=mutableListOf<String>()
                val fallback=WebMediaResolver(context,9000,diagnostic={fallbackEvents.add(it)},forceCompatibility=true)
                    .resolve(base+"/no-range-parent",org.kazumi.tv.rules.SourceRule(JSONObject().put("name","iframe-fixture").put("baseURL",base)),"fixture")
                check(fallback.url=="http://localhost:${server.localPort}/manifest")
                check(fallback.headers.entries.any { it.key.equals("Referer",true)&&it.value.endsWith("/no-range-child") })
                check(fallbackEvents.count { it.startsWith("iframe_fallback") }==1)
                // Both the ad and the player carry valid media data, and neither JS player
                // runs. Only the visible player may supply a candidate without a legacy flag.
                val configured=WebMediaResolver(context,9000,forceCompatibility=true)
                    .resolve(base+"/broken-player-parent",org.kazumi.tv.rules.SourceRule(JSONObject().put("name","broken-bundle-fixture").put("baseURL",base)),"fixture")
                check(configured.url=="http://localhost:${server.localPort}/manifest.m3u8") { "Player query data was missed or a tiny or hidden ad became media" }
                check(configured.headers.entries.any { it.key.equals("Referer",true)&&it.value.contains("/broken-player?url=") })
                val recoveryEvents=mutableListOf<String>()
                val recovered=WebMediaResolver(context,9000,diagnostic={recoveryEvents.add(it)},forceCompatibility=true)
                    .resolve(base+"/bad-frame-parent",org.kazumi.tv.rules.SourceRule(JSONObject().put("name","bad-frame-fixture").put("baseURL",base)),"fixture")
                check(recovered.url=="http://localhost:${server.localPort}/manifest")
                check(recoveryEvents.count { it.startsWith("iframe_fallback") }==2)
                check(recoveryEvents.any { it.startsWith("iframe_load_failed")&&it.contains("HTTP 404") })
                // Some real players reject top-level navigation. The speculative page may
                // redirect, but must not cancel a delayed request in the original iframe.
                val embeddedEvents=mutableListOf<String>()
                val embeddedStart=android.os.SystemClock.elapsedRealtime()
                val embedded=WebMediaResolver(context,18000,diagnostic={embeddedEvents.add(it)},forceCompatibility=true)
                    .resolve(base+"/embedded-parent",org.kazumi.tv.rules.SourceRule(JSONObject().put("name","embedding-fixture").put("baseURL",base)),"fixture")
                check(embedded.url=="http://localhost:${server.localPort}/delayed-embedded.m3u8")
                check(android.os.SystemClock.elapsedRealtime()-embeddedStart>=5000)
                check(redirectRequests.get()>0&&embeddedEvents.any { it.startsWith("iframe_fallback") }) { "redirecting candidate was not exercised" }
                check(embedded.headers.entries.any { it.key.equals("Referer",true)&&it.value.endsWith("/embedded-child") }) { "original iframe Referer was replaced by candidate page" }
                check(embeddedEvents.count { it.startsWith("web_released") }==2) { "both discovery pages must be released after success" }
                val contextEvents=mutableListOf<String>()
                val contextual=WebMediaResolver(context,18000,diagnostic={contextEvents.add(it)},forceCompatibility=true)
                    .resolve(base+"/context-parent",org.kazumi.tv.rules.SourceRule(JSONObject().put("name","context-fixture").put("baseURL",base)),"fixture")
                check(contextual.url==base+"/context-manifest.m3u8")
                check(contextEvents.any { it.startsWith("candidate=media")&&it.contains("HTTP 403") }) { "wrong-context media probe did not fail first" }
                check(wrongContextRequests.get()>0&&rightContextRequests.get()>0)
                check(contextual.headers.entries.any { it.key.equals("Referer",true)&&it.value.endsWith("/context-child") }) { "later valid request context was deduplicated or overwritten" }
                check(contextEvents.any { it.startsWith("iframe_fallback") })
                suspend fun challengeCase(path:String,expected:String) {
                    val events=mutableListOf<String>()
                    val started=android.os.SystemClock.elapsedRealtime()
                    val resolver=WebMediaResolver(context,7000,diagnostic={events.add(it)},forceCompatibility=true)
                    val rule=org.kazumi.tv.rules.SourceRule(JSONObject().put("name","challenge-discovery-fixture").put("baseURL",base))
                    val failure=try {
                        val result=resolver.resolve(base+path,rule,"fixture")
                        check(expected=="media"&&result.url==base+"/manifest.m3u8") { "unexpected challenge resolution" }
                        null
                    } catch(error:org.kazumi.tv.rules.SourceVerificationRequired) { error }
                    catch(error:org.kazumi.tv.playback.MediaResolutionFailure) { error }
                    check(events.any { it.startsWith("candidate=media")&&it.contains("HTTP 403") })
                    check(events.any { it.startsWith("iframe_challenge ") }) { "candidate challenge was never observed" }
                    when(expected) {
                        "challenge" -> {
                            check(failure is org.kazumi.tv.rules.SourceVerificationRequired) { "old probe failure hid the active challenge" }
                            check(failure.pageUrl.endsWith("/challenge-child"))
                            check(android.os.SystemClock.elapsedRealtime()-started>=6500) { "candidate challenge prematurely stopped original discovery" }
                        }
                        "media" -> check(failure==null) { "candidate challenge blocked later original media" }
                        "probe" -> {
                            check(failure is org.kazumi.tv.playback.MediaResolutionFailure&&failure.message.orEmpty().contains("HTTP 403")) { "candidate retained a challenge after navigation" }
                            check(events.any { it.startsWith("iframe_challenge_cleared") })
                        }
                    }
                    check(events.count { it.startsWith("web_released") }==2)
                }
                challengeCase("/challenge-parent","challenge")
                challengeCase("/challenge-delay-parent","media")
                challengeCase("/challenge-redirect-parent","probe")
                // Cancellation after the secondary page starts owns both lifetimes.
                val cancelEvents=mutableListOf<String>()
                val candidateStarted=CompletableDeferred<Unit>()
                val pending=launch {
                    WebMediaResolver(context,18000,diagnostic={ event ->
                        cancelEvents.add(event)
                        if(event.startsWith("iframe_fallback"))candidateStarted.complete(Unit)
                    },forceCompatibility=true).resolve(base+"/cancel-parent",
                        org.kazumi.tv.rules.SourceRule(JSONObject().put("name","cancel-fixture").put("baseURL",base)),"fixture")
                }
                try { withTimeout(8000) { candidateStarted.await() };delay(100) }
                finally { pending.cancelAndJoin() }
                check(cancelEvents.count { it.startsWith("web_released") }==2) { "cancellation leaked a discovery page" }
                val noisy=WebMediaResolver(context,9000,forceCompatibility=true)
                    .resolve(base+"/noise-parent",org.kazumi.tv.rules.SourceRule(JSONObject().put("name","noise-fixture").put("baseURL",base)),"fixture")
                check(noisy.url==base+"/manifest") { "Speculative API traffic starved the delayed typed media candidate" }
                val verificationRule=org.kazumi.tv.rules.SourceRule(JSONObject().put("name","viewport-verification").put("baseURL",base)
                    .put("antiCrawlerConfig",JSONObject().put("enabled",true).put("captchaType",2).put("captchaButton","//*[@id='verify']")))
                val viewportEvents=mutableListOf<String>()
                check(org.kazumi.tv.rules.AutomaticVerification.run(context,verificationRule,base+"/viewport-verification",diagnostic={viewportEvents.add(it)})) {
                    "Headless verification did not receive a usable viewport"
                }
                check(viewportEvents.any { it.startsWith("web_viewport width=") })
                checkPage("/late", false) // Force polling even on a modern provider.
                "candidate_challenge_priority=PASS candidate_challenge_late_media=PASS stale_challenge_navigation=PASS same_media_request_context=PASS " + if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                    checkPage("/early", true)
                    checkPage("/parent", true)
                    "compatibility=PASS cross_origin_range_compat=PASS iframe_no_range_fallback=PASS responsive_viewport=PASS failed_iframe_recovery=PASS retained_embedding_delayed_media=PASS dual_page_cancel_release=PASS broken_bundle_media_parameter=PASS speculative_noise_budget=PASS headless_verification_viewport=PASS dynamic_iframe=PASS script_range_rejected=PASS document_start_early_xhr=PASS cross_origin_frame=PASS"
                } else "compatibility=PASS cross_origin_range_compat=PASS iframe_no_range_fallback=PASS responsive_viewport=PASS failed_iframe_recovery=PASS retained_embedding_delayed_media=PASS dual_page_cancel_release=PASS broken_bundle_media_parameter=PASS speculative_noise_budget=PASS headless_verification_viewport=PASS dynamic_iframe=PASS script_range_rejected=PASS document_start=SKIP unsupported_provider"
            }
        } finally {
            server.close()
            acceptor.join(1000)
        }
    }
}
