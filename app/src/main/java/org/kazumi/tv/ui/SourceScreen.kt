@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.tv.material3.*
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.kazumi.tv.data.Subject
import org.kazumi.tv.playback.*
import org.kazumi.tv.rules.*

data class SourceTransfer(val episode:Episode,val position:Long)
data class SourcePlaybackSelection(val ruleName:String,val episode:Episode,val roads:List<Road>,val road:Int,val origin:org.kazumi.tv.data.PlaybackOrigin,val position:Long)

@Composable
fun SourceScreen(subject: Subject,transfer:SourceTransfer?=null,onSelect:((SourcePlaybackSelection)->Unit)?=null,onCancel:()->Unit={},catalog:SourceCatalog?=null,
                 resolveEpisode:(suspend (String,Episode)->PlaybackRequest)?=null) {
    val context = LocalContext.current
    val repository = catalog ?: remember { RuleRepository(context) }
    if (repository.rules.isEmpty()) {
        Column { Text("没有启用的来源，请在设置的规则管理中启用规则。"); if(transfer!=null)PlayerAction("返回播放",onClick=onCancel) }
        BackHandler(transfer!=null,onBack=onCancel); return
    }
    var query by rememberSaveable(subject.id) { mutableStateOf(subject.title) }
    var keyword by rememberSaveable(subject.id) { mutableStateOf(subject.title) }
    var sourceName by rememberSaveable(subject.id) { mutableStateOf(repository.rules.first().name) }
    var removedSourceName by rememberSaveable(subject.id) { mutableStateOf<String?>(null) }
    val sourceExists = repository.rules.any { it.name == sourceName }
    val source = repository.rules.indexOfFirst { it.name == sourceName }.coerceAtLeast(0)
    var match by rememberSaveable(subject.id,stateSaver=PlaybackStateSavers.match) { mutableStateOf<SourceMatch?>(null) }
    var roads by remember { mutableStateOf(emptyList<Road>()) }
    var road by rememberSaveable(subject.id) { mutableIntStateOf(0) }
    var roadTitle by rememberSaveable(subject.id) { mutableStateOf("") }
    var episode by rememberSaveable(subject.id,stateSaver=PlaybackStateSavers.episode) { mutableStateOf<Episode?>(null) }
    var busy by remember { mutableStateOf(false) }
    var pageError by remember { mutableStateOf<String?>(null) }
    var refresh by remember { mutableIntStateOf(0) }
    var chapterRetry by remember { mutableIntStateOf(0) }
    var verifying by remember { mutableStateOf(false) }
    val results = remember { mutableStateMapOf<Int, List<SourceMatch>>() }
    val states = remember { mutableStateMapOf<Int, String>() }
    val verificationPages = remember { mutableStateMapOf<Int, SourceVerificationRequired>() }
    val sourceFocus = remember { FocusRequester() }
    val roadFocus = remember { FocusRequester() }
    val grid = rememberLazyGridState()
    val episodeFocus = remember { mutableMapOf<Int, FocusRequester>() }
    var returnEpisode by rememberSaveable(subject.id) { mutableStateOf<Int?>(null) }
    var returnPage by rememberSaveable(subject.id) { mutableStateOf<String?>(null) }
    val currentEpisodes = roads.getOrNull(road)?.episodes.orEmpty()
    LaunchedEffect(Unit) { withFrameNanos { }; if(match==null)runCatching { sourceFocus.requestFocus() } }
    LaunchedEffect(sourceExists) {
        if(!sourceExists) {
            match=null;episode=null;roads=emptyList();road=0;roadTitle="";returnEpisode=null;returnPage=null
            val recovered=PlaybackStateSavers.recoverSource(sourceName,repository.rules.map { it.name },removedSourceName)
            sourceName=recovered.selectedName;removedSourceName=recovered.removedName
        }
    }
    LaunchedEffect(keyword, refresh) {
        results.clear(); states.clear(); verificationPages.clear()
        val limit = Semaphore(3)
        coroutineScope {
            repository.rules.forEachIndexed { index, rule -> launch {
                states[index] = "正在搜索…"
                limit.withPermit {
                    try {
                        val found = repository.search(rule, keyword).distinctBy { it.url }
                        results[index] = found
                        states[index] = if (found.isEmpty()) "没有结果" else "${found.size} 个结果"
                    } catch (cancelled: CancellationException) { throw cancelled }
                    catch (failure: SourceVerificationRequired) { states[index] = failure.message.orEmpty(); verificationPages[index] = failure }
                    catch (error: Exception) { states[index] = if (error is IllegalStateException) error.message ?: "检索失败" else "连接失败，可重试" }
                }
            } }
        }
    }
    LaunchedEffect(match, source, chapterRetry) {
        roads = emptyList(); pageError = null
        if(!sourceExists)return@LaunchedEffect
        val chosen = match ?: return@LaunchedEffect
        busy = true
        try {
            roads = repository.chapters(repository.rules[source], chosen)
            road=PlaybackStateSavers.roadIndex(roads,roadTitle,road,episode?.pageUrl ?: returnPage)
            roadTitle=roads.getOrNull(road)?.title.orEmpty()
            val returnIndex=roads.getOrNull(road)?.episodes?.indexOfFirst { it.pageUrl==returnPage } ?: -1
            returnEpisode=returnIndex.takeIf { it>=0 }
        }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: SourceVerificationRequired) { pageError = failure.message; verificationPages[source] = failure }
        catch (error: Exception) { pageError = error.message ?: "线路加载失败" }
        finally { busy = false }
        if (roads.isNotEmpty()&&episode==null&&returnEpisode==null) { withFrameNanos { }; runCatching { roadFocus.requestFocus() } }
    }
    fun choose(index:Int,position:Long=0) {
        val selected=currentEpisodes[index]
        returnPage=selected.pageUrl;returnEpisode=index;roadTitle=roads[road].title
        if(onSelect==null)episode=selected
        else onSelect(SourcePlaybackSelection(repository.rules[source].name,selected,roads,road,
            org.kazumi.tv.data.PlaybackOrigin(repository.rules[source].name,match!!.title,match!!.url,roads[road].title),position))
    }
    BackHandler(transfer!=null && match==null,onBack=onCancel)
    fun closePlayer() { returnPage=episode?.pageUrl ?: returnPage; returnEpisode = currentEpisodes.indexOfFirst { it.pageUrl==returnPage }.takeIf { it>=0 }; episode = null }
    BackHandler(match != null) { match = null; episode = null; pageError = null }
    BackHandler(episode != null) { closePlayer() }
    if (verifying) Dialog(onDismissRequest = { verifying = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        VerificationScreen(repository.rules[source], verificationPages[source]?.pageUrl ?: match?.url ?: repository.rules[source].baseUrl, challenge=verificationPages[source]) { verifying = false; refresh++; chapterRetry++ }
    }
    episode?.takeIf { sourceExists }?.let { selected ->
        Dialog(onDismissRequest = { closePlayer() }, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
            PlaybackSessionScreen(subject, repository.rules[source].name, selected, roads, road,
                sourceCatalog = repository,resolveEpisode=resolveEpisode,
                initialOrigin = match?.let { org.kazumi.tv.data.PlaybackOrigin(repository.rules[source].name, it.title, it.url, roads.getOrNull(road)?.title ?: roadTitle) },
                onSelection = { next ->
                    road=PlaybackStateSavers.roadIndex(roads,roadTitle,road,next.pageUrl)
                    episode = next;returnPage=next.pageUrl;roadTitle=roads.getOrNull(road)?.title ?: roadTitle
                }, onReturnContext = { selection ->
                    // The active session may have switched source or advanced several episodes.
                    // Return the complete context, not the original Dialog entry arguments.
                    if(repository.rules.any { it.name==selection.ruleName }) {
                        sourceName=selection.ruleName
                        match=selection.origin?.let { SourceMatch(it.sourceTitle,it.sourceUrl) }
                        roads=selection.roads;road=selection.road
                        roadTitle=selection.roads.getOrNull(selection.road)?.title ?: selection.origin?.roadTitle.orEmpty()
                        returnPage=selection.episode.pageUrl
                        returnEpisode=selection.roads.getOrNull(selection.road)?.episodes?.indexOfFirst { it.pageUrl==returnPage }?.takeIf { it>=0 }
                        episode=null;pageError=null;removedSourceName=null
                    } else {
                        removedSourceName=selection.ruleName;match=null;episode=null;roads=emptyList();returnEpisode=null;returnPage=null
                    }
                }, onClose = { closePlayer() })
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if(transfer!=null) {
            Row(horizontalArrangement=Arrangement.spacedBy(14.dp),verticalAlignment=androidx.compose.ui.Alignment.CenterVertically) {
                PlayerAction("返回播放",onClick=onCancel)
                Text("更换来源 · 当前 ${transfer.episode.title}",style=KazumiType.title)
            }
            Text("请确认新来源的作品与季度一致，再选择同集续播。",style=KazumiType.caption)
        } else {
            Text(if (match == null) "选择播放来源" else "线路与选集", style = KazumiType.heading)
            Text(subject.title, style = KazumiType.caption, color = KazumiColors.muted, maxLines = 1)
        }
        if (match == null) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            TvTextInput(query, { query = it.take(150) }, modifier = Modifier.weight(1f))
            Button(onClick = { if (query.isNotBlank()) { keyword = query.trim(); refresh++ } }) { Text("重新搜索") }
        }
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            LazyColumn(Modifier.width(166.dp).fillMaxHeight().background(KazumiColors.surface).padding(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(repository.rules.indices.toList()) { index ->
                    Button(onClick = { sourceName = repository.rules[index].name; removedSourceName=null; match = null; episode = null; pageError = null;road=0;roadTitle="";returnEpisode=null;returnPage=null },
                        modifier = Modifier.fillMaxWidth().then(if (index == source) Modifier.focusRequester(sourceFocus) else Modifier),
                        colors = ButtonDefaults.colors(containerColor = if (source == index) KazumiColors.selected else KazumiColors.surface)) {
                        Column {
                            Text(repository.rules[index].name, style = KazumiType.control)
                            Text(states[index] ?: "等待搜索", style = KazumiType.caption, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
            Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (busy) Text(if (episode != null) "正在解析 ${episode!!.title}…" else "正在读取线路…", color = KazumiColors.accent)
                removedSourceName?.let { Text("原来源 $it 已停用或移除，请重新选择来源",style=KazumiType.caption) }
                pageError?.let { Text(it, style = KazumiType.caption) }
                if (match == null) {
                    Text("${repository.rules[source].name} · ${states[source] ?: "正在搜索…"}", style = KazumiType.title)
                    if (results[source].isNullOrEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { refresh++ }) { Text("重试搜索") }
                        Button(onClick = { verifying = true }) { Text("网页验证") }
                    }
                    LazyColumn(contentPadding = PaddingValues(6.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        items(results[source].orEmpty(), key = { it.url }) { found ->
                            Button(modifier = Modifier.fillMaxWidth(), onClick = { road=0;roadTitle="";returnEpisode=null;returnPage=null;match = found }) {
                                Column(Modifier.fillMaxWidth()) {
                                    Text(found.title, style = KazumiType.title, maxLines = 2)
                                    Text("查看线路与集数", style = KazumiType.caption, color = KazumiColors.muted)
                                }
                            }
                        }
                    }
                } else {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Button(onClick = { match = null; episode = null }) { Text("返回匹配结果") }
                        if (pageError != null) Button(onClick = { chapterRetry++ }) { Text("重试") }
                    }
                    Text(match!!.title, style = KazumiType.title, maxLines = 1)
                    if (!busy && roads.isEmpty()) {
                        Text("没有读取到集数，可重试或完成网页验证。", style = KazumiType.caption)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = { chapterRetry++ }) { Text("重新读取") }
                            Button(onClick = { verifying = true }) { Text("网页验证") }
                        }
                    }
                    LazyRow(contentPadding = PaddingValues(6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(roads.indices.toList()) { index ->
                            Button(modifier = if (index == road) Modifier.focusRequester(roadFocus) else Modifier,
                                onClick = { road = index;roadTitle=roads[index].title; episode = null; returnEpisode=null;returnPage=null; pageError = null },
                                colors = ButtonDefaults.colors(containerColor = if (road == index) KazumiColors.selected else KazumiColors.surface)) { Text(roads[index].title) }
                        }
                    }
                    if(transfer!=null && !busy && currentEpisodes.isNotEmpty()) {
                        val matched=org.kazumi.tv.domain.PlaybackIdentity.matchingAcrossSources(transfer.episode,currentEpisodes)
                        if(matched!=null) {
                            PlayerAction("续播 ${currentEpisodes[matched].title} · 保留进度") { choose(matched,transfer.position.coerceAtLeast(0)) }
                            Text("下方手动选集均从头播放。",style=KazumiType.caption)
                        } else Text("未找到唯一同集，请手动选集；所选集从头播放。",style=KazumiType.caption)
                    }
                    key(source,match?.url,road) {
                        val viewed=org.kazumi.tv.data.LibraryStore(context).history().filter { it.subject.id==subject.id && it.position>0 }.map { it.key }.toSet()
                        val seen=currentEpisodes.indices.filter { "${repository.rules[source].name}|${currentEpisodes[it].pageUrl}" in viewed }.toSet()
                        EpisodeBrowser(currentEpisodes.map { it.title },current=returnEpisode ?: -1,seen=seen,
                            modifier=Modifier.weight(1f),restoreIndex=if(episode==null)returnEpisode else null,compact=true) { index -> choose(index) }
                    }
                }
            }
        }
    }
}
