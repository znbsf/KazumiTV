package org.kazumi.tv

import android.app.Instrumentation
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import androidx.activity.compose.setContent
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import org.kazumi.tv.data.*
import org.kazumi.tv.playback.PlaybackSleepTimer
import org.kazumi.tv.rules.*
import org.kazumi.tv.ui.*
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** Full real-time episode through the production session, then automatic next and 10 seconds of playback.
 * Never seeks or injects STATE_ENDED. No URLs/cookies are emitted. Parent owns device selection.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object RealWatchRegression {
    fun run(test:Instrumentation,args:Bundle=Bundle()) {
        val sourceName=args.getString("sourceName") ?: "sorani"
        val maxWatchMs=(args.getString("watchMs")?.toLongOrNull() ?: 30*60_000L).coerceIn(120_000L,120*60_000L)
        val episodeIndex=(args.getString("episodeIndex")?.toIntOrNull() ?: 0).coerceAtLeast(0)
        val context=test.targetContext
        val stores=listOf("tv_settings","tv_library").associateWith { context.getSharedPreferences(it,0) }
        val snapshots=stores.mapValues { it.value.all.toMap() }
        val folder=File(context.getExternalFilesDir(null),"real-watch-${System.currentTimeMillis()}").apply { check(mkdirs()) }
        // Durable typed snapshot exists before any preferences change, including for process/crash recovery.
        for((name,values) in snapshots) {
            val json=JSONObject()
            for((key,value) in values)json.put(key,JSONObject().put("type",when(value) { is Set<*>->"set";is Boolean->"boolean";is Int->"int";is Long->"long";is Float->"float";else->"string" }).put("value",if(value is Set<*>)JSONArray(value.toList()) else value))
            File(folder,"$name.backup.json").writeText(json.toString())
        }
        val trace=File(folder,"trace.txt")
        fun report(text:String) { trace.appendText(text+"\n");test.sendStatus(0,Bundle().apply { putString("stream",text+"\n") }) }
        var activity:MainActivity?=null
        var outcome="INCOMPLETE"
        try {
            check(PlaybackSleepTimer.shared.state.value.let { it.remainingMs==0L&&!it.expired }) { "Active or expired sleep timer must be resolved before full-watch acceptance" }
            val repository=RuleRepository(context)
            val rule=repository.rules.firstOrNull { it.name.equals(sourceName,true) } ?: error("Requested installed source absent")
            val (match,roads)=runBlocking { withTimeout(90_000) {
                val found=repository.search(rule,"无职转生").firstOrNull { it.title.contains("第三季") }
                    ?: error("Third season not present; no silent title fallback")
                found to repository.chapters(rule,found)
            } }
            val roadIndex=roads.indexOfFirst { it.episodes.size>episodeIndex+1 }
            check(roadIndex>=0) { "Need selected episode plus a next episode in one real road" }
            val episode=roads[roadIndex].episodes[episodeIndex]
            val next=roads[roadIndex].episodes[episodeIndex+1]
            report("source=${rule.name}; title=${match.title}; road=$roadIndex; start=${episode.title}; next=${next.title}; budget_ms=$maxWatchMs")
            val prefs=TvPreferences(context)
            prefs.incognito=true;prefs.resumePlayback=false;prefs.autoNext=true;prefs.speed=1f;prefs.danmakuEnabled=false
            report("Scope: real-time playback and automatic next; danmaku disabled; actual settings/library backup saved before changes")
            activity=test.startActivitySync(Intent(context,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            val selected=AtomicReference(episode.pageUrl)
            val active=checkNotNull(activity)
            test.runOnMainSync { active.setContent { KazumiTheme(false) {
                PlaybackSessionScreen(Subject(19000922,match.title,"",""),rule.name,episode,
                    initialRoads=roads,initialRoad=roadIndex,
                    initialOrigin=PlaybackOrigin(rule.name,match.title,match.url,roads[roadIndex].title),
                    sourceCatalog=repository,onSelection={ selected.set(it.pageUrl) },onClose={})
            } } }
            fun find(view:View):Player? {
                if(view is PlayerView && view.player!=null)return view.player
                if(view is ViewGroup)for(i in 0 until view.childCount)find(view.getChildAt(i))?.let { return it }
                return null
            }
            fun shot(name:String) { test.uiAutomation.takeScreenshot()?.let { b->File(folder,name).outputStream().use { b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) };b.recycle() } }
            val begin=SystemClock.elapsedRealtime()
            var first:Player?=null
            val ended=AtomicBoolean(false)
            val failure=AtomicReference<String?>(null)
            val listener=object:Player.Listener {
                override fun onPlaybackStateChanged(state:Int) { if(state==Player.STATE_ENDED)ended.set(true) }
                override fun onPlayerError(error:androidx.media3.common.PlaybackException) { failure.set("player_error_code=${error.errorCode}") }
            }
            var firstDuration=0L
            var firstAt=0L
            var lastPosition=0L
            var lastSample=begin
            var lastAdvanced=begin
            var lastReport=begin-60_000
            var middleShot=false
            var nextShot=false
            while(SystemClock.elapsedRealtime()-begin<maxWatchMs) {
                val now=SystemClock.elapsedRealtime()
                var player:Player?=null;var position=0L;var duration=0L;var state=0;var frames=0;var dropped=0;var speed=0f
                test.runOnMainSync {
                    player=find(active.window.decorView)
                    player?.let { p->
                        position=p.currentPosition;duration=p.duration;state=p.playbackState;speed=p.playbackParameters.speed
                        (p as? ExoPlayer)?.videoDecoderCounters?.let { frames=it.renderedOutputBufferCount;dropped=it.droppedBufferCount }
                        if(first==null) { first=p;p.addListener(listener) }
                        p.playerError?.let { failure.set("player_error_code=${it.errorCode}") }
                    }
                }
                failure.get()?.let { error(it) }
                if(firstAt==0L && frames>0 && player===first) {
                    check(position in 0..2000) { "Full-watch did not begin near zero" }
                    check(duration in 60_000..(maxWatchMs-60_000)) { "Unknown or out-of-budget duration; no partial-watch pass" }
                    firstDuration=duration;firstAt=now;lastPosition=position;lastSample=now;lastAdvanced=now
                    report("first_frame duration_ms=$duration position_ms=$position")
                    shot("first-frame.png")
                }
                if(firstAt==0L && now-begin>90_000)error("No rendered frame within 90 seconds")
                if(firstAt>0 && player===first) {
                    check(speed==1f) { "Full-watch requires actual 1x speed" }
                    check(position-lastPosition<=now-lastSample+5000) { "Unexpected forward jump; full-watch invalid" }
                    if(position>lastPosition)lastAdvanced=now
                    if(!ended.get()&&now-lastAdvanced>90_000)error("Playback stalled longer than 90 seconds")
                    lastPosition=position;lastSample=now
                    if(!middleShot && position>=firstDuration/2) {
                        middleShot=true
                        test.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_DPAD_UP)
                        Thread.sleep(250);shot("midwatch-controls.png")
                    }
                }
                if(now-lastReport>=60_000) {
                    val memory=android.os.Debug.MemoryInfo().also { android.os.Debug.getMemoryInfo(it) }
                    report("elapsed_ms=${now-begin}; episode=${if(selected.get()==episode.pageUrl) "initial" else if(selected.get()==next.pageUrl) "next" else "unexpected"}; position_ms=$position; duration_ms=$duration; state=$state; rendered=$frames; dropped=$dropped; pss_kib=${memory.totalPss}")
                    lastReport=now
                }
                if(player!=null && player!==first && selected.get()==next.pageUrl && frames>0) {
                    check(ended.get()) { "Episode switched without observed natural end" }
                    check(firstAt>0 && now-firstAt>=firstDuration-3000) { "Elapsed real time did not cover a full episode" }
                    if(!nextShot) { nextShot=true;shot("automatic-next.png") }
                    if(position>=10_000 && state==Player.STATE_READY) {
                        outcome="PASS full_episode_real_time=true automatic_next=true next_progress_ms=$position"
                        report(outcome);break
                    }
                }
                Thread.sleep(1000)
            }
            check(outcome.startsWith("PASS")) { "Watch budget exhausted without full episode and 10 seconds of automatic next" }
        } catch(failure:Throwable) {
            outcome="FAIL ${failure.javaClass.simpleName}"
            report(outcome)
            throw failure
        } finally {
            try {
                activity?.let { a->test.runOnMainSync { a.setContent { };a.finish() };test.waitForIdleSync() }
            } finally {
                val restorationFailures=stores.mapNotNull { (name,prefs)->runCatching { restore(prefs,snapshots.getValue(name)) }.exceptionOrNull() }
                File(folder,"result.txt").writeText(outcome+"\nactual_settings_and_library_restored=${restorationFailures.isEmpty()}\n")
                restorationFailures.firstOrNull()?.let { throw it }
            }
        }
    }
    private fun restore(prefs:SharedPreferences,values:Map<String,*>) {
        val edit=prefs.edit().clear()
        for((key,value) in values)when(value) {
            is String->edit.putString(key,value);is Boolean->edit.putBoolean(key,value);is Int->edit.putInt(key,value)
            is Long->edit.putLong(key,value);is Float->edit.putFloat(key,value)
            is Set<*>->{ @Suppress("UNCHECKED_CAST") edit.putStringSet(key,value as Set<String>) }
        }
        check(edit.commit());check(prefs.all==values) { "Actual preferences restoration mismatch" }
    }
}
