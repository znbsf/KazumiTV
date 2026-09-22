@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.tv.material3.*
import kotlinx.coroutines.CancellationException
import org.kazumi.tv.data.*

@Composable
internal fun CreditsScreen(subject:Subject,load:suspend(Int,Boolean)->List<CreditEntry> = { id,characters -> CreditsRepository().list(id,characters) },loadDetail:suspend(CreditEntry)->CreditEntry={ CreditsRepository().detail(it) },onBack:()->Unit) {
    var characters by rememberSaveable { mutableStateOf(true) }
    var retry by remember { mutableIntStateOf(0) }
    var rows by remember { mutableStateOf<List<CreditEntry>?>(null) }
    var failed by remember { mutableStateOf(false) }
    var path by rememberSaveable(stateSaver=NavigationStateSavers.credits) { mutableStateOf(arrayListOf<CreditEntry>()) }
    var query by rememberSaveable { mutableStateOf("") }
    var selected by rememberSaveable { mutableStateOf<String?>(null) }
    val grid=rememberLazyGridState(); val focus=remember { mutableMapOf<String,FocusRequester>() }
    val backFocus=remember { FocusRequester() }
    val visible=CreditQuery.filter(rows.orEmpty(),query)
    val revision by NetworkSettings.catalogRevision.collectAsState()
    BackHandler(path.isNotEmpty()) { path=ArrayList(path.dropLast(1)) }
    LaunchedEffect(subject.id,characters,retry,revision) {
        rows=null; failed=false
        try { rows=load(subject.id,characters) } catch(e:CancellationException) { throw e } catch(_:Exception) { failed=true }
    }
    LaunchedEffect(path.isEmpty(),rows) {
        if(path.isEmpty()) {
            withFrameNanos { }
            val index=visible.indexOfFirst { it.key==selected }
            if(index>=0) { grid.scrollToItem(index); withFrameNanos { }; withFrameNanos { }; focus[selected]?.requestFocus() }
            else backFocus.requestFocus()
        }
    }
    if(path.isNotEmpty()) {
        key(path.last().key) { CreditDetail(path.last(),if(path.size>1) "返回角色资料" else "返回名单",loadDetail,{ path=ArrayList(path.dropLast(1)) }) { path=ArrayList(path+it) } }
        return
    }
    Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
        Text("${subject.title} · 角色与制作",style=KazumiType.heading,maxLines=2,overflow=TextOverflow.Ellipsis)
        Row(horizontalArrangement=Arrangement.spacedBy(12.dp)) {
            PlayerAction("返回作品详情",Modifier.focusRequester(backFocus),onClick=onBack)
            PlayerAction(if(characters) "✓ 角色与配音" else "角色与配音") { characters=true; selected=null; query="" }
            PlayerAction(if(!characters) "✓ 制作人员" else "制作人员") { characters=false; selected=null; query="" }
        }
        BasicTextField(value=query,onValueChange={ query=it.take(100); selected=null },singleLine=true,
            textStyle=KazumiType.body.copy(color=KazumiColors.text),cursorBrush=SolidColor(KazumiColors.accent),
            modifier=Modifier.fillMaxWidth().background(KazumiColors.surface).padding(10.dp),
            decorationBox={ inner -> if(query.isEmpty())Text("筛选姓名、职务或配音",style=KazumiType.body,color=KazumiColors.muted); inner() })
        if(failed)PlayerAction("名单加载失败，重试") { retry++ }
        else if(rows==null)Text("正在读取名单…",style=KazumiType.caption)
        else if(visible.isEmpty())Text(if(rows!!.isEmpty()) "暂无相关资料" else "没有符合筛选的资料",style=KazumiType.body)
        LazyVerticalGrid(columns=GridCells.Fixed(3),state=grid,modifier=Modifier.weight(1f),contentPadding=PaddingValues(6.dp),horizontalArrangement=Arrangement.spacedBy(12.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
            items(visible,key={it.key}) { row ->
                DisposableEffect(row.key) { onDispose { focus.remove(row.key) } }
                Card(onClick={ selected=row.key; path=arrayListOf(row) },modifier=Modifier.height(105.dp).focusRequester(focus.getOrPut(row.key) { FocusRequester() }),colors=CardDefaults.colors(containerColor=KazumiColors.surface,focusedContainerColor=KazumiColors.selected),scale=CardDefaults.scale(focusedScale=1.02f)) {
                    Row(Modifier.fillMaxSize(),horizontalArrangement=Arrangement.spacedBy(10.dp)) {
                        CoverImage(row.image,row.name,Modifier.width(70.dp).fillMaxHeight(),alignment=if(row.character) Alignment.TopCenter else Alignment.Center,emptyLabel="暂无头像")
                        Column(Modifier.weight(1f).padding(vertical=8.dp),verticalArrangement=Arrangement.spacedBy(4.dp)) {
                            Text(row.name,style=KazumiType.body,maxLines=1,overflow=TextOverflow.Ellipsis)
                            Text(row.job.ifBlank { "资料" },style=KazumiType.caption,maxLines=1,overflow=TextOverflow.Ellipsis)
                            val extra=if(characters)row.actors.joinToString(" / ") { it.name } else row.episodes.takeIf { it.isNotBlank() }?.let { "参与集数 $it" }.orEmpty()
                            if(extra.isNotBlank())Text(extra,style=KazumiType.caption,maxLines=2,overflow=TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}
@Composable
private fun CreditDetail(initial:CreditEntry,backLabel:String,load:suspend(CreditEntry)->CreditEntry,onBack:()->Unit,onActor:(CreditEntry)->Unit) {
    var entry by remember { mutableStateOf(initial) }; var failed by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(true) }; var retry by remember { mutableIntStateOf(0) }
    val focus=remember { FocusRequester() }
    var reading by rememberSaveable { mutableStateOf(false) }
    BackHandler(reading) { reading=false }
    LaunchedEffect(retry) {
        loading=true; failed=false
        try { entry=load(initial) } catch(e:CancellationException) { throw e } catch(_:Exception) { failed=true }
        finally { loading=false }
    }
    LaunchedEffect(reading) { if(!reading) { withFrameNanos { }; focus.requestFocus() } }
    if(reading) { SynopsisReader(entry.name,SynopsisText.clean(entry.summary)) { reading=false }; return }
    Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
        PlayerAction(backLabel,Modifier.focusRequester(focus),onClick=onBack)
        Row(horizontalArrangement=Arrangement.spacedBy(20.dp),modifier=Modifier.weight(1f)) {
            CoverImage(entry.image,entry.name,Modifier.width(158.dp).height(237.dp),contentScale=ContentScale.Fit,allowRetry=true,emptyLabel="暂无头像")
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                Text(entry.name,style=KazumiType.heading)
                if(entry.job.isNotBlank())Text(entry.job,style=KazumiType.caption)
                if(entry.episodes.isNotBlank())Text("参与集数 ${entry.episodes}",style=KazumiType.caption)
                if(loading)Text("正在加载完整资料…",style=KazumiType.caption)
                if(failed)PlayerAction("资料加载失败，重试") { retry++ }
                for(actor in entry.actors)PlayerAction("配音 · ${actor.name}") { onActor(actor) }
                Text(SynopsisText.clean(entry.summary).ifBlank { "暂无简介" },style=KazumiType.body,maxLines=6,overflow=TextOverflow.Ellipsis)
                if(entry.summary.isNotBlank())PlayerAction("阅读完整简介") { reading=true }
            }
        }
    }
}
