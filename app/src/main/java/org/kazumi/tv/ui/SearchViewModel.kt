package org.kazumi.tv.ui

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.first
import org.kazumi.tv.data.*

class SearchViewModel @JvmOverloads constructor(private val saved: SavedStateHandle,
    loader: (suspend (String,Int,String) -> List<Subject>)? = null) : ViewModel() {
    private val repository=CatalogRepository()
    val pager=SearchPager(viewModelScope,loader ?: { query,offset,sort -> repository.search(query,offset,sort) })
    var text: String
        get()=saved["text"] ?: ""
        set(value) { saved["text"]=value.take(150) }
    var focusId: Int?
        get()=saved["focus"]
        set(value) { saved["focus"]=value }
    var scrollIndex: Int
        get()=saved.get<Int>("scrollIndex")?.coerceAtLeast(0) ?: 0
        set(value) { saved["scrollIndex"]=value.coerceAtLeast(0) }
    var scrollOffset: Int
        get()=saved.get<Int>("scrollOffset")?.coerceAtLeast(0) ?: 0
        set(value) { saved["scrollOffset"]=value.coerceAtLeast(0) }
    var restoreFocus=false
    private var restoreJob: Job? = null
    private var restoreLastOffset=0
    var restoringPages by mutableStateOf(false)
        private set
    val scrollAnchorId: Int? get()=saved["scrollAnchor"]
    init {
        var revision=NetworkSettings.catalogRevision.value
        viewModelScope.launch {
            NetworkSettings.catalogRevision.collect { next ->
                if(next!=revision) {
                    revision=next; repository.clearCache()
                    val current=pager.state.value
                    if(current.query.isNotBlank())submit(current.query,current.sort)
                }
            }
        }
        val query=saved.get<String>("query").orEmpty()
        if(query.isNotBlank()) {
            restoreFocus=focusId != null || scrollAnchorId != null
            val first=(saved.get<Int>("windowFirst") ?: saved.get<Int>("offset") ?: 0).coerceAtLeast(0) / 20 * 20
            val last=(saved.get<Int>("windowLast") ?: first).coerceIn(first,first+80) / 20 * 20
            restoringPages=true
            pager.submit(query,saved["sort"] ?: "match",first)
            restoreWindow(last)
        }
    }
    private fun restoreWindow(last: Int) {
            restoreLastOffset=last
            restoreJob=viewModelScope.launch {
                try {
                    repeat(5) {
                        val state=pager.state.first { !it.loading }
                        if(state.failedOffset!=null || state.endReached || (state.pages.lastOrNull()?.offset ?: last)>=last)return@launch
                        pager.next()
                    }
                } finally { restoringPages=false }
            }
    }
    fun retry() {
        if(pager.state.value.failedOffset==null)return
        if(restoreFocus) {
            restoringPages=true
            pager.retry()
            restoreWindow(restoreLastOffset)
        } else pager.retry()
    }
    fun submit(query: String,sort: String) {
        restoreJob?.cancel(); restoringPages=false
        saved["query"]=query.trim().take(150); saved["sort"]=sort; saved["offset"]=0
        saved.remove<Int>("scrollAnchor"); saved.remove<Int>("windowFirst"); saved.remove<Int>("windowLast")
        focusId=null; scrollIndex=0; scrollOffset=0; restoreFocus=false
        pager.submit(query,sort)
    }
    fun selected(id: Int,index: Int,offset: Int) {
        // An explicit selection from retained results overrides a failed restore.
        restoreJob?.cancel(); restoringPages=false; restoreFocus=false
        focused(id)
        scrolled(index,offset)
        restoreFocus=true
    }
    fun focused(id: Int) { if(!restoreFocus && !restoringPages)focusId=id }
    fun scrolled(index: Int,offset: Int) {
        if(restoreFocus || restoringPages)return
        val state=pager.state.value
        val anchor=state.items.getOrNull(index) ?: return
        saved["scrollAnchor"]=anchor.id
        saved["windowFirst"]=state.firstOffset
        saved["windowLast"]=state.pages.last().offset
        saved["offset"]=pager.pageFor(anchor.id)
        scrollIndex=index; scrollOffset=offset
    }
}
