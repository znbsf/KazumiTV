package org.kazumi.tv

import android.app.Instrumentation
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import com.google.common.util.concurrent.ListenableFuture
import org.kazumi.tv.playback.NativePlayer
import org.kazumi.tv.playback.PlaybackRequest
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Actual MediaController connection verifies advertised commands and dispatched episode callbacks. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object EpisodeMediaSessionRegression {
    fun run(test: Instrumentation): String {
        val sample=java.io.File(test.targetContext.cacheDir,"episode-session-fixture.mp4")
        test.context.assets.open("tracks-fixture.mp4").use { input -> sample.outputStream().use { input.copyTo(it) } }
        fun await(label:String,predicate:()->Boolean) {
            val end=System.currentTimeMillis()+10000
            while(System.currentTimeMillis()<end) {
                var success=false;test.runOnMainSync { success=predicate() };if(success)return;Thread.sleep(100)
            }
            error("Episode session timeout: $label")
        }
        try {
            for(previous in listOf(false,true)) {
                lateinit var engine:NativePlayer
                var created=false
                lateinit var future:ListenableFuture<MediaController>
                var controller:MediaController?=null
                val selected=AtomicInteger()
                try {
                    test.runOnMainSync {
                        engine=NativePlayer(test.targetContext,sample.toURI().toString())
                        created=true
                        engine.open(PlaybackRequest(sample.toURI().toString(),emptyMap(),"系统选集样片"))
                        engine.player.pause()
                        future=MediaController.Builder(test.targetContext,engine.sessionToken!!).buildAsync()
                    }
                    controller=future.get(10,TimeUnit.SECONDS)
                    val remote=checkNotNull(controller)
                    val command=if(previous)Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM else Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM
                    val opposite=if(previous)Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM else Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM
                    await("no neighbour commands") { !remote.availableCommands.contains(command)&&!remote.availableCommands.contains(opposite) }
                    test.runOnMainSync { engine.setEpisodeNavigation(if(previous)({selected.incrementAndGet();Unit})else null,if(!previous)({selected.incrementAndGet();Unit})else null) }
                    await("dynamic neighbour command") { remote.availableCommands.contains(command)&&!remote.availableCommands.contains(opposite) }
                    test.runOnMainSync { if(previous)remote.seekToPreviousMediaItem()else remote.seekToNextMediaItem() }
                    await("select neighbour once") { selected.get()==1 }
                    await("selection removes duplicate command") { !remote.availableCommands.contains(command) }
                    test.runOnMainSync { if(previous)remote.seekToPrevious()else remote.seekToNext() }
                    Thread.sleep(300);check(selected.get()==1)
                    test.runOnMainSync { engine.setForegroundActive(false) }
                    await("background disconnect") { !remote.isConnected&&engine.sessionToken==null }
                    test.runOnMainSync { if(previous)remote.seekToPreviousMediaItem()else remote.seekToNextMediaItem() }
                    Thread.sleep(300);check(selected.get()==1)
                    test.runOnMainSync { engine.release() }
                    Thread.sleep(200);check(selected.get()==1)
                } finally {
                    test.runOnMainSync { controller?.release();if(created)engine.release() }
                }
            }
            return "next_previous_commands=PASS dynamic_updates=PASS callback_once=PASS missing_neighbour=PASS foreground_release=PASS"
        } finally { sample.delete() }
    }
}
