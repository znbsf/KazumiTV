package org.kazumi.tv

import android.app.Instrumentation
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlinx.coroutines.*
import org.json.JSONObject
import org.kazumi.tv.rules.*

object VerificationRegression {
    fun run(test:Instrumentation)=runBlocking {
        suspend fun exercise(type:Int,html:String,script:String="",submit:Boolean=false,shouldPass:Boolean=true) {
            val config=JSONObject().put("enabled",true).put("captchaType",type).put("captchaDetectType",1)
                .put("captchaDetectValue","//*[@id='challenge']").put("captchaButton","//*[@id='verify']")
                .put("captchaImage",if(type==1)"//*[@id='image']" else "").put("captchaInput","//*[@id='code']").put("captchaScript",script)
            val rule=SourceRule(JSONObject().put("name","fixture").put("baseURL","http://127.0.0.1").put("antiCrawlerConfig",config))
            withContext(Dispatchers.Main) {
                val web=WebView(test.targetContext)
                try {
                    VerificationSession.configure(web,rule);web.webViewClient=WebViewClient()
                    web.loadDataWithBaseURL("http://127.0.0.1/verification-test",html,"text/html","UTF-8",null)
                    var submitted=false
                    val progress=VerificationProgress()
                    val passed=withTimeoutOrNull(if(shouldPass)8000 else 2200) {
                        VerificationSession.await(web,rule,progress) { snapshot ->
                            if(submit&&!submitted&&snapshot.optString("image").isNotBlank()) {
                                submitted=true;progress.markAction()
                                web.evaluateJavascript(VerificationScript.submit(rule,"a'b+42"),null)
                            }
                        };true
                    } ?: false
                    check(passed==shouldPass) { "verification type=$type pass=$passed expected=$shouldPass" }
                    if(submit)check(submitted)
                } finally { web.stopLoading();web.destroy() }
            }
        }
        exercise(2,"""<html><body><div id="challenge"><button id="verify" onclick="setTimeout(function(){document.getElementById('challenge').remove()},200)">verify</button></div><p>result</p></body></html>""")
        exercise(3,"<html><body><div id='challenge'>wait</div><p>result</p></body></html>","setTimeout(function(){document.getElementById('challenge').remove();KazumiCaptcha.done()},200)")
        exercise(1,"""<html><body><div id="challenge"><img id="image" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jM1sAAAAASUVORK5CYII="><input id="code"><button id="verify" onclick="if(document.getElementById('code').value===&quot;a'b+42&quot;)document.getElementById('challenge').remove()">submit</button></div><p>result</p></body></html>""",submit=true)
        exercise(2,"<html><body><div id='challenge'><button id='verify'>no effect</button></div></body></html>",shouldPass=false)
        exercise(3,"<html><body><div id='challenge'>still blocked</div></body></html>","KazumiCaptcha.done()",shouldPass=false)
        exercise(3,"<html><body><p>result</p></body></html>","KazumiCaptcha.fail('test')",shouldPass=false)
        exercise(2,"<html><body></body></html>",shouldPass=false)
        // A successful action callback followed by a rate-limit page is not verification success.
        exercise(3,"<html><body><div id='challenge'>wait</div></body></html>",
            "setTimeout(function(){document.body.innerHTML=\"<div class='jump'><div class='tit'>系统提示</div><div>亲爱的用户：</div><div>请不要频繁操作，搜索时间间隔为3秒</div><div>页面自动关闭 等待时间：3</div></div>\";KazumiCaptcha.done()},200)",shouldPass=false)
        val activity=test.startActivitySync(android.content.Intent(test.targetContext,MainActivity::class.java).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
        val exited=java.util.concurrent.atomic.AtomicBoolean()
        var pointer:org.kazumi.tv.ui.VerificationWebView?=null
        try {
            withContext(Dispatchers.Main) {
                pointer=org.kazumi.tv.ui.VerificationWebView(activity).apply {
                    settings.javaScriptEnabled=true;webViewClient=WebViewClient();onExitPointer={ exited.set(true) }
                }
                activity.setContentView(pointer)
                pointer!!.loadDataWithBaseURL("http://127.0.0.1/pointer-test","<html><body style='margin:0'><button style='position:fixed;inset:0;width:100%;height:100%' onclick='window.pointerClicks=(window.pointerClicks||0)+1'>pointer target</button></body></html>","text/html","UTF-8",null)
            }
            withContext(Dispatchers.Main) {
                withTimeout(5000) { while(pointer!!.width==0||VerificationSession.evaluate(pointer!!,"document.readyState")!="\"complete\"")delay(100) }
                pointer!!.pointerEnabled=true;pointer!!.requestFocus()
            }
            test.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_DPAD_RIGHT)
            test.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_DPAD_CENTER)
            withContext(Dispatchers.Main) { withTimeout(4000) { while(VerificationSession.evaluate(pointer!!,"window.pointerClicks")!="1")delay(100) } }
            test.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
            check(exited.get()) { "back must exit pointer without leaving verification" }
        } finally { test.runOnMainSync { pointer?.destroy();activity.finish() } }
        // The exact POST, body and cookie must survive an automatic challenge and its retry.
        val server=ChallengeServer()
        try {
            val rule=SourceRule(JSONObject().put("name","cookie fixture").put("baseURL",server.url)
                .put("usePost",true).put("searchURL",server.url+"/search?wd=@keyword")
                .put("searchList","//a[@class='result']").put("searchName",".").put("searchResult",".")
                .put("antiCrawlerConfig",JSONObject().put("enabled",true).put("captchaType",2).put("captchaDetectType",1)
                    .put("captchaDetectValue","//*[@id='challenge']").put("captchaButton","//*[@id='verify']")))
            val results=RuleRepository(test.targetContext).search(rule,"fixture")
            check(results.single().title=="Fixture episode")
            check(server.successfulPost && server.sawBody)
        } finally { server.close() }
    }
    private class ChallengeServer {
        private val server=java.net.ServerSocket(0,20,java.net.InetAddress.getByName("127.0.0.1"))
        val url="http://127.0.0.1:${server.localPort}"
        @Volatile var successfulPost=false
        @Volatile var sawBody=false
        private val cookie="kazumi_fixture_${server.localPort}"
        init { Thread {
            while(!server.isClosed) {
                val socket=try { server.accept() } catch(_:Exception) { break }
                Thread { try { socket.use {
                    val reader=it.getInputStream().bufferedReader();val request=reader.readLine().orEmpty()
                    val headers=mutableMapOf<String,String>()
                    while(true) { val line=reader.readLine()?:break;if(line.isEmpty())break;headers[line.substringBefore(':').lowercase()]=line.substringAfter(':').trim() }
                    val size=headers["content-length"]?.toIntOrNull()?:0
                    val body=CharArray(size);var count=0;while(count<size) { val n=reader.read(body,count,size-count);if(n<0)break;count+=n }
                    if(String(body)=="wd=fixture")sawBody=true
                    val verified=headers["cookie"].orEmpty().contains("$cookie=ok")
                    if(verified&&request.startsWith("POST /search"))successfulPost=true
                    val html=if(verified)"<html><body><a class='result' href='/episode'>Fixture episode</a></body></html>"
                    else """<html><body><div id="challenge"><button id="verify" onclick="document.cookie='$cookie=ok; path=/';document.getElementById('challenge').remove()">verify</button></div><p>done</p></body></html>"""
                    val status=if(verified)"200 OK" else "403 Forbidden"
                    val bytes=html.toByteArray();it.getOutputStream().write(("HTTP/1.1 $status\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n").toByteArray()+bytes)
                } } catch(_:Exception) {} }.apply { isDaemon=true;start() }
            }
        }.apply { isDaemon=true;start() } }
        fun close() { server.close() }
    }
}
