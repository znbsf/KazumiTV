@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
package org.kazumi.tv.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text
import androidx.media3.exoplayer.offline.Download
import org.kazumi.tv.download.*
import org.kazumi.tv.rules.RuleRepository
import org.kazumi.tv.playback.*

@Composable
internal fun DownloadRecoveryPanel(expected:Download,resolveOverride:(suspend ()->PlaybackRequest)?=null,onClose:()->Unit) {
    val context=LocalContext.current
    val metadata=remember(expected.request) { runCatching { DownloadMetadata.read(expected.request.data) }.getOrNull() }
    val rules=remember { RuleRepository(context) }
    val origin=metadata?.origin
    val rule=rules.rules.firstOrNull { it.name==origin?.rule }
    BackHandler(onBack=onClose)
    ResolvingPlayback("download:${expected.request.id}:${expected.startTimeMs}",metadata?.title ?: "恢复下载地址",resolve={
        if(resolveOverride!=null)resolveOverride() else {
            if(metadata==null || origin==null || rule==null)throw MediaResolutionFailure("原来源","原来源未启用或记录缺失，请先恢复对应规则。")
            val prefix=origin.rule+"|"
            if(!metadata.resumeKey.startsWith(prefix))throw MediaResolutionFailure("原集数","原集数地址缺失，请回原播放页选择该集。")
            val page=metadata.resumeKey.removePrefix(prefix)
            if(java.net.URI(page).scheme !in listOf("http","https"))throw MediaResolutionFailure("原集数","原集数地址无效，请回原播放页选择该集。")
            WebMediaResolver(context).resolve(page,rule,metadata.title)
        }
    },verification=if(rule!=null) ({ challenge,done -> VerificationScreen(rule,challenge.pageUrl,challenge=challenge,onDone=done) }) else null,onClose=onClose,closeLabel="返回下载列表") { resolved ->
        var problem by remember(resolved) { mutableStateOf("") }
        val first=remember { FocusRequester() }
        LaunchedEffect(resolved) { withFrameNanos { }; first.requestFocus() }
        Column(Modifier.fillMaxSize().background(KazumiColors.background).padding(32.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
            Text(metadata?.title ?: "恢复下载地址",style=KazumiType.heading)
            Text("已重新解析。确认后清除本集旧片段，使用新地址从头下载；作品、来源和离线历史身份保留。",style=KazumiType.body)
            Text("取消会保留现有任务和文件。",style=KazumiType.caption)
            PlayerAction("用新地址重新下载",Modifier.focusRequester(first)) {
                runCatching { OfflineDownloads.get(context).replaceResolved(expected,resolved) }.onSuccess { onClose() }
                    .onFailure { problem=it.message ?: "无法替换下载任务" }
            }
            PlayerAction("取消，保留原任务",onClick=onClose)
            if(problem.isNotBlank())Text(problem,style=KazumiType.body)
        }
    }
}
