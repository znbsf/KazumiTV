package org.kazumi.tv

import android.annotation.SuppressLint
import android.app.Instrumentation
import android.os.Bundle
import android.webkit.*
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import org.kazumi.tv.data.AppHttp
import org.kazumi.tv.playback.MediaProbe
import okhttp3.Request
import okhttp3.CookieJar
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.TimeUnit
import org.kazumi.tv.rules.HeadlessWebViewport
import org.kazumi.tv.rules.SourceRule
import java.io.File
import java.net.URI
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Diagnostic only: normal remote-page execution, then read two own DATA descriptors.
 * Does not replace Artplayer, decode data, invent a URL, or claim playback.
 * Optional probeComputed=true checks anonymous endpoint readability only, without
 * cookies, Referer or redirects; it does not validate production playback request context.
 * Dedicated WebView instance; old providers still share their normal browser profile.
 * Never clears cookies/storage, writes application preferences, or emits remote text/URLs.
 */
object AgeComputedMediaDiagnostic {
    @SuppressLint("SetJavaScriptEnabled")
    fun run(test:Instrumentation,args:Bundle):String=runBlocking {
        require(args.keySet().none { it.equals("url",true)||it.equals("iframeUrl",true) }) { "Direct URL arguments are not supported" }
        val external=checkNotNull(test.targetContext.getExternalFilesDir(null)).canonicalFile
        val relative=args.getString("inputRelativePath") ?: "age-media-private.json"
        require(relative.matches(Regex("[A-Za-z0-9_./-]{1,160}")) && relative.split('/').none { it==".."||it=="."||it.isEmpty() }) { "Invalid diagnostic relative path" }
        val input=File(external,relative).canonicalFile
        require(input.path.startsWith(external.path+File.separator) && input.name in setOf("media-private.json","age-media-private.json")) { "Input outside diagnostic boundary" }
        require(input.isFile && input.length() in 1..65536) { "Missing or oversized diagnostic input" }
        val frames=JSONObject(input.readText(Charsets.UTF_8)).optJSONArray("iframes") ?: error("No observed iframe list")
        require(frames.length() in 1..24) { "Invalid observed iframe count" }
        val accepted=(0 until frames.length()).mapNotNull { index ->
            val value=frames.optString(index)
            if(value.length !in 1..16384)return@mapNotNull null
            val uri=runCatching { URI(value) }.getOrNull() ?: return@mapNotNull null
            value.takeIf { uri.scheme.equals("https",true) && uri.host.equals("jx.wuzhoupai.com",true) &&
                uri.port in listOf(-1,443,8443) && uri.rawUserInfo==null }
        }.distinct()
        require(accepted.size==1) { "Expected one observed allowlisted iframe" }
        val frame=accepted.single()
        val episodeFile=File(input.parentFile,"episode_page-private.json").canonicalFile
        require(episodeFile.path.startsWith(external.path+File.separator) && episodeFile.isFile && episodeFile.length() in 1..2_500_000) { "Missing or invalid episode diagnostic" }
        val referer=JSONObject(episodeFile.readText(Charsets.UTF_8)).optString("responseUrl")
        require(referer.length in 1..16384) { "Invalid episode referer length" }
        val episodeUri=runCatching { URI(referer) }.getOrNull() ?: error("Invalid episode referer")
        require(episodeUri.host.equals("www.agedm.io",true) && episodeUri.rawUserInfo==null &&
            ((episodeUri.scheme.equals("https",true) && episodeUri.port in listOf(-1,443)) ||
             (episodeUri.scheme.equals("http",true) && episodeUri.port in listOf(-1,80)))) { "Episode referer outside observed boundary" }
        val rulesFile=File(external,"source-audit-rules.json").canonicalFile
        require(rulesFile.path.startsWith(external.path+File.separator) && rulesFile.isFile && rulesFile.length() in 1..2_000_000) { "Invalid fixed rules input" }
        val rules=JSONArray(rulesFile.readText(Charsets.UTF_8))
        require(rules.length() in 1..512)
        val rule=(0 until rules.length()).map { SourceRule(rules.getJSONObject(it)) }
            .singleOrNull { it.name.equals("AGE",true) } ?: error("Fixed AGE rule missing")
        val outputName="age-computed-media-${System.currentTimeMillis()}"
        val folder=File(File(external,"source-diagnosis"),outputName).canonicalFile
        require(folder.path.startsWith(external.path+File.separator)) { "Diagnostic output outside application directory" }
        check(folder.mkdirs())
        var web:WebView?=null
        var destroyed=false
        var consoleCount=0
        var blockedNavigations=0
        val consoleTypes=linkedSetOf<String>()
        val networkErrors=mutableListOf<Int>()
        fun safeError(value:String)=value.takeIf { it in setOf("SyntaxError","ReferenceError","TypeError","RangeError","SecurityError","Error") } ?: "Error"
        try {
            withContext(Dispatchers.Main) {
                val browser=WebView(test.targetContext)
                web=browser
                browser.settings.javaScriptEnabled=true
                browser.settings.domStorageEnabled=true
                browser.settings.allowFileAccess=false
                browser.settings.allowContentAccess=false
                browser.settings.userAgentString=rule.userAgent
                browser.settings.mediaPlaybackRequiresUserGesture=false
                browser.settings.mixedContentMode=WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
                HeadlessWebViewport.prepare(browser)
                browser.webChromeClient=object:WebChromeClient() {
                    override fun onConsoleMessage(message:ConsoleMessage):Boolean {
                        if(message.messageLevel()!=ConsoleMessage.MessageLevel.ERROR||consoleCount>=16)return true
                        consoleCount++
                        val full=message.message()
                        consoleTypes.add(listOf("SyntaxError","ReferenceError","TypeError","RangeError","SecurityError").firstOrNull { full.contains(it) } ?: "Error")
                        var source=message.sourceId().orEmpty().take(1024)
                        var body=full.take(3072)
                        fun record()=JSONObject().put("sourceId",source).put("message",body).put("line",message.lineNumber()).put("level","ERROR")
                        var data=record()
                        while(data.toString().toByteArray(Charsets.UTF_8).size>4096) {
                            if(body.length>=source.length)body=body.take(body.length/2) else source=source.take(source.length/2)
                            data=record()
                        }
                        File(folder,"console-private.jsonl").appendText(data.toString()+"\n",Charsets.UTF_8)
                        return true
                    }
                }
                browser.webViewClient=object:WebViewClient() {
                    override fun onReceivedError(view:WebView,request:WebResourceRequest,error:WebResourceError) {
                        if(request.isForMainFrame && networkErrors.size<16)networkErrors.add(error.errorCode)
                    }
                    override fun shouldOverrideUrlLoading(view:WebView,request:WebResourceRequest):Boolean {
                        // This diagnostic is scoped to the observed iframe, not an arbitrary URL bridge.
                        val uri=request.url
                        val blocked=uri.scheme!="https" || !uri.host.equals("jx.wuzhoupai.com",true) || uri.port !in listOf(-1,443,8443) || uri.userInfo!=null
                        if(blocked)blockedNavigations++
                        return blocked
                    }
                    override fun onRenderProcessGone(view:WebView,detail:RenderProcessGoneDetail):Boolean {
                        destroyed=true
                        runCatching { view.destroy() }
                        return true
                    }
                }
                browser.loadUrl(frame,mapOf("Referer" to referer))
            }
            delay(30_000)
            val snapshot=withContext(Dispatchers.Main) {
                if(destroyed)JSONObject().put("errorType","RendererGone") else {
                    val raw=withTimeoutOrNull(4000) {
                        suspendCancellableCoroutine<String> { continuation ->
                            checkNotNull(web).evaluateJavascript(DESCRIPTORS) { result -> if(continuation.isActive)continuation.resume(result ?: "null") }
                        }
                    }
                    if(raw==null)JSONObject().put("errorType","CallbackTimeout") else
                        runCatching { JSONObject(JSONTokener(raw).nextValue().toString()) }.getOrElse { JSONObject().put("errorType","InvalidSnapshot") }
                }
            }
            // Candidate values remain only in app-specific diagnostic storage, never stream output.
            File(folder,"candidate-private.json").writeText(snapshot.toString(),Charsets.UTF_8)
            val summary=JSONObject().put("diagnostic","age_computed_own_data").put("waitMs",30000)
            for(name in listOf("rootExists","rootData","rootObject","rootPlain","urlExists","urlData","urlString","http","mediaSuffix","rendererOptionPresent","matchesStrayUrl"))summary.put(name,snapshot.optBoolean(name))
            summary.put("length",snapshot.optInt("length")).put("candidateCount",if(snapshot.optBoolean("http")&&snapshot.optBoolean("mediaSuffix"))1 else 0)
                .put("httpCandidateCount",if(snapshot.optBoolean("http")&&snapshot.optInt("length") in 1..16384)1 else 0)
                .put("candidateCountDefinition","HTTP with recognized media suffix; httpCandidateCount does not require suffix")
                .put("errorType",snapshot.optString("errorType").let { if(it in setOf("RendererGone","CallbackTimeout","InvalidSnapshot",""))it else safeError(it) })
                .put("consoleCount",consoleCount).put("consoleErrorTypes",JSONArray(consoleTypes.toList()))
                .put("mainFrameErrorCodes",JSONArray(networkErrors)).put("blockedNavigations",blockedNavigations)
                .put("privateOutputDirectory","source-diagnosis/$outputName")
                .put("mediaProbePerformed",false).put("probePerformed",false).put("playbackValidated",false)
            if(args.getString("probeComputed")?.equals("true",true)==true) {
                val value=snapshot.optString("value")
                val ordinary=listOf("rootData","rootObject","rootPlain","urlData","urlString","http").all { snapshot.optBoolean(it) }
                val uri=runCatching { URI(value) }.getOrNull()
                val valid=ordinary && value.length in 1..16384 && uri?.scheme in listOf("http","https") &&
                    !uri?.host.isNullOrBlank() && uri?.rawUserInfo==null
                if(valid) {
                    summary.put("probePerformed",true).put("mediaProbePerformed",true)
                        .put("probeRequestPolicy","anonymous_no_cookies_no_referer_no_redirects")
                        .put("probeScope","anonymous_endpoint_readability_not_production_playback")
                    try {
                        val client=AppHttp.client.newBuilder().cookieJar(CookieJar.NO_COOKIES)
                            .followRedirects(false).followSslRedirects(false)
                            .callTimeout(5,TimeUnit.SECONDS).retryOnConnectionFailure(false).build()
                        val request=Request.Builder().url(value).header("User-Agent",rule.userAgent)
                            .header("Range","bytes=0-1023").build()
                        val probe=withTimeoutOrNull(5000) {
                            suspendCancellableCoroutine<JSONObject> { continuation ->
                              val call=client.newCall(request)
                              continuation.invokeOnCancellation { call.cancel() }
                              call.enqueue(object:Callback {
                                override fun onFailure(call:Call,error:IOException) {
                                  if(continuation.isActive)continuation.resumeWithException(error)
                                }
                                override fun onResponse(call:Call,response:Response) {
                                 try {
                                  val payload=response.use {
                                val result=JSONObject().put("probeStatus",response.code)
                                if(response.isSuccessful && response.body!=null) {
                                    val body=response.body!!
                                    val bytes=ByteArray(1024)
                                    var count=0
                                    body.byteStream().use { stream ->
                                        while(count<bytes.size) {
                                            val read=stream.read(bytes,count,bytes.size-count)
                                            if(read<0)break
                                            count+=read
                                        }
                                    }
                                    result.put("probeMime",MediaProbe.mime(bytes,count,body.contentType()?.toString().orEmpty().lowercase(java.util.Locale.ROOT)) ?: "")
                                } else result.put("probeMime","")
                                    result
                                  }
                                  if(continuation.isActive)continuation.resume(payload)
                                 } catch(error:Exception) {
                                  if(continuation.isActive)continuation.resumeWithException(error)
                                 }
                                }
                              })
                            }
                        }
                        if(probe==null)summary.put("probeErrorType","TimeoutCancellationException")
                        else {
                            summary.put("probeStatus",probe.getInt("probeStatus"))
                            summary.put("probeMime",probe.getString("probeMime"))
                        }
                    } catch(cancelled:CancellationException) { throw cancelled }
                    catch(error:Exception) { summary.put("probeErrorType",error.javaClass.simpleName) }
                } else summary.put("probeErrorType","IneligibleSnapshot")
            }
            File(folder,"summary.json").writeText(summary.toString(),Charsets.UTF_8)
            return@runBlocking summary.toString()
        } finally {
            withContext(NonCancellable+Dispatchers.Main) {
                web?.let { browser -> if(!destroyed) {
                    destroyed=true
                    runCatching { browser.stopLoading() }
                    runCatching { browser.webViewClient=WebViewClient();browser.webChromeClient=WebChromeClient() }
                    runCatching { browser.destroy() }
                } }
                web=null
            }
        }
    }

