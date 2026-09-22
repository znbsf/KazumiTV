package org.kazumi.tv

import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.KeyEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.kazumi.tv.data.*
import org.kazumi.tv.domain.PlaybackIdentity
import org.kazumi.tv.rules.*
import org.kazumi.tv.ui.*
import java.io.File
import kotlin.math.abs

/** Real catalogue/media and production SourceScreen -> player -> road chooser -> episodes.
 * Dialog reads the real application preferences: durable three-store checkpoint + finally restore.
 * No injected media, player state or fake catalogue. The subject ID marks acceptance records.
 * Acceptance is deliberately short-play A04 evidence, never a complete-episode claim.
 */
object RealRoadSwitchRegression {
    fun run(test:Instrumentation,args:Bundle=Bundle()):String {
        val sourceName=args.getString("sourceName") ?: "baimao"
        val from=(args.getString("roadFrom")?.toIntOrNull() ?: 0).coerceAtLeast(0)
        val to=(args.getString("roadTo")?.toIntOrNull() ?: 1).coerceAtLeast(0)
        val episodeIndex=(args.getString("episodeIndex")?.toIntOrNull() ?: 11).coerceAtLeast(0)
        val start=SystemClock.elapsedRealtime()
        val budget=(args.getString("maxMs")?.toLongOrNull() ?: 240_000).coerceIn(90_000,300_000)
        val context=test.targetContext
        val snapshots=listOf("tv_settings","tv_library","search_history").associateWith { context.getSharedPreferences(it,0).all.toMap() }
        val checkpoint="road-switch-${System.currentTimeMillis()}"
        var checkpointSaved=false
        var activity:MainActivity?=null
        var phase="catalogue"
        val folder=File(test.targetContext.getExternalFilesDir(null),"real-road-switch-${System.currentTimeMillis()}").apply { check(mkdirs()) }
        fun report(message:String) {
            File(folder,"trace.txt").appendText(message+"\n")
            test.sendStatus(0,Bundle().apply { putString("stream",message+"\n") })
        }
        fun shot(name:String) { test.uiAutomation.takeScreenshot()?.let { bitmap ->
            File(folder,"$name.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) };bitmap.recycle()
        } }
        fun nodes():List<AccessibilityNodeInfo> {
            val result=mutableListOf<AccessibilityNodeInfo>()
            fun visit(node:AccessibilityNodeInfo?) { if(node==null)return;result.add(node);for(i in 0 until node.childCount)visit(node.getChild(i)) }
            visit(test.uiAutomation.rootInActiveWindow);return result
        }
        fun has(label:String)=nodes().any { it.text?.toString()==label }
        fun await(label:String,limit:Long=90_000,predicate:()->Boolean) {
            val until=minOf(start+budget,SystemClock.elapsedRealtime()+limit)
            while(SystemClock.elapsedRealtime()<until) { if(predicate())return;Thread.sleep(200) }
            error("timeout_$label")
        }
        fun click(label:String) {
            await("button",15_000) { has(label) }
            var node=nodes().first { it.text?.toString()==label }
            while(!node.isClickable)node=node.parent ?: error("not_clickable")
            check(node.performAction(AccessibilityNodeInfo.ACTION_CLICK));Thread.sleep(250)
        }
        fun clockMs():Long? = nodes().mapNotNull { node ->
            Regex("^(\\d+):(\\d{2}) / (\\d+):(\\d{2})$").matchEntire(node.text?.toString().orEmpty())
        }.firstOrNull()?.let { (it.groupValues[1].toLong()*60+it.groupValues[2].toLong())*1000 }
        try {
            report("checkpoint_label=$checkpoint; stores=tv_settings,tv_library,search_history; temporary real-store writes with mandatory restore")
            report(UserDataCheckpoint.run(test,"user-data-backup",checkpoint))
            checkpointSaved=true
            val repository=RuleRepository(test.targetContext)
            val rule=repository.rules.firstOrNull { it.name.equals(sourceName,true) } ?: error("installed_source_missing")
            val (match,roads)=runBlocking { withTimeout(80_000) {
                val found=repository.search(rule,"无职转生").firstOrNull { it.title.contains("第三季") }
                    ?: error("exact_season_missing")
                found to repository.chapters(rule,found)
            } }
            check(from!=to && from in roads.indices && to in roads.indices) { "requested_road_missing" }
            val first=roads[from].episodes.getOrNull(episodeIndex) ?: error("requested_episode_missing")
            val targetIndex=PlaybackIdentity.matchingEpisode(first,roads[to].episodes) ?: error("same_episode_not_unique")
            val target=roads[to].episodes[targetIndex]
            check(first.pageUrl!=target.pageUrl) { "same_page_is_not_meaningful_road_switch" }
            check(roads.map { it.title }.distinct().size==roads.size) { "road_labels_not_unique" }
            val subject=Subject(19000923,match.title,"","")
            val origin=PlaybackOrigin(rule.name,match.title,match.url,roads[from].title)
            val firstKey="${rule.name}|${first.pageUrl}";val targetKey="${rule.name}|${target.pageUrl}"
            val library=LibraryStore(context)
            check(library.history().none { it.subject.id==subject.id }) { "stale_acceptance_history_restore_previous_checkpoint_first" }
            TvPreferences(context).apply { incognito=false;resumePlayback=false;autoNext=false;speed=1f;danmakuEnabled=false;controlsSeconds=10;seekSeconds=10 }
            report("source=${rule.name} from=$from to=$to episode=${first.title}; real media and real Dialog history; checkpoint=$checkpoint; no full-watch claim")
            activity=test.startActivitySync(Intent(test.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            val active=activity!!
            test.runOnMainSync { active.setContent {
                CompositionLocalProvider(LocalContext provides context) { KazumiTheme(false) {
                    Box(Modifier.fillMaxSize().padding(24.dp)) {
                        SourceScreen(subject,catalog=repository,initialHistory=HistoryEntry(firstKey,subject,first.title,0,0,origin))
                    }
                } }
            } }
            phase="initial_play"
            await("episode_browser") { nodes().any { it.text?.toString()?.let { value->value.startsWith("${episodeIndex+1}.")&&value.contains(first.title) }==true } }
            click(nodes().first { it.text?.toString()?.let { value->value.startsWith("${episodeIndex+1}.")&&value.contains(first.title) }==true }.text.toString())
            await("rendered_progress") { library.history().any { it.subject.id==subject.id&&it.key==firstKey&&it.position>=6000&&it.duration>60_000 } }
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PAUSE)
            await("initial_pause",10_000) { has("▷ 播放") && clockMs()!=null }
            val paused=clockMs()!!
            check(paused>=5000)
            report("initial_progress_ms=$paused rendered_history=true")
            shot("01-paused")
            phase="cancel_paused_road_menu"
            click("线路");await("road_menu",10_000) { has("选择线路 · 仅确认同一集时继承进度") }
            click("返回播放")
            await("cancel_paused_ready") { has("▷ 播放")&&clockMs()?.let { abs(it-paused)<=2000 }==true }
            val afterCancel=clockMs()!!
            Thread.sleep(2500)
            check(has("▷ 播放") && abs((clockMs() ?: -10000)-afterCancel)<=1000) { "cancel_changed_pause_or_position" }
            report("cancel=PASS paused_before_ms=$paused paused_after_ms=$afterCancel")
            shot("02-cancel-paused")
            phase="commit_playing_road_switch"
            click("▷ 播放")
            await("explicit_play",10_000) { has("Ⅱ 暂停")&&clockMs()?.let { it>=afterCancel+2000 }==true }
            // Remote seek establishes a clearly nonzero checkpoint; it is not full-watch evidence.
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD)
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD)
            await("remote_seek_checkpoint",15_000) { clockMs()?.let { it>=afterCancel+15000 }==true }
            val switchPosition=clockMs()!!
            report("remote_seek_checkpoint_ms=$switchPosition")
            click("线路");await("commit_menu",10_000) { has("选择线路 · 仅确认同一集时继承进度") }
            click(roads[to].title.ifBlank { "线路 ${to+1}" })
            // History is written only after a real rendered frame. Target key proves the selected road.
            await("target_rendered_frame") { library.history().any { it.subject.id==subject.id&&it.key==targetKey&&it.duration>60_000 } }
            val firstTarget=library.history().first { it.key==targetKey }.position
            check(firstTarget in (switchPosition-2000)..(switchPosition+15000)) { "target_started_outside_preserved_position" }
            await("target_rendered_progress",20_000) { library.history().any { it.key==targetKey&&it.position>=firstTarget+3000 } }
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PAUSE)
            await("target_pause",10_000) { has("▷ 播放")&&clockMs()!=null }
            val switched=clockMs()!!
            check(switched>=switchPosition && switched<=switchPosition+35_000) { "switch_position_not_preserved" }
            report("switch=PASS before_ms=$switchPosition after_ms=$switched target_road=$to target_episode=${target.title}")
            shot("03-target-road")
            phase="return_episode_browser"
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
            await("returned_selected_episode",15_000) {
                has("返回匹配结果") && nodes().any { it.text?.toString()?.let { value->value.startsWith("${targetIndex+1}.")&&value.contains(target.title)&&value.contains("当前") }==true }
            }
            // Returning must retain target road context, rather than the original dialog arguments.
            val saved=library.history().first { it.key==targetKey }
            check(saved.origin?.roadTitle==roads[to].title)
            report("return=PASS origin_road=${saved.origin?.roadTitle} current_episode=${target.title} duration_ms=${saved.duration}")
            shot("04-returned-episodes")
            return "real_road_switch=PASS cancel_paused=PASS same_episode_progress=PASS target_short_advance=PASS return_selection=PASS"
        } catch(failure:Exception) {
            report("result=FAIL phase=$phase error=${failure.javaClass.simpleName}")
            shot("failure");throw failure
        } finally {
            try {
                activity?.let { active->
                    test.runOnMainSync { active.finish() };test.waitForIdleSync()
                    val stopDeadline=SystemClock.elapsedRealtime()+8000
                    while(!active.isDestroyed && SystemClock.elapsedRealtime()<stopDeadline)Thread.sleep(100)
                    check(active.isDestroyed) { "activity_not_destroyed_before_restore" }
                }
            } finally {
                if(checkpointSaved) {
                    report(UserDataCheckpoint.run(test,"user-data-restore",checkpoint))
                    test.waitForIdleSync()
                    check(snapshots.all { (name,values)->context.getSharedPreferences(name,0).all==values }) { "user_data_differs_after_restore" }
                    report("user_data_restored_and_equal=true checkpoint_label=$checkpoint stores=3")
                }
            }
        }
    }
}
