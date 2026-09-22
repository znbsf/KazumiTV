package org.kazumi.tv

import android.app.Instrumentation
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import org.kazumi.tv.data.*
import org.kazumi.tv.playback.PlaybackRequest
import org.kazumi.tv.ui.*

/** Credential-free RELEASE only. Isolated preferences, public fixture values and local media.
 * No real credential store is read, no credential is sent to a service, and the shared
 * Keystore alias is never removed. This proves local setup, not remote authorization.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object CredentialFreeReleaseRegression {
    fun run(test:Instrumentation):String {
        check(test.targetContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE==0) { "Requires release APK" }
        check(BuildConfig.DANDAN_APP_ID.isEmpty() && BuildConfig.DANDAN_APP_SECRET.isEmpty()) { "Requires credential-free APK" }
        val touched=java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
        val isolated=object:ContextWrapper(test.targetContext) {
            override fun getSharedPreferences(name:String,mode:Int):android.content.SharedPreferences {
                touched.add(name)
                return baseContext.getSharedPreferences("credential_free_release_fixture_$name",mode)
            }
        }
        // Only this fixture namespace is cleared, including leftovers from an interrupted run.
        listOf("danmaku_credentials","tv_settings","tv_library","danmaku_selections").forEach {
            isolated.getSharedPreferences(it,0).edit().clear().commit()
        }
        val prefs=TvPreferences(isolated)
        prefs.incognito=true; prefs.danmakuEnabled=true; prefs.autoNext=false; prefs.controlsSeconds=10
        val store=DanmakuCredentialStore(isolated)
        check(store.read()==null) { "Empty fixture unexpectedly has credentials" }
        val fixtureId="kazumi_release_fixture"
        val fixtureSecret="not-a-real-service-secret-2468"
        val server=AdaptiveDownloadRegression.Server(mapOf("/release.mp4" to
            test.context.assets.open("tracks-fixture.mp4").use { it.readBytes() }),0)
        var activity:MainActivity?=null
        try {
            val host=test.startActivitySync(Intent(test.targetContext,MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            activity=host
            var page by mutableStateOf("settings")
            var generation by mutableIntStateOf(0)
            test.runOnMainSync { host.setContent {
                CompositionLocalProvider(LocalContext provides isolated) { KazumiTheme(false) {
                    key(page,generation) {
                        if(page=="settings")Box(Modifier.fillMaxSize().padding(24.dp)) { DanmakuSettings() }
                        else PlayerScreen(
                            PlaybackRequest("http://127.0.0.1:${server.port}/release.mp4",emptyMap(),"无凭证播放测试 · 第1集",mimeType="video/mp4"),
                            Subject(19000925,"无凭证播放测试","",""),initialPosition=0,initialPlayWhenReady=true,onClose={})
                    }
                } }
            } }
            fun mount(next:String) { test.runOnMainSync { page=next;generation++ };test.waitForIdleSync() }
            fun nodes():List<AccessibilityNodeInfo> {
                if(android.os.Build.VERSION.SDK_INT>=33)test.uiAutomation.clearCache()
                val result=mutableListOf<AccessibilityNodeInfo>()
                fun walk(node:AccessibilityNodeInfo?) {
                    if(node==null)return
                    result.add(node);for(i in 0 until node.childCount)walk(node.getChild(i))
                }
                walk(test.uiAutomation.rootInActiveWindow);return result
            }
            fun has(label:String)=nodes().any { it.text?.toString()==label }
            fun await(label:String,condition:()->Boolean) {
                repeat(200) { if(condition())return;Thread.sleep(100) }
                error("Credential-free release timeout: $label")
            }
            fun click(label:String) {
                await(label) { has(label) }
                var node=nodes().first { it.text?.toString()==label }
                node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SHOW_ON_SCREEN.id)
                while(!node.isClickable)node=node.parent ?: error("No fixture button: $label")
                check(node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) { "Fixture button rejected action" }
                test.waitForIdleSync()
            }
            fun setInput(index:Int,value:String) {
                val fields=nodes().filter { it.isEditable }
                check(fields.size==2) { "Expected AppId and AppSecret fields" }
                check(fields[index].performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,value)
                })) { "Fixture text entry rejected" }
                test.waitForIdleSync()
            }
            await("unconfigured settings") { has("尚未配置弹幕凭证") }
            setInput(0,fixtureId);setInput(1,fixtureSecret)
            click("保存凭证")
            await("local encrypted save") { has("凭证已加密保存在这台电视，可在播放器中搜索并选择弹幕剧集") }
            val saved=checkNotNull(DanmakuCredentialStore(isolated).read())
            check(saved.appId==fixtureId && saved.secret==fixtureSecret) { "Fixture credential roundtrip failed" }
            val encrypted=isolated.getSharedPreferences("danmaku_credentials",0).getString("value",null)
            check(encrypted!=null && !encrypted.contains(fixtureSecret) && !encrypted.contains(fixtureId)) { "Fixture not encrypted" }
            mount("settings")
            await("settings restored local credential") { has("已保存凭证，密钥不回显") && has(fixtureId) }
            check(nodes().none { it.text?.toString()?.contains(fixtureSecret)==true }) { "Fixture secret visible after remount" }
            // Leaving secret empty with the same AppId must preserve the saved secret.
            click("保存凭证")
            await("blank secret preserved") { has("凭证已加密保存在这台电视，可在播放器中搜索并选择弹幕剧集") }
            check(DanmakuCredentialStore(isolated).read()?.secret==fixtureSecret)
            click("移除凭证")
            await("removed local credential") { has("已移除本机凭证") && store.read()==null }
            mount("settings")
            await("removal survives settings remount") { has("尚未配置弹幕凭证") }
            mount("player")
            fun advanced():Boolean {
                fun find(view:View):ExoPlayer? {
                    if(view is PlayerView)return view.player as? ExoPlayer
                    if(view is ViewGroup)for(i in 0 until view.childCount)find(view.getChildAt(i))?.let { return it }
                    return null
                }
                var passed=false
                test.runOnMainSync {
                    val player=find(host.window.decorView)
                    val counters=player?.videoDecoderCounters
                    counters?.ensureUpdated()
                    passed=player!=null && player.playbackState==Player.STATE_READY && player.isPlaying &&
                        player.currentPosition>=3000 && (counters?.renderedOutputBufferCount ?: 0)>0
                }
                return passed
            }
            await("actual rendered video advances without credentials") { advanced() }
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PAUSE)
            await("paused player controls") { has("▷ 播放") && has("设置") }
            click("设置");click("弹幕设置")
            await("missing credentials guidance") { has("请先到电视设置保存 AppId 和 AppSecret，再进入播放。") }
            check(store.read()==null)
            check(LibraryStore(isolated).history().isEmpty()) { "Fixture incognito playback wrote history" }
            return "credential_free_release=PASS non_debuggable=PASS local_settings_save_read_remove=PASS " +
                "secret_not_redisplayed=PASS no_credentials_rendered_video_3s=PASS missing_credentials_guidance=PASS " +
                "remote_credential_authorization=NOT_TESTED"
        } finally {
            try {
                activity?.let { host -> test.runOnMainSync { host.setContent {};host.finish() };test.waitForIdleSync() }
            } finally {
                server.close()
                touched.toList().forEach { isolated.getSharedPreferences(it,0).edit().clear().commit() }
            }
        }
    }
}
