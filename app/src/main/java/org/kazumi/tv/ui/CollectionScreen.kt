@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.*
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import org.kazumi.tv.data.*

@Composable
internal fun CollectionTypePicker(title: String, current: CollectionType?, onCancel: () -> Unit, onChoose: (CollectionType?) -> Unit) {
    val focus=remember { FocusRequester() }
    LaunchedEffect(Unit) { withFrameNanos { }; focus.requestFocus() }
    Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
        Text(title,style=KazumiType.heading)
        PlayerAction("取消",Modifier.focusRequester(focus),onClick=onCancel)
        CollectionType.entries.forEach { type -> PlayerAction(type.label+(if(type==current) " · 当前" else "")) { onChoose(type) } }
        PlayerAction("取消收藏") { onChoose(null) }
    }
}

@Composable
internal fun CollectionScreen(onSelect: (Subject) -> Unit) {
    val context=LocalContext.current
    val store=remember { LibraryStore(context) }
    var revision by remember { mutableIntStateOf(0) }
    var category by rememberSaveable { mutableIntStateOf(0) }
    var sortIndex by rememberSaveable { mutableIntStateOf(0) }
    var query by rememberSaveable { mutableStateOf("") }
    var managing by rememberSaveable { mutableStateOf(false) }
    var selected by rememberSaveable { mutableStateOf(arrayListOf<Int>()) }
    var choosing by rememberSaveable { mutableStateOf(false) }
    var confirmRemove by rememberSaveable { mutableStateOf(false) }
    var notice by remember { mutableStateOf<String?>(null) }
    var lastId by rememberSaveable { mutableStateOf<Int?>(null) }
    var pendingReturn by rememberSaveable { mutableStateOf(false) }
    var viewportId by rememberSaveable { mutableStateOf<Int?>(null) }
    var viewportIndex by rememberSaveable { mutableIntStateOf(0) }
    var viewportOffset by rememberSaveable { mutableIntStateOf(0) }
    var restore by remember { mutableStateOf(false) }
    val grid=rememberLazyGridState()
    val actions=remember { FocusRequester() }
    val cancel=remember { FocusRequester() }
    val itemFocus=remember { mutableMapOf<Int,FocusRequester>() }
    val all=remember(revision) { store.collections() }
    val type=CollectionType.entries.firstOrNull { it.code==category }
    val sort=CollectionSort.entries[sortIndex]
    val entries=remember(all,category,sortIndex,query) { CollectionQuery.results(all,type,sort,query) }
    BackHandler(managing || choosing || confirmRemove) {
        when { confirmRemove -> { confirmRemove=false; choosing=true }; choosing -> { choosing=false; restore=true }; else -> { managing=false; selected=arrayListOf(); restore=true } }
    }
    LaunchedEffect(confirmRemove) { if(confirmRemove) { withFrameNanos { }; cancel.requestFocus() } }
    LaunchedEffect(choosing,confirmRemove,restore) {
        if(!choosing && !confirmRemove && restore) { withFrameNanos { }; actions.requestFocus(); restore=false }
    }
    LaunchedEffect(pendingReturn,entries,managing,choosing,confirmRemove) {
        if(!pendingReturn || managing || choosing || confirmRemove)return@LaunchedEffect
        lastId?.let { id ->
            val target=ReturnViewport.resolve(entries.map { it.subject.id },id,viewportId,viewportIndex,viewportOffset)
            if(target!=null) {
                grid.scrollToItem(target.scrollIndex,target.scrollOffset); withFrameNanos { }; withFrameNanos { }
                if(grid.layoutInfo.visibleItemsInfo.none { it.index==target.focusIndex }) {
                    grid.scrollToItem(target.focusIndex); withFrameNanos { }; withFrameNanos { }
                }
                val restoredId=entries[target.focusIndex].subject.id
                itemFocus[restoredId]?.requestFocus(); lastId=restoredId
            } else { withFrameNanos { }; actions.requestFocus(); lastId=null }
        }
        pendingReturn=false
    }
    fun apply(type: CollectionType?) {
        val count=store.changeCollections(selected.toSet(),type)
        notice=if(type==null) "已取消 $count 条收藏" else "已将 $count 条收藏设为${type.label}"
        revision++; selected=arrayListOf(); managing=false; choosing=false; confirmRemove=false; restore=true
    }
    if(confirmRemove) {
        Column(verticalArrangement=Arrangement.spacedBy(16.dp)) {
            Text("取消选中的 ${selected.size} 条收藏？",style=KazumiType.heading)
            Text("不会删除观看历史。",style=KazumiType.body)
            PlayerAction("返回管理",Modifier.focusRequester(cancel)) { confirmRemove=false; choosing=false; restore=true }
            PlayerAction("确认取消收藏") { apply(null) }
        }
        return
    }
    if(choosing) {
        CollectionTypePicker("修改 ${selected.size} 条收藏",null,onCancel={ choosing=false; restore=true }) {
            if(it==null) { choosing=false; confirmRemove=true } else apply(it)
        }
        return
    }
    Column(verticalArrangement=Arrangement.spacedBy(10.dp)) {
        Text("收藏 · ${entries.size} / ${all.size}",style=KazumiType.heading)
        notice?.let { Text(it,style=KazumiType.caption) }
        store.warning()?.let { Text(it,style=KazumiType.caption) }
        Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
            PlayerAction("分类：${type?.label ?: "全部"}") { pendingReturn=false; category=(category+1)%6; selected=arrayListOf() }
            PlayerAction("排序：${sort.label}") { pendingReturn=false; sortIndex=(sortIndex+1)%CollectionSort.entries.size }
            PlayerAction(if(managing) "结束管理" else "管理收藏",Modifier.focusRequester(actions)) { pendingReturn=false; managing=!managing; selected=arrayListOf() }
            if(managing) {
                PlayerAction("选择当前结果") { selected=ArrayList(entries.map { it.subject.id }) }
                if(selected.isNotEmpty())PlayerAction("修改所选（${selected.size}）") { choosing=true }
            }
        }
        BasicTextField(value=query,onValueChange={ pendingReturn=false; query=it.take(100); selected=arrayListOf() },singleLine=true,
            textStyle=KazumiType.body.copy(color=KazumiColors.text),cursorBrush=SolidColor(KazumiColors.accent),
            modifier=Modifier.fillMaxWidth().background(KazumiColors.surface).padding(10.dp),
            decorationBox={ inner -> if(query.isEmpty())Text("搜索收藏名称 / 原名",style=KazumiType.body,color=KazumiColors.muted); inner() })
        if(entries.isEmpty()) Text("没有符合条件的收藏",style=KazumiType.body)
        LazyVerticalGrid(columns=GridCells.Fixed(6),state=grid,modifier=Modifier.weight(1f),
            horizontalArrangement=Arrangement.spacedBy(12.dp),verticalArrangement=Arrangement.spacedBy(12.dp),contentPadding=PaddingValues(4.dp)) {
            items(entries,key={it.subject.id}) { entry ->
                Card(onClick={
                    if(managing) selected=ArrayList(if(entry.subject.id in selected)selected-entry.subject.id else selected+entry.subject.id)
                    else {
                        lastId=entry.subject.id
                        pendingReturn=true
                        viewportIndex=grid.firstVisibleItemIndex; viewportOffset=grid.firstVisibleItemScrollOffset
                        viewportId=entries.getOrNull(viewportIndex)?.subject?.id
                        onSelect(entry.subject)
                    }
                },modifier=Modifier.height(200.dp).focusRequester(itemFocus.getOrPut(entry.subject.id) { FocusRequester() }),
                    colors=CardDefaults.colors(containerColor=KazumiColors.surface,focusedContainerColor=KazumiColors.selected),
                    scale=CardDefaults.scale(focusedScale=1.035f)) {
                    Box(Modifier.fillMaxSize()) {
                        CoverImage(entry.subject.cover,entry.subject.title,Modifier.fillMaxSize(),contentScale=ContentScale.Crop)
                        Box(Modifier.fillMaxWidth().height(90.dp).align(Alignment.BottomCenter)
                            .background(Brush.verticalGradient(listOf(Color.Transparent,Color.Black.copy(alpha=.94f)))))
                        Text((if(managing) if(entry.subject.id in selected) "已选 · " else "未选 · " else "")+entry.type.label,
                            style=KazumiType.caption,modifier=Modifier.padding(8.dp).background(Color.Black.copy(alpha=.6f)).padding(4.dp))
                        Text(entry.subject.title,style=KazumiType.body,maxLines=2,overflow=TextOverflow.Ellipsis,
                            color=Color.White,modifier=Modifier.align(Alignment.BottomStart).padding(10.dp))
                    }
                }
            }
        }
    }
}
