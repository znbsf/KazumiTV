@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text
import androidx.webkit.WebViewCompat
import kotlinx.coroutines.*
import org.kazumi.tv.data.DiagnosticLog
import java.io.File

/** Explicit export only. No network upload, playback titles, URLs, account data or private sinks. */
@Composable
fun DiagnosticsScreen(log:DiagnosticLog=DiagnosticLog.shared) {
    val context=LocalContext.current
    val events by log.events.collectAsState()
    val scope=rememberCoroutineScope()
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var exportRaw by remember { mutableStateOf<String?>(null) }
    fun report():String=log.report(
        runCatching { context.packageManager.getPackageInfo(context.packageName,0).versionName.orEmpty() }.getOrDefault(""),
        runCatching { WebViewCompat.getCurrentWebViewPackage(context)?.versionName.orEmpty() }.getOrDefault(""),
        android.os.Build.VERSION.SDK_INT)
    fun work(action:suspend()->Unit) {
        if(busy)return
        busy=true
        scope.launch { try { action() }catch(cancelled:CancellationException){throw cancelled}
            catch(_:Exception){status="诊断文件操作失败，请重试"}finally{busy=false} }
    }
    fun files():List<File> = File(context.filesDir,"playback-diagnostics").listFiles()?.filter {
        it.isFile&&it.name.matches(Regex("report-[0-9]+\\.json"))
    }?.sortedByDescending { it.name } ?: emptyList()
    val exporter=rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        val raw=exportRaw;exportRaw=null
        if(uri!=null && raw!=null)work {
            withContext(Dispatchers.IO) {
                context.contentResolver.openOutputStream(uri,"wt")?.bufferedWriter()?.use { it.write(raw) }
                    ?: error("write unavailable")
            }
            status="已导出脱敏播放诊断"
        } else status="已取消导出"
    }
    LazyColumn(Modifier.fillMaxSize(),verticalArrangement=Arrangement.spacedBy(12.dp)) {
        item { Text("播放诊断",style=KazumiType.heading) }
        item { Text("仅记录本次应用进程中的解析阶段和播放错误码，最多200条、64 KiB。重启应用后内存记录清空；不含片名、网址、请求头、账号或网页内容。",style=KazumiType.caption) }
        item { Text("当前 ${events.size} 条。这里只覆盖播放诊断，不包含全部应用日志。",style=KazumiType.caption) }
        if(status.isNotBlank())item { Text(status,style=KazumiType.body) }
        if(!busy && exportRaw==null) {
            item { PlayerAction("导出脱敏诊断") {
                exportRaw=report()
                try { exporter.launch("KazumiTV-playback-${System.currentTimeMillis()}.json") }
                catch(_:android.content.ActivityNotFoundException) { exportRaw=null;status="此电视没有文件保存器，可保存本机诊断" }
            } }
            item { PlayerAction("保存本机诊断") { val raw=report();work {
                withContext(Dispatchers.IO) {
                    val directory=File(context.filesDir,"playback-diagnostics")
                    check(directory.isDirectory||directory.mkdirs())
                    val atomic=android.util.AtomicFile(File(directory,"report-${System.currentTimeMillis()}.json"))
                    val stream=atomic.startWrite()
                    try { stream.write(raw.toByteArray(Charsets.UTF_8));atomic.finishWrite(stream) }
                    catch(e:Exception){atomic.failWrite(stream);throw e}
                    files().drop(3).forEach { check(it.delete()) }
                }
                status="已保存本机诊断，最多保留3份；卸载应用会删除"
            } } }
            item { PlayerAction("清空播放诊断") { work {
                withContext(Dispatchers.IO) { files().forEach { check(it.delete()) } }
                log.clear();status="已清空内存及本机诊断；已导出的文件需自行删除"
            } } }
        }
        if(busy)item { Text("正在处理…",style=KazumiType.caption) }
        items(events.asReversed()) { event ->
            val time=java.text.SimpleDateFormat("HH:mm:ss",java.util.Locale.ROOT).format(java.util.Date(event.time))
            Text("$time · ${event.kind.label}"+
                (if(event.stage!=DiagnosticLog.Stage.NONE)" · ${event.stage.name}" else "")+
                (event.code?.let { " · 错误码 $it" } ?: "")+(event.http?.let { " · HTTP $it" } ?: ""),style=KazumiType.body)
        }
    }
}
