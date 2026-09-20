package org.kazumi.tv.playback

import android.webkit.WebView
import androidx.webkit.ScriptHandler
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature

/** Feature support belongs to the installed provider, not the Android API level. */
object WebDiscoveryCapabilities {
    fun install(web: WebView, diagnostic: (String) -> Unit = {}): ScriptHandler? {
        return try {
            if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                // Player frames may live on unrelated hosts. This script has no native bridge,
                // credentials or privileged APIs; every emitted URL still needs an HTTP media probe.
                WebViewCompat.addDocumentStartJavaScript(web, MediaDiscoveryScript.poll, setOf("*")).also {
                    diagnostic("web_discovery mode=document_start")
                }
            } else {
                diagnostic("web_discovery mode=compatibility")
                null
            }
        } catch (_: RuntimeException) {
            // Some vendor providers advertise support but fail to register. Polling remains active.
            diagnostic("web_discovery mode=compatibility registration_failed")
            null
        }
    }
}
