@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.*
import coil.compose.AsyncImage
import kotlinx.coroutines.CancellationException
import org.kazumi.tv.data.*

@Composable
fun SearchScreen(model: SearchViewModel = viewModel(), onSelect: (Subject) -> Unit) {
    val state by model.pager.state.collectAsState()
    val results = remember(state.pages) { state.items }
    var query by remember { mutableStateOf(model.text) }
    val context = LocalContext.current
    val store = remember { SearchHistoryStore(context) }
    var history by remember { mutableStateOf(store.read()) }
    val grid = rememberLazyGridState(model.scrollIndex,model.scrollOffset)
    val focus = remember { mutableMapOf<Int,FocusRequester>() }
    var displayed by remember(state.query,state.sort) { mutableStateOf(emptyList<Subject>()) }
    fun submit(text: String,sort: String=state.sort) {
        if(text.isBlank())return
        query=text; model.text=text; store.add(text); history=store.read(); model.submit(text,sort)
    }
    LaunchedEffect(state.pages,state.loading,model.restoringPages) {
        if(model.restoringPages)return@LaunchedEffect
        val anchor=displayed.getOrNull(grid.firstVisibleItemIndex)?.id
        val index=results.indexOfFirst { it.id==anchor }
        if(index>=0 && displayed!=results)grid.scrollToItem(index,grid.firstVisibleItemScrollOffset)
        else if(displayed.isEmpty() && !model.restoreFocus)grid.scrollToItem(0)
        displayed=results
        focus.keys.retainAll(results.map { it.id }.toSet())
        if(model.restoreFocus) {
            // Retain the original anchor until the failed window can be retried.
            if(state.failedOffset!=null)return@LaunchedEffect
            val selected=results.indexOfFirst { it.id==model.focusId }
            val restoredAnchor=results.indexOfFirst { it.id==model.scrollAnchorId }
            if(results.isNotEmpty() && !state.loading) {
                grid.scrollToItem(if(restoredAnchor>=0)restoredAnchor else selected.coerceAtLeast(0),
                    if(restoredAnchor>=0)model.scrollOffset else 0)
                withFrameNanos { }; withFrameNanos { }
                // Preserve the saved viewport. Scroll to the focused item only if
                // changed server results moved it outside that viewport.
                if(selected>=0) {
                    if(grid.layoutInfo.visibleItemsInfo.none { it.index==selected }) {
                        grid.scrollToItem(selected)
                        withFrameNanos { }; withFrameNanos { }
                    }
                    focus[model.focusId]?.requestFocus()
                }
                model.restoreFocus=false
            } else if(!state.loading && results.isEmpty()) {
                model.restoreFocus=false
                model.focusId=null
                model.scrollIndex=0; model.scrollOffset=0
            }
        }
    }
    LaunchedEffect(grid,state.pages,model.restoringPages) {
        if(model.restoringPages)return@LaunchedEffect
        snapshotFlow { grid.firstVisibleItemIndex to grid.firstVisibleItemScrollOffset }.collect { (index,offset) ->
            model.scrolled(index,offset)
        }
    }
    LaunchedEffect(grid,state.pages,state.loading,state.failedOffset) {
        snapshotFlow { grid.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: -1 }.collect { last ->
            if(last >= results.size-12 && results.isNotEmpty() && !state.loading && !model.restoringPages && !model.restoreFocus)model.pager.next()
        }
    }
    Column(Modifier.fillMaxSize(),verticalArrangement=Arrangement.spacedBy(12.dp)) {
        Text("搜索番剧",style=KazumiType.heading)
        Row(horizontalArrangement=Arrangement.spacedBy(12.dp)) {
            TvTextInput(query,{ query=it.take(150); model.text=query },modifier=Modifier.weight(1f))
            PlayerAction("搜索") { submit(query) }
            PlayerAction(if(state.sort=="match") "排序：相关" else "排序：评分") {
                submit(query,if(state.sort=="match") "score" else "match")
            }
        }
        if(history.isNotEmpty()) LazyRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
            item { PlayerAction("清除搜索历史") { store.clear(); history=emptyList() } }
            items(history,key={it}) { term -> PlayerAction(term) { submit(term) } }
        }
        Row(horizontalArrangement=Arrangement.spacedBy(12.dp)) {
            Text(when {
                state.failedOffset!=null -> "搜索失败，已保留当前结果"
                state.loading -> "正在搜索…"
                state.query.isBlank() -> "输入番剧名称，按搜索查找"
                results.isEmpty() -> "没有找到匹配番剧"
                state.endReached -> "已到结果末尾"
                else -> "向下浏览自动加载更多"
            },style=KazumiType.caption)
            if(state.failedOffset!=null)PlayerAction("重试搜索") { model.retry() }
            if(state.firstOffset>0)PlayerAction("更早结果") { model.pager.previous() }
        }
        LazyVerticalGrid(columns=GridCells.Fixed(6),state=grid,modifier=Modifier.weight(1f),contentPadding=PaddingValues(8.dp),
            horizontalArrangement=Arrangement.spacedBy(16.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
            items(results,key={it.id}) { item ->
                val requester=focus.getOrPut(item.id) { FocusRequester() }
                Card(onClick={ model.selected(item.id,grid.firstVisibleItemIndex,grid.firstVisibleItemScrollOffset); onSelect(item) },
                    modifier=Modifier.height(180.dp).focusRequester(requester).onFocusChanged { if(it.isFocused)model.focused(item.id) }) {
                    CoverImage(item.cover,item.title,contentScale=ContentScale.Crop,modifier=Modifier.fillMaxWidth().weight(1f))
                    Text(item.title,maxLines=2,minLines=2,modifier=Modifier.padding(8.dp),style=KazumiType.caption)
                }
            }
        }
    }
}
