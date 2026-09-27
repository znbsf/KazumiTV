package org.kazumi.tv

import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import org.json.JSONObject
import org.kazumi.tv.data.LibraryStore
import java.io.File
import kotlin.math.abs

/** Host force-stopped a pending real-source recovery. Fresh normal launcher + explicit recent
 * history resume; does not claim saved Activity restoration or spontaneous low-memory death. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object TransportProcessCompletion {
    fun run(test:Instrumentation):String {
        val context=test.targetContext
        val expected=JSONObject(File(context.getExternalFilesDir(null),"transport-process-private.json").readText())
        val receipt=JSONObject(File(context.getExternalFilesDir(null),"transport-process-kill-receipt.json").readText())
        check(receipt.getString("checkpoint")==expected.getString("checkpoint")&&receipt.getInt("oldPid")==expected.getInt("pid"))
        check(android.os.SystemClock.elapsedRealtime()-receipt.getLong("confirmedDeviceMs") in 0..120000)
        check(android.os.Process.myPid()!=expected.getInt("pid")) { "Expected a new app process" }
        val key=expected.getString("key")
        val episode=expected.getString("episode")
        val saved=LibraryStore(context).history().single { it.key==key&&it.subject.id==expected.getInt("subjectId") }
        check(abs(saved.position-expected.getLong("position"))<=2500)
        val activity=test.startActivitySync(Intent(context,MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        fun player():ExoPlayer? {
            fun find(view:View):ExoPlayer? {
                if(view is PlayerView)return view.player as? ExoPlayer
                if(view is ViewGroup)for(i in 0 until view.childCount)find(view.getChildAt(i))?.let { return it }
                return null
            }
            var value:ExoPlayer?=null
            test.runOnMainSync {
                value=android.view.inspector.WindowInspector.getGlobalWindowViews().firstNotNullOfOrNull(::find)
            }
            return value
        }
        fun nodes():List<AccessibilityNodeInfo> {
            if(android.os.Build.VERSION.SDK_INT>=33)test.uiAutomation.clearCache()
            val found=mutableListOf<AccessibilityNodeInfo>()
            fun visit(node:AccessibilityNodeInfo?) {
                if(node==null)return
                found.add(node);for(i in 0 until node.childCount)visit(node.getChild(i))
            }
            visit(test.uiAutomation.rootInActiveWindow);return found
        }
        fun await(limit:Long,condition:()->Boolean) {
            val deadline=android.os.SystemClock.elapsedRealtime()+limit
            while(android.os.SystemClock.elapsedRealtime()<deadline) {
                if(condition())return
                Thread.sleep(200)
            }
            error("Process recovery completion timed out")
        }
        fun click(label:String) {
            await(30_000) { nodes().any { it.text?.toString()==label } }
            var node=nodes().first { it.text?.toString()==label }
            while(!node.isClickable)node=node.parent ?: error("Process recovery control not clickable")
            check(node.performAction(AccessibilityNodeInfo.ACTION_CLICK))
        }
        try {
            val quietUntil=android.os.SystemClock.elapsedRealtime()+10_000
            while(android.os.SystemClock.elapsedRealtime()<quietUntil) {
                check(player()==null) { "Fresh launcher resumed playback without explicit action" }
                Thread.sleep(200)
            }
            click("${saved.subject.title} · $episode")
            click("继续 $episode")
            await(90_000) { player()?.let { engine ->
                var ready=false
                test.runOnMainSync { ready=engine.playbackState==androidx.media3.common.Player.STATE_READY&&
                    engine.currentPosition>=saved.position-2500&&engine.currentPosition<=saved.position+20000 }
                ready
            }==true }
            val before=LibraryStore(context).history().single { it.key==key }.position
            await(20_000) { LibraryStore(context).history().single { it.key==key }.position>=before+5000 }
            click("选集")
            await(30_000) { nodes().any { it.text?.toString()?.let { label -> label.contains(episode)&&label.contains("当前") }==true } }
            check(LibraryStore(context).history().single { it.key==key }.origin==saved.origin)
            return "real_transport_process=PASS forced_death_during_pending_resolve=true new_pid=true normal_launcher_no_auto_play_10s=PASS explicit_recent_same_identity_progress_advance=PASS saved_activity_restore=NOT_TESTED physical_outage=NOT_TESTED"
        } finally {
            test.runOnMainSync { activity.finish() }
            test.waitForIdleSync()
            listOf("tv_settings","tv_library","search_history").forEach { name ->
                check(context.getSharedPreferences("transport_recovery_fixture_$name",0).edit().clear().commit())
            }
        }
    }
}
