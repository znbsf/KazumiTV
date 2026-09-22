package org.kazumi.tv

import android.app.Instrumentation
import android.os.Bundle
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import kotlinx.coroutines.*
import org.json.JSONObject
import org.json.JSONTokener
import org.kazumi.tv.rules.*

/** Local page handlers only; no real CAPTCHA is read or submitted. */
object LegacyMacCmsVerificationRegression {
    fun run(test: Instrumentation) = runBlocking {
        for (mode in listOf("legacy", "duplicate-input", "duplicate-button", "non-mac", "configured", "foreign-image", "disabled", "wrong-type")) {
            withContext(Dispatchers.Main) {
                val web = WebView(test.targetContext)
                val config = JSONObject().put("enabled", true).put("captchaType", 1)
                    .put("captchaInput", "//*[@id='configured']").put("captchaButton", "//*[@id='missing-button']")
                    .put("captchaImage", "//*[@id='missing-image']")
                if (mode == "disabled") config.put("enabled", false)
                if (mode == "wrong-type") config.put("captchaType", 2)
                val rule = SourceRule(JSONObject().put("name", "legacy controls fixture")
                    .put("baseURL", "https://fixture.invalid/").put("antiCrawlerConfig", config))
                suspend fun evaluate(script: String) = VerificationSession.evaluate(web, script)
                suspend fun snapshot() = JSONObject(JSONTokener(evaluate(VerificationScript.poll(rule))).nextValue().toString())
                try {
                    VerificationSession.configure(web, rule)
                    web.webViewClient = object : WebViewClient() {
                        override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse {
                            val pixel = android.util.Base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aQ1cAAAAASUVORK5CYII=", android.util.Base64.DEFAULT)
                            return WebResourceResponse("image/png", null, pixel.inputStream())
                        }
                    }
                    // Every image request is intercepted locally, including the rejected foreign-origin fixture.
                    web.loadDataWithBaseURL("https://fixture.invalid/", fixture(mode), "text/html", "UTF-8", null)
                    // A fresh WebView's about:blank is already complete before loadData commits.
                    withTimeout(8000) {
                        while (evaluate("document.readyState==='complete'&&typeof window.focusCount==='number'&&typeof window.submitCount==='number'&&!!document.getElementById('code')&&!!document.getElementById('submit')") != "true") delay(50)
                    }
                    var state = snapshot()
                    val eligible = mode in listOf("legacy", "foreign-image")
                    check(state.optBoolean("fallbackAvailable") == eligible) {
                        "eligibility mode=$mode expected=$eligible ready=${state.optBoolean("ready")} fallback=${state.optBoolean("fallbackAvailable")} challenge=${state.optBoolean("challenge")} failed=${state.optBoolean("failed")} done=${state.optBoolean("done")}"
                    }
                    if (eligible) {
                        check(state.optBoolean("challenge") && !state.optBoolean("done"))
                        state = snapshot()
                        val actualFocusCount = evaluate("window.focusCount")
                        val actualImageCount = evaluate("document.querySelectorAll('img.mac_verify_img').length")
                        check(actualFocusCount == "1") { "focus count=$actualFocusCount image count=$actualImageCount mode=$mode" }
                        check(actualImageCount == "1") { "image count=$actualImageCount focus count=$actualFocusCount mode=$mode" }
                        check(state.optString("image").isNotEmpty() == (mode == "legacy")) { "image origin gate" }
                        check(!state.optBoolean("hasInput"))
                        check(evaluate(VerificationScript.submit(rule, "")) == "false")
                        check(evaluate("window.submitCount") == "0")
                        // A supplied human code reaches the existing handler, which clears the rejected input.
                        check(evaluate(VerificationScript.submit(rule, "fixture-wrong")) == "true")
                        check(evaluate("window.received==='fixture-wrong'") == "true")
                        check(evaluate("window.submitCount") == "1")
                        state = snapshot()
                        check(!state.optBoolean("hasInput") && !state.optBoolean("done") && state.optBoolean("challenge"))
                        val progress = VerificationProgress()
                        repeat(4) { check(!progress.observe(state)) }
                        // Empty native input preserves text manually entered in the webpage.
                        evaluate("document.querySelector('input[name=verify]').value='fixture-manual'")
                        check(snapshot().optBoolean("hasInput"))
                        check(evaluate(VerificationScript.submit(rule, "")) == "true")
                        check(evaluate("window.received==='fixture-manual'&&window.submitCount===2") == "true")
                    } else {
                        check(evaluate("window.focusCount") == "0")
                        check(evaluate(VerificationScript.submit(rule, "fixture-wrong")) == "false")
                        check(evaluate("window.submitCount") == "0")
                    }
                    test.sendStatus(0, Bundle().apply { putString("stream", "legacy-mac-cms-controls: $mode=OK\n") })
                } catch (failure: Exception) {
                    val state = runCatching { snapshot() }.getOrNull()
                    val focusCount = runCatching { evaluate("window.focusCount") }.getOrDefault("unavailable")
                    val imageCount = runCatching { evaluate("document.querySelectorAll('img.mac_verify_img').length") }.getOrDefault("unavailable")
                    test.sendStatus(0, Bundle().apply {
                        putString("stream", "legacy-mac-cms-controls: failure mode=$mode focusCount=$focusCount imageCount=$imageCount ready=${state?.optBoolean("ready")} fallback=${state?.optBoolean("fallbackAvailable")} challenge=${state?.optBoolean("challenge")} failed=${state?.optBoolean("failed")} done=${state?.optBoolean("done")} hasInput=${state?.optBoolean("hasInput")}\n")
                    })
                    throw failure
                } finally { web.stopLoading(); web.destroy() }
            }
        }
    }

    private fun fixture(mode: String): String {
        val extra = when (mode) {
            "duplicate-input" -> "<input type='text' name='verify'>"
            "duplicate-button" -> "<input type='button' class='verify_submit'>"
            "configured" -> "<input id='configured'>"
            else -> ""
        }
        return """
          <html><head><title>Fixture</title></head><body>
          <input id='code' type='text' name='verify' class='mac_verify'>
          <input id='submit' type='button' class='verify_submit' value='Submit'>$extra
          <script>
          var maccms={},focusCount=0,submitCount=0,received='';
          ${if (mode != "non-mac") "var MAC={Verify:{Init:function(){},Refresh:function(){}}};" else ""}
          document.getElementById('code').addEventListener('focus',function(){
            if(document.querySelector('img.mac_verify_img'))return;
            focusCount++;this.className='';
            var img=document.createElement('img');img.className='mac_verify_img';
            img.src='${if (mode == "foreign-image") "https://foreign.invalid/" else "/"}fixture.png';
            this.parentNode.appendChild(img);
          });
          document.getElementById('submit').onclick=function(){
            submitCount++;received=document.getElementById('code').value;document.getElementById('code').value='';
          };
          </script></body></html>
        """.trimIndent()
    }
}
