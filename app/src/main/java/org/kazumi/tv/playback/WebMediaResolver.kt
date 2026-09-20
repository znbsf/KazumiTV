package org.kazumi.tv.playback

import android.annotation.SuppressLint
import android.content.Context
import android.webkit.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import org.kazumi.tv.rules.*
import org.kazumi.tv.data.AppHttp
import okhttp3.*
import org.json.*
import java.io.IOException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** One isolated WebView per attempt; dynamic ES5 discovery and bounded, cancellable probes. */
class WebMediaResolver(private val context: Context, private val timeoutMs: Long = 25000,
    private val diagnostic: (String) -> Unit = {}, private val forceCompatibility: Boolean = false,
    private val privateConsoleDiagnostic: ((JSONObject) -> Unit)? = null) {
    // Test-only opt-in sink. Never forward these records to the public diagnostic callback.
    private var privateConsoleCount = 0
    private fun capturePrivateConsole(message: ConsoleMessage) {
        val sink = privateConsoleDiagnostic ?: return
        if(message.messageLevel()!=ConsoleMessage.MessageLevel.ERROR||privateConsoleCount>=16)return
        privateConsoleCount++
        var source = message.sourceId().orEmpty().take(1024)
        var detail = message.message().orEmpty().take(3072)
        fun record() = JSONObject().put("sourceId",source).put("line",message.lineNumber())
            .put("level","ERROR").put("message",detail)
        var event=record()
        // Bound the serialized UTF-8 record, including escaped controls and multi-byte text.
        while(event.toString().toByteArray(Charsets.UTF_8).size>4096) {
            if(detail.length>=source.length)detail=detail.take(detail.length/2)
            else source=source.take(source.length/2)
            event=record()
        }
        runCatching { sink(event) } // Private debug-file failures cannot affect playback.
    }
    suspend fun resolve(pageUrl:String,rule:SourceRule,title:String):PlaybackRequest = try {
        resolveOnce(pageUrl,rule,title)
    } catch(challenge:SourceVerificationRequired) {
        if(!AutomaticVerification.run(context,rule,challenge.pageUrl))throw challenge
        resolveOnce(pageUrl,rule,title)
    }
    @SuppressLint("SetJavaScriptEnabled")
    private suspend fun resolveOnce(pageUrl: String, rule: SourceRule, title: String): PlaybackRequest = withContext(Dispatchers.Main) {
        SourceRule.httpUrl(pageUrl)
        val defaults = mapOf("Referer" to rule.referer, "User-Agent" to rule.userAgent)
        var lastProbe: MediaResolutionFailure? = null
        if (MediaAddress.isMedia(pageUrl)) return@withContext probe(PlaybackRequest(pageUrl,MediaRequestHeaders.forMedia(rule,rule.baseUrl),title))
        SoraniPlayback.resolveFromRule(pageUrl,rule,defaults,title)?.let {
            diagnostic("source_api resolved")
            return@withContext probe(it.copy(headers = MediaRequestHeaders.forMedia(rule,pageUrl,it.headers)))
        }
        // Some TV WebViews cannot execute modern site bundles even though player data is ordinary JSON.
        // A discovered address still has to pass the same HTTP/media probe as a WebView candidate.
        val sourcePage=try { withTimeoutOrNull(12000) { org.kazumi.tv.data.HttpText.pageAsync(pageUrl,headers=defaults) } }
            catch(cancelled:CancellationException) { throw cancelled } catch(_:Exception) { null }
        if(sourcePage!=null)SourcePageChecks.check(rule,sourcePage.body,sourcePage.url)
        val html=sourcePage?.takeIf { it.status in 200..299 }?.body
        diagnostic("page_metadata bytes=${html?.length ?: 0}")
        if(html!=null) {
            SourcePageChecks.check(rule,html,pageUrl)
            diagnostic("page_metadata direct=${PageMediaMetadata.extract(html).size} sorani=${SoraniPlayback.apiUrl(pageUrl,html)!=null}")
            SoraniPlayback.resolve(pageUrl,html,defaults,title)?.let { return@withContext probe(it.copy(headers = MediaRequestHeaders.forMedia(rule,pageUrl,it.headers))) }
            for(url in PageMediaMetadata.extract(html)) {
                try { return@withContext probe(PlaybackRequest(url,MediaRequestHeaders.forMedia(rule,sourcePage?.url ?: pageUrl),title)) }
                catch(cancelled:CancellationException) { throw cancelled }
                catch(failure:MediaResolutionFailure) { lastProbe=failure; diagnostic("metadata: ${failure.message}") }
            }
        }
        val candidates = Channel<PlaybackRequest>(24)
        val speculativeCandidates = Channel<PlaybackRequest>(8)
        val speculativeSeen = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
        val seen = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
        val fatal = AtomicReference<Exception?>(null)
        var scriptError = false
        var lastFrameSummary = ""
        data class Frame(val url:String,val referer:String,val depth:Int)
        val pendingFrames=java.util.ArrayDeque<Frame>()
        val visitedFrames=mutableSetOf(pageUrl)
        val queuedFrames=mutableSetOf<String>()
        var currentPage=pageUrl
        var currentDepth=0
        var navigation=0
        var followedFrames=0
        var frameFailed=false
        var lastFrameFailure:MediaResolutionFailure?=null
        var navigationStarted=android.os.SystemClock.elapsedRealtime()
        val frameWaitMs=(timeoutMs/4).coerceIn(2000,4000)
        val web = try { WebView(context) } catch (_: RuntimeException) {
            candidates.close()
            speculativeCandidates.close()
            throw MediaResolutionFailure("网页初始化", "WebView 无法启动，请检查系统 WebView 后重试")
        }
        fun offer(url: String, headers: Map<String,String>, speculative: Boolean = false) {
            val dedup = if(speculative) speculativeSeen else seen
            val limit = if(speculative) 8 else 24
            val queue = if(speculative) speculativeCandidates else candidates
            if (runCatching { SourceRule.httpUrl(url) }.isSuccess && dedup.size < limit && dedup.add(url))
                queue.trySend(PlaybackRequest(url,MediaRequestHeaders.forMedia(rule,pageUrl,headers),title))
        }
        var polling: Job? = null
        var startScript: androidx.webkit.ScriptHandler? = null
        var destroyed = false
        fun destroyWeb() {
            if (destroyed) return
            destroyed = true
            polling?.cancel()
            runCatching { startScript?.remove() }
            runCatching { web.stopLoading() }
            runCatching { web.webViewClient = WebViewClient(); web.webChromeClient = WebChromeClient() }
            runCatching { web.destroy() }
        }
        fun pageFailure(request:WebResourceRequest,failure:MediaResolutionFailure) {
            if(destroyed||!request.isForMainFrame)return
            if(currentDepth==0)fatal.set(failure)
            else if(request.url.toString()==currentPage) {
                // A promoted iframe is only one discovery candidate. Keep sibling fallbacks.
                frameFailed=true
                lastFrameFailure=failure
                diagnostic("iframe_load_failed depth=$currentDepth attempt=$followedFrames ${failure.message}")
            }
        }
        try {
            web.settings.javaScriptEnabled = true
            web.settings.domStorageEnabled = true
            web.settings.allowFileAccess = false
            web.settings.allowContentAccess = false
            web.settings.mediaPlaybackRequiresUserGesture = false
            web.settings.userAgentString = rule.userAgent
            web.settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            HeadlessWebViewport.prepare(web,diagnostic)
            web.webChromeClient = object : WebChromeClient() {
                override fun onConsoleMessage(message: ConsoleMessage): Boolean {
                    capturePrivateConsole(message)
                    if (message.messageLevel() == ConsoleMessage.MessageLevel.ERROR &&
                        (message.message().contains("SyntaxError") || message.message().contains("Unexpected token"))) {
                        if(!scriptError)diagnostic("script_syntax_error line=${message.lineNumber()} host=${runCatching { java.net.URI(message.sourceId()).host }.getOrNull().orEmpty()}")
                        scriptError = true
                    }
                    return true // Do not copy remote console text, URLs or tokens into application logs.
                }
            }
            web.webViewClient = object : WebViewClient() {
                override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                    // Best-effort early hook on providers without document-start support.
                    // Polling still installs it if this callback precedes the new document.
                    if (!destroyed) {
                        if(url!=null&&runCatching { SourceRule.httpUrl(url) }.isSuccess)currentPage=url
                        view.evaluateJavascript(MediaDiscoveryScript.poll, null)
                    }
                }
                override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                    fatal.set(MediaResolutionFailure("网页渲染", "WebView 进程已退出，请重试或更换来源"))
                    destroyWeb()
                    return true
                }
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = request.url.scheme !in listOf("http","https")
                override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                    pageFailure(request,MediaResolutionFailure("网页加载", "连接或证书错误（${error.errorCode}）"))
                }
                override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                    pageFailure(request,MediaResolutionFailure("网页加载", "HTTP ${response.statusCode}"))
                }
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                    if(isMediaCandidate(request.url.toString(), request.requestHeaders)) {
                        val headers = request.requestHeaders.filterKeys { it.equals("Referer",true)||it.equals("User-Agent",true)||it.equals("Origin",true) }.toMutableMap()
                        if(headers.keys.none { it.equals("Referer",true) }) headers["Referer"] = currentPage
                        if(headers.keys.none { it.equals("User-Agent",true) }) headers["User-Agent"] = rule.userAgent
                        offer(request.url.toString(),headers)
                    }
                    return null
                }
            }
            startScript = if(forceCompatibility)null else WebDiscoveryCapabilities.install(web, diagnostic)
            if(forceCompatibility)diagnostic("web_discovery mode=compatibility forced")
            web.loadUrl(pageUrl,mapOf("Referer" to rule.referer))
            polling = launch {
                while(isActive && !destroyed) {
                    val snapshotNavigation=navigation
                    web.evaluateJavascript(MediaDiscoveryScript.poll) { raw ->
                        if(snapshotNavigation!=navigation||destroyed)return@evaluateJavascript
                        runCatching {
                            val snapshot = JSONObject(JSONTokener(raw).nextValue().toString())
                            val frameSummary = "frames=${snapshot.optJSONArray("frames")?.length() ?: 0} inaccessible=${snapshot.optInt("inaccessibleFrames")} candidates=${snapshot.optJSONArray("urls")?.length() ?: 0}"
                            if (frameSummary != lastFrameSummary) {
                                lastFrameSummary = frameSummary
                                diagnostic("web_snapshot $frameSummary")
                            }
                            if(SourcePageChecks.looksLikeChallengeTitle(snapshot.optString("title"))) fatal.set(SourceVerificationRequired(currentPage))
                            val urls = snapshot.optJSONArray("urls") ?: JSONArray()
                            for(i in 0 until urls.length()) {
                                val media = urls.getJSONObject(i)
                                offer(media.getString("url"), mapOf("Referer" to media.optString("referer",pageUrl),"User-Agent" to rule.userAgent))
                            }
                            val guesses = snapshot.optJSONArray("speculative") ?: JSONArray()
                            for(i in 0 until guesses.length()) {
                                val media = guesses.getJSONObject(i)
                                offer(media.getString("url"), mapOf("Referer" to media.optString("referer",currentPage),"User-Agent" to rule.userAgent), speculative=true)
                            }
                            // Old providers cannot install hooks inside unrelated-origin frames.
                            // Follow only visible player containers, one WebView, at most three pages
                            // and two nesting levels. This remains discovery, never proof of playback.
                            if(startScript==null&&currentDepth<2) {
                                val frames=snapshot.optJSONArray("frames") ?: JSONArray()
                                for(i in 0 until frames.length()) {
                                    val frame=frames.getJSONObject(i)
                                    val url=frame.optString("url")
                                    if(frame.optBoolean("crossOrigin")&&frame.optBoolean("playerLike")&&queuedFrames.size<8&&
                                        url !in visitedFrames&&runCatching { SourceRule.httpUrl(url) }.isSuccess&&queuedFrames.add(url))
                                        pendingFrames.add(Frame(url,frame.optString("referer",currentPage),currentDepth+1))
                                }
                            }
                            // Player configuration may already carry the HTTP media address even
                            // when its JS bundle cannot parse on an old provider. Decode data only;
                            // never evaluate site scripts or accept arbitrary non-media parameters.
                            val configuredFrames = snapshot.optJSONArray("frames") ?: JSONArray()
                            for(i in 0 until configuredFrames.length()) {
                                val frame = configuredFrames.getJSONObject(i)
                                if(rule.json.optBoolean("useLegacyParser")||frame.optBoolean("playerLike")) {
                                    LegacyMediaAddress.extract(frame.getString("url")).forEach { url ->
                                        offer(url, mapOf("Referer" to frame.getString("url"), "User-Agent" to rule.userAgent))
                                    }
                                }
                            }
                        }
                    }
                    delay(300)
                }
            }
            val resolved = withTimeoutOrNull(timeoutMs) {
                var found: PlaybackRequest? = null
                while(found == null) {
                    fatal.get()?.let { throw it }
                    // Typed/Range discoveries retain their own budget and always win the next
                    // probe. Resource Timing guesses get at most eight probes per attempt.
                    val confirmed = candidates.tryReceive().getOrNull()
                        ?: withTimeoutOrNull(300) { candidates.receive() }
                    // Once the frame wait expires, a bounded iframe navigation takes priority
                    // over more untyped API guesses. A failed promoted page skips its wait.
                    if(confirmed==null&&startScript==null&&followedFrames<3&&pendingFrames.isNotEmpty()&&
                        (frameFailed||android.os.SystemClock.elapsedRealtime()-navigationStarted>=frameWaitMs)) {
                        val frame=pendingFrames.removeFirst()
                        if(visitedFrames.add(frame.url)) {
                            followedFrames++;currentDepth=frame.depth;currentPage=frame.url;navigation++
                            frameFailed=false
                            navigationStarted=android.os.SystemClock.elapsedRealtime()
                            web.stopLoading()
                            CookieManager.getInstance().flush()
                            diagnostic("iframe_fallback depth=$currentDepth attempt=$followedFrames")
                            web.loadUrl(frame.url,mapOf("Referer" to frame.referer))
                        }
                        continue
                    }
                    val candidate = confirmed ?: speculativeCandidates.tryReceive().getOrNull()
                    val speculative = confirmed == null
                    if(candidate==null)continue
                    try { found = probe(candidate) }
                    catch(cancelled: CancellationException) { throw cancelled }
                    catch(failure: MediaResolutionFailure) {
                        if(!speculative) lastProbe = failure
                        diagnostic("candidate=${if(speculative) "speculative" else "media"} host=${runCatching { java.net.URI(candidate.url).host }.getOrDefault("unknown")} ${failure.message}")
                    }
                }
                found
            }
            // A third-party analytics SyntaxError is not proof the player failed to run.
            // Keep it in diagnostics; report the observed discovery/probe failure instead.
            resolved ?: throw (fatal.get() ?: lastProbe ?: lastFrameFailure ?:
                MediaResolutionFailure("媒体发现", "等待超时，未找到可用媒体（候选 ${seen.size}）"))
        } finally {
            destroyWeb()
            candidates.close()
            speculativeCandidates.close()
        }
    }
    companion object {
        /** Mirrors upstream's old-provider Range fallback; every candidate still needs a media probe. */
        fun isMediaCandidate(url: String, headers: Map<String, String>): Boolean {
            if (MediaAddress.isMedia(url)) return true
            val uri = runCatching { java.net.URI(SourceRule.httpUrl(url)) }.getOrNull() ?: return false
            val range = headers.entries.firstOrNull { it.key.equals("Range", true) }?.value ?: return false
            if (!range.trimStart().startsWith("bytes=", true)) return false
            val path = uri.path.orEmpty().lowercase()
            return listOf(".js", ".css", ".html", ".htm", ".json", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".woff", ".woff2", ".wasm")
                .none { path.endsWith(it) }
        }
    }
    private suspend fun probe(request: PlaybackRequest): PlaybackRequest = suspendCancellableCoroutine { continuation ->
        val builder = Request.Builder().url(request.url).header("Range","bytes=0-1023")
        request.headers.forEach { (name,value) -> builder.header(name,value) }
        val call = AppHttp.client.newBuilder().callTimeout(5,TimeUnit.SECONDS).build().newCall(builder.build())
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                val reason = when(e) {
                    is java.net.UnknownHostException -> "DNS解析失败"
                    is javax.net.ssl.SSLException -> "TLS连接失败"
                    is java.net.SocketTimeoutException -> "连接或读取超时"
                    else -> "连接失败或超时"
                }
                if(continuation.isActive) continuation.resumeWithException(MediaResolutionFailure("媒体探测",reason))
            }
            override fun onResponse(call: Call, response: Response) {
                try {
                    val result = response.use {
                        if(!it.isSuccessful) throw MediaResolutionFailure("媒体探测","HTTP ${it.code}")
                        val body = it.body ?: throw MediaResolutionFailure("媒体探测","空响应")
                        val bytes = ByteArray(1024)
                        var count = 0
                        body.byteStream().use { stream ->
                            while(count < bytes.size) { val n = stream.read(bytes,count,bytes.size-count); if(n < 0) break; count += n }
                        }
                        val mime = MediaProbe.mime(bytes,count,body.contentType()?.toString().orEmpty().lowercase())
                            ?: throw MediaResolutionFailure("媒体探测","响应不是可识别的视频或播放清单")
                        request.copy(mimeType = mime)
                    }
                    if(continuation.isActive) continuation.resume(result)
                } catch(e: Exception) {
                    if(continuation.isActive) continuation.resumeWithException(if(e is MediaResolutionFailure) e else MediaResolutionFailure("媒体探测","读取失败"))
                }
            }
        })
    }
}