    private val DESCRIPTORS="""
        (function(){
          var result={rootExists:false,rootData:false,rootObject:false,rootPlain:false,
            urlExists:false,urlData:false,urlString:false,http:false,mediaSuffix:false,length:0,
            rendererOptionPresent:false,matchesStrayUrl:false};
          try {
            var own=Object.prototype.hasOwnProperty;
            var descriptor=Object.getOwnPropertyDescriptor(window,'stray');
            result.rootExists=!!descriptor;
            if(!descriptor)return JSON.stringify(result);
            result.rootData=own.call(descriptor,'value');
            if(!result.rootData)return JSON.stringify(result);
            var object=descriptor.value;
            result.rootObject=!!object&&typeof object==='object';
            if(!result.rootObject)return JSON.stringify(result);
            var prototype=Object.getPrototypeOf(object);
            result.rootPlain=prototype===null||prototype===Object.prototype;
            if(!result.rootPlain)return JSON.stringify(result);
            var field=Object.getOwnPropertyDescriptor(object,'url');
            result.urlExists=!!field;
            if(!field)return JSON.stringify(result);
            result.urlData=own.call(field,'value');
            if(!result.urlData)return JSON.stringify(result);
            result.urlString=typeof field.value==='string';
            if(!result.urlString)return JSON.stringify(result);
            var value=field.value;
            result.length=value.length;
            result.http=/^https?:\/\//i.test(value);
            result.mediaSuffix=/\.(m3u8|mp4|mpd|m4v|webm)(?:[?#]|$)/i.test(value);
            if(value.length<=16384)result.value=value;
            // Observe only data properties along the already-created renderer instance.
            // Accessor/inherited/missing layers remain unobservable; never call them.
            var ad=Object.getOwnPropertyDescriptor(object,'ad');
            if(ad&&own.call(ad,'value')&&ad.value&&typeof ad.value==='object') {
              var option=Object.getOwnPropertyDescriptor(ad.value,'option');
              if(option&&own.call(option,'value')&&option.value&&typeof option.value==='object') {
                var rendererUrl=Object.getOwnPropertyDescriptor(option.value,'url');
                if(rendererUrl&&own.call(rendererUrl,'value')&&typeof rendererUrl.value==='string') {
                  result.rendererOptionPresent=true;
                  result.matchesStrayUrl=rendererUrl.value===value;
                }
              }
            }
            return JSON.stringify(result);
          } catch(error) {result.errorType=error&&error.name||'Error';return JSON.stringify(result);}
        })();
    """.trimIndent()
}
