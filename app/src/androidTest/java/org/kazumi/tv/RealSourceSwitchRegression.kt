package org.kazumi.tv

import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.KeyEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.kazumi.tv.data.*
import org.kazumi.tv.domain.EpisodeNumber
import org.kazumi.tv.rules.*
import org.kazumi.tv.ui.*
import java.io.File
import kotlin.math.abs

/** Cross-source production UI, real rules/search/chapters/media. No injected playback state.
 * A durable checkpoint protects the real stores used by Compose Dialog; not full-watch evidence.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object RealSourceSwitchRegression {
    fun run(test:Instrumentation,args:Bundle=Bundle()):String {
        val context=test.targetContext
        val sourceName=args.getString("sourceName") ?: "baimao"
        val targetName=args.getString("targetName") ?: "MXdm"
        val episodeIndex=(args.getString("episodeIndex")?.toIntOrNull() ?: 11).coerceAtLeast(0)
        val targetRoad=(args.getString("targetRoad")?.toIntOrNull() ?: 0).coerceAtLeast(0)
        val verifyReentry=args.getString("verifyReentry")=="true"
        val verifyStandby=args.getString("verifyStandby")=="true"
        require(!verifyStandby||verifyReentry)
        val power=context.getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
        var powerOwned=false
        fun shell(command:String) { android.os.ParcelFileDescriptor.AutoCloseInputStream(test.uiAutomation.executeShellCommand(command)).use { it.readBytes() } }
        val start=SystemClock.elapsedRealtime()
        val budget=(args.getString("maxMs")?.toLongOrNull() ?: 240_000L).coerceIn(90_000L,300_000L)
        val snapshots=listOf("tv_settings","tv_library","search_history").associateWith { context.getSharedPreferences(it,0).all.toMap() }
        val checkpoint="source-switch-${System.currentTimeMillis()}"
        val folder=File(context.getExternalFilesDir(null),checkpoint).apply { check(mkdirs()) }
        var checkpointSaved=false
        var activity:MainActivity?=null
        var phase="catalogue"
        fun report(message:String) {
            File(folder,"trace.txt").appendText(message+"\n")
            test.sendStatus(0,Bundle().apply { putString("stream",message+"\n") })
        }
        fun shot(name:String) { test.uiAutomation.takeScreenshot()?.let { b->
            File(folder,"$name.png").outputStream().use { b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) };b.recycle()
        } }
        fun nodes():List<AccessibilityNodeInfo> {
            val result=mutableListOf<AccessibilityNodeInfo>()
            fun visit(n:AccessibilityNodeInfo?) { if(n==null)return;result.add(n);for(i in 0 until n.childCount)visit(n.getChild(i)) }
            visit(test.uiAutomation.rootInActiveWindow);return result
        }
        fun has(text:String)=nodes().any { it.text?.toString()==text }
        fun await(label:String,limit:Long=90_000,condition:()->Boolean) {
            val end=minOf(start+budget,SystemClock.elapsedRealtime()+limit)
            while(SystemClock.elapsedRealtime()<end) { if(condition())return;Thread.sleep(200) }
            report("timeout=$label phase=$phase")
            error("source_switch_timeout")
        }
        fun click(text:String) {
            await("button",20_000) { has(text) }
            var n=nodes().first { it.text?.toString()==text }
            while(!n.isClickable)n=n.parent ?: error("source_switch_target_not_clickable")
            check(n.performAction(AccessibilityNodeInfo.ACTION_CLICK));Thread.sleep(250)
        }
        fun clockMs():Long?=nodes().mapNotNull { Regex("^(\\d+):(\\d{2}) / (\\d+):(\\d{2})$").matchEntire(it.text?.toString().orEmpty()) }
            .firstOrNull()?.let { (it.groupValues[1].toLong()*60+it.groupValues[2].toLong())*1000 }
        try {
            report("checkpoint_label=$checkpoint; temporary real-store writes; original stores restored in finally")
            report(UserDataCheckpoint.run(test,"user-data-backup",checkpoint));checkpointSaved=true
            val sequence=java.util.concurrent.atomic.AtomicInteger()
            val repository=RuleRepository(context) { rule,page ->
                if(args.getString("captureResponses")=="true") {
                    val id=sequence.incrementAndGet()
                    val prefix="response-$id-${rule.name.replace(Regex("[^A-Za-z0-9_-]"),"_")}"
                    // App-private diagnostic artifacts only; never emit bodies, URLs or cookies.
                    File(folder,"$prefix.html").writeText(page.body)
                    val digest=java.security.MessageDigest.getInstance("SHA-256").digest(page.body.toByteArray()).joinToString("") { "%02x".format(it) }
                    report("response=$id source=${rule.name} phase=$phase http=${page.status} chars=${page.body.length} sha256=$digest")
                }
            }
            val from=repository.rules.firstOrNull { it.name.equals(sourceName,true) } ?: error("source_missing")
            val to=repository.rules.firstOrNull { it.name.equals(targetName,true) } ?: error("target_missing")
            check(from.name!=to.name)
            // Limits UI search to two genuine installed rules; no synthetic matches or roads.
            val catalog=object:SourceCatalog {
                override val rules=listOf(from,to)
                override suspend fun search(rule:SourceRule,keyword:String):List<SourceMatch> {
                    val found=repository.search(rule,keyword)
                    val expectedKeyword=keyword=="无职转生"
                    report("ui_search source=${rule.name} expected_keyword=$expectedKeyword count=${found.size}")
                    return found
                }
                override suspend fun chapters(rule:SourceRule,match:SourceMatch)=repository.chapters(rule,match)
            }
            val prepared=runBlocking { withTimeout(80_000) {
                val firstMatch=repository.search(from,"无职转生").filter { it.title.contains("第三季") }.singleOrNull() ?: error("source_season_ambiguous")
                val targetMatch=repository.search(to,"无职转生").filter { it.title.contains("第三季") }.singleOrNull() ?: error("target_season_ambiguous")
                Triple(firstMatch to repository.chapters(from,firstMatch),targetMatch,repository.chapters(to,targetMatch))
            } }
            val firstMatch=prepared.first.first;val firstRoad=prepared.first.second.firstOrNull() ?: error("source_road_missing")
            val first=firstRoad.episodes.getOrNull(episodeIndex) ?: error("source_episode_missing")
            val nextRoad=prepared.third.getOrNull(targetRoad) ?: error("target_road_missing")
            val number=EpisodeNumber.parse(first.title) ?: error("source_episode_number_missing")
            val target=nextRoad.episodes.filter { EpisodeNumber.parse(it.title)==number }.singleOrNull() ?: error("target_episode_ambiguous")
            val targetIndex=nextRoad.episodes.indexOf(target)
            val subject=Subject(19000924,firstMatch.title,"","")
            val sourceKey="${from.name}|${first.pageUrl}";val targetKey="${to.name}|${target.pageUrl}"
            val library=LibraryStore(context)
            check(library.history().none { it.subject.id==subject.id }) { "restore_stale_acceptance_checkpoint_first" }
            TvPreferences(context).apply { incognito=false;resumePlayback=verifyReentry;autoNext=false;speed=1f;danmakuEnabled=false;controlsSeconds=10;seekSeconds=10 }
            report("source=${from.name} target=${to.name} episode=${first.title} target_road=$targetRoad; real network; no full-watch claim")
            activity=test.startActivitySync(Intent(context,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            val host=activity!!
            test.runOnMainSync { host.setContent { KazumiTheme(false) {
                Box(Modifier.fillMaxSize().padding(24.dp)) {
                    SourceScreen(subject,catalog=catalog,initialHistory=HistoryEntry(sourceKey,subject,first.title,0,0,
                        PlaybackOrigin(from.name,firstMatch.title,firstMatch.url,firstRoad.title)))
                }
            } } }
            phase="initial_play"
            await("initial_episode_browser") { nodes().any { it.text?.toString()?.let { s->s.startsWith("${episodeIndex+1}.")&&s.contains(first.title) }==true } }
            click(nodes().first { it.text?.toString()?.let { s->s.startsWith("${episodeIndex+1}.")&&s.contains(first.title) }==true }.text.toString())
            await("initial_rendered_progress") { library.history().any { it.subject.id==subject.id&&it.key==sourceKey&&it.position>=6000&&it.duration>60_000 } }
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PAUSE)
            await("initial_pause",10_000) { has("▷ 播放")&&clockMs()!=null }
            val paused=clockMs()!!;check(paused>=5000)
            phase="cancel_source_menu"
            click("换源");await("source_menu",10_000) { has("返回播放") }
            click(to.name)
            click("返回播放")
            await("cancel_paused_ready") { has("▷ 播放")&&clockMs()?.let { abs(it-paused)<=2000 }==true }
            val cancelledAt=clockMs()!!;Thread.sleep(2500)
            check(has("▷ 播放")&&abs((clockMs() ?: -10000)-cancelledAt)<=1000)
            report("cancel_source=PASS position_before_ms=$paused position_after_ms=$cancelledAt")
            shot("01-cancel-paused")
            phase="commit_cross_source"
            click("▷ 播放")
            await("playing_before_seek",10_000) { clockMs()?.let { it>=cancelledAt+2000 }==true }
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD);test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD)
            await("seek_checkpoint",15_000) { clockMs()?.let { it>=cancelledAt+15000 }==true }
            val before=clockMs()!!
            click("换源");await("source_menu_again",10_000) { has("返回播放") }
            click(to.name)
            // Adjust the visible keyword as a user can: source display titles may contain
            // punctuation/suffixes that another site's search does not accept verbatim.
            val keyword=nodes().firstOrNull { it.isEditable } ?: error("source_keyword_input_missing")
            check(keyword.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,"无职转生")
            }))
            await("edited_keyword_visible",10_000) { nodes().any { it.isEditable&&it.text?.toString()=="无职转生" } }
            test.waitForIdleSync()
            click("重新搜索")
            await("target_real_search_result",60_000) { has(prepared.second.title) }
            // The visible source result is selected normally; production matching chooses the same episode.
            click(prepared.second.title)
            if(targetRoad!=0)click(nextRoad.title)
            click("续播 ${target.title} · 保留进度")
            await("target_first_rendered_progress") { library.history().any { it.subject.id==subject.id&&it.key==targetKey&&it.duration>60_000 } }
            val targetFirst=library.history().first { it.key==targetKey }.position
            check(targetFirst in (before-2000)..(before+15000)) { "cross_source_started_outside_saved_position" }
            await("target_short_advance",20_000) { library.history().any { it.key==targetKey&&it.position>=targetFirst+3000 } }
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PAUSE)
            await("target_pause",10_000) { has("▷ 播放")&&clockMs()!=null }
            report("cross_source=PASS before_ms=$before target_first_ms=$targetFirst after_ms=${clockMs()} source=${to.name}")
            shot("02-target-source")
            phase="return_target_episodes"
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
            await("return_target_selected_episode",15_000) {
                has("返回匹配结果")&&nodes().any { it.text?.toString()?.let { s->s.startsWith("${targetIndex+1}.")&&s.contains(target.title)&&s.contains("当前") }==true }
            }
            val saved=library.history().first { it.key==targetKey }
            check(saved.origin?.rule==to.name&&saved.origin?.roadTitle==nextRoad.title)
            report("return=PASS source=${to.name} road=${nextRoad.title} episode=${target.title}")
            shot("03-return-target-episodes")
            if(verifyReentry) {
                phase="reenter_target_episode"
                val savedAt=saved.position
                val label=nodes().first { it.text?.toString()?.let { s->s.startsWith("${targetIndex+1}.")&&s.contains(target.title)&&s.contains("当前") }==true }.text.toString()
                click(label)
                await("reentered_target_advance") { library.history().any { it.key==targetKey&&it.position>=savedAt+3000 } }
                test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PAUSE)
                await("reentered_target_pause",10_000) { has("▷ 播放")&&clockMs()!=null }
                val reenteredAt=clockMs()!!
                check(reenteredAt in savedAt..(savedAt+20_000)) { "reentry_lost_saved_position" }
                report("reentry=PASS saved_ms=$savedAt reentered_ms=$reenteredAt source=${to.name} episode=${target.title}")
                shot("04-target-reentry")
                if(verifyStandby) {
                    phase="power_standby"
                    check(power.isInteractive) { "standby_requires_initially_awake_device" }
                    // Resolve only this app's single active test session, never another app's media.
                    lateinit var activePlayer:androidx.media3.common.Player
                    test.runOnMainSync {
                        val type=androidx.media3.session.MediaSession::class.java
                        val lock=type.getDeclaredField("STATIC_LOCK").apply { isAccessible=true }.get(null)
                        val sessions=type.getDeclaredField("SESSION_ID_TO_SESSION_MAP").apply { isAccessible=true }
                        activePlayer=synchronized(lock) {
                            (sessions.get(null) as Map<*,*>).values.filterIsInstance<androidx.media3.session.MediaSession>()
                                .single { it.player.mediaMetadata.title?.toString()=="${subject.title} · ${target.title}" }.player
                        }
                    }
                    fun playerState():Pair<Long,Boolean> { var result=0L to false;test.runOnMainSync { result=activePlayer.currentPosition to activePlayer.playWhenReady };return result }
                    test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PLAY)
                    await("playing_before_standby",10_000) { playerState().let { it.second&&it.first>reenteredAt+1000 } }
                    powerOwned=true;shell("input keyevent 26")
                    await("device_became_noninteractive",10_000) { !power.isInteractive }
                    await("playback_paused_on_screen_off",10_000) { !playerState().second }
                    val stoppedAt=playerState().first
                    Thread.sleep(2000)
                    check(abs(playerState().first-stoppedAt)<350) { "playback_advanced_while_screen_off" }
                    if(!power.isInteractive)shell("input keyevent 26")
                    await("device_awake",15_000) { power.isInteractive };powerOwned=false
                    context.startActivity(Intent(context,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
                    await("same_activity_resumed",15_000) { var resumed=false;test.runOnMainSync { resumed=host.lifecycle.currentState==androidx.lifecycle.Lifecycle.State.RESUMED };resumed }
                    check(!playerState().second&&abs(playerState().first-stoppedAt)<1000) { "wake_did_not_preserve_pause_position" }
                    test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PLAY)
                    await("explicit_continue_after_standby",20_000) { playerState().let { it.second&&it.first>stoppedAt+3000 } }
                    test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PAUSE)
                    report("standby=PASS noninteractive=true stable_pause=true explicit_resume=true before_ms=$stoppedAt after_ms=${playerState().first}; short_screen_off_not_deep_power_cycle")
                    shot("05-standby-resumed")
                }
            }
            return "real_source_switch=PASS cancel_pause=PASS same_episode_progress=PASS real_target_advance=PASS return_target_context=PASS reentry=${if(verifyReentry)"PASS" else "NOT_RUN"} standby=${if(verifyStandby)"PASS" else "NOT_RUN"}"
        } catch(failure:Exception) {
            report("result=FAIL phase=$phase error=${failure.javaClass.simpleName}");shot("failure");throw failure
        } finally {
            if(powerOwned&&!power.isInteractive)runCatching { shell("input keyevent 26") }
            try {
                activity?.let { host->
                    test.runOnMainSync { host.finish() };test.waitForIdleSync()
                    val end=SystemClock.elapsedRealtime()+8000
                    while(!host.isDestroyed&&SystemClock.elapsedRealtime()<end)Thread.sleep(100)
                    check(host.isDestroyed)
                }
            } finally {
                if(checkpointSaved) {
                    report(UserDataCheckpoint.run(test,"user-data-restore",checkpoint));test.waitForIdleSync()
                    check(snapshots.all { (name,values)->context.getSharedPreferences(name,0).all==values })
                    report("user_data_restored_and_equal=true checkpoint_label=$checkpoint stores=3")
                }
            }
        }
    }
}
