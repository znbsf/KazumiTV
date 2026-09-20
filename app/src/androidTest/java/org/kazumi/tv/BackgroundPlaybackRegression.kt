package org.kazumi.tv

import android.app.Instrumentation
import android.content.ContextWrapper
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.view.KeyEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaController
import androidx.media3.session.MediaSession
import androidx.media3.ui.PlayerView
import org.kazumi.tv.data.*
import org.kazumi.tv.playback.PlaybackRequest
import org.kazumi.tv.ui.*
import java.util.concurrent.TimeUnit

/** Supplements S3MediaRegression: actual Activity HOME/ON_STOP, not a direct lifecycle-method call.
 * Does not toggle device power/network or dispatch global media commands to other applications.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object BackgroundPlaybackRegression {
    fun run(test:Instrumentation) {
        val original=test.targetContext
        val beforeSettings=original.getSharedPreferences("tv_settings",0).all.toMap()
        val beforeLibrary=original.getSharedPreferences("tv_library",0).all.toMap()
        val isolated=object:ContextWrapper(original) { override fun getSharedPreferences(name:String,mode:Int)=baseContext.getSharedPreferences("background_fixture_$name",mode) }
        isolated.getSharedPreferences("tv_settings",0).edit().clear().commit()
        TvPreferences(isolated).apply { incognito=true;danmakuEnabled=false;controlsSeconds=10;speed=1f }
        val server=AdaptiveDownloadRegression.Server(mapOf("/background.mp4" to test.context.assets.open("tracks-fixture.mp4").use { it.readBytes() }),0)
        val activity=test.startActivitySync(Intent(original,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        var controller:MediaController?=null
        fun player():Player? {
            fun find(v:View):Player? { if(v is PlayerView&&v.player!=null)return v.player;if(v is ViewGroup)for(i in 0 until v.childCount)find(v.getChildAt(i))?.let { return it };return null }
            return find(activity.window.decorView)
        }
        fun await(label:String,condition:()->Boolean) { repeat(150) { var ok=false;test.runOnMainSync { ok=condition() };if(ok)return;Thread.sleep(100) };error("timeout $label") }
        fun shot(name:String) { test.uiAutomation.takeScreenshot()?.let { b->java.io.File(original.getExternalFilesDir(null),name).outputStream().use { b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) };b.recycle() } }
        try {
            test.runOnMainSync { activity.setContent { CompositionLocalProvider(LocalContext provides isolated) { KazumiTheme(false) {
                PlayerScreen(PlaybackRequest("http://127.0.0.1:${server.port}/background.mp4",emptyMap(),"后台恢复测试",mimeType="video/mp4"),
                    Subject(19000925,"后台恢复测试","",""),initialPosition=0,initialPlayWhenReady=false,onClose={})
            } } } }
            await("prepared foreground player") { player()?.playbackState==Player.STATE_READY }
            lateinit var future:com.google.common.util.concurrent.ListenableFuture<MediaController>
            test.runOnMainSync {
                val mediaId=checkNotNull(player()).currentMediaItem!!.mediaId
                // Test-only lookup, verified against bundled Media3 1.8.0. No public lookup exists for
                // a session owned privately by PlayerScreen. Match this exact media ID; never another app.
                val lockField=MediaSession::class.java.getDeclaredField("STATIC_LOCK").apply { isAccessible=true }
                val mapField=MediaSession::class.java.getDeclaredField("SESSION_ID_TO_SESSION_MAP").apply { isAccessible=true }
                val session=synchronized(lockField.get(null)) {
                    (mapField.get(null) as Map<*,*>).values.filterIsInstance<MediaSession>().single { it.player.currentMediaItem?.mediaId==mediaId }
                }
                future=MediaController.Builder(activity,session.token).buildAsync()
            }
            controller=future.get(10,TimeUnit.SECONDS)
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PLAY)
            await("rendered advancing foreground") {
                val p=player();p!=null&&p.isPlaying&&p.currentPosition>=2000&&((p as? ExoPlayer)?.videoDecoderCounters?.renderedOutputBufferCount ?: 0)>0
            }
            val originalPlayer=run { var p:Player?=null;test.runOnMainSync { p=player() };checkNotNull(p) }
            android.os.ParcelFileDescriptor.AutoCloseInputStream(test.uiAutomation.executeShellCommand("input keyevent 3")).use { it.readBytes() }
            await("activity stopped and session disconnected") { !activity.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)&&!originalPlayer.playWhenReady&&controller?.isConnected==false }
            var stoppedAt=0L;test.runOnMainSync { stoppedAt=originalPlayer.currentPosition;controller?.play() }
            Thread.sleep(1000)
            test.runOnMainSync { check(!originalPlayer.playWhenReady);check(kotlin.math.abs(originalPlayer.currentPosition-stoppedAt)<250) }
            // REORDER_TO_FRONT resumes this existing activity; no new playback screen is mounted.
            original.startActivity(Intent(original,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
            await("same activity resumed paused") { activity.lifecycle.currentState==Lifecycle.State.RESUMED&&player()===originalPlayer&&!originalPlayer.playWhenReady }
            Thread.sleep(750)
            test.runOnMainSync { check(kotlin.math.abs(originalPlayer.currentPosition-stoppedAt)<250) }
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_UP);Thread.sleep(150);shot("background-return-paused.png")
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PLAY)
            await("explicit continue advances") { originalPlayer.isPlaying&&originalPlayer.currentPosition>stoppedAt+1500 }
            shot("background-explicit-resume.png")
        } catch(failure:Throwable) { runCatching { shot("background-playback-failure.png") };throw failure }
        finally {
            test.runOnMainSync { controller?.release();activity.setContent { };activity.finish() };test.waitForIdleSync();server.close()
            isolated.getSharedPreferences("tv_settings",0).edit().clear().commit()
            check(beforeSettings==original.getSharedPreferences("tv_settings",0).all)
            check(beforeLibrary==original.getSharedPreferences("tv_library",0).all)
        }
    }
}
