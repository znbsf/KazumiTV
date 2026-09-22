package org.kazumi.tv

import android.app.Instrumentation
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.view.KeyEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.lifecycle.SavedStateHandle
import org.kazumi.tv.data.*
import org.kazumi.tv.ui.*

object S4SearchRegression {
    fun run(test: Instrumentation, defaultModel: Boolean = false) {
        val context=object:ContextWrapper(test.targetContext) {
            override fun getSharedPreferences(name: String, mode: Int)=baseContext.getSharedPreferences("s4_search_fixture",Context.MODE_PRIVATE)
        }
        val raw=context.getSharedPreferences("",0)
        raw.edit().clear().commit()
        try {
            val history=SearchHistoryStore(context)
            repeat(25) { history.add("term$it") }; history.add("term20")
            check(SearchHistoryStore(context).read().size==20 && history.read().first()=="term20")
            history.clear(); check(history.read().isEmpty())
        } finally { raw.edit().clear().commit() }
        val activity=test.startActivitySync(Intent(test.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        lateinit var model: SearchViewModel
        lateinit var saved: SavedStateHandle
        fun nodes(): List<AccessibilityNodeInfo> {
            val result=mutableListOf<AccessibilityNodeInfo>()
            fun visit(node: AccessibilityNodeInfo?) { if(node==null)return; result.add(node); for(i in 0 until node.childCount)visit(node.getChild(i)) }
            visit(test.uiAutomation.rootInActiveWindow); return result
        }
        fun find(text: String): AccessibilityNodeInfo {
            repeat(50) { nodes().firstOrNull { it.text?.toString()==text }?.let { node -> return node }; Thread.sleep(100) }
            error("Missing $text")
        }
        fun click(text: String) {
            var node: AccessibilityNodeInfo?=find(text)
            while(node!=null && !node.isClickable)node=node.parent
            check(node?.performAction(AccessibilityNodeInfo.ACTION_CLICK)==true); Thread.sleep(700)
        }
        fun awaitRestore(value: SearchViewModel) {
            repeat(50) {
                var done=false
                test.runOnMainSync { done=!value.restoringPages }
                if(done)return
                Thread.sleep(100)
            }
            error("Search window restoration did not settle")
        }
        try {
            test.runOnMainSync {
                saved=SavedStateHandle(mapOf("query" to "fixture","text" to "fixture"))
                model=SearchViewModel(saved) { _,offset,_ -> List(48) { Subject(987000+offset+it,"Search item ${offset+it}","","") } }
                activity.setContent { TvApp(if(defaultModel) null else model) }
            }
            click("搜索")
            find("搜索番剧")
            if(defaultModel) { find("排序：相关"); return }
            click("Search item 0")
            find("返回搜索"); find("搜索播放来源")
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
            find("搜索番剧"); find("Search item 0")
            Thread.sleep(700)
            check(model.pager.state.value.items.first().title=="Search item 0")
            check(!model.restoreFocus && model.focusId==987000)
            val image=test.uiAutomation.takeScreenshot()
            java.io.File(test.targetContext.getExternalFilesDir(null),"search-return.png").outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) }
            image.recycle()
            repeat(7) { test.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_DOWN); Thread.sleep(180) }
            Thread.sleep(600)
            check(model.pager.state.value.pages.size>=2) { "Remote browsing did not auto-load next page" }
            lateinit var restored: SearchViewModel
            val requestedOffsets=mutableListOf<Int>()
            test.runOnMainSync {
                check(saved.get<String>("query")=="fixture")
                check(model.focusId!=987000) { "Remote browsing did not persist focused result" }
                model.scrolled(12,37)
                check(saved.get<Int>("scrollAnchor")==model.pager.state.value.items[12].id)
                check(saved.get<Int>("windowFirst")==model.pager.state.value.firstOffset)
                check(saved.get<Int>("windowLast")==model.pager.state.value.pages.last().offset)
                model.selected(987000,12,37)
                restored=SearchViewModel(SavedStateHandle(saved.keys().associateWith { saved.get<Any?>(it) })) { _,offset,_ ->
                    requestedOffsets.add(offset)
                    List(48) { Subject(987000+offset+it,"restored","","") }
                }
                check(restored.text=="fixture" && restored.focusId==987000 && restored.restoreFocus)
                check(restored.scrollIndex==12 && restored.scrollOffset==37)
            }
            awaitRestore(restored)
            test.runOnMainSync {
                check(!restored.restoringPages)
                val first=saved.get<Int>("windowFirst")!!
                val last=saved.get<Int>("windowLast")!!
                check(requestedOffsets==(first..last step 20).toList())
                check(restored.pager.state.value.pages.size<=5)
                check(restored.pager.state.value.items[restored.scrollIndex].id==restored.scrollAnchorId)
                restored.submit("new fixture","score")
                check(restored.scrollIndex==0 && restored.scrollOffset==0 && restored.focusId==null)
            }
            // A failed later page must remain retryable without losing the saved window.
            var failOnce=true
            test.runOnMainSync {
                restored=SearchViewModel(SavedStateHandle(saved.keys().associateWith { saved.get<Any?>(it) })) { _,offset,_ ->
                    if(offset==saved.get<Int>("windowFirst")!!+20 && failOnce) { failOnce=false; error("offline") }
                    List(20) { Subject(987000+offset+it,"retried","","") }
                }
            }
            awaitRestore(restored)
            test.runOnMainSync {
                check(restored.pager.state.value.failedOffset!=null && restored.restoreFocus)
                restored.retry()
            }
            awaitRestore(restored)
            test.runOnMainSync {
                check(restored.pager.state.value.failedOffset==null)
                check(restored.pager.state.value.pages.last().offset==saved.get<Int>("windowLast"))
                restored=SearchViewModel(SavedStateHandle(saved.keys().associateWith { saved.get<Any?>(it) })) { _,_,_ -> emptyList() }
                activity.setContent { KazumiTheme(false) { SearchScreen(restored) {} } }
            }
            awaitRestore(restored)
            find("没有找到匹配番剧")
            test.waitForIdleSync()
            test.runOnMainSync { check(!restored.restoreFocus && restored.focusId==null) }
        } finally { test.runOnMainSync { activity.finish() } }
    }
}
