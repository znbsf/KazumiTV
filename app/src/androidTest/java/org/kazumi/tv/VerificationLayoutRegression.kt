package org.kazumi.tv

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Rect
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.webkit.WebView
import androidx.activity.compose.setContent
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.kazumi.tv.rules.*
import org.kazumi.tv.ui.*
import java.util.concurrent.atomic.AtomicBoolean

/** Local fixture only: layout, real Back, known test input and original-request recovery. */
object VerificationLayoutRegression {
    fun run(test:Instrumentation)=runBlocking {
        val server=FixtureServer()
        val repo=RuleRepository(test.targetContext)
        val rule=SourceRule(JSONObject().put("name","verification layout fixture").put("baseURL",server.url)
            .put("searchURL",server.url+"/search?wd=@keyword")
            .put("searchList","//a[@class='result']").put("searchName",".").put("searchResult",".")
            .put("antiCrawlerConfig",JSONObject().put("enabled",true).put("captchaType",1)
                .put("captchaDetectValue","//*[@id='challenge']").put("captchaImage","//*[@id='image']")
                .put("captchaInput","//*[@id='code']").put("captchaButton","//*[@id='verify']")))
        var activity:MainActivity?=null
        val done=AtomicBoolean()
        try {
            val challenge=try { repo.search(rule,"fixture");error("fixture must initially require verification") }
                catch(expected:SourceVerificationRequired) { expected }
            val host=test.startActivitySync(Intent(test.targetContext,MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            activity=host
            test.uiAutomation.serviceInfo=test.uiAutomation.serviceInfo.apply {
                flags=flags or android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            }
            test.runOnMainSync { host.setContent { KazumiTheme(false) {
                VerificationScreen(rule,challenge.pageUrl,challenge) { done.set(true) }
            } } }
            fun findWeb(view:View):WebView? {
                if(view is WebView)return view
                if(view is ViewGroup)for(i in 0 until view.childCount)findWeb(view.getChildAt(i))?.let { return it }
                return null
            }
            fun webBounds():Rect {
                val rect=Rect()
                test.runOnMainSync { findWeb(host.window.decorView)?.getGlobalVisibleRect(rect) }
                return rect
            }
            fun nodes():List<AccessibilityNodeInfo> {
                val found=mutableListOf<AccessibilityNodeInfo>()
                fun walk(node:AccessibilityNodeInfo?) {
                    if(node==null)return
                    found.add(node)
                    for(i in 0 until node.childCount)walk(node.getChild(i))
                }
                val roots=test.uiAutomation.windows.mapNotNull { it.root }
                    .filter { it.packageName?.toString()==test.targetContext.packageName }
                if(roots.isEmpty())walk(test.uiAutomation.rootInActiveWindow) else roots.forEach(::walk)
                return found
            }
            fun bounds(node:AccessibilityNodeInfo)=Rect().also { node.getBoundsInScreen(it) }
            fun waitFor(message:String,condition:()->Boolean) {
                val deadline=System.currentTimeMillis()+12000
                while(System.currentTimeMillis()<deadline) { if(condition())return;Thread.sleep(100) }
                if(condition())return
                // Fixture-only diagnostic: no webpage text, URLs, HTML or cookies.
                val knownLabels=setOf("重新检测","重新加载","操作网页","提交验证码")
                val labelNodes=nodes().filter { it.text?.toString() in knownLabels }
                val toolbarRestored=labelNodes.any { it.text?.toString()=="提交验证码" }
                report(test,"failure toolbarRestored=$toolbarRestored labels="+labelNodes.joinToString { node ->
                    "${node.text}:focused=${node.isFocused}:parentFocused=${node.parent?.isFocused}:bounds=${bounds(node)}"
                })
                test.runOnMainSync {
                    val web=findWeb(host.window.decorView)
                    val rect=Rect();web?.getGlobalVisibleRect(rect)
                    report(test,"failure browser bounds=$rect pointerEnabled=${(web as? VerificationWebView)?.pointerEnabled} hasFocus=${web?.hasFocus()}")
                }
                runCatching {
                    val folder=java.io.File(test.targetContext.getExternalFilesDir(null),"verification-layout").apply { mkdirs() }
                    val file=java.io.File(folder,"failure-${System.currentTimeMillis()}.png")
                    test.uiAutomation.takeScreenshot()?.let { bitmap ->
                        file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) }
                        bitmap.recycle()
                        report(test,"failure fixture screenshot saved=${file.name}")
                    }
                }
                error(message)
            }
            fun click(label:String) {
                var node=nodes().first { it.text?.toString()==label }
                while(!node.isClickable)node=node.parent ?: error("No clickable parent for $label")
                check(node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) { "Could not click $label" }
            }
            fun toolbar()=nodes().filter { bounds(it).bottom<=webBounds().top }
            waitFor("fixture image and toolbar did not appear") {
                val list=toolbar()
                !webBounds().isEmpty&&list.any { it.contentDescription?.toString()=="验证码图片" }&&
                    list.any { it.isEditable }&&list.any { it.text?.toString()=="提交验证码" }
            }
            val initialWeb=webBounds()
            val screen=Rect()
            test.runOnMainSync { host.window.decorView.getGlobalVisibleRect(screen) }
            val controls=toolbar()
            val checked=listOf(controls.first { it.isEditable },
                controls.first { it.text?.toString()=="提交验证码" },
                controls.first { it.contentDescription?.toString()=="验证码图片" })
            for(node in checked) {
                val rect=bounds(node)
                check(!rect.isEmpty&&screen.contains(rect)&&!Rect.intersects(rect,initialWeb)) {
                    "verification control outside screen or overlaps WebView"
                }
            }
            check(checked.map(::bounds).let { rects ->
                rects.indices.all { a -> rects.indices.all { b -> a==b||!Rect.intersects(rects[a],rects[b]) } }
            }) { "verification controls overlap each other" }
            report(test,"image/input/submit fit screen without overlap=OK")
            click("操作网页")
            waitFor("operating mode did not enlarge WebView and hide toolbar") {
                webBounds().height()>initialWeb.height()&&nodes().none { it.text?.toString()=="提交验证码" }
            }
            check(!done.get())
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
            waitFor("Back did not restore toolbar and focus") {
                val list=toolbar()
                list.any { it.text?.toString()=="提交验证码" }&&list.any { node ->
                    (node.text?.toString()=="操作网页"&&(node.isFocused||node.parent?.isFocused==true))||
                        (node.isFocused&&node.findAccessibilityNodeInfosByText("操作网页").isNotEmpty())
                }
            }
            check(!host.isFinishing&&!done.get()) { "Back left verification instead of pointer mode" }
            report(test,"operating mode enlarges browser; real Back restores toolbar/focus=OK")
            // Website input must also enable the native submit action; no OCR is involved.
            test.runOnMainSync { findWeb(host.window.decorView)?.evaluateJavascript("document.getElementById('code').value='1357'",null) }
            waitFor("web input did not enable native submit") {
                nodes().any { it.text?.toString()=="提交验证码"&&it.isEnabled&&it.parent?.isEnabled!=false }
            }
            test.runOnMainSync { findWeb(host.window.decorView)?.evaluateJavascript("document.getElementById('code').value=''",null) }
            waitFor("cleared web input left native submit enabled") {
                nodes().any { it.text?.toString()=="提交验证码"&&(!it.isEnabled||it.parent?.isEnabled==false) }
            }
            report(test,"web input enables native submit; clearing disables it=OK")
            val input=toolbar().first { it.isEditable }
            check(input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,"2468")
            }))
            waitFor("submit not enabled after controlled input") {
                nodes().any { it.text?.toString()=="提交验证码"&&it.isEnabled&&it.parent?.isEnabled!=false }
            }
            click("提交验证码")
            waitFor("controlled verification did not complete") { done.get() }
            check(repo.search(rule,"fixture").single().title=="Fixture episode")
            check(server.verifiedRequest) { "original request did not carry verification cookie" }
            report(test,"controlled image input submits, done fires, original search resumes=OK")
        } finally {
            activity?.let { host -> test.runOnMainSync { host.finish() } }
            server.close()
        }
    }
    private fun report(test:Instrumentation,message:String) {
        test.sendStatus(0,Bundle().apply { putString("stream","verification-layout: $message\n") })
    }
    private class FixtureServer {
        private val server=java.net.ServerSocket(0,20,java.net.InetAddress.getByName("127.0.0.1"))
        val url="http://127.0.0.1:${server.localPort}"
        private val cookie="kazumi_layout_${server.localPort}"
        @Volatile var verifiedRequest=false
        private val png=java.io.ByteArrayOutputStream().use { out ->
            val bitmap=android.graphics.Bitmap.createBitmap(140,52,android.graphics.Bitmap.Config.ARGB_8888)
            val canvas=android.graphics.Canvas(bitmap)
            canvas.drawColor(android.graphics.Color.WHITE)
            canvas.drawText("2468",16f,38f,android.graphics.Paint().apply { color=android.graphics.Color.BLACK;textSize=32f })
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,out);bitmap.recycle();out.toByteArray()
        }
        init { Thread {
            while(!server.isClosed) {
                val socket=try { server.accept() } catch(_:Exception) { break }
                Thread { try { socket.use {
                    it.soTimeout=5000
                    val reader=it.getInputStream().bufferedReader()
                    val request=reader.readLine().orEmpty()
                    val headers=mutableMapOf<String,String>()
                    while(true) { val line=reader.readLine()?:break;if(line.isEmpty())break
                        headers[line.substringBefore(':').lowercase()]=line.substringAfter(':').trim() }
                    val verified=headers["cookie"].orEmpty().contains("$cookie=ok")
                    if(verified&&request.startsWith("GET /search"))verifiedRequest=true
                    val image=request.startsWith("GET /image")
                    val html=if(verified)"<html><body><a class='result' href='/episode'>Fixture episode</a></body></html>"
                    else """<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body>
                        <div id="challenge"><img id="image" src="/image"><input id="code">
                        <button id="verify" onclick="if(document.getElementById('code').value==='2468'){document.cookie='$cookie=ok; path=/';location.href='/ready';}">fixture submit</button></div>
                        </body></html>"""
                    val body=if(image)png else html.toByteArray(Charsets.UTF_8)
                    val type=if(image)"image/png" else "text/html; charset=utf-8"
                    it.getOutputStream().write(("HTTP/1.1 200 OK\r\nContent-Type: $type\r\nContent-Length: ${body.size}\r\nConnection: close\r\n\r\n").toByteArray()+body)
                } } catch(_:Exception) {} }.apply { isDaemon=true;start() }
            }
        }.apply { isDaemon=true;start() } }
        fun close() { server.close() }
    }
}
