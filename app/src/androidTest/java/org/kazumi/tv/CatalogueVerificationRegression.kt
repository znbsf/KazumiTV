package org.kazumi.tv

import android.app.Instrumentation
import android.content.ContextWrapper
import android.content.Intent
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import org.json.JSONObject
import org.kazumi.tv.data.*
import org.kazumi.tv.playback.PlaybackRequest
import org.kazumi.tv.playback.PlaybackSleepTimer
import org.kazumi.tv.rules.*
import org.kazumi.tv.ui.*
import java.net.ServerSocket
import java.net.InetAddress
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

/** Real local verification UI and local video; isolated preferences, no real CAPTCHA. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object CatalogueVerificationRegression {
    fun run(test: Instrumentation): String {
        val touched=mutableSetOf<String>()
        val context=object:ContextWrapper(test.targetContext) {
            override fun getSharedPreferences(name:String,mode:Int):android.content.SharedPreferences {
                synchronized(touched) { touched.add(name) }
                return baseContext.getSharedPreferences("catalogue_verify_fixture_$name",mode)
            }
        }
        context.getSharedPreferences("tv_settings",0).edit().clear().commit()
        TvPreferences(context).apply { incognito=true;danmakuEnabled=false;autoNext=false;controlsSeconds=60 }
        val video=AdaptiveDownloadRegression.Server(mapOf("/video.mp4" to test.context.assets.open("tracks-fixture.mp4").use { it.readBytes() }),0)
        val fixture=VerificationFixture()
        val rule=SourceRule(JSONObject().put("name","集表验证样本").put("baseURL",fixture.base)
            .put("antiCrawlerConfig",JSONObject().put("enabled",true).put("captchaType",1)
                .put("captchaInput","//*[@id='code']").put("captchaImage","//*[@id='image']").put("captchaButton","//*[@id='submit']")))
        val episode=Episode("第1集",fixture.base+"/episode")
        val calls=AtomicInteger();val resolves=AtomicInteger()
        val originalAccessibilityFlags=test.uiAutomation.serviceInfo.flags
        test.uiAutomation.serviceInfo=test.uiAutomation.serviceInfo.apply {
            flags=flags or android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        lateinit var timer:PlaybackSleepTimer
        test.runOnMainSync { timer=PlaybackSleepTimer() }
        val catalog=object:SourceCatalog {
            override val rules=listOf(rule)
            override suspend fun search(rule:SourceRule,keyword:String)=error("origin is available")
            override suspend fun chapters(rule:SourceRule,match:SourceMatch):List<Road> {
                calls.incrementAndGet()
                val response=HttpText.pageAsync(fixture.base+"/catalog","POST",mapOf("Content-Type" to "application/x-www-form-urlencoded"),"keyword=a%2Bb&season=3")
                try { SourcePageChecks.check(rule,response.body,response.url) }
                catch(_:SourceVerificationRequired) { throw SourceVerificationRequired(response.url,"POST","keyword=a%2Bb&season=3") }
                return listOf(Road("线路1",listOf(episode,Episode("第2集",fixture.base+"/next"))))
            }
        }
        var host:MainActivity?=null
        var failureDiagnostic:()->Unit={}
        var originalPlayer:ExoPlayer?=null
        var phase="setup"
        val pauses=AtomicInteger();val stops=AtomicInteger();val starts=AtomicInteger();val resumes=AtomicInteger()
        val lifecycleObserver=LifecycleEventObserver { _,event -> when(event) {
            Lifecycle.Event.ON_PAUSE -> pauses.incrementAndGet()
            Lifecycle.Event.ON_STOP -> stops.incrementAndGet()
            Lifecycle.Event.ON_START -> starts.incrementAndGet()
            Lifecycle.Event.ON_RESUME -> resumes.incrementAndGet()
            else -> Unit
        } }
        try {
            val activity=test.startActivitySync(Intent(context,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            host=activity
            test.runOnMainSync { activity.lifecycle.addObserver(lifecycleObserver) }
            var showing by mutableStateOf(true)
            var generation by mutableIntStateOf(0)
            test.runOnMainSync { activity.setContent { CompositionLocalProvider(LocalContext provides context) {
                KazumiTheme(false) { if(showing)key(generation) {
                    PlaybackSessionScreen(Subject(19000929,"集表验证样本","",""),rule.name,episode,
                        initialOrigin=PlaybackOrigin(rule.name,"集表验证样本",fixture.base+"/show","线路1"),sourceCatalog=catalog,sleepTimer=timer,
                        resolveEpisode={ _,_-> resolves.incrementAndGet();PlaybackRequest("http://127.0.0.1:${video.port}/video.mp4",emptyMap(),"集表验证样本 · 第1集",mimeType="video/mp4") },onClose={ showing=false })
                } }
            } } }
            fun nodes():List<AccessibilityNodeInfo> {
                if(android.os.Build.VERSION.SDK_INT>=33)test.uiAutomation.clearCache()
                val all=mutableListOf<AccessibilityNodeInfo>()
                fun visit(node:AccessibilityNodeInfo?) { if(node==null)return;all.add(node);for(i in 0 until node.childCount)visit(node.getChild(i)) }
                val active=test.uiAutomation.rootInActiveWindow
                if(active!=null)visit(active)
                else {
                    val windows=test.uiAutomation.windows.filter { it.isActive || it.isFocused }
                    windows.mapNotNull { it.root }.filter { it.packageName?.toString()==test.targetContext.packageName }.forEach { visit(it) }
                }
                return all
            }
            fun has(label:String)=nodes().any { it.text?.toString()==label }
            fun await(label:String,condition:()->Boolean) { phase=label;repeat(200) { if(condition())return;Thread.sleep(100) };error("catalogue verification timeout: $label") }
            fun click(label:String) {
                await(label) { has(label) }
                var node=nodes().first { it.text?.toString()==label }
                node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SHOW_ON_SCREEN.id)
                while(!node.isClickable)node=node.parent ?: error("missing clickable ancestor")
                check(node.performAction(AccessibilityNodeInfo.ACTION_CLICK));test.waitForIdleSync()
            }
            fun player():ExoPlayer? {
                fun find(view:View):ExoPlayer? {
                    if(view is PlayerView)return view.player as? ExoPlayer
                    if(view is ViewGroup)for(i in 0 until view.childCount)find(view.getChildAt(i))?.let { return it }
                    return null
                }
                var value:ExoPlayer?=null;test.runOnMainSync { value=find(activity.window.decorView) };return value
            }
            fun paused(current:ExoPlayer):Boolean { var value=false;test.runOnMainSync { value=!current.playWhenReady };return value }
            fun position(current:ExoPlayer):Long { var value=0L;test.runOnMainSync { value=current.currentPosition };return value }
            failureDiagnostic={
                val present=listOf("验证并恢复集表","重试集表","正在恢复集表…","提交验证码","Ⅱ 暂停","▷ 播放","重新解析","下一集","定时停止","继续播放","取消定时","返回播放").associateWith { has(it) }
                val current=player()
                var state="player_present=false"
                test.runOnMainSync {
                    current?.let {
                        it.videoDecoderCounters?.ensureUpdated()
                        state="player_present=true position=${it.currentPosition} playbackState=${it.playbackState} playWhenReady=${it.playWhenReady} isPlaying=${it.isPlaying} errorCode=${it.playerError?.errorCode} frames=${it.videoDecoderCounters?.renderedOutputBufferCount}"
                    }
                    state+=" lifecycle=${activity.lifecycle.currentState} sleepExpired=${timer.refresh().expired} showing=$showing activityIdentity=${System.identityHashCode(activity)} isDestroyed=${activity.isDestroyed} isFinishing=${activity.isFinishing} originalPlayerIdentity=${originalPlayer?.let { System.identityHashCode(it) }} currentPlayerIdentity=${current?.let { System.identityHashCode(it) }} samePlayer=${current===originalPlayer}"
                    originalPlayer?.let { original -> state+=" originalPaused=${runCatching { !original.playWhenReady }.getOrNull()}" }
                }
                val power=context.getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
                val rootPackage=test.uiAutomation.rootInActiveWindow?.packageName?.toString()
                var screenshot="capture_failed"
                run {
                    val file=java.io.File(test.targetContext.getExternalFilesDir(null),"catalogue-verification-failure-${System.currentTimeMillis()}.png")
                    screenshot=runCatching {
                        val bitmap=checkNotNull(test.uiAutomation.takeScreenshot())
                        try { file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) } } finally { bitmap.recycle() }
                        file.name
                    }.getOrDefault("capture_failed")
                }
                test.sendStatus(0,Bundle().apply { putString("stream","catalogue_verification_diagnostic phase=$phase $state pauses=${pauses.get()} stops=${stops.get()} starts=${starts.get()} resumes=${resumes.get()} interactive=${power.isInteractive} rootPackage=$rootPackage calls=${calls.get()} resolves=${resolves.get()} badPost=${fixture.badPost.get()} verifiedCatalog=${fixture.verifiedCatalog.get()} labels=$present screenshot=$screenshot\n") })
            }
            await("video and challenge action") { player()?.let { position(it)>1500 }==true && has("验证并恢复集表") }
            check(!has("提交验证码")) // Challenge never opens itself.
            click("Ⅱ 暂停")
            val original=requireNotNull(player());val saved=position(original)
            originalPlayer=original
            click("验证并恢复集表");await("verification") { has("提交验证码") }
            check(player()===original && paused(original))
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
            await("physical back closes only dialog") { !has("提交验证码") && has("验证并恢复集表") }
            check(showing && player()===original && paused(original) && kotlin.math.abs(position(original)-saved)<1000)
            // A playing intent is suspended by the overlay. Backgrounding invalidates auto-resume.
            click("▷ 播放");await("playing intent") { !paused(original) }
            click("验证并恢复集表");await("second verification paused") { has("提交验证码") && paused(original) }
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
            await("playing intent restored") { !has("提交验证码") && !paused(original) }
            check(player()===original)
            click("验证并恢复集表");await("sleep verification paused") { has("提交验证码") && paused(original) }
            test.runOnMainSync { timer.start(300) }
            Thread.sleep(700)
            test.runOnMainSync { check(timer.refresh().expired) }
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
            await("sleep dialog closed") { !has("提交验证码") }
            Thread.sleep(300)
            check(player()===original && paused(original)) { "expired sleep timer overwritten by verification return" }
            await("sleep expiry menu retained") { has("继续播放") && has("取消定时") }
            val downTime=android.os.SystemClock.uptimeMillis()
            test.sendKeySync(KeyEvent(downTime,downTime,KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_BACK,0))
            test.waitForIdleSync()
            check(has("继续播放") && player()===original) { "BACK DOWN prematurely removed focused menu" }
            test.sendKeySync(KeyEvent(downTime,android.os.SystemClock.uptimeMillis(),KeyEvent.ACTION_UP,KeyEvent.KEYCODE_BACK,0))
            await("sleep menu back retains paused controls") { has("▷ 播放") && !has("继续播放") }
            test.runOnMainSync { timer.cancel() }
            click("▷ 播放");await("playing before background") { !paused(original) }
            click("验证并恢复集表");await("background verification paused") { has("提交验证码") && paused(original) }
            val stopsBeforeHome=stops.get()
            android.os.ParcelFileDescriptor.AutoCloseInputStream(test.uiAutomation.executeShellCommand("input keyevent 3")).use { it.readBytes() }
            await("HOME actually reaches ON_STOP") { stops.get()>stopsBeforeHome }
            test.sendStatus(0,Bundle().apply { putString("stream","catalogue_verification_home pauses=${pauses.get()} stops=${stops.get()} activityIdentity=${System.identityHashCode(activity)}\n") })
            test.targetContext.startActivity(Intent(test.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
            await("verification after home") { activity.lifecycle.currentState==androidx.lifecycle.Lifecycle.State.RESUMED && has("提交验证码") }
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
            await("background cancel") { !has("提交验证码") }
            check(player()===original && paused(original))
            click("验证并恢复集表");await("native input") { nodes().any { it.isEditable } }
            check(nodes().first { it.isEditable }.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,"fixture")
            }))
            click("提交验证码")
            await("verified directory") { has("下一集") && !has("验证并恢复集表") && !has("提交验证码") }
            check(player()===original && paused(original) && resolves.get()==1)
            check(calls.get()==2 && fixture.verifiedCatalog.get()==1 && fixture.badPost.get()==0)
            // Dispose an open challenge and replace the session: no old dialog may survive.
            fixture.authorized=false
            test.runOnMainSync { generation++ }
            await("replacement challenge") { has("验证并恢复集表") }
            click("验证并恢复集表");await("replacement dialog") { has("提交验证码") }
            fixture.authorized=true
            test.runOnMainSync { generation++ }
            await("old dialog invalidated") { has("下一集") && !has("提交验证码") && !has("验证并恢复集表") }
            return "catalogue_verification=PASS explicit_entry=true physical_back_same_player=true post_cookie_retry=true sleep_expiry_preserved=true background_no_autoplay=true stale_dialog_disposed=true"
        } catch(failure:Exception) {
            runCatching { failureDiagnostic() }
            throw failure
        } finally {
            test.uiAutomation.serviceInfo=test.uiAutomation.serviceInfo.apply { flags=originalAccessibilityFlags }
            host?.let { test.runOnMainSync { it.lifecycle.removeObserver(lifecycleObserver);it.finish() };test.waitForIdleSync() }
            test.runOnMainSync { timer.cancel() }
            fixture.close();video.close()
            synchronized(touched) { touched.forEach { context.getSharedPreferences(it,0).edit().clear().commit() } }
        }
    }

    private class VerificationFixture {
        private val server=ServerSocket(0,16,InetAddress.getByName("127.0.0.1"))
        val base="http://127.0.0.1:${server.localPort}"
        @Volatile var authorized=false
        val verifiedCatalog=AtomicInteger();val badPost=AtomicInteger()
        private val cookie="catalogue_fixture_${server.localPort}"
        init { thread(isDaemon=true) { while(!server.isClosed) {
            val socket=try { server.accept() } catch(_:Exception) { break }
            thread(isDaemon=true) { try { socket.use {
                it.soTimeout=3000
                val reader=it.getInputStream().bufferedReader();val request=reader.readLine().orEmpty()
                val headers=mutableMapOf<String,String>()
                while(true) { val line=reader.readLine()?:break;if(line.isEmpty())break;headers[line.substringBefore(':').lowercase()]=line.substringAfter(':').trim() }
                val payload=CharArray(headers["content-length"]?.toIntOrNull() ?: 0)
                var read=0;while(read<payload.size) { val n=reader.read(payload,read,payload.size-read);if(n<0)break;read+=n }
                var extra=""
                if(request.startsWith("POST /verify ") && String(payload)=="verify=fixture") { authorized=true;extra="Set-Cookie: $cookie=ok; Path=/\r\n" }
                val isCatalog=request.contains(" /catalog ")
                if(isCatalog && (!request.startsWith("POST ") || String(payload)!="keyword=a%2Bb&season=3"))badPost.incrementAndGet()
                val cleared=authorized && (!isCatalog || headers["cookie"].orEmpty().contains("$cookie=ok"))
                if(isCatalog && cleared)verifiedCatalog.incrementAndGet()
                val body=if(cleared)"<html><body>verified</body></html>" else """<html><body><form method='post' action='/verify'><input id='code' name='verify'><img id='image' src='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aQ1cAAAAASUVORK5CYII='><button id='submit' type='submit'>Verify fixture</button></form></body></html>"""
                val bytes=body.toByteArray()
                it.getOutputStream().write(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n${extra}Content-Length: ${bytes.size}\r\nConnection: close\r\n\r\n").toByteArray()+bytes)
            } } catch(_:Exception) { } }
        } } }
        fun close() { server.close();android.webkit.CookieManager.getInstance().setCookie(base,"$cookie=; Max-Age=0; Path=/") }
    }
}
