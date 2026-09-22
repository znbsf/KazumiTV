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
import androidx.lifecycle.Lifecycle
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.kazumi.tv.rules.*
import org.kazumi.tv.ui.*
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Local fixture only: layout, real Back, known test input and original-request recovery. */
object VerificationLayoutRegression {
    fun run(test:Instrumentation,waitBeforeInputMs:Long=0)=runBlocking {
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
                // Re-read current semantics after Compose updates instead of retained
                // accessibility nodes; older TV versions do not expose this API.
                if(android.os.Build.VERSION.SDK_INT>=33)test.uiAutomation.clearCache()
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
            fun evaluateFixture(script:String):String {
                val value=AtomicReference<String>()
                val callback=CountDownLatch(1)
                test.runOnMainSync {
                    checkNotNull(findWeb(host.window.decorView)).evaluateJavascript(script) { value.set(it);callback.countDown() }
                }
                check(callback.await(4,TimeUnit.SECONDS)) { "Fixture JS diagnostic callback timed out" }
                return value.get()
            }
            fun ancestors(node:AccessibilityNodeInfo):List<AccessibilityNodeInfo> {
                val result=mutableListOf<AccessibilityNodeInfo>()
                var current:AccessibilityNodeInfo?=node
                while(current!=null) { result.add(current);current=current.parent }
                return result
            }
            fun button(label:String):AccessibilityNodeInfo? {
                val labelNode=nodes().firstOrNull { it.text?.toString()==label } ?: return null
                val chain=ancestors(labelNode)
                // Disabled Compose buttons may omit clickable/actions; role class remains
                // the same. Never mistake an enabled child Text for its disabled Button.
                return chain.firstOrNull { it.className?.toString()=="android.widget.Button" }
                    ?: chain.firstOrNull { it.isClickable || it.actionList.any { action -> action.id==AccessibilityNodeInfo.ACTION_CLICK } }
            }
            fun reportSubmitState(phase:String) {
                nodes().firstOrNull { it.text?.toString()=="提交验证码" }?.let { label ->
                    report(test,"$phase submit ancestors="+ancestors(label).mapIndexed { depth,node ->
                        "$depth:class=${node.className}:enabled=${node.isEnabled}:clickable=${node.isClickable}:focused=${node.isFocused}:actions=${node.actionList.map { it.id }}"
                    }.joinToString(" | "))
                }
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
                reportSubmitState("failure")
                runCatching {
                    evaluateFixture("JSON.stringify({inputLength:document.getElementById('code').value.length,pollCount:window.__layoutPollCount||0})")
                }.onSuccess { report(test,"failure fixture input/poll=$it") }
                    .onFailure { report(test,"failure fixture diagnostic=${it.javaClass.simpleName}") }
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
                val node=checkNotNull(button(label)) { "No button ancestor for $label" }
                check(node.isEnabled) { "Button disabled: $label" }
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
            if(waitBeforeInputMs>0) {
                report(test,"waiting ${waitBeforeInputMs}ms before human-input simulation")
                kotlinx.coroutines.delay(waitBeforeInputMs)
                check(!done.get()&&!host.isFinishing) { "waiting completed or closed verification" }
                var originalWeb:WebView?=null
                test.runOnMainSync { originalWeb=findWeb(host.window.decorView) }
                val watchedWeb=checkNotNull(originalWeb)
                // Count production VerificationScript.poll reads, without reading cookies/page text.
                check(evaluateFixture("""(function(){
                    var state=window.__kazumiVerification;
                    window.__layoutPollCount=0;
                    Object.defineProperty(window,'__kazumiVerification',{configurable:true,
                      get:function(){window.__layoutPollCount++;return state;},
                      set:function(value){state=value;}});
                    return true;
                })()""")=="true")
                fun pollCount()=evaluateFixture("window.__layoutPollCount").toInt()
                waitFor("polling did not continue beyond human-input deadline") { pollCount()>0 }
                android.os.ParcelFileDescriptor.AutoCloseInputStream(test.uiAutomation.executeShellCommand("input keyevent 3")).use { it.readBytes() }
                waitFor("HOME did not stop verification Activity") {
                    var stopped=false
                    test.runOnMainSync { stopped=!host.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED) }
                    stopped
                }
                // Allow any already-dispatched single JS evaluation to settle before comparison.
                kotlinx.coroutines.delay(1800)
                val stoppedCount=pollCount()
                kotlinx.coroutines.delay(1600)
                val laterCount=pollCount()
                check(laterCount==stoppedCount && !done.get()) { "Verification polled or completed while Activity stopped" }
                report(test,"real HOME pauses polling count=$stoppedCount->$laterCount; done remains false=OK")
                test.targetContext.startActivity(Intent(test.targetContext,MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
                waitFor("same verification Activity/WebView did not resume") {
                    var resumed=false
                    test.runOnMainSync { resumed=host.lifecycle.currentState==Lifecycle.State.RESUMED&&findWeb(host.window.decorView)===watchedWeb }
                    resumed
                }
                waitFor("foreground verification did not restart polling") { pollCount()>laterCount }
                check(!done.get())
                report(test,"same Activity/WebView resumes polling without remount=OK")
            }
            // Website input must also enable the native submit action; no OCR is involved.
            check(evaluateFixture("(function(){var input=document.getElementById('code');input.value='1357';return input.value.length;})()") == "4") {
                "Fixture web input did not become four characters"
            }
            waitFor("web input did not enable native submit") {
                button("提交验证码")?.isEnabled==true
            }
            reportSubmitState("web-input-filled")
            check(evaluateFixture("(function(){var input=document.getElementById('code');input.value='';return input.value.length;})()") == "0") {
                "Fixture web input did not clear"
            }
            waitFor("cleared web input left native submit enabled") {
                button("提交验证码")?.isEnabled==false
            }
            reportSubmitState("web-input-cleared")
            report(test,"fixture DOM length 4->0; native Button enabled->disabled=OK")
            val input=toolbar().first { it.isEditable }
            check(input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,"2468")
            }))
            waitFor("submit not enabled after controlled input") {
                button("提交验证码")?.isEnabled==true
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
