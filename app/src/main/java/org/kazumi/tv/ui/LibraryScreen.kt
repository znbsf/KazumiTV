@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.tv.material3.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import org.kazumi.tv.data.*

/** Observe progress writes so returning from playback refreshes shortcuts immediately. */
@Composable
internal fun rememberWatchHistory(): List<HistoryEntry> {
    val context=LocalContext.current
    val store=remember(context) { LibraryStore(context) }
    val prefs=remember(context) { context.getSharedPreferences("tv_library",0) }
    var revision by remember(context) { mutableIntStateOf(0) }
    DisposableEffect(prefs) {
        val listener=android.content.SharedPreferences.OnSharedPreferenceChangeListener { _,key ->
            if(key=="history" || key==null)revision++
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        onDispose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }
    return remember(context,revision) { HistoryQuery.filter(store.history()) }
}

@Composable
fun LibraryScreen(mode: String, onResume: (HistoryEntry) -> Unit, onSelect: (Subject) -> Unit) {
    if(mode=="收藏") { CollectionScreen(onSelect); return }
    val context=LocalContext.current
    val store=remember { LibraryStore(context) }
    var revision by remember { mutableIntStateOf(0) }
    var managing by rememberSaveable { mutableStateOf(false) }
    var marked by rememberSaveable { mutableStateOf(arrayListOf<String>()) }
    var confirm by remember { mutableStateOf(false) }
    var notice by remember { mutableStateOf<String?>(null) }
    var query by rememberSaveable { mutableStateOf("") }
    var kindIndex by rememberSaveable { mutableIntStateOf(0) }
    var groupingIndex by rememberSaveable { mutableIntStateOf(0) }
    val managementFocus=remember { FocusRequester() }
    val deleteFocus=remember { FocusRequester() }
    val cancelFocus=remember { FocusRequester() }
    val list=rememberLazyListState()
    var selectedKey by rememberSaveable { mutableStateOf<String?>(null) }
    val requesters=remember { mutableMapOf<String,FocusRequester>() }
    val history=rememberWatchHistory()
    val grouping=HistoryGrouping.entries[groupingIndex]
    val visible=remember(history,query,kindIndex) { HistoryQuery.filter(history,query,HistoryKind.entries.getOrNull(kindIndex-1)) }
    val groups=remember(visible,grouping) { HistoryQuery.groups(visible,grouping) }
    // Includes group headers so return-to-record indexes match the actual lazy list.
    val rowKeys=remember(groups) { groups.flatMap { group -> listOf(group.key)+group.entries.map { it.key } } }
    BackHandler(managing) { if(confirm)confirm=false else { managing=false; marked=arrayListOf() } }
    LaunchedEffect(confirm,managing) {
        if(confirm) { withFrameNanos { }; cancelFocus.requestFocus() }
        else if(managing && marked.isNotEmpty()) { withFrameNanos { }; withFrameNanos { }; deleteFocus.requestFocus() }
    }
    LaunchedEffect(revision) { if(revision>0) { withFrameNanos { }; managementFocus.requestFocus() } }
    LaunchedEffect(selectedKey) {
        selectedKey?.let { key ->
            val index=rowKeys.indexOf(key)
            if(index>=0) { list.scrollToItem(index); withFrameNanos { }; withFrameNanos { }; requesters[key]?.requestFocus() }
        }
    }
    fun clearSelection() { marked=arrayListOf(); selectedKey=null }
    Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
        Text("历史 · ${visible.size} / ${history.size}",style=KazumiType.heading)
        if(confirm) {
            Column(Modifier.background(KazumiColors.surface).padding(24.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
                Text("删除选中的 ${marked.size} 条历史？",style=KazumiType.title)
                Text("可以撤销最近一次删除。",style=KazumiType.body)
                Row(horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                    PlayerAction("取消",Modifier.focusRequester(cancelFocus)) { confirm=false }
                    PlayerAction("确认删除") {
                        val count=store.deleteHistory(marked.toSet())
                        notice="已删除 $count 条记录"; clearSelection(); managing=false; confirm=false; revision++
                    }
                }
            }
        } else {
            store.warning()?.let { Text(it,style=KazumiType.caption) }
            notice?.let { Text(it,style=KazumiType.caption) }
            Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                PlayerAction(grouping.label) { groupingIndex=(groupingIndex+1)%HistoryGrouping.entries.size; clearSelection() }
                PlayerAction("来源：${HistoryKind.entries.getOrNull(kindIndex-1)?.label ?: "全部"}") { kindIndex=(kindIndex+1)%3; clearSelection() }
                PlayerAction(if(managing) "结束管理" else "管理记录",Modifier.focusRequester(managementFocus)) { managing=!managing; clearSelection() }
                if(managing) {
                    PlayerAction("全选") { marked=ArrayList(visible.map { it.key }) }
                    if(marked.isNotEmpty())PlayerAction("删除所选（${marked.size}）",Modifier.focusRequester(deleteFocus)) { confirm=true }
                }
                if(store.deletedHistoryCount()>0)PlayerAction("撤销上次删除") {
                    val count=store.undoHistoryDeletion(); notice="已恢复 $count 条记录"; revision++
                }
            }
            BasicTextField(value=query,onValueChange={ query=it.take(100); clearSelection() },singleLine=true,
                textStyle=KazumiType.body.copy(color=KazumiColors.text),cursorBrush=SolidColor(KazumiColors.accent),
                modifier=Modifier.fillMaxWidth().background(KazumiColors.surface).padding(10.dp),
                decorationBox={ inner -> if(query.isEmpty())Text("搜索节目、集数或来源",style=KazumiType.body,color=KazumiColors.muted); inner() })
            if(TvPreferences(context).incognito)Text("隐身播放已开启，新观看进度不会写入。",style=KazumiType.caption)
            Text(if(managing) "全选仅选择当前筛选结果。" else "选择记录继续观看；按作品分组仍保留每条来源和进度。",style=KazumiType.caption)
            if(visible.isEmpty())Text(if(history.isEmpty()) "暂无记录" else "没有符合条件的记录",style=KazumiType.body)
            LazyColumn(state=list,modifier=Modifier.weight(1f),contentPadding=PaddingValues(4.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                groups.forEach { group ->
                    item(key=group.key) {
                        Row(horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                            Text("${group.label} · ${group.entries.size}条",style=KazumiType.title,modifier=Modifier.padding(vertical=8.dp))
                            if(grouping==HistoryGrouping.SUBJECT && !managing)PlayerAction("继续最近观看") {
                                val latest=group.entries.first(); selectedKey=latest.key; onResume(latest)
                            }
                        }
                    }
                    items(group.entries,key={it.key}) { entry ->
                        val source=entry.origin?.rule?.takeIf { it.isNotBlank() } ?: "来源未记录"
                        Row(horizontalArrangement=Arrangement.spacedBy(8.dp),verticalAlignment=androidx.compose.ui.Alignment.CenterVertically) {
                        Button(modifier=Modifier.weight(1f).height(64.dp).focusRequester(requesters.getOrPut(entry.key) { FocusRequester() }),
                            scale=ButtonDefaults.scale(focusedScale=1f),
                            colors=ButtonDefaults.colors(containerColor=Color.Transparent,focusedContainerColor=Color.White.copy(alpha=.12f),contentColor=KazumiColors.text,focusedContentColor=KazumiColors.accent),
                            onClick={
                                if(managing) marked=ArrayList(if(entry.key in marked)marked-entry.key else marked+entry.key)
                                else { selectedKey=entry.key; onResume(entry) }
                            }) {
                            Column(Modifier.fillMaxWidth()) {
                                Text("${if(managing) if(entry.key in marked) "已选 · " else "未选 · " else ""}${entry.subject.title} · ${entry.episode}",style=KazumiType.body,maxLines=1,overflow=TextOverflow.Ellipsis)
                                Text("${entry.position/60000}分${entry.position/1000%60}秒 · ${entry.kind.label} · $source",style=KazumiType.caption,maxLines=1,overflow=TextOverflow.Ellipsis)
                            }
                        }
                        if(!managing)PlayerAction("番剧详情") { selectedKey=entry.key; onSelect(entry.subject) }
                        }
                    }
                }
            }
        }
    }
}
