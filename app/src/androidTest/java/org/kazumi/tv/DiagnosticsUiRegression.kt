package org.kazumi.tv

import android.app.Instrumentation
import android.content.ContextWrapper
import android.content.Intent
import android.view.KeyEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalContext
import org.json.JSONObject
import org.kazumi.tv.data.*
import org.kazumi.tv.playback.MediaResolutionFailure
import org.kazumi.tv.rules.*
import org.kazumi.tv.ui.*
import java.io.File

/** Controlled production-session failure followed by actual diagnostic UI; no remote request. */
object DiagnosticsUiRegression {
    fun run(test:Instrumentation):String {
        val original=test.targetContext
        val stores=listOf("tv_settings","tv_library","tv_rules").associateWith { original.getSharedPreferences(it,0).all.toMap() }
        val directory=File(original.cacheDir,"diagnostics-ui-${System.currentTimeMillis()}").apply { check(mkdirs()) }
        val log=DiagnosticLog.shared
        val activity=test.startActivitySync(Intent(original,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        val context=object:ContextWrapper(activity) { override fun getFilesDir()=directory }
        fun nodes():List<AccessibilityNodeInfo> {
            val out=mutableListOf<AccessibilityNodeInfo>()
            fun walk(n:AccessibilityNodeInfo?) { if(n==null)return;out+=n;for(i in 0 until n.childCount)walk(n.getChild(i)) }
            walk(test.uiAutomation.rootInActiveWindow);return out
        }
        fun await(label:String,predicate:()->Boolean) { repeat(120) { if(predicate())return;Thread.sleep(100) };error("timeout $label") }
        fun has(text:String)=nodes().any { it.text?.toString()?.contains(text)==true }
        fun click(text:String) {
            await(text) { has(text) }
            var node=nodes().first { it.text?.toString()==text }
            node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SHOW_ON_SCREEN.id)
            while(!node.isClickable&&node.parent!=null)node=node.parent
            check(node.performAction(AccessibilityNodeInfo.ACTION_CLICK));test.waitForIdleSync()
        }
        val rule=SourceRule(JSONObject().put("name","diagnostic-fixture").put("baseURL","http://127.0.0.1"))
        val episode=Episode("PRIVATE_EPISODE_MARKER","http://127.0.0.1/?token=PRIVATE_URL_MARKER")
        val roads=listOf(Road("fixture",listOf(episode)))
        val catalog=object:SourceCatalog {
            override val rules=listOf(rule)
            override suspend fun search(rule:SourceRule,keyword:String)=emptyList<SourceMatch>()
            override suspend fun chapters(rule:SourceRule,match:SourceMatch)=roads
        }
        fun reports()=File(directory,"playback-diagnostics").listFiles()?.filter { it.extension=="json" }.orEmpty()
        try {
            test.runOnMainSync { activity.setContent { KazumiTheme(false) {
                PlaybackSessionScreen(Subject(19000923,"PRIVATE_TITLE_MARKER","",""),rule.name,episode,roads,
                    sourceCatalog=catalog,resolveEpisode={ _,_->throw MediaResolutionFailure("媒体探测","PRIVATE_EXCEPTION_MARKER") },onClose={})
            } } }
            await("production resolve failure recorded") { log.events.value.any { it.kind==DiagnosticLog.Kind.RESOLVE_FAILURE && it.stage==DiagnosticLog.Stage.PROBE } }
            test.runOnMainSync { activity.setContent { CompositionLocalProvider(LocalContext provides context) { KazumiTheme(false) { DiagnosticsScreen() } } } }
            await("diagnostic UI") { has("播放诊断") && has("解析失败") }
            repeat(4) {
                val before=reports().map { file->file.name }.toSet()
                click("保存本机诊断")
                await("saved bounded report") { has("已保存本机诊断") && reports().size==minOf(it+1,3) && reports().any { file->file.name !in before } }
                Thread.sleep(150)
            }
            check(reports().size==3)
            reports().forEach { file ->
                val raw=file.readText();check(raw.toByteArray().size<=65536)
                check(!raw.contains("PRIVATE_")&&!raw.contains("127.0.0.1")&&!raw.contains("token="))
                val events=JSONObject(raw).getJSONArray("events")
                check((0 until events.length()).any { events.getJSONObject(it).optString("event")=="RESOLVE_FAILURE" })
            }
            val saved=reports().associate { it.name to it.readText() }
            click("导出脱敏诊断")
            await("export launch or immediate cancellation") { has("已取消导出") || has("没有文件保存器") || !activity.hasWindowFocus() }
            Thread.sleep(300)
            if(!has("没有文件保存器") && !has("已取消导出"))test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
            await("export cancelled or unavailable") { has("已取消导出") || has("没有文件保存器") }
            check(saved==reports().associate { it.name to it.readText() })
            click("清空播放诊断")
            await("cleared") { has("已清空内存及本机诊断") && reports().isEmpty() && log.events.value.isEmpty() }
            return "production_session_failure, private_fields_absent, local_report_JSON, retention3, export_cancel_or_unavailable, clear, user_stores_preserved=OK"
        } finally {
            test.runOnMainSync { activity.setContent { };activity.finish() }
            // Delete only this run's empty fixture directories; never touch user reports.
            File(directory,"playback-diagnostics").delete();directory.delete()
            stores.forEach { (name,before)->check(before==original.getSharedPreferences(name,0).all) }
        }
    }
}
