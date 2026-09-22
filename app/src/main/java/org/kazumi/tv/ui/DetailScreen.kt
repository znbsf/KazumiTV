@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui

import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.tv.material3.*
import coil.compose.AsyncImage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.kazumi.tv.data.*

@Composable
internal fun DetailScreen(subject: Subject, loadRelations:suspend(Int)->RelationResult={ RelationRepository().load(it) },
                          sourceCatalog:org.kazumi.tv.rules.SourceCatalog?=null,onResume:((HistoryEntry)->Unit)?=null,
                          resolveEpisode:(suspend (String,org.kazumi.tv.rules.Episode)->org.kazumi.tv.playback.PlaybackRequest)?=null,
                          loadDetail: suspend (Int) -> Subject = { CatalogRepository().detail(it) }) {
    var path by rememberSaveable(subject.id,stateSaver=NavigationStateSavers.subjects) { mutableStateOf(arrayListOf(subject)) }
    val states=rememberSaveableStateHolder()
    var depthNotice by remember { mutableStateOf(false) }
    fun back() { depthNotice=false; val removed=path.last(); path=ArrayList(path.dropLast(1)); states.removeState(removed.id) }
    BackHandler(path.size>1) { back() }
    Column(Modifier.fillMaxSize()) {
        if(depthNotice)Text("已打开较多关联作品，请先返回上个作品。",style=KazumiType.caption)
        if(path.size>1)PlayerAction("返回上个作品") { back() }
        states.SaveableStateProvider(path.last().id) {
            DetailContent(path.last(),loadDetail,loadRelations,sourceCatalog,onResume,resolveEpisode) { next ->
                val index=path.indexOfFirst { it.id==next.id }
                if(index>=0) { path.drop(index+1).forEach { states.removeState(it.id) }; path=ArrayList(path.take(index+1)) }
                else if(path.size<32)path=ArrayList(path+next) else depthNotice=true
            }
        }
    }
}

