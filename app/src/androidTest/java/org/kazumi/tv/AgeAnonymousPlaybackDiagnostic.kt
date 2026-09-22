package org.kazumi.tv

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.view.TextureView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import okhttp3.CookieJar
import org.json.JSONObject
import org.kazumi.tv.data.AppHttp
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Explicit diagnostic only. No history store, production resolver or authentication headers. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object AgeAnonymousPlaybackDiagnostic {
    fun run(test:Instrumentation,url:String,userAgent:String,folder:File):JSONObject {
        val activity=test.startActivitySync(Intent(test.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        val firstFrame=AtomicBoolean()
        val failure=AtomicInteger()
        var player:ExoPlayer?=null
        val result=JSONObject().put("scope","anonymous_decoder_short_test_not_production_resolver")
            .put("correctEpisodeConfirmed",false)
        fun position():Long { var value=0L;test.runOnMainSync { value=player!!.currentPosition };return value }
        fun await(label:String,timeout:Long=25000,ready:()->Boolean) {
            val end=android.os.SystemClock.elapsedRealtime()+timeout
            while(android.os.SystemClock.elapsedRealtime()<end) {
                check(failure.get()==0) { "decoder_error" }
                if(ready())return
                Thread.sleep(100)
            }
            error("timeout_$label")
        }
        fun capture(name:String) {
            val bitmap=test.uiAutomation.takeScreenshot() ?: error("screenshot_unavailable")
            try { File(folder,name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) } }
            finally { bitmap.recycle() }
        }
        try {
            test.runOnMainSync {
                val client=AppHttp.streamingClient.newBuilder().cookieJar(CookieJar.NO_COOKIES)
                    .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).build()
                val factory=OkHttpDataSource.Factory(client).setUserAgent(userAgent)
                player=ExoPlayer.Builder(activity).setMediaSourceFactory(DefaultMediaSourceFactory(activity).setDataSourceFactory(factory)).build()
                val texture=TextureView(activity)
                activity.setContentView(texture)
                player!!.setVideoTextureView(texture)
                player!!.volume=0f
                player!!.addListener(object:Player.Listener {
                    override fun onRenderedFirstFrame() { firstFrame.set(true) }
                    override fun onPlayerError(error:PlaybackException) { failure.set(error.errorCode) }
                })
                player!!.setMediaItem(MediaItem.Builder().setUri(url).setMimeType("video/mp4").build())
                player!!.prepare();player!!.play()
            }
            await("first_frame") { firstFrame.get() };result.put("firstFrame",true)
            await("advance") { position()>=5000 };result.put("advance5s",true)
            capture("frame-start.png")
            for(target in listOf(90000L,180000L)) {
                test.runOnMainSync { player!!.seekTo(target) }
                await("seek") { position()>=target+1500 }
                test.runOnMainSync { player!!.pause() }
                Thread.sleep(400)
                capture("frame-${target/1000}.png")
                val paused=position();Thread.sleep(700)
                check(kotlin.math.abs(position()-paused)<250)
                test.runOnMainSync { player!!.play() }
                await("resume") { position()>=paused+1500 }
            }
            var duration=0L;test.runOnMainSync { duration=player!!.duration }
            result.put("seekPauseResume",true).put("durationMs",duration).put("shortTestPassed",true)
        } catch(error:Exception) {
            result.put("shortTestPassed",false).put("errorType",error.javaClass.simpleName).put("playerErrorCode",failure.get())
        } finally {
            test.runOnMainSync { player?.release();activity.finish() }
        }
        return result
    }
}
