package org.kazumi.tv

import android.app.Instrumentation
import android.os.Bundle
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlinx.coroutines.*
import org.json.JSONObject
import org.json.JSONTokener
import org.kazumi.tv.rules.*

/** Only a localhost fixture, with known input. Never reads or solves a real CAPTCHA. */
object MacCmsVerificationRegression {
    fun run(test:Instrumentation)=runBlocking {
        suspend fun exercise(mode:String,code:String,expectedError:Boolean=false) {
            val server=FixtureServer(mode)
            try { withContext(Dispatchers.Main) {
                val web=WebView(test.targetContext)
                val rule=SourceRule(JSONObject().put("name","compat fixture").put("baseURL",server.url)
                    .put("antiCrawlerConfig",JSONObject().put("enabled",true).put("captchaType",1)
                        .put("captchaDetectValue","//*[@id='challenge']").put("captchaInput","//*[@id='code']")
                        .put("captchaButton","//*[@id='verify']").put("captchaImage","//*[@id='image']")))
                suspend fun evaluate(script:String)=VerificationSession.evaluate(web,script)
                suspend fun snapshot():JSONObject=JSONObject(JSONTokener(evaluate(VerificationScript.poll(rule))).nextValue().toString())
                suspend fun awaitSnapshot(predicate:(JSONObject)->Boolean):JSONObject=withTimeout(14000) {
                    var state=snapshot()
                    while(!predicate(state)) { delay(100);state=snapshot() }
                    state
                }
                try {
                    VerificationSession.configure(web,rule);web.webViewClient=WebViewClient()
                    web.loadUrl(server.url+"/fixture")
                    val initial=awaitSnapshot { it.optBoolean("ready")&&it.optBoolean("challenge") }
                    val fallback=mode=="legacy"
                    check(initial.optBoolean("fallbackAvailable")==fallback) { "unexpected fallback eligibility $mode" }
                    check(!initial.optBoolean("hasInput")&&!initial.optBoolean("done"))
                    // Model the user's own input in the webpage; empty native code must preserve it.
                    evaluate("document.getElementById('code').value=${JSONObject.quote(code)}")
                    check(snapshot().optBoolean("hasInput"))
                    check(evaluate(VerificationScript.submit(rule,""))=="true")
                    if(fallback) {
                        check(evaluate(VerificationScript.submit(rule,"duplicate"))=="false") { "pending request submitted twice" }
                        if(expectedError) {
                            val failed=awaitSnapshot { it.optString("submitError").isNotEmpty() }
                            check(failed.optBoolean("challenge")&&!failed.optBoolean("done")&&!failed.optBoolean("submitting"))
                            check(!failed.optBoolean("hasInput")) { "rejected code was not cleared" }
                            check(failed.optBoolean("serverRejected")==(code=="wrong")) { "transport/invalid JSON confused with server rejection" }
                            check(server.posts==1)
                            // A failed or timed-out request must allow the user to retry normally.
                            check(evaluate(VerificationScript.submit(rule,"ok"))=="true")
                        }
                        val clear=awaitSnapshot { it.optBoolean("ready")&&!it.optBoolean("challenge") }
                        check(!clear.optBoolean("done")) { "adapter fabricated success rather than server reload" }
                        check(server.verifiedReload) { "successful server verification was not followed by a cookie-backed reload" }
                        check(server.posts==if(expectedError)2 else 1)
                    } else {
                        delay(400)
                        check(server.posts==0) { "unsupported template used compatibility endpoint" }
                        check(snapshot().optBoolean("challenge"))
                    }
                    test.sendStatus(0,Bundle().apply { putString("stream","mac-cms-verification: $mode/$code error=$expectedError=OK\n") })
                } finally { web.stopLoading();web.destroy() }
            } } finally { server.close() }
        }
        exercise("legacy","ok")
        exercise("legacy","wrong",expectedError=true)
        exercise("legacy","timeout",expectedError=true)
        exercise("legacy","invalid",expectedError=true)
        exercise("unknown","ok")
        exercise("modern","ok")
        exercise("bound","ok")
        exercise("working-template","ok")
    }
    private class FixtureServer(private val mode:String) {
        private val server=java.net.ServerSocket(0,20,java.net.InetAddress.getByName("127.0.0.1"))
        val url="http://127.0.0.1:${server.localPort}"
        private val cookie="compat_fixture_${server.localPort}"
        @Volatile var posts=0
        @Volatile var verifiedReload=false
        init { Thread {
            while(!server.isClosed) {
                val socket=try { server.accept() } catch(_:Exception) { break }
                Thread { try { socket.use {
                    it.soTimeout=5000
                    val reader=it.getInputStream().bufferedReader();val request=reader.readLine().orEmpty()
                    val headers=mutableMapOf<String,String>()
                    while(true) { val line=reader.readLine()?:break;if(line.isEmpty())break
                        headers[line.substringBefore(':').lowercase()]=line.substringAfter(':').trim() }
                    val verified=headers["cookie"].orEmpty().contains("$cookie=ok")
                    var extra=""
                    val endpoint=request.startsWith("POST /index.php/ajax/verify_check?type=search&verify=")
                    val body=if(endpoint) {
                        posts++
                        Thread.sleep(300)
                        val success=request.substringBefore(" HTTP/").endsWith("verify=ok")
                        if(request.contains("verify=timeout"))Thread.sleep(9500)
                        if(success)extra="Set-Cookie: $cookie=ok; Path=/\r\n"
                        if(success)"{\"code\":1}" else if(request.contains("verify=invalid"))"{\"msg\":\"missing code\"}" else "{\"code\":0,\"msg\":\"not copied into app\"}"
                    } else if(request.startsWith("GET /template/"))"/* fixture bundle intentionally absent */"
                    else if(verified) { verifiedReload=true;"<html><body>verified fixture</body></html>" }
                    else fixture()
                    val bytes=body.toByteArray(Charsets.UTF_8)
                    it.getOutputStream().write(("HTTP/1.1 200 OK\r\nContent-Type: ${if(endpoint) "application/json" else "text/html"}; charset=utf-8\r\n$extra"+
                        "Content-Length: ${bytes.size}\r\nConnection: close\r\n\r\n").toByteArray()+bytes)
                } } catch(_:Exception) {} }.apply { isDaemon=true;start() }
            }
        }.apply { isDaemon=true;start() } }
        private fun fixture():String {
            // Fixed feature-probe stub tests both provider branches on either old or modern devices.
            val feature=if(mode=="modern")"return function(){return undefined;};" else "throw new SyntaxError('fixture unsupported');"
            val events=if(mode=="bound")"return {click:[{}]};" else "return undefined;"
            val template=if(mode=="unknown")"/unknown/" else "/template/dsn2/"
            val ec=if(mode=="working-template")"var EC={};" else ""
            return """<html><head><script>
                const ds_cms={path_tpl:'$template'};let maccms={path:''};$ec
                var RealFunction=Function;window.Function=function(source){
                    if(source==='var value={};return value.user?.name;'){$feature}
                    return RealFunction.apply(null,arguments);
                };
                window.jQuery={_data:function(){ $events }};
                </script><script src="/template/dsn2/static/js/script.js"></script></head><body>
                <div id="challenge"><input id="code" type="text" name="verify" class="input ds-verify">
                <img id="image" class="ds-verify-img" src="/image">
                <button id="verify" class="button verify-submit" data-type="search">verify</button></div>
                </body></html>"""
        }
        fun close(){server.close()}
    }
}
