@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.LocalActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.*
import org.kazumi.tv.data.*

@Composable
internal fun LibraryBackupScreen() {
    val context=LocalContext.current
    val store=remember { LibraryStore(context) }; val files=remember { LocalLibraryBackups(context) }
    var saved by remember { mutableStateOf(files.list()) }
    var status by remember { mutableStateOf("") }; var busy by remember { mutableStateOf(false) }
    var pending by remember { mutableStateOf<String?>(null) }; var fingerprint by remember { mutableStateOf("") }
    val transfer:DocumentTransferViewModel=viewModel(key="library-document-transfer")
    val activity=LocalActivity.current
    DisposableEffect(transfer,activity) {
        onDispose { if(activity?.isChangingConfigurations!=true)transfer.finish() }
    }
    val scope=rememberCoroutineScope()
    var readJob by remember { mutableStateOf<Job?>(null) }
    var readGeneration by remember { mutableIntStateOf(0) }
    fun work(action:suspend()->Unit) {
        if(busy)return
        busy=true
        scope.launch { try { action() } catch(e:CancellationException) { throw e } catch(_:Exception) { status="备份操作失败：请检查文件格式、版本及本地数据是否变化，然后重试" } finally { busy=false } }
    }
    fun preview(raw:String) { LibraryArchiveCodec.read(raw); pending=raw; fingerprint=store.backupFingerprint(); status="" }
    fun cancelRead() {
        readGeneration++; readJob?.cancel(); readJob=null
        busy=false; pending=null; status="已取消读取，收藏与历史保持不变"
    }
    BackHandler(pending!=null || busy) { if(readJob!=null)cancelRead() else if(!busy)pending=null }
    val importer=rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        transfer.finish()
        if(uri==null)status="已取消文件选择" else if(!busy) {
            busy=true
            val generation=++readGeneration
            val signal=android.os.CancellationSignal()
            readJob=scope.launch(start=CoroutineStart.LAZY) {
                try {
                    val raw=DocumentText.readCancellable(LibraryArchiveCodec.MAX_CHARS,cancelOpen={ signal.cancel() }) {
                        context.contentResolver.openAssetFileDescriptor(uri,"r",signal)?.let { descriptor ->
                            try { descriptor.createInputStream() } catch(failure:Exception) { descriptor.close(); throw failure }
                        }
                    }
                    ensureActive()
                    if(generation==readGeneration)preview(raw)
                } catch(cancelled:CancellationException) { throw cancelled }
                catch(_:Exception) { if(generation==readGeneration)status="读取备份失败，请检查文件或提供者后重试" }
                finally { if(generation==readGeneration) { busy=false; readJob=null } }
            }
            readJob?.start()
        }
    }
    val exporter=rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        val raw=transfer.takeExport()
        if(uri==null)status="已取消导出" else if(raw==null)status="导出内容已失效，请重新导出" else work {
            withContext(Dispatchers.IO) { DocumentText.write(raw) { context.contentResolver.openOutputStream(uri,"wt") } }
            status="已导出收藏与历史备份"
        }
    }
    val archive=pending?.let { LibraryArchiveCodec.read(it) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(12.dp)) {
        Text("收藏与历史备份",style=KazumiType.heading)
        Text("包含收藏分类、观看进度和续播来源信息。来源规则及账号配置需另行保存。",style=KazumiType.caption)
        if(status.isNotBlank())Text(status,style=KazumiType.body)
        if(busy)Text("正在处理…",style=KazumiType.caption)
        if(readJob!=null)PlayerAction("取消读取") { cancelRead() }
        if(archive!=null) {
            Text("恢复预览：${archive.collections.size} 条收藏，${archive.history.size} 条历史",style=KazumiType.title)
            Text("确认后将替换当前收藏与历史；已保留的内部旧版本不会被删除。恢复后可撤销一次，产生新记录后将禁止撤销覆盖。",style=KazumiType.body)
            archive.collections.take(3).forEach { Text("${it.type.label} · ${it.subject.title}",style=KazumiType.body) }
            archive.history.take(3).forEach { Text("${it.subject.title} · ${it.episode}",style=KazumiType.body) }
            if(!busy) {
                PlayerAction("确认替换收藏与历史") { val raw=pending!!; val expected=fingerprint; work { withContext(Dispatchers.IO) { store.restoreBackup(raw,expected) }; pending=null; status="恢复完成，可撤销上次恢复" } }
                PlayerAction("取消恢复") { pending=null }
            }
        } else if(!busy && transfer.operation==null) {
            PlayerAction("保存本机备份") { work { withContext(Dispatchers.IO) { files.save(store.exportBackup()) }; saved=files.list(); status="本机备份已保存" } }
            Text("本机保留最近5份备份，继续保存会删除最旧的一份。卸载应用会删除本机备份，请导出重要副本。",style=KazumiType.caption)
            PlayerAction("导出到文件") { work {
                if(!transfer.beginExport(withContext(Dispatchers.IO) { store.exportBackup() }))return@work
                try { exporter.launch("KazumiTV-library-${System.currentTimeMillis()}.json") }
                catch(_:android.content.ActivityNotFoundException) { transfer.finish(); status="此电视没有文件保存器，可先保存本机备份" }
                catch(_:Exception) { transfer.finish(); status="无法打开文件保存器，请重试" }
            } }
            PlayerAction("从文件恢复") {
                if(busy || !transfer.beginImport())return@PlayerAction
                try { importer.launch(arrayOf("application/json","text/plain","application/octet-stream")) }
                catch(_:android.content.ActivityNotFoundException) { transfer.finish(); status="此电视没有文件选择器，可使用下方本机备份" }
                catch(_:Exception) { transfer.finish(); status="无法打开文件选择器，请重试" }
            }
            if(store.canUndoRestore())PlayerAction("撤销上次恢复") { work { withContext(Dispatchers.IO) { store.undoRestore() }; status="已撤销恢复" } }
            Text("本机备份",style=KazumiType.title)
            if(saved.isEmpty())Text("暂无本机备份",style=KazumiType.caption)
            saved.forEachIndexed { index,file ->
                val date=java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss",java.util.Locale.CHINA).format(java.util.Date(file.name.substringBefore('-').toLong()))
                PlayerAction("预览备份 ${index+1} · $date") { work { preview(withContext(Dispatchers.IO) { files.read(file) }) } }
            }
        }
    }
}
