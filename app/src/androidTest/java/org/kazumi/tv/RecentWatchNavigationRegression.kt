package org.kazumi.tv

import android.app.Instrumentation
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.view.KeyEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import org.json.JSONObject
import org.kazumi.tv.data.*
import org.kazumi.tv.rules.*
import org.kazumi.tv.ui.*
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/** Production navigation with isolated library preferences; no media or user-history writes. */
object RecentWatchNavigationRegression {
    fun run(test:Instrumentation):String {
        val context=object:ContextWrapper(test.targetContext) {
            override fun getSharedPreferences(name:String,mode:Int)=baseContext.getSharedPreferences("recent_navigation_fixture_$name",Context.MODE_PRIVATE)
        }
        val libraryPrefs=context.getSharedPreferences("tv_library",0)
        val settingsPrefs=context.getSharedPreferences("tv_settings",0)
        libraryPrefs.edit().clear().commit(); settingsPrefs.edit().clear().commit()
        val original=test.targetContext.getSharedPreferences("tv_library",0).all.toMap()
        val subject=Subject(9900922,"最近观看样本","","导航验收")
        val ep=Episode("第12集","https://recent.invalid/play/12")
        val origin=PlaybackOrigin("原来源","最近观看样本","https://recent.invalid/show","原线路")
        val previous=HistoryEntry("原来源|${ep.pageUrl}",subject,"最近观看样本 · 第12集",65000,140000,origin)
        val store=LibraryStore(context)
        val searches=AtomicInteger(); val chapters=AtomicInteger(); val resolves=AtomicInteger()
        val resumed=AtomicReference<HistoryEntry?>()
        fun catalog(name:String)=object:SourceCatalog {
            override val rules=listOf(SourceRule(JSONObject().put("name",name).put("baseURL","https://recent.invalid")))
            override suspend fun search(rule:SourceRule,keyword:String):List<SourceMatch> {
                searches.incrementAndGet(); return listOf(SourceMatch(subject.title,origin.sourceUrl))
            }
            override suspend fun chapters(rule:SourceRule,match:SourceMatch):List<Road> {
                check(rule.name=="原来源" && match.url==origin.sourceUrl)
                chapters.incrementAndGet()
                return listOf(Road("原线路",listOf(Episode("第11集","https://recent.invalid/play/11"),ep)))
            }
        }
        val sources=catalog("原来源")
        var screen by mutableStateOf("recent")
        var chosen by mutableStateOf(subject)
        val activity=test.startActivitySync(Intent(test.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        fun nodes():List<AccessibilityNodeInfo> {
            val result=mutableListOf<AccessibilityNodeInfo>()
            fun visit(node:AccessibilityNodeInfo?) { if(node==null)return; result.add(node); for(i in 0 until node.childCount)visit(node.getChild(i)) }
            visit(test.uiAutomation.rootInActiveWindow); return result
        }
        fun await(label:String,predicate:()->Boolean) {
            repeat(70) { if(predicate())return; Thread.sleep(100) }
            error("Recent navigation missing $label")
        }
        fun find(label:String) { await(label) { nodes().any { it.text?.toString()==label } } }
        fun click(label:String) {
            find(label)
            var node=nodes().first { it.text?.toString()==label }
            while(!node.isClickable)node=node.parent ?: error("No clickable $label")
            check(node.performAction(AccessibilityNodeInfo.ACTION_CLICK)); Thread.sleep(300)
        }
        try {
            store.save(previous.copy(key="原来源|https://recent.invalid/play/11",episode="第11集"))
            store.save(previous)
            test.runOnMainSync { activity.setContent {
                CompositionLocalProvider(LocalContext provides context) { KazumiTheme(false) {
                    Box(Modifier.fillMaxSize().padding(24.dp)) {
                        when(screen) {
                            "recent" -> RecentWatchLinks(rememberWatchHistory()) { chosen=it;screen="detail" }
                            "detail" -> DetailScreen(chosen,sourceCatalog=sources,onResume={ resumed.set(it) },loadDetail={ chosen },
                                resolveEpisode={ _,_ -> resolves.incrementAndGet();error("Browsing must not resolve media") })
                            "history" -> LibraryScreen("历史",{ resumed.set(it) }) { chosen=it;screen="detail" }
                            "missing" -> SourceScreen(subject,catalog=catalog("其他来源"),initialHistory=previous,
                                resolveEpisode={ _,_ -> resolves.incrementAndGet();error("Browsing must not resolve media") })
                        }
                    }
                } }
            } }
            click("最近观看样本 · 第12集")
            find("继续 第12集")
            check(resumed.get()==null && resolves.get()==0)
            click("继续 第12集")
            check(resumed.get()?.key==previous.key && resumed.get()?.position==65000L)
            click("查看原来源选集")
            find("线路与选集")
            await("selected last episode") { nodes().any { it.text?.toString()?.let { t->t.contains("第12集")&&t.contains("当前") }==true } }
            check(chapters.get()==1 && searches.get()==0 && resolves.get()==0)
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);find("选择播放来源")
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);find("继续 第12集")
            test.runOnMainSync { screen="history" }
            click("番剧详情");find("继续 第12集")
            // A newer cached watch must not hide the last online directory or change
            // which history entry the independent Continue action opens.
            val offline=previous.copy(key="offline|recent-navigation",episode="第20集",position=85000,
                origin=null,kind=HistoryKind.OFFLINE)
            store.save(offline)
            find("继续 第20集")
            click("继续 第20集")
            check(resumed.get()?.key==offline.key && resumed.get()?.kind==HistoryKind.OFFLINE)
            val chapterCount=chapters.get()
            val searchCount=searches.get()
            click("查看原来源选集")
            find("线路与选集")
            await("online directory retained after cached watch") {
                nodes().any { it.text?.toString()?.let { t->t.contains("第12集")&&t.contains("当前") }==true }
            }
            check(chapters.get()==chapterCount+1 && searches.get()==searchCount && resolves.get()==0)
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);find("选择播放来源")
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);find("继续 第20集")
            await("return focus to online directory action") {
                var node=nodes().firstOrNull { it.text?.toString()=="查看原来源选集" }
                var focused=false
                while(node!=null) { if(node.isFocused) { focused=true;break };node=node.parent }
                focused
            }
            // No remount is needed: a new progress write must update the detail shortcut.
            store.save(previous.copy(key="原来源|https://recent.invalid/play/13",episode="第13集",position=75000))
            find("继续 第13集")
            test.runOnMainSync { screen="recent" }
            find("最近观看样本 · 第13集")
            check(nodes().none { it.text?.toString()=="最近观看样本 · 第12集" })
            TvPreferences(context).incognito=true
            store.save(previous.copy(episode="第99集"))
            check(store.history().none { it.episode=="第99集" })
            test.runOnMainSync { screen="missing" }
            find("选择播放来源")
            find("原来源 原来源 已停用或移除，请重新选择来源")
            check(resolves.get()==0)
            check(original==test.targetContext.getSharedPreferences("tv_library",0).all)
            return "recent_watch=PASS detail_resume=PASS original_episode_browser=PASS no_autoplay=PASS history_detail=PASS mixed_online_offline_directory=PASS live_refresh=PASS missing_source=PASS incognito=PASS"
        } finally {
            test.runOnMainSync { activity.finish() }; test.waitForIdleSync()
            libraryPrefs.edit().clear().commit(); settingsPrefs.edit().clear().commit()
        }
    }
}
