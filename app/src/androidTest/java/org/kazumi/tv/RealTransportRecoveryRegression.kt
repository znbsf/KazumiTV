package org.kazumi.tv

import android.app.Instrumentation
import android.content.ContextWrapper
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalContext
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.json.JSONArray
import org.kazumi.tv.data.*
import org.kazumi.tv.rules.RuleRepository
import org.kazumi.tv.rules.SourceRule
import org.kazumi.tv.ui.*
import java.io.File
import kotlin.math.abs

/** Real baimao requests/media, host-controlled emulator transport impairment (not physical outage).
 * Commands contain only impaired/restored/abort. No injected errors, media or resolver results.
 * Remote fast-forward is only positioning beyond the observed buffered region.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object RealTransportRecoveryRegression {
    private data class Reading(val player:ExoPlayer?,val position:Long=0,val buffered:Long=0,val duration:Long=0,
        val ready:Boolean=false,val playing:Boolean=false,val intent:Boolean=false,val frames:Int=0,val error:Int?=null,
        val state:Int=Player.STATE_IDLE,val suppression:Int=0,val videoWidth:Int=0,val videoHeight:Int=0)
    fun run(test:Instrumentation, delayedRetry:Boolean=false):String {
        val started=SystemClock.elapsedRealtime()
        val deadline=started+360_000
        val actual=test.targetContext
        val phaseFile=File(actual.getExternalFilesDir(null),"transport-recovery-phase.json")
        val commandFile=File(actual.getExternalFilesDir(null),"transport-recovery-command.txt")
        val checkpoint="transport-recovery-${System.currentTimeMillis()}"
        val before=listOf("tv_settings","tv_library","search_history").associateWith { actual.getSharedPreferences(it,0).all.toMap() }
        val touched=java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
        val isolated=object:ContextWrapper(actual) {
            override fun getSharedPreferences(name:String,mode:Int):android.content.SharedPreferences {
                touched.add(name)
                return baseContext.getSharedPreferences("transport_recovery_fixture_$name",mode)
            }
        }
        var host:MainActivity?=null
        var backedUp=false
        var phase="starting"
        var result="RUNNING"
        var targetPosition=0L
        var errorCode:Int?=null
        val diagnosticsFolder=File(actual.getExternalFilesDir(null),checkpoint)
        var diagnose:(String)->Unit={}
        fun report(message:String) { test.sendStatus(0,Bundle().apply { putString("stream",message+"\n") }) }
        fun publish(next:String) {
            phase=next
            val json=JSONObject().put("phase",next).put("checkpoint",checkpoint).put("elapsedMs",SystemClock.elapsedRealtime()-started)
                .put("result",result).put("positionMs",targetPosition).put("errorCode",errorCode ?: JSONObject.NULL)
                .put("scope","emulator_transport_impairment_paused_recovery")
            val staging=File(phaseFile.path+".tmp")
            staging.writeText(json.toString());check(staging.renameTo(phaseFile))
            report("transport phase=$next position_ms=$targetPosition error_code=${errorCode ?: "none"}")
            diagnose("phase")
        }
        fun command():String {
            if(!commandFile.exists())return ""
            check(commandFile.length()<=32) { "Invalid transport command length" }
            val value=commandFile.readText().trim()
            check(value in listOf("","impaired","restored","abort")) { "Invalid transport command" }
            check(value!="abort") { "Host aborted transport test" }
            return value
        }
        fun await(limit:Long,condition:()->Boolean):Boolean {
            val until=minOf(deadline,SystemClock.elapsedRealtime()+limit)
            var nextDiagnostic=0L
            while(SystemClock.elapsedRealtime()<until) {
                command()
                if(condition())return true
                if(SystemClock.elapsedRealtime()>=nextDiagnostic) {
                    diagnose("waiting");nextDiagnostic=SystemClock.elapsedRealtime()+5000
                }
                Thread.sleep(200)
            }
            diagnose("wait_timeout")
            return false
        }
        fun nodes():List<AccessibilityNodeInfo> {
            if(android.os.Build.VERSION.SDK_INT>=33)test.uiAutomation.clearCache()
            val found=mutableListOf<AccessibilityNodeInfo>()
            fun walk(node:AccessibilityNodeInfo?) { if(node==null)return;found.add(node);for(i in 0 until node.childCount)walk(node.getChild(i)) }
            walk(test.uiAutomation.rootInActiveWindow);return found
        }
        fun has(label:String)=nodes().any { it.text?.toString()==label }
        fun click(label:String) {
            check(await(12_000) { has(label) }) { "Expected production control missing" }
            var node=nodes().first { it.text?.toString()==label }
            while(!node.isClickable)node=node.parent ?: error("Production button missing")
            check(node.performAction(AccessibilityNodeInfo.ACTION_CLICK));test.waitForIdleSync()
        }
        fun reading():Reading {
            fun find(view:View):ExoPlayer? {
                if(view is PlayerView)return view.player as? ExoPlayer
                if(view is ViewGroup)for(i in 0 until view.childCount)find(view.getChildAt(i))?.let { return it }
                return null
            }
            var value=Reading(null)
            test.runOnMainSync {
                val player=host?.let { find(it.window.decorView) }
                if(player!=null) {
                    player.videoDecoderCounters?.ensureUpdated()
                    value=Reading(player,player.currentPosition,player.bufferedPosition,player.duration,
                        player.playbackState==Player.STATE_READY,player.isPlaying,player.playWhenReady,
                        player.videoDecoderCounters?.renderedOutputBufferCount ?: 0,player.playerError?.errorCode,
                        player.playbackState,player.playbackSuppressionReason,player.videoSize.width,player.videoSize.height)
                }
            }
            return value
        }
        diagnose={ event ->
            runCatching {
                val current=reading()
                val labels=nodes().mapNotNull { it.text?.toString() }.toSet()
                val snapshot=JSONObject().put("event",event).put("phase",phase)
                    .put("elapsedMs",SystemClock.elapsedRealtime()-started)
                    .put("remainingBudgetMs",(deadline-SystemClock.elapsedRealtime()).coerceAtLeast(0))
                    .put("playerPresent",current.player!=null)
                    .put("playerIdentity",current.player?.let { System.identityHashCode(it) } ?: 0)
                    .put("ready",current.ready).put("state",current.state)
                    .put("positionMs",current.position).put("targetPositionMs",targetPosition)
                    .put("positionDeltaMs",current.position-targetPosition)
                    .put("bufferedMs",current.buffered).put("durationMs",current.duration)
                    .put("playing",current.playing).put("playWhenReady",current.intent)
                    .put("suppression",current.suppression).put("frames",current.frames)
                    .put("videoWidth",current.videoWidth).put("videoHeight",current.videoHeight)
                    .put("playerError",current.error ?: JSONObject.NULL)
                    .put("hasReparse","重新解析" in labels).put("hasReload","重新加载" in labels)
                    .put("hasVerification","网页验证" in labels)
                    .put("hasPlay","▷ 播放" in labels).put("hasPause","Ⅱ 暂停" in labels)
                diagnosticsFolder.mkdirs()
                File(diagnosticsFolder,"state.jsonl").appendText(snapshot.toString()+"\n")
                report("transport diagnostic=$snapshot")
            }.onFailure { report("transport diagnostic_unavailable=${it.javaClass.simpleName}") }
        }
        fun failureScreenshot() {
            runCatching {
                diagnosticsFolder.mkdirs()
                val file=File(diagnosticsFolder,"failure.png")
                test.uiAutomation.takeScreenshot()?.let { bitmap ->
                    try { file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) } }
                    finally { bitmap.recycle() }
                    report("transport private_failure_screenshot=$checkpoint/failure.png")
                }
            }.onFailure { report("transport screenshot_unavailable=${it.javaClass.simpleName}") }
        }
        fun notTriggered(reason:String):String {
            result="NOT_TRIGGERED_$reason";publish("not_triggered")
            return "real_transport_recovery=$result; not a PASS; physical_outage=NOT_TESTED"
        }
        try {
            if(commandFile.exists())check(commandFile.delete())
            report(UserDataCheckpoint.run(test,"user-data-backup",checkpoint));backedUp=true
            listOf(actual,isolated).forEach { context ->
                if(context===isolated)listOf("tv_settings","tv_library","search_history").forEach { isolated.getSharedPreferences(it,0).edit().clear().commit() }
                TvPreferences(context).apply { incognito=true;resumePlayback=false;autoNext=false;speed=1f;danmakuEnabled=false;controlsSeconds=30;seekSeconds=10 }
            }
            publish("catalogue")
            val input=JSONArray(File(actual.getExternalFilesDir(null),"source-audit-rules.json").readText())
            val rule=(0 until input.length()).map { SourceRule(input.getJSONObject(it)) }
                .singleOrNull { it.name.equals("baimao",true) } ?: error("Fixed audit input lacks unique baimao")
            val repository=RuleRepository(actual,rulesOverride=listOf(rule))
            val (match,roads)=runBlocking { withTimeout(65_000) {
                val matches=repository.search(rule,"无职转生").filter { it.title.contains("第三季") }
                val found=matches.firstOrNull() ?: error("Requested season missing")
                found to repository.chapters(rule,found)
            } }
            val episode=roads.firstOrNull()?.episodes?.getOrNull(11) ?: error("Episode 12 missing")
            val subject=Subject(19000927,match.title,"","")
            val activity=test.startActivitySync(Intent(actual,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            host=activity
            test.runOnMainSync {
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                activity.setContent { CompositionLocalProvider(LocalContext provides isolated) { KazumiTheme(false) {
                    PlaybackSessionScreen(subject,rule.name,episode,initialRoads=roads,initialRoad=0,
                        initialOrigin=PlaybackOrigin(rule.name,match.title,match.url,roads.first().title),sourceCatalog=repository,onClose={ activity.finish() })
                } } }
            }
            check(await(70_000) { reading().let { it.ready&&it.playing&&it.frames>0&&it.position>=5000 } }) { "Real initial playback did not advance" }
            targetPosition=reading().position;publish("ready")
            check(await(35_000) { command()=="impaired" }) { "Host impairment command missing" }
            publish("impaired")
            val beforeSeek=reading()
            val destination=minOf(beforeSeek.buffered+20_000,beforeSeek.duration-30_000)
            if(beforeSeek.error==null) {
                if(destination<=beforeSeek.buffered+2000 || destination<=beforeSeek.position)return notTriggered("FULLY_BUFFERED")
                val steps=((destination-beforeSeek.position+9999)/10_000).coerceAtMost(60).toInt()
                report("transport positioning=remote_fast_forward steps=$steps buffer_ms=${beforeSeek.buffered}; no injected error")
                repeat(steps) {
                    if(reading().error==null) { test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD);Thread.sleep(80) }
                }
            }
            if(!await(90_000) { reading().error!=null })return notTriggered("PLAYER_ERROR")
            val failed=reading();errorCode=failed.error
            if((errorCode ?: -1) !in 2000..2999)return notTriggered("NON_IO_ERROR")
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PAUSE)
            check(await(8000) { !reading().intent&&has("重新加载") }) { "Error pause control failed" }
            targetPosition=reading().position;publish("player_error_paused")
            click("重新加载")
            publish("retrying_impaired")
            // A real resolver failure under the impaired transport is required, not fabricated.
            if(!await(55_000) { has("重新解析") })return notTriggered("RESOLVER_FAILURE")
            publish("restore_requested")
            check(await(35_000) { command()=="restored" }) { "Host restore command missing" }
            click("重新解析")
            publish("restoring_media")
            var recoveryAttempts=1
            if(delayedRetry) {
                // Separate diagnostic scenario: do not relabel a failed immediate retry as a pass.
                Thread.sleep(1000)
                check(await(35_000) { reading().ready || has("重新解析") }) { "First restored attempt did not settle" }
                if(has("重新解析") && !reading().ready) {
                    val code=nodes().mapNotNull { it.text?.toString() }
                        .firstNotNullOfOrNull { Regex("（(-?[0-9]+)）").find(it)?.groupValues?.get(1) }
                    report("transport immediate_retry=FAIL web_error_code=${code ?: "unknown"}; delayed retry is a separate diagnostic")
                    publish("delayed_retry_wait")
                    Thread.sleep(15_000)
                    val probeStarted=SystemClock.elapsedRealtime()
                    try {
                        val page=runBlocking { withTimeout(8000) { HttpText.pageAsync(episode.pageUrl,
                            headers=mapOf("User-Agent" to rule.userAgent,"Referer" to rule.referer)) } }
                        report("transport restored_http status=${page.status} elapsed_ms=${SystemClock.elapsedRealtime()-probeStarted}")
                    } catch(error:Exception) {
                        report("transport restored_http failure=${error.javaClass.simpleName} elapsed_ms=${SystemClock.elapsedRealtime()-probeStarted}")
                    }
                    click("重新解析");recoveryAttempts++
                    publish("restoring_media_delayed")
                }
            }
            check(await(70_000) { reading().let { it.ready&&it.frames>0&&!it.intent&&abs(it.position-targetPosition)<=2500 } }) { "Paused retry did not restore target position" }
            val restored=reading()
            publish("restored_paused")
            check(restored.player!==failed.player) { "Media retry did not create a new resolved player" }
            Thread.sleep(1800)
            check(!reading().intent&&abs(reading().position-restored.position)<=500) { "Paused retry advanced unexpectedly" }
            click("▷ 播放")
            publish("explicit_play")
            check(await(18_000) { reading().let { it.playing&&it.frames>restored.frames&&it.position>=restored.position+5000 } }) { "Explicit resumed playback did not advance" }
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PAUSE)
            click("选集")
            check(await(8000) { nodes().any { it.text?.toString()?.let { value->value.contains(episode.title)&&value.contains("当前") }==true } }) { "Recovered episode selection changed" }
            result="PASS";publish("passed")
            return "real_transport_recovery=PASS scenario=${if(delayedRetry) "delayed_retry_diagnostic" else "immediate_retry"} recovery_attempts=$recoveryAttempts real_error_code=$errorCode paused_position=PASS explicit_advance_5s=PASS same_episode=PASS physical_outage=NOT_TESTED"
        } catch(error:Exception) {
            result="FAIL"
            diagnose("failure_before_cleanup")
            failureScreenshot()
            report("transport failure phase=$phase type=${error.javaClass.simpleName}")
            publish("failed");throw error
        } finally {
            try {
                host?.let { activity ->
                    test.runOnMainSync { activity.setContent {};activity.finish() };test.waitForIdleSync()
                    val until=SystemClock.elapsedRealtime()+8000
                    while(!activity.isDestroyed&&SystemClock.elapsedRealtime()<until)Thread.sleep(100)
                    check(activity.isDestroyed) { "Activity not destroyed before restore" }
                }
            } finally {
                touched.toList().forEach { isolated.getSharedPreferences(it,0).edit().clear().commit() }
                if(backedUp) {
                    report(UserDataCheckpoint.run(test,"user-data-restore",checkpoint))
                    check(before.all { (name,values)->actual.getSharedPreferences(name,0).all==values }) { "User data restoration differs" }
                    publish("finished")
                    report("transport user_data_restored_and_equal=true; host must restore emulator network")
                }
            }
        }
    }
}
