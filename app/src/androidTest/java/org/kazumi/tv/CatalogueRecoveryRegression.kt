package org.kazumi.tv

import android.app.Instrumentation
import android.content.ContextWrapper
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.kazumi.tv.data.*
import org.kazumi.tv.playback.PlaybackRequest
import org.kazumi.tv.rules.*
import org.kazumi.tv.ui.*
import java.util.concurrent.atomic.AtomicInteger

/** Controlled directory failures with a real local player. No physical network outage claim. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object CatalogueRecoveryRegression {
    fun run(test:Instrumentation):String {
        val touched=java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
        val context=object:ContextWrapper(test.targetContext) {
            override fun getSharedPreferences(name:String,mode:Int):android.content.SharedPreferences {
                touched.add(name)
                return baseContext.getSharedPreferences("catalogue_recovery_fixture_$name",mode)
            }
        }
        context.getSharedPreferences("tv_settings",0).edit().clear().commit()
        TvPreferences(context).apply { incognito=true;danmakuEnabled=false;autoNext=false;controlsSeconds=30 }
        val server=AdaptiveDownloadRegression.Server(mapOf("/video.mp4" to test.context.assets.open("tracks-fixture.mp4").use { it.readBytes() }),0)
        val calls=AtomicInteger();val resolves=AtomicInteger();val cancelled=AtomicInteger()
        val gate=CompletableDeferred<Unit>()
        val lateResult=CompletableDeferred<Unit>()
        var cancelMode=false
        val ep=Episode("第12集","https://catalogue.invalid/12")
        val episodes=listOf(Episode("第11集","https://catalogue.invalid/11"),ep,Episode("第13集","https://catalogue.invalid/13"))
        val rule=SourceRule(JSONObject().put("name","目录恢复样本").put("baseURL","https://catalogue.invalid"))
        val catalog=object:SourceCatalog {
            override val rules=listOf(rule)
            override suspend fun search(rule:SourceRule,keyword:String)=error("Known origin must avoid search")
            override suspend fun chapters(rule:SourceRule,match:SourceMatch):List<Road> {
                val call=calls.incrementAndGet()
                if(cancelMode)try { awaitCancellation() } catch(_:CancellationException) {
                    cancelled.incrementAndGet()
                    // Simulate a provider that reports an obsolete catalogue after cancellation.
                    withContext(NonCancellable) { lateResult.await() }
                    return listOf(Road("过期目录",listOf(ep)))
                }
                if(call<=2)error("Controlled directory outage")
                gate.await()
                return listOf(Road("线路1",episodes),Road("线路2",episodes))
            }
        }
        var host:MainActivity?=null
        try {
            val activity=test.startActivitySync(Intent(test.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            host=activity
            var showing by mutableStateOf(true)
            var generation by mutableIntStateOf(0)
            test.runOnMainSync { activity.setContent {
                CompositionLocalProvider(LocalContext provides context) { KazumiTheme(false) {
                    if(showing)key(generation) {
                        PlaybackSessionScreen(Subject(19000926,"目录恢复样本","",""),rule.name,ep,
                            initialOrigin=PlaybackOrigin(rule.name,"目录恢复样本","https://catalogue.invalid/show","线路1"),
                            sourceCatalog=catalog,resolveEpisode={ _,_ ->
                                if(resolves.incrementAndGet()==1)error("Controlled initial media resolution failure")
                                PlaybackRequest("http://127.0.0.1:${server.port}/video.mp4",emptyMap(),"目录恢复样本 · 第12集",mimeType="video/mp4")
                            },onClose={ showing=false })
                    }
                } }
            } }
            fun nodes():List<AccessibilityNodeInfo> {
                if(android.os.Build.VERSION.SDK_INT>=33)test.uiAutomation.clearCache()
                val result=mutableListOf<AccessibilityNodeInfo>()
                fun walk(node:AccessibilityNodeInfo?) { if(node==null)return;result.add(node);for(i in 0 until node.childCount)walk(node.getChild(i)) }
                walk(test.uiAutomation.rootInActiveWindow);return result
            }
            fun has(label:String)=nodes().any { it.text?.toString()==label }
            fun await(label:String,condition:()->Boolean) { repeat(200) { if(condition())return;Thread.sleep(100) };error("Catalogue recovery timeout: $label") }
            fun click(label:String) {
                await(label) { has(label) }
                var node=nodes().first { it.text?.toString()==label }
                node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SHOW_ON_SCREEN.id)
                while(!node.isClickable)node=node.parent ?: error("No button for $label")
                check(node.performAction(AccessibilityNodeInfo.ACTION_CLICK));test.waitForIdleSync()
            }
            fun player():ExoPlayer? {
                fun find(view:View):ExoPlayer? {
                    if(view is PlayerView)return view.player as? ExoPlayer
                    if(view is ViewGroup)for(i in 0 until view.childCount)find(view.getChildAt(i))?.let { return it }
                    return null
                }
                var found:ExoPlayer?=null
                test.runOnMainSync { found=find(activity.window.decorView) }
                return found
            }
            fun snapshot():Triple<ExoPlayer?,Long,Boolean> {
                val current=player();var position=0L;var playing=false
                test.runOnMainSync { position=current?.currentPosition ?: 0;playing=current?.playWhenReady ?: false }
                return Triple(current,position,playing)
            }
            click("重新解析")
            await("video works without catalogue") {
                val current=player();var ready=false
                test.runOnMainSync {
                    current?.videoDecoderCounters?.ensureUpdated()
                    ready=current!=null && current.playbackState==Player.STATE_READY && current.currentPosition>=1500 &&
                        (current.videoDecoderCounters?.renderedOutputBufferCount ?: 0)>0
                };ready
            }
            click("Ⅱ 暂停")
            await("paused and retry available") { has("▷ 播放") && has("重试集表") }
            val before=snapshot();check(!before.third && before.second>=1500)
            check(calls.get()==1)
            click("重试集表")
            await("failed retry available again") { calls.get()==2 && has("重试集表") }
            Thread.sleep(1000);check(calls.get()==2) { "Directory failure looped automatically" }
            val failed=snapshot();check(failed.first===before.first && !failed.third && kotlin.math.abs(failed.second-before.second)<500)
            click("重试集表")
            await("directory loading") { calls.get()==3 && has("正在恢复集表…") }
            check(!has("重试集表"))
            Thread.sleep(800);check(calls.get()==3) { "Duplicate directory request while loading" }
            gate.complete(Unit)
            await("catalogue actions restored") { has("选集") && has("下一集") && has("线路") && !has("重试集表") }
            val after=snapshot()
            check(after.first===before.first && !after.third && kotlin.math.abs(after.second-before.second)<500) { "Catalogue retry replaced or moved paused player" }
            check(resolves.get()==2) { "Catalogue retry re-resolved media" }
            await("focus restored to play control") {
                var node=nodes().firstOrNull { it.text?.toString()=="▷ 播放" };var focused=false
                while(node!=null) { if(node.isFocused) { focused=true;break };node=node.parent };focused
            }
            click("设置");await("previous episode restored") { has("上一集") }
            click("返回播放")
            // Re-enter with a suspended request, then remove the owning screen.
            test.runOnMainSync { cancelMode=true;generation++ }
            await("pending directory request") { calls.get()==4 }
            test.runOnMainSync { showing=false };test.waitForIdleSync()
            await("exit cancels directory request") { cancelled.get()==1 }
            test.runOnMainSync { cancelMode=false;generation++;showing=true }
            await("replacement session catalogue") { calls.get()==5 && has("下一集") && has("线路") }
            lateResult.complete(Unit)
            Thread.sleep(600)
            check(calls.get()==5 && has("下一集") && has("线路")) { "Late cancelled result polluted replacement session" }
            return "catalogue_recovery=PASS initial_media_retry=PASS failed_retry_no_loop=PASS " +
                "same_player_paused_position=PASS catalogue_actions_focus=PASS exit_cancellation=PASS late_result_isolation=PASS"
        } finally {
            lateResult.complete(Unit)
            gate.complete(Unit)
            try { host?.let { activity -> test.runOnMainSync { activity.setContent {};activity.finish() };test.waitForIdleSync() } }
            finally { server.close();touched.toList().forEach { context.getSharedPreferences(it,0).edit().clear().commit() } }
        }
    }
}
