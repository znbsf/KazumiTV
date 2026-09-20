package org.kazumi.tv

import android.app.Instrumentation
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.saveable.LocalSaveableStateRegistry
import androidx.compose.runtime.saveable.SaveableStateRegistry
import androidx.compose.ui.Modifier
import androidx.media3.common.Player
import androidx.media3.ui.PlayerView
import org.json.JSONObject
import org.kazumi.tv.data.*
import org.kazumi.tv.playback.PlaybackRequest
import org.kazumi.tv.rules.*
import org.kazumi.tv.ui.*
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/** Production composables with a real saveable registry, disposed and restored like StateRestorationTester.
 * This is not an OS process-death test: the parent runs that separately on the app's normal entry point.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object PlaybackRestoreRegression {
    fun run(test: Instrumentation): String {
        val context = test.targetContext
        val snapshots = listOf("tv_library", "tv_settings").associateWith { context.getSharedPreferences(it, 0).all.toMap() }
        val sample = java.io.File(context.cacheDir, "playback-restore-fixture.mp4")
        test.context.assets.open("tracks-fixture.mp4").use { input -> sample.outputStream().use { input.copyTo(it) } }
        val activity = test.startActivitySync(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        val subject = Subject(99000921, "恢复样片", "", "")
        val epA = Episode("第1集", "https://restore.invalid/a/1")
        val epB = Episode("第1集", "https://restore.invalid/b/1")
        val epB2 = Episode("第2集", "https://restore.invalid/b/2")
        val resolved = AtomicReference("")
        val resolvedPage = AtomicReference("")
        val resolves = AtomicInteger()
        val chapters = mutableListOf<Pair<String, String>>()
        fun catalog(names: List<String>) = object : SourceCatalog {
            override val rules = names.map { SourceRule(JSONObject().put("name", it).put("baseURL", "https://restore.invalid")) }
            override suspend fun search(rule: SourceRule, keyword: String) = listOf(SourceMatch("恢复样片", "https://restore.invalid/${if(rule.name=="恢复源A")"a" else "b"}/show"))
            override suspend fun chapters(rule: SourceRule, match: SourceMatch): List<Road> {
                synchronized(chapters) { chapters.add(rule.name to match.url) }
                return listOf(Road("恢复线路", if(rule.name=="恢复源A")listOf(epA) else listOf(epB,epB2)))
            }
        }
        fun await(label: String, predicate: () -> Boolean) {
            val deadline = System.currentTimeMillis() + 15000
            while (System.currentTimeMillis() < deadline) { if(predicate())return;Thread.sleep(100) }
            error("Restore regression timeout: $label")
        }
        fun nodes(): List<AccessibilityNodeInfo> {
            val result = mutableListOf<AccessibilityNodeInfo>()
            fun walk(n: AccessibilityNodeInfo?) { if(n==null)return;result.add(n);for(i in 0 until n.childCount)walk(n.getChild(i)) }
            walk(test.uiAutomation.rootInActiveWindow);return result
        }
        fun click(label: String) {
            fun targets()=nodes().filter { it.text?.toString()==label && !it.isEditable }.mapNotNull { original ->
                var candidate:AccessibilityNodeInfo?=original
                while(candidate!=null&&!candidate.isClickable)candidate=candidate.parent
                candidate?.takeUnless { it.isEditable }
            }
            await("clickable action $label") { targets().any { it.performAction(AccessibilityNodeInfo.ACTION_CLICK) } }
            Thread.sleep(300)
        }
        fun player(): Player? {
            fun walk(v: View): Player? {
                if(v is PlayerView&&v.player!=null)return v.player
                if(v is ViewGroup)for(i in 0 until v.childCount)walk(v.getChildAt(i))?.let { return it }
                return null
            }
            return walk(activity.window.decorView)
        }
        fun ready(rule: String) = await("player ready") {
            var ok=false;test.runOnMainSync { ok=resolved.get()==rule&&player()?.let { it.playbackState==Player.STATE_READY&&it.videoSize.width>0 }==true };ok
        }
        fun dispose() {
            test.runOnMainSync { activity.setContent { androidx.tv.material3.Text("恢复测试已卸载") } }
            await("composition disposal") { nodes().any { it.text?.toString()=="恢复测试已卸载" } }
            await("player disposal") { var gone=false;test.runOnMainSync { gone=player()==null };gone }
            test.waitForIdleSync()
        }
        fun mount(registry: SaveableStateRegistry, sources: SourceCatalog, sourcePage: Boolean) {
            test.runOnMainSync { activity.setContent {
                CompositionLocalProvider(LocalSaveableStateRegistry provides registry) { KazumiTheme(false) {
                    if(sourcePage) SourceScreen(subject,catalog=sources,resolveEpisode={ rule,ep ->
                        resolves.incrementAndGet();resolved.set(rule);resolvedPage.set(ep.pageUrl)
                        PlaybackRequest(sample.toURI().toString(),emptyMap(),"恢复样片 · ${ep.title}")
                    })
                    else PlaybackSessionScreen(subject,"恢复源A",epA,listOf(Road("恢复线路",listOf(epA))),
                        initialOrigin=PlaybackOrigin("恢复源A","恢复样片","https://restore.invalid/a/show","恢复线路"),sourceCatalog=sources,
                        resolveEpisode={ rule,_ -> resolves.incrementAndGet();resolved.set(rule);PlaybackRequest(sample.toURI().toString(),emptyMap(),"恢复样片") },onClose={})
                } }
            } }
        }
        fun save(registry: SaveableStateRegistry): Map<String,List<Any?>> {
            var result:Map<String,List<Any?>> = emptyMap();test.runOnMainSync { result=registry.performSave() };return result
        }
        val allSources=catalog(listOf("恢复源A","恢复源B"))
        try {
            TvPreferences(context).apply { danmakuEnabled=false;incognito=false;resumePlayback=true;controlsSeconds=10;autoNext=false;speed=1f }
            // Save a switched-source session, then recreate from the ORIGINAL entry arguments.
            var registry=SaveableStateRegistry(null) { true }
            mount(registry,allSources,false);ready("恢复源A")
            test.runOnMainSync { player()!!.apply { pause();seekTo(6000) } };Thread.sleep(500)
            click("换源");click("恢复源B");click("恢复样片");click("续播 第1集 · 保留进度");ready("恢复源B")
            test.runOnMainSync { player()!!.pause() };Thread.sleep(300)
            val state=save(registry);dispose()
            val savedProgress=LibraryStore(context).history().first { it.key=="恢复源B|${epB.pageUrl}" }.position
            check(savedProgress>=5700)
            synchronized(chapters) { chapters.clear() }
            resolved.set("")
            registry=SaveableStateRegistry(state) { true };mount(registry,allSources,false);ready("恢复源B")
            var pausedAt=0L
            test.runOnMainSync { player()!!.let { check(!it.playWhenReady);pausedAt=it.currentPosition;check(kotlin.math.abs(pausedAt-savedProgress)<300) } }
            Thread.sleep(1000)
            test.runOnMainSync { check(kotlin.math.abs(player()!!.currentPosition-pausedAt)<150) }
            await("restored switched origin chapters") { synchronized(chapters) { chapters.any { it.first=="恢复源B"&&it.second.endsWith("/b/show") } } }
            check(synchronized(chapters) { chapters.none { it.first=="恢复源B"&&it.second.endsWith("/a/show") } })
            dispose()

            // A removed saved source must never resolve using the first remaining source.
            val count=resolves.get()
            mount(SaveableStateRegistry(state) { true },catalog(listOf("恢复源A")),false)
            await("missing source error") { nodes().any { it.text?.toString()?.contains("解析失败")==true } }
            check(resolves.get()==count);test.runOnMainSync { check(player()==null) };dispose()

            // SourcePage itself restores selection and reloads chapters; missing source returns to results.
            registry=SaveableStateRegistry(null) { true };mount(registry,allSources,true)
            click("恢复源B");click("恢复样片")
            await("source chapters") { nodes().any { it.text?.toString()=="返回匹配结果" } }
            val sourceState=save(registry);dispose()
            synchronized(chapters) { chapters.clear() }
            mount(SaveableStateRegistry(sourceState) { true },allSources,true)
            await("restored source chapters") { synchronized(chapters) { chapters.any { it.first=="恢复源B"&&it.second.endsWith("/b/show") } } }
            check(nodes().any { it.text?.toString()=="返回匹配结果" });dispose()
            mount(SaveableStateRegistry(sourceState) { true },catalog(listOf("恢复源A")),true)
            await("missing source cleared") { nodes().any { it.text?.toString()=="选择播放来源" } }
            check(nodes().none { it.text?.toString()=="返回匹配结果" });dispose()

            // Real SourceScreen Dialog: A -> B -> episode 2 -> hardware Back returns B episode 2.
            mount(SaveableStateRegistry(null) { true },allSources,true)
            click("恢复样片")
            await("first episode button") { nodes().any { it.text?.toString()?.let { t->t.startsWith("1.")&&t.contains("第1集") }==true } }
            click(nodes().first { it.text?.toString()?.let { t->t.startsWith("1.")&&t.contains("第1集") }==true }.text.toString())
            await("A player dialog") { resolvedPage.get()==epA.pageUrl&&nodes().any { it.text?.toString()=="换源" } }
            click("换源");click("恢复源B");click("恢复样片");click("续播 第1集 · 保留进度")
            await("B next episode control") { resolvedPage.get()==epB.pageUrl&&nodes().any { it.text?.toString()=="下一集" } }
            click("下一集")
            await("B episode 2 rendered progress") { LibraryStore(context).history().any { it.key=="恢复源B|${epB2.pageUrl}"&&it.position>=1000 } }
            test.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_MEDIA_PAUSE)
            await("B episode 2 pause") { nodes().any { it.text?.toString()=="▷ 播放" } }
            test.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
            await("return to current source episode") { nodes().any { it.text?.toString()?.let { t->t.startsWith("2.")&&t.contains("当前")&&t.contains("第2集") }==true } }
            check(nodes().any { it.text?.toString()=="返回匹配结果" })
            // A only has one episode, so the highlighted second episode also proves B's roads returned.
            dispose()

            // An incognito restore must stay paused and must not write normal viewing progress.
            TvPreferences(context).incognito=true
            val beforePrivate=context.getSharedPreferences("tv_library",0).all.toMap()
            resolved.set("");mount(SaveableStateRegistry(state) { true },allSources,false);ready("恢复源B")
            test.runOnMainSync { check(!player()!!.playWhenReady);player()!!.play() }
            Thread.sleep(1200);dispose()
            check(context.getSharedPreferences("tv_library",0).all==beforePrivate) { "Incognito restoration changed history" }
            return "session_restore=PASS switched_origin=PASS paused_progress=PASS missing_source=PASS source_selection=PASS source_switch_episode_back_context=PASS incognito=PASS"
        } catch(failure:Exception) {
            test.sendStatus(0,android.os.Bundle().apply { putString("stream","PlaybackRestoreRegression failed: ${failure.javaClass.simpleName}: ${failure.message?.take(160)}\n") })
            runCatching {
                val screenshot=test.uiAutomation.takeScreenshot()
                java.io.File(context.getExternalFilesDir(null),"playback-restore-failure.png").outputStream().use { screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) }
                screenshot.recycle()
            }
            throw failure
        } finally {
            val disposal=runCatching { dispose() }
            test.runOnMainSync { activity.finish() };test.waitForIdleSync()
            for((name,values) in snapshots) {
                val prefs=context.getSharedPreferences(name,0);val edit=prefs.edit().clear()
                for((key,value) in values)when(value) {
                    is String->edit.putString(key,value);is Boolean->edit.putBoolean(key,value);is Int->edit.putInt(key,value)
                    is Long->edit.putLong(key,value);is Float->edit.putFloat(key,value)
                    is Set<*>->{@Suppress("UNCHECKED_CAST") edit.putStringSet(key,value as Set<String>)}
                }
                check(edit.commit());check(prefs.all==values)
            }
            sample.delete();disposal.getOrThrow()
        }
    }
}
