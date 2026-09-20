package org.kazumi.tv.rules

import android.annotation.SuppressLint
import android.webkit.*
import kotlinx.coroutines.*
import org.json.*
import kotlin.coroutines.resume

/** Main-thread ownership for both visible and automatic verification WebViews. */
class VerificationWebLifetime(val web: WebView) {
    var released = false
        private set
    var failure: String? = null
        private set
    fun fail(message: String, rendererGone: Boolean = false) {
        failure = message
        if (rendererGone) release()
    }
    fun release() {
        if (released) return
        released = true
        runCatching { (web.parent as? android.view.ViewGroup)?.removeView(web) }
        runCatching { web.stopLoading() }
        runCatching { web.webViewClient = WebViewClient() }
        runCatching { web.webChromeClient = WebChromeClient() }
        runCatching { CookieManager.getInstance().flush() }
        runCatching { web.destroy() }
    }
}

/** UI owns the WebView and cancels this loop before destroying it. No credentials or page text are logged. */
object VerificationSession {
    @SuppressLint("SetJavaScriptEnabled")
    fun configure(web:WebView,rule:SourceRule) {
        web.settings.javaScriptEnabled=true
        web.settings.domStorageEnabled=true
        web.settings.allowFileAccess=false
        web.settings.allowContentAccess=false
        web.settings.userAgentString=rule.userAgent
        web.settings.mixedContentMode=WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
    }
    suspend fun evaluate(web:WebView,script:String):String = suspendCancellableCoroutine { continuation ->
        web.evaluateJavascript(script) { if(continuation.isActive)continuation.resume(it?:"null") }
    }
    suspend fun await(web:WebView,rule:SourceRule,progress:VerificationProgress=VerificationProgress(),failure:()->String?={null},onSnapshot:(JSONObject)->Unit={}) {
        while(currentCoroutineContext().isActive) {
            failure()?.let { throw IllegalStateException(it) }
            // A dead provider may never deliver evaluateJavascript's callback.
            val raw=withTimeoutOrNull(1500) { evaluate(web,VerificationScript.poll(rule)) }
            failure()?.let { throw IllegalStateException(it) }
            if(raw==null) { delay(100); continue }
            val snapshot=runCatching { JSONObject(JSONTokener(raw).nextValue().toString()) }.getOrNull()
            if(snapshot!=null) {
                onSnapshot(snapshot)
                if(progress.observe(snapshot)) { CookieManager.getInstance().flush(); return }
            }
            delay(400)
        }
    }
}
