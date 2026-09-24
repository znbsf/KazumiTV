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
import androidx.lifecycle.Lifecycle
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
import java.net.InetAddress
import java.net.URI
import java.net.UnknownHostException
import java.util.concurrent.Executors
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import kotlin.math.abs

/** Real fixed-source requests/media, host-controlled emulator transport impairment (not physical outage).
 * Commands contain only impaired/restored/abort. No injected errors, media or resolver results.
 * Remote fast-forward is only positioning beyond the observed buffered region.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object RealTransportRecoveryRegression {
    private data class Reading(val player:ExoPlayer?,val position:Long=0,val buffered:Long=0,val duration:Long=0,
        val ready:Boolean=false,val playing:Boolean=false,val intent:Boolean=false,val frames:Int=0,val error:Int?=null,
        val state:Int=Player.STATE_IDLE,val suppression:Int=0,val videoWidth:Int=0,val videoHeight:Int=0)
    fun run(test:Instrumentation, delayedRetry:Boolean=false, phaseDiagnostics:Boolean=false,
        sourceName:String="baimao", pauseAfterError:Boolean=true, initialOutage:Boolean=false,
        interruption:String="none", repeatOutage:Boolean=false):String {
        require(sourceName in setOf("baimao","AGE")) { "Unsupported transport source" }
        require(interruption in setOf("none","back","home")) { "Unsupported interruption" }
        require(!initialOutage || interruption=="none")
        require(!repeatOutage || (!initialOutage && interruption=="none" && pauseAfterError))
        val started=SystemClock.elapsedRealtime()
        val diagnosticStarted=System.currentTimeMillis()
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
        var restoreCompletedDeviceMs:Long?=null
        var restoreObservedDeviceMs:Long?=null
        var recoveryAttempt=0
        var dnsProbes=0
        var httpProbes=0
        var restoredClickWallMs=Long.MAX_VALUE
        var displayedTitle:String?=null
        val diagnosticsFolder=File(actual.getExternalFilesDir(null),checkpoint)
        var diagnose:(String)->Unit={}
        fun report(message:String) { test.sendStatus(0,Bundle().apply { putString("stream",message+"\n") }) }
        fun event(name:String,fields:JSONObject=JSONObject()) {
            val now=SystemClock.elapsedRealtime()
            val record=fields.put("event",name).put("phase",phase).put("attempt",recoveryAttempt)
                .put("elapsedRealtimeMs",now).put("elapsedMs",now-started)
                .put("restoreCompletedDeviceMs",restoreCompletedDeviceMs ?: JSONObject.NULL)
                .put("restoreObservedDeviceMs",restoreObservedDeviceMs ?: JSONObject.NULL)
                .put("activeProbesEnabled",phaseDiagnostics)
            runCatching {
                diagnosticsFolder.mkdirs()
                File(diagnosticsFolder,"stages.jsonl").appendText(record.toString()+"\n")
                report("transport stage=$record")
            }.onFailure { report("transport stage_diagnostic_unavailable") }
        }
        fun publish(next:String) {
            phase=next
            val json=JSONObject().put("phase",next).put("checkpoint",checkpoint).put("elapsedMs",SystemClock.elapsedRealtime()-started)
                .put("result",result).put("positionMs",targetPosition).put("errorCode",errorCode ?: JSONObject.NULL)
                .put("scope",if(initialOutage) "emulator_initial_resolve_impairment" else "emulator_transport_impairment_playback_recovery")
                .put("elapsedRealtimeMs",SystemClock.elapsedRealtime())
                .put("recoveryAttempt",recoveryAttempt)
                .put("activeProbesEnabled",phaseDiagnostics)
                .put("restoreCompletedDeviceMs",restoreCompletedDeviceMs ?: JSONObject.NULL)
                .put("restoreObservedDeviceMs",restoreObservedDeviceMs ?: JSONObject.NULL)
            val staging=File(phaseFile.path+".tmp")
            staging.writeText(json.toString());check(staging.renameTo(phaseFile))
            report("transport phase=$next position_ms=$targetPosition error_code=${errorCode ?: "none"}")
            diagnose("phase")
        }
        fun command():String {
            if(!commandFile.exists())return ""
            check(commandFile.length()<=32) { "Invalid transport command length" }
            val value=commandFile.readText().trim()
            check(value in listOf("","impaired","restored","abort") ||
                Regex("restored:[0-9]{1,12}").matches(value)) { "Invalid transport command" }
            check(value!="abort") { "Host aborted transport test" }
            if(value.startsWith("restored") && restoreObservedDeviceMs==null) {
                restoreObservedDeviceMs=SystemClock.elapsedRealtime()
                restoreCompletedDeviceMs=value.substringAfter(':',"").toLongOrNull()
                event("restore_command_observed",JSONObject().put("hostCompletionTimestampAvailable",restoreCompletedDeviceMs!=null))
            }
            return value.substringBefore(':')
        }
        fun waitDelay(durationMs:Long) {
            val until=minOf(deadline,SystemClock.elapsedRealtime()+durationMs)
            while(SystemClock.elapsedRealtime()<until) {
                command()
                Thread.sleep(minOf(200L,until-SystemClock.elapsedRealtime()).coerceAtLeast(1L))
            }
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
        fun webFailureText(labels:Set<String>):String? = if("重新解析" !in labels) null else
            labels.singleOrNull { it!=displayedTitle && it.startsWith("解析失败 · 网页加载：") }
        // Accept Preview6 and the classified wording, only on the known retryable error screen.
        fun webFailureCode(labels:Set<String>):Int? = webFailureText(labels)?.let {
            Regex("（(-?[0-9]+)）$").find(it)?.groupValues?.get(1)?.toIntOrNull()
        }
        fun webHttpStatus(labels:Set<String>):Int? = webFailureText(labels)?.let {
            Regex("HTTP ([0-9]{3})$").find(it)?.groupValues?.get(1)?.toIntOrNull()
        }
        fun observeWebFailure(eventName:String) {
            val labels=nodes().mapNotNull { it.text?.toString() }.toSet()
            event(eventName,JSONObject().put("webErrorCode",webFailureCode(labels) ?: JSONObject.NULL)
                .put("webHttpStatus",webHttpStatus(labels) ?: JSONObject.NULL)
                .put("webErrorVisible","重新解析" in labels)
                .put("webFrame","unavailable_from_production_ui")
                .put("webNavigationGeneration",JSONObject.NULL))
        }
        fun probeObservedPage(pageUrl:String,rule:SourceRule) {
            if(!phaseDiagnostics) {
                event("active_probes_skipped",JSONObject().put("reason","baseline"))
                return
            }
            // Only the already selected episode page is probed. Each kind runs at most once per attempt.
            if(recoveryAttempt !in 1..2 || dnsProbes>=recoveryAttempt || httpProbes>=recoveryAttempt) {
                event("active_probes_skipped",JSONObject().put("reason","attempt_limit"))
                return
            }
            val hostName=runCatching { URI(pageUrl).host }.getOrNull()
            if(hostName.isNullOrBlank()) {
                event("active_probes_skipped",JSONObject().put("reason","observed_page_host_unavailable"))
                return
            }
            command()
            dnsProbes++
            val dnsStarted=SystemClock.elapsedRealtime()
            val executor=Executors.newSingleThreadExecutor { runnable ->
                Thread(runnable,"transport-dns-probe").apply { isDaemon=true }
            }
            val dnsResult=try {
                val future=executor.submit<Boolean> { InetAddress.getAllByName(hostName).isNotEmpty() }
                try { if(future.get(3000,TimeUnit.MILLISECONDS))"success" else "empty" }
                catch(_:TimeoutException) { future.cancel(true);"timeout" }
                catch(error:ExecutionException) {
                    if(error.cause is UnknownHostException)"unknown_host" else "other_failure"
                }
            } finally { executor.shutdownNow() }
            event("java_dns",JSONObject().put("result",dnsResult)
                .put("durationMs",SystemClock.elapsedRealtime()-dnsStarted))
            command()
            httpProbes++
            val httpStarted=SystemClock.elapsedRealtime()
            var status:Int?=null
            val httpResult=try {
                val page=runBlocking { withTimeout(8000) { HttpText.pageAsync(pageUrl,
                    headers=mapOf("User-Agent" to rule.userAgent,"Referer" to rule.referer)) } }
                status=page.status
                "response"
            } catch(_:kotlinx.coroutines.TimeoutCancellationException) { "timeout" }
            catch(cancelled:kotlinx.coroutines.CancellationException) { throw cancelled }
            catch(_:UnknownHostException) { "unknown_host" }
            catch(_:Exception) { "other_failure" }
            event("http_text",JSONObject().put("result",httpResult)
                .put("status",status ?: JSONObject.NULL)
                .put("durationMs",SystemClock.elapsedRealtime()-httpStarted))
            command()
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
                    .put("recoveryAttempt",recoveryAttempt)
                    .put("elapsedRealtimeMs",SystemClock.elapsedRealtime())
                    .put("restoreCompletedDeviceMs",restoreCompletedDeviceMs ?: JSONObject.NULL)
                    .put("restoreObservedDeviceMs",restoreObservedDeviceMs ?: JSONObject.NULL)
                    .put("activeProbesEnabled",phaseDiagnostics)
                    .put("dnsProbesExecuted",dnsProbes).put("httpProbesExecuted",httpProbes)
                    .put("webErrorCode",webFailureCode(labels) ?: JSONObject.NULL)
                    .put("webHttpStatus",webHttpStatus(labels) ?: JSONObject.NULL)
                    .put("webFrame","unavailable_from_production_ui")
                    .put("webNavigationGeneration",JSONObject.NULL)
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
                .singleOrNull { it.name.equals(sourceName,true) } ?: error("Fixed audit input lacks unique transport source")
            val repository=RuleRepository(actual,rulesOverride=listOf(rule))
            val (match,roads)=runBlocking { withTimeout(65_000) {
                val matches=repository.search(rule,"无职转生").filter {
                    it.title.contains("第三季") || it.title.contains("Ⅲ") ||
                        Regex("(?i)(?<![a-z])III(?![a-z])").containsMatchIn(it.title)
                }
                val found=matches.firstOrNull() ?: error("Requested season missing")
                found to repository.chapters(rule,found)
            } }
            val episode=roads.firstOrNull()?.episodes?.getOrNull(11) ?: error("Episode 12 missing")
            val subject=Subject(19000927,match.title,"","")
            displayedTitle="${subject.title} · ${episode.title}"
            if(initialOutage) {
                // The catalogue was fetched while online; only the first media resolution is impaired.
                publish("ready")
                check(await(35_000) { command()=="impaired" }) { "Host impairment command missing" }
                publish("impaired")
            }
            val activity=test.startActivitySync(Intent(actual,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            host=activity
            test.runOnMainSync {
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                activity.setContent { CompositionLocalProvider(LocalContext provides isolated) { KazumiTheme(false) {
                    PlaybackSessionScreen(subject,rule.name,episode,initialRoads=roads,initialRoad=0,
                        initialOrigin=PlaybackOrigin(rule.name,match.title,match.url,roads.first().title),sourceCatalog=repository,onClose={ activity.finish() })
                } } }
            }
            if(initialOutage) {
                check(await(100_000) { has("重新解析") }) { "Initial resolver did not reach the retryable error screen" }
                val initialLabels=nodes().mapNotNull { it.text?.toString() }.toSet()
                val initialFailure=when {
                    webFailureCode(initialLabels)==-2 -> "web_host_lookup"
                    webFailureCode(initialLabels)==-6 -> "web_connect_failure"
                    webFailureCode(initialLabels)==-8 -> "web_timeout"
                    initialLabels.any { it.startsWith("解析失败 · 网页与媒体发现：") && it.contains("请检查网络或来源后重试") } -> "web_or_media_timeout"
                    else -> error("Initial impairment was not classified as a network failure")
                }
                event("initial_network_failure",JSONObject().put("classification",initialFailure))
                check("网页验证" !in initialLabels) { "Network failure was misclassified as verification" }
                publish("restore_requested")
                check(await(35_000) { command()=="restored" }) { "Host restore command missing" }
                recoveryAttempt=1
                restoredClickWallMs=System.currentTimeMillis()
                click("重新解析")
                publish("restoring_media")
                check(await(95_000) { reading().let { it.ready&&it.playing&&it.frames>0&&it.position>=5000 } }) {
                    "Initial media resolution did not recover"
                }
                click("选集")
                check(await(8000) { nodes().any { it.text?.toString()?.let { value ->
                    value.contains(episode.title)&&value.contains("当前") }==true } }) { "Recovered initial episode changed" }
                result="PASS";publish("passed")
                val hostEvents=DiagnosticLog.shared.events.value.filter {
                    it.time>=diagnosticStarted&&it.kind==DiagnosticLog.Kind.HOST_LOOKUP_RETRY
                }
                val impairedRetries=hostEvents.count { it.time<restoredClickWallMs&&(it.code ?: 0)>0 }
                val restoredEvents=hostEvents.filter { it.time>=restoredClickWallMs }
                val restoredRetries=restoredEvents.count { (it.code ?: 0)>0 }
                event("host_lookup_recovery_summary",JSONObject().put("restoredStarted",restoredEvents.any { it.code==0 })
                    .put("impairedRetries",impairedRetries).put("restoredRetries",restoredRetries))
                return "real_initial_transport_recovery=PASS source=$sourceName active_probes=$phaseDiagnostics dns_probes=$dnsProbes http_probes=$httpProbes impaired_host_retries=$impairedRetries restored_host_retries=$restoredRetries initial_error=$initialFailure playback_advance_5s=PASS same_episode=PASS physical_outage=NOT_TESTED"
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
            if(pauseAfterError)test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PAUSE)
            check(await(8000) { reading().intent!=pauseAfterError&&has("重新加载") }) { "Error play intent control failed" }
            targetPosition=reading().position;publish("player_error_paused")
            click("重新加载")
            publish("retrying_impaired")
            // A real resolver failure under the impaired transport is required, not fabricated.
            if(!await(55_000) { has("重新解析") })return notTriggered("RESOLVER_FAILURE")
            if(interruption!="none") {
                val previousSuccesses=DiagnosticLog.shared.events.value.count {
                    it.time>=diagnosticStarted&&it.kind==DiagnosticLog.Kind.RESOLVE_SUCCESS
                }
                click("重新解析")
                check(await(5000) { !has("重新解析") }) { "Interrupted retry did not start" }
                publish("retrying_interrupted")
                if(interruption=="back")test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
                else android.os.ParcelFileDescriptor.AutoCloseInputStream(
                    test.uiAutomation.executeShellCommand("input keyevent 3")
                ).use { it.readBytes() }
                if(interruption=="back")check(await(8000) { activity.isFinishing }) { "Back did not close the recovery screen" }
                else check(await(8000) { !activity.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED) }) {
                    "HOME did not stop the recovery activity"
                }
                publish("restore_requested")
                check(await(35_000) { command()=="restored" }) { "Host restore command missing" }
                waitDelay(45_000)
                val laterSuccesses=DiagnosticLog.shared.events.value.count {
                    it.time>=diagnosticStarted&&it.kind==DiagnosticLog.Kind.RESOLVE_SUCCESS
                }
                event("interruption_outcome",JSONObject().put("successesBefore",previousSuccesses)
                    .put("successesAfter",laterSuccesses).put("playerPresent",reading().player!=null))
                check(laterSuccesses==previousSuccesses) { "Interrupted recovery resolved after leaving the screen" }
                check(reading().player==null) { "Interrupted recovery started a player" }
                if(interruption=="home") {
                    actual.startActivity(Intent(actual,MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
                    check(await(8000) { activity.lifecycle.currentState==Lifecycle.State.RESUMED }) { "HOME return did not resume" }
                    check(!reading().playing) { "HOME return started playback" }
                    check(await(8000) { has("重新解析")&&has("已返回后台，请重新解析。") }) {
                        "HOME return did not require an explicit retry"
                    }
                }
                result="PASS";publish("passed")
                return "real_transport_interruption=PASS source=$sourceName action=$interruption active_probes=$phaseDiagnostics real_error_code=$errorCode stale_resolve_success=0 background_player=0 physical_outage=NOT_TESTED"
            }
            publish("restore_requested")
            check(await(35_000) { command()=="restored" }) { "Host restore command missing" }
            recoveryAttempt=1
            event("recovery_attempt_start")
            probeObservedPage(episode.pageUrl,rule)
            restoredClickWallMs=System.currentTimeMillis()
            click("重新解析")
            event("recovery_click_completed")
            publish("restoring_media")
            var recoveryAttempts=1
            if(delayedRetry) {
                // Separate diagnostic scenario: do not relabel a failed immediate retry as a pass.
                waitDelay(1000)
                check(await(35_000) { reading().ready || has("重新解析") }) { "First restored attempt did not settle" }
                if(has("重新解析") && !reading().ready) {
                    observeWebFailure("first_attempt_failed")
                    publish("delayed_retry_wait")
                    waitDelay(15_000)
                    recoveryAttempt=2
                    event("recovery_attempt_start")
                    probeObservedPage(episode.pageUrl,rule)
                    click("重新解析");recoveryAttempts=2
                    event("recovery_click_completed")
                    publish("restoring_media_delayed")
                } else {
                    event("delayed_retry_not_triggered",JSONObject().put("reason","first_attempt_succeeded"))
                }
            }
            check(await(70_000) { reading().let { it.ready&&it.frames>0&&
                if(pauseAfterError) !it.intent&&abs(it.position-targetPosition)<=2500
                else it.intent&&it.playing&&it.position>=targetPosition+5000
            } }) { "Retry did not restore target position and play intent" }
            val restored=reading()
            publish(if(pauseAfterError) "restored_paused" else "restored_playing")
            check(restored.player!==failed.player) { "Media retry did not create a new resolved player" }
            if(pauseAfterError) {
                Thread.sleep(1800)
                check(!reading().intent&&abs(reading().position-restored.position)<=500) { "Paused retry advanced unexpectedly" }
                click("▷ 播放")
                publish("explicit_play")
                check(await(18_000) { reading().let { it.playing&&it.frames>restored.frames&&it.position>=restored.position+5000 } }) { "Explicit resumed playback did not advance" }
            }
            if(repeatOutage) {
                restoreObservedDeviceMs=null;restoreCompletedDeviceMs=null
                targetPosition=reading().position
                publish("ready_again")
                check(await(35_000) { command()=="impaired" }) { "Second host impairment missing" }
                restoreObservedDeviceMs=null;restoreCompletedDeviceMs=null
                publish("impaired_again")
                val beforeSecondSeek=reading()
                val secondDestination=minOf(beforeSecondSeek.buffered+20_000,beforeSecondSeek.duration-30_000)
                check(secondDestination>beforeSecondSeek.buffered+2000&&secondDestination>beforeSecondSeek.position) {
                    "Second outage media was already fully buffered"
                }
                val secondSteps=((secondDestination-beforeSecondSeek.position+9999)/10_000).coerceAtMost(60).toInt()
                repeat(secondSteps) {
                    if(reading().error==null) { test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD);Thread.sleep(80) }
                }
                check(await(90_000) { reading().error!=null }) { "Second outage did not cause real player failure" }
                val secondFailed=reading()
                check((secondFailed.error ?: -1) in 2000..2999) { "Second outage error was not IO" }
                test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PAUSE)
                check(await(8000) { !reading().intent&&has("重新加载") }) { "Second outage pause intent failed" }
                targetPosition=reading().position;publish("player_error_again")
                click("重新加载")
                check(await(55_000) { has("重新解析") }) { "Second outage resolver failure missing" }
                publish("restore_requested_again")
                check(await(35_000) { command()=="restored" }) { "Second host restore missing" }
                val retryButton=nodes().first { it.text?.toString()=="重新解析" }
                var clickable=retryButton
                while(!clickable.isClickable)clickable=clickable.parent ?: error("Second retry button missing")
                val successesBefore=DiagnosticLog.shared.events.value.count {
                    it.time>=diagnosticStarted&&it.kind==DiagnosticLog.Kind.RESOLVE_SUCCESS
                }
                recoveryAttempt=2
                val secondClickWallMs=System.currentTimeMillis()
                check(clickable.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                val secondClickAccepted=clickable.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                event("rapid_retry_click",JSONObject().put("secondClickAccepted",secondClickAccepted))
                test.waitForIdleSync()
                publish("restoring_media_again")
                check(await(95_000) { reading().let {
                    it.ready&&!it.intent&&abs(it.position-targetPosition)<=2500
                } }) { "Second restored attempt lost paused progress" }
                val secondRestored=reading()
                check(secondRestored.player!==secondFailed.player) { "Second outage retained old player" }
                val successesAfter=DiagnosticLog.shared.events.value.count {
                    it.time>=diagnosticStarted&&it.kind==DiagnosticLog.Kind.RESOLVE_SUCCESS
                }
                check(successesAfter-successesBefore==1) { "Rapid retry created multiple completed resolutions" }
                val secondHostRetries=DiagnosticLog.shared.events.value.count {
                    it.time>=secondClickWallMs&&it.kind==DiagnosticLog.Kind.HOST_LOOKUP_RETRY&&(it.code ?: 0)>0
                }
                event("second_outage_host_retries",JSONObject().put("count",secondHostRetries))
                check(secondHostRetries<=5) { "Rapid retry exceeded the bounded host lookup attempt count" }
                click("▷ 播放")
                check(await(18_000) { reading().let {
                    it.playing&&it.frames>secondRestored.frames&&it.position>=secondRestored.position+5000
                } }) { "Second restored playback did not advance" }
            }
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_MEDIA_PAUSE)
            click("选集")
            check(await(8000) { nodes().any { it.text?.toString()?.let { value->value.contains(episode.title)&&value.contains("当前") }==true } }) { "Recovered episode selection changed" }
            result="PASS";publish("passed")
            val hostEvents=DiagnosticLog.shared.events.value.filter { it.time>=diagnosticStarted&&it.kind==DiagnosticLog.Kind.HOST_LOOKUP_RETRY }
            val impairedRetries=hostEvents.count { it.time<restoredClickWallMs&&(it.code ?: 0)>0 }
            val restoredEvents=hostEvents.filter { it.time>=restoredClickWallMs }
            val restoredRetries=restoredEvents.count { (it.code ?: 0)>0 }
            event("host_lookup_recovery_summary",JSONObject().put("restoredStarted",restoredEvents.any { it.code==0 })
                .put("impairedRetries",impairedRetries).put("restoredRetries",restoredRetries))
            return "real_transport_recovery=PASS source=$sourceName scenario=${if(delayedRetry) "delayed_retry_diagnostic" else "immediate_retry"} active_probes=$phaseDiagnostics dns_probes=$dnsProbes http_probes=$httpProbes recovery_attempts=$recoveryAttempts delayed_retry=${if(recoveryAttempts==2) "executed" else "not_triggered"} repeated_outage=${if(repeatOutage) "PASS" else "NOT_REQUESTED"} impaired_host_retries=$impairedRetries restored_host_retries=$restoredRetries real_error_code=$errorCode position=PASS play_intent=${if(pauseAfterError) "paused" else "playing"} advance_5s=PASS same_episode=PASS physical_outage=NOT_TESTED"
        } catch(error:Exception) {
            result="FAIL"
            diagnose("failure_before_cleanup")
            failureScreenshot()
            report("transport failure phase=$phase type=${error.javaClass.simpleName}")
            publish("failed")
            throw IllegalStateException("Transport recovery failed at $phase type=${error.javaClass.simpleName}")
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
