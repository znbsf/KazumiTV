package org.kazumi.tv

import android.app.Instrumentation
import android.content.ContextWrapper
import android.content.Intent
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import org.kazumi.tv.data.*
import org.kazumi.tv.playback.*
import org.kazumi.tv.ui.*

/** Controlled playback and failure interaction, with no source/cookie or user-history mutation. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object PlayerControlsRegression {
    fun run(test: Instrumentation, inDialog:Boolean=false) {
        val original=test.targetContext
        val beforeSettings=original.getSharedPreferences("tv_settings",0).all.toMap()
        val beforeLibrary=original.getSharedPreferences("tv_library",0).all.toMap()
        val isolated=object:ContextWrapper(original) {
            override fun getSharedPreferences(name:String,mode:Int)=baseContext.getSharedPreferences("controls_fixture_$name",mode)
        }
        isolated.getSharedPreferences("tv_settings",0).edit().clear().commit()
        TvPreferences(isolated).incognito=true
        TvPreferences(isolated).danmakuEnabled=false
        TvPreferences(isolated).controlsSeconds=10
        val server=AdaptiveDownloadRegression.Server(mapOf("/controls.mp4" to test.context.assets.open("tracks-fixture.mp4").use { it.readBytes() }, "/broken.mp4" to "this is not a media file".toByteArray()),0)
        val activity=test.startActivitySync(Intent(original,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        fun playbackReady(requireRendered:Boolean=false):Boolean {
            fun find(view:View):Player? {
                if(view is PlayerView && view.player!=null)return view.player
                if(view is ViewGroup)for(i in 0 until view.childCount)find(view.getChildAt(i))?.let { return it }
                return null
            }
            var ready=false
            test.runOnMainSync {
                val player=find(activity.window.decorView)
                val counters=(player as? ExoPlayer)?.videoDecoderCounters
                counters?.ensureUpdated()
                ready=player!=null && player.playbackState==Player.STATE_READY && player.duration>0 &&
                    (!requireRendered || ((counters?.renderedOutputBufferCount ?: 0)>0 && player.currentPosition>=1000))
            }
            return ready
        }
        fun nodes():List<AccessibilityNodeInfo> {
            val found=mutableListOf<AccessibilityNodeInfo>()
            fun walk(n:AccessibilityNodeInfo?) { if(n==null)return;found+=n;for(i in 0 until n.childCount)walk(n.getChild(i)) }
            walk(test.uiAutomation.rootInActiveWindow);return found
        }
        fun await(label:String,condition:()->Boolean) { repeat(150) { if(condition())return;Thread.sleep(100) };error("timeout $label") }
        fun has(label:String)=nodes().any { it.text?.toString()==label }
        fun focused(label:String):Boolean {
            var node=nodes().firstOrNull { it.text?.toString()==label } ?: return false
            while (true) {
                if(node.isFocused)return true
                node=node.parent ?: return false
            }
        }
        fun click(label:String) {
            await(label) { has(label) }
            var n=nodes().first { it.text?.toString()==label }
            n.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SHOW_ON_SCREEN.id)
            while(!n.isClickable && n.parent!=null)n=n.parent
            check(n.performAction(AccessibilityNodeInfo.ACTION_CLICK));test.waitForIdleSync()
        }
        fun shot(name:String) { test.uiAutomation.takeScreenshot()?.let { b->java.io.File(original.getExternalFilesDir(null),name).outputStream().use { b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) };b.recycle() } }
        var retries=0
        fun mount(path:String) {
            test.runOnMainSync { activity.setContent { CompositionLocalProvider(LocalContext provides isolated) { KazumiTheme(false) {
                @Composable fun player() {
                    PlayerScreen(PlaybackRequest("http://127.0.0.1:${server.port}/$path",emptyMap(),"控制测试",mimeType="video/mp4"),
                        Subject(19000921,"播放器控制回归","",""),initialPosition=0,initialPlayWhenReady=false,
                        onNext={}, episodes=listOf("第1集","第2集"),currentEpisode=0,onEpisodeSelected={},
                        onChooseRoad={ _,_-> },onChooseSource={ _,_-> },
                        onResolveAgain={ _,_-> retries++ },onClose={})
                }
                if(inDialog)Dialog(onDismissRequest={},properties=DialogProperties(usePlatformDefaultWidth=false,decorFitsSystemWindows=false)) { player() }
                else player()
            } } } }
        }
        try {
            mount("controls.mp4")
            if(inDialog)await("dialog mounted") { has("▷ 播放") }
            else await("ready duration") { playbackReady() }
            await("initial control focus after mount") { focused("▷ 播放") }
            click("▷ 播放")
            if(inDialog) {
                Thread.sleep(11_000)
                await("dialog controls auto-hide") { !has("设置") }
                test.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_UP)
                await("dialog controls reappear") { has("设置")&&has("Ⅱ 暂停") }
                return
            }
            await("rendered frame and advancing position") { playbackReady(requireRendered=true) }
            // A hardware media key pauses even if slow decoding outlasts the controls timer.
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PAUSE)
            await("paused controls") { has("▷ 播放")&&has("设置") }
            val common=listOf("▷ 播放","选集","下一集","线路","换源","弹幕 关","设置")
            val screen=android.graphics.Rect().also { test.uiAutomation.rootInActiveWindow.getBoundsInScreen(it) }
            for(label in common) {
                check(has(label))
                val bounds=android.graphics.Rect().also { box->nodes().first { it.text?.toString()==label }.getBoundsInScreen(box) }
                check(bounds.width()>0 && screen.contains(bounds)) { "common control clipped: $label $bounds" }
            }
            check(!has("外部播放器"));shot("player-controls-grouped.png")
            repeat(common.size-1) { test.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_RIGHT);test.waitForIdleSync() }
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_CENTER)
            await("settings") { has("播放信息") }
            check(!has("下一集")) { "main controls must not overlap settings" }
            shot("player-controls-settings.png")
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);await("menu closed") { !has("播放信息") }
            click("▷ 播放");Thread.sleep(350)
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);await("controls hidden") { !has("设置") }
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_RIGHT)
            await("seek feedback") { nodes().any { it.text?.toString()?.startsWith("快进 · ")==true } };shot("player-controls-seek.png")
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_CENTER);await("single center pauses") { has("▷ 播放")&&has("设置") }
            // A separate invalid media request exercises visible recovery without a website dependency.
            mount("broken.mp4")
            await("failed") { nodes().any { it.text?.toString()?.startsWith("播放失败：")==true } }
            await("reload control after player error") { has("重新加载") };shot("player-controls-error.png")
            await("failure moves focus to attached retry control") { focused("重新加载") }
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_CENTER)
            await("single retry callback") { retries==1 }
        } catch(failure:Throwable) {
            runCatching { shot("player-controls-failure.png") }
            test.sendStatus(0,android.os.Bundle().apply { putString("stream","Player controls failure: ${failure.javaClass.simpleName}: ${failure.message}\n") })
            throw failure
        } finally {
            test.runOnMainSync { activity.setContent { };activity.finish() };test.waitForIdleSync()
            server.close()
            isolated.getSharedPreferences("tv_settings",0).edit().clear().commit()
            check(beforeSettings==original.getSharedPreferences("tv_settings",0).all)
            check(beforeLibrary==original.getSharedPreferences("tv_library",0).all)
        }
    }
}