@Composable
private fun DetailContent(subject:Subject,loadDetail:suspend(Int)->Subject,loadRelations:suspend(Int)->RelationResult,
                          sourceCatalog:org.kazumi.tv.rules.SourceCatalog?,onResume:((HistoryEntry)->Unit)?,
                          resolveEpisode:(suspend (String,org.kazumi.tv.rules.Episode)->org.kazumi.tv.playback.PlaybackRequest)?,onRelated:(Subject)->Unit) {
    val latest=rememberWatchHistory().firstOrNull { it.subject.id==subject.id }
    var resume by rememberSaveable(subject.id,stateSaver=NavigationStateSavers.history) { mutableStateOf<HistoryEntry?>(null) }
    var sourceHistory by rememberSaveable(subject.id,stateSaver=NavigationStateSavers.history) { mutableStateOf<HistoryEntry?>(null) }
    var detail by remember(subject.id) { mutableStateOf(subject) }
    var error by remember(subject.id) { mutableStateOf(false) }
    var loading by remember(subject.id) { mutableStateOf(true) }
    var attempt by remember(subject.id) { mutableIntStateOf(0) }
    val catalogRevision by NetworkSettings.catalogRevision.collectAsState()
    LaunchedEffect(subject.id,attempt,catalogRevision) {
        loading = true; error = false
        try { detail = loadDetail(subject.id) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { error = true }
        finally { loading = false }
    }
    var sources by rememberSaveable(subject.id) { mutableStateOf(false) }
    var credits by rememberSaveable(subject.id) { mutableStateOf(false) }
    val creditsFocus=remember { FocusRequester() }
    var relations by rememberSaveable(subject.id) { mutableStateOf(false) }
    val relationsFocus=remember { FocusRequester() }
    var reading by rememberSaveable(subject.id) { mutableStateOf(false) }
    var restore by rememberSaveable(subject.id) { mutableStateOf<String?>(null) }
    val playFocus = remember { FocusRequester() }
    val episodesFocus = remember { FocusRequester() }
    val sourceChoiceFocus = remember { FocusRequester() }
    val summaryFocus = remember { FocusRequester() }
    BackHandler(sources) { sources = false; restore = if(sourceHistory!=null) "episodes" else "source" }
    BackHandler(credits) { credits=false; restore="credits" }
    BackHandler(relations) { relations=false; restore="relations" }
    BackHandler(reading) { reading = false; restore = "summary" }
    LaunchedEffect(sources, reading, relations, credits, restore) {
        if (!sources && !reading && !relations && !credits && restore != null && restore != "collection") {
            withFrameNanos { }
            withFrameNanos { }
            (when(restore) { "summary" -> summaryFocus; "relations" -> relationsFocus; "credits" -> creditsFocus;
                "episodes" -> if(latest?.kind==HistoryKind.ONLINE)episodesFocus else sourceChoiceFocus;
                "source" -> sourceChoiceFocus; else -> if(latest!=null)playFocus else sourceChoiceFocus }).requestFocus()
            restore = null
        }
    }
    val summary = remember(detail.summary) { SynopsisText.clean(detail.summary) }
    if (sources) { SourceScreen(detail,catalog=sourceCatalog,initialHistory=sourceHistory,resolveEpisode=resolveEpisode); return }
    if(credits) { CreditsScreen(detail) { credits=false; restore="credits" }; return }
    if(relations) { RelationsScreen(detail,loadRelations,{ relations=false; restore="relations" },onRelated); return }
    if (reading) { SynopsisReader(detail.title,summary) { reading = false; restore = "summary" }; return }
    resume?.let { entry -> ResumeScreen(entry) { resume=null; restore="play" } }
    val context = LocalContext.current
    val library = remember { LibraryStore(context) }
    var collection by remember(subject.id) { mutableStateOf(library.collections().firstOrNull { it.subject.id==subject.id }?.type) }
    var choosingCollection by rememberSaveable(subject.id) { mutableStateOf(false) }
    val collectionFocus=remember { FocusRequester() }
    BackHandler(choosingCollection) { choosingCollection=false }
    if(choosingCollection) {
        CollectionTypePicker(detail.title,collection,onCancel={ choosingCollection=false }) { type ->
            if(library.setCollection(detail,type)) { collection=type; choosingCollection=false }
        }
        return
    }
    LaunchedEffect(choosingCollection) { if(restore=="collection") { withFrameNanos { }; collectionFocus.requestFocus(); restore=null } }
    Row(Modifier.fillMaxSize(),horizontalArrangement = Arrangement.spacedBy(24.dp)) {
        CoverImage(detail.cover,detail.title,modifier = Modifier.width(158.dp).height(237.dp),contentScale = ContentScale.Crop,allowRetry=true)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()),verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(detail.title,style = KazumiType.heading,maxLines = 2,overflow = TextOverflow.Ellipsis)
            val info = detail.metadata
            val facts = buildList {
                if(info.date.isNotBlank()) add(info.date)
                if(info.platform.isNotBlank()) add(info.platform)
                info.episodes?.let { add("${it}集") }
                info.score?.let { add("评分 ${String.format(java.util.Locale.ROOT,"%.1f",it)}") }
                info.votes?.let { add("${it}人评价") }
                info.rank?.let { add("排名 #$it") }
            }
            if(facts.isNotEmpty()) Text(facts.joinToString(" · "),style = KazumiType.caption,color = KazumiColors.muted)
            if(latest!=null)Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    PlayerAction("继续 ${latest.episode.substringAfterLast(" · ")}",Modifier.focusRequester(playFocus)) {
                        if(onResume!=null)onResume(latest) else resume=latest
                    }
                    if(latest.kind==HistoryKind.ONLINE)PlayerAction("查看原来源选集",Modifier.focusRequester(episodesFocus)) { sourceHistory=latest; sources=true }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                PlayerAction(if(latest==null) "搜索播放来源" else "更换播放来源",
                    Modifier.focusRequester(sourceChoiceFocus)) { sourceHistory=null; sources = true }
                PlayerAction(collection?.let { "收藏 · ${it.label}" } ?: "收藏节目",Modifier.focusRequester(collectionFocus)) { restore="collection"; choosingCollection=true }
            }
            latest?.let { Text("上次看到 ${it.episode.substringAfterLast(" · ")} · ${it.position/60000}分${it.position/1000%60}秒",style=KazumiType.caption,color=KazumiColors.muted) }
            if(loading) Text("正在加载完整资料…",style = KazumiType.caption,color = KazumiColors.muted)
            if(error) {
                Text("完整资料加载失败，仍可搜索播放来源。",style = KazumiType.caption)
                PlayerAction("重试资料") { attempt++ }
            }
            if(info.originalTitle.isNotBlank() && info.originalTitle != detail.title)
                Text(info.originalTitle,style = KazumiType.caption,color = KazumiColors.muted)
            Text("简介",style = KazumiType.title)
            Text(summary.ifBlank { if(loading) "正在加载…" else "暂无简介" },maxLines = 5,overflow = TextOverflow.Ellipsis,style = KazumiType.body)
            PlayerAction("角色与制作",Modifier.focusRequester(creditsFocus)) { credits=true }
            PlayerAction("关联动画",Modifier.focusRequester(relationsFocus)) { relations=true }
            if(summary.isNotBlank()) PlayerAction("阅读完整简介",Modifier.focusRequester(summaryFocus)) { reading = true }
        }
    }
}

@Composable
internal fun SynopsisReader(title: String, summary: String, onBack: () -> Unit) {
    val scroll = rememberScrollState()
    val focus = remember { FocusRequester() }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { withFrameNanos { }; focus.requestFocus() }
    Column(Modifier.fillMaxSize(),verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title,style = KazumiType.heading,maxLines = 1,overflow = TextOverflow.Ellipsis)
        PlayerAction("返回详情",onClick = onBack)
        Text("方向键上下阅读，返回键回到详情。",style = KazumiType.caption,color = KazumiColors.muted)
        Box(Modifier.weight(1f).fillMaxWidth().focusRequester(focus).onPreviewKeyEvent { event ->
            if(event.nativeKeyEvent.action != KeyEvent.ACTION_DOWN) false else {
                val delta = when(event.nativeKeyEvent.keyCode) {
                    KeyEvent.KEYCODE_DPAD_DOWN -> 220
                    KeyEvent.KEYCODE_DPAD_UP -> -220
                    else -> 0
                }
                if(delta == 0 || (delta > 0 && !scroll.canScrollForward) || (delta < 0 && !scroll.canScrollBackward)) false
                else { scope.launch { scroll.scrollTo((scroll.value + delta).coerceIn(0,scroll.maxValue)) }; true }
            }
        }.focusable().verticalScroll(scroll)) { Text(summary,style = KazumiType.body) }
    }
}
