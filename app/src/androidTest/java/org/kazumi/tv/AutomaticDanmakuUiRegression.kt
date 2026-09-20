package org.kazumi.tv

import android.app.Instrumentation
import android.content.ContextWrapper
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalContext
import androidx.media3.common.Player
import org.kazumi.tv.data.*
import org.kazumi.tv.playback.PlaybackRequest
import org.kazumi.tv.ui.*

/** Real service mapping/comments on a controlled video. Does not claim a site/season match. */
object AutomaticDanmakuUiRegression {
    fun run(test:Instrumentation) {
        val original=test.targetContext
        val before=listOf("tv_settings","tv_library").associateWith { original.getSharedPreferences(it,0).all.toMap() }
        val context=object:ContextWrapper(original) {
            override fun getSharedPreferences(name:String,mode:Int)=baseContext.getSharedPreferences("automatic_danmaku_fixture_$name",mode)
        }
        context.getSharedPreferences("tv_settings",0).edit().clear().commit()
        TvPreferences(context).apply { incognito=true;danmakuEnabled=true;resumePlayback=false;autoNext=false;speed=1f }
        val server=AdaptiveDownloadRegression.Server(mapOf("/danmaku.mp4" to test.context.assets.open("tracks-fixture.mp4").use { it.readBytes() }),0)
        val activity=test.startActivitySync(Intent(original,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        fun overlay():DanmakuView? {
            fun find(view:View):DanmakuView? {
                if(view is DanmakuView)return view
                if(view is ViewGroup)for(i in 0 until view.childCount)find(view.getChildAt(i))?.let { return it }
                return null
            }
            return find(activity.window.decorView)
        }
        fun await(label:String,condition:()->Boolean) {
            repeat(600) { var ok=false;test.runOnMainSync { ok=condition() };if(ok)return;Thread.sleep(100) }
            error("timeout $label")
        }
        try {
            test.runOnMainSync { activity.setContent { CompositionLocalProvider(LocalContext provides context) { KazumiTheme(false) {
                PlayerScreen(PlaybackRequest("http://127.0.0.1:${server.port}/danmaku.mp4",emptyMap(),"第1集",mimeType="video/mp4"),
                    Subject(400602,"真实弹幕服务验证","",""),initialPosition=0,initialPlayWhenReady=false,onClose={})
            } } } }
            await("automatic real comments attached") { overlay()?.let { it.isShown&&it.timeline.scheduled.isNotEmpty()&&it.player?.playbackState==Player.STATE_READY }==true }
            test.runOnMainSync {
                val view=checkNotNull(overlay());val player=checkNotNull(view.player)
                val comment=view.timeline.scheduled.firstOrNull { it.comment.timeMs+1500<player.duration } ?: error("No comment in fixture duration")
                player.seekTo(comment.comment.timeMs+1500)
            }
            await("visible real comments at paused position") { overlay()?.let { it.timeline.visible((it.player?.currentPosition ?: 0)-it.offsetMs).isNotEmpty() }==true }
            Thread.sleep(600)
            test.uiAutomation.takeScreenshot()?.let { bitmap ->
                java.io.File(original.getExternalFilesDir(null),"automatic-danmaku-real-service.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) };bitmap.recycle()
            }
            test.runOnMainSync { checkNotNull(overlay()?.player).play() }
            await("comments remain attached during playback") { overlay()?.let { it.player?.isPlaying==true&&it.timeline.scheduled.isNotEmpty() }==true }
        } finally {
            test.runOnMainSync { activity.setContent { };activity.finish() };test.waitForIdleSync();server.close()
            for((name,values) in before)check(values==original.getSharedPreferences(name,0).all)
        }
    }
}
