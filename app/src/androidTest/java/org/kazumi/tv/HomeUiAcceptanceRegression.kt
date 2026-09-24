package org.kazumi.tv

import android.app.Instrumentation
import android.content.Intent
import android.view.KeyEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import org.kazumi.tv.data.NetworkSettings
import org.kazumi.tv.data.Subject
import org.kazumi.tv.data.TvCatalog
import org.kazumi.tv.data.TvPreferences
import org.kazumi.tv.ui.TvApp
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger

object HomeUiAcceptanceRegression {
    private val sampleIds = (1..12).map { 99024000 + it }
    private fun sample(index: Int, name: String = "首页样本$index") = Subject(sampleIds[index - 1], name, "", "")

    fun run(test: Instrumentation): String {
        val settings = test.targetContext.getSharedPreferences("tv_settings", 0)
        val originalSettings = settings.all.toMap()
        val library = test.targetContext.getSharedPreferences("tv_library", 0)
        val originalLibrary = library.all.toMap()
        fun restore(prefs: android.content.SharedPreferences, values: Map<String, *>) {
            val editor = prefs.edit().clear()
            for ((key, value) in values) when (value) {
                is String -> editor.putString(key, value)
                is Boolean -> editor.putBoolean(key, value)
                is Int -> editor.putInt(key, value)
                is Long -> editor.putLong(key, value)
                is Float -> editor.putFloat(key, value)
                is Set<*> -> {
                    @Suppress("UNCHECKED_CAST")
                    editor.putStringSet(key, value as Set<String>)
                }
            }
            check(editor.commit() && prefs.all == values) { "home test changed user preferences" }
        }
        TvPreferences(test.targetContext).setupComplete = true
        check(library.edit().clear().commit())
        val catalog = MutableCatalog()
        catalog.setRows("", (1..12).map(::sample))
        catalog.setRows("日常", listOf(sample(1, "日常迟到数据")))
        catalog.setRows("原创", listOf(sample(2, "原创旧数据")))
        catalog.setDelay("日常", 1_000)
        catalog.setDelay("原创", 40)
        val activity = try {
            test.startActivitySync(
                Intent(test.targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ) as MainActivity
        } catch (failure: Exception) {
            restore(settings, originalSettings)
            restore(library, originalLibrary)
            throw failure
        }
        val evidence = java.io.File(test.targetContext.getExternalFilesDir(null), "p3-home-ui-${System.currentTimeMillis()}").apply {
            check(mkdirs())
        }
        fun screenshot(name: String) {
            test.uiAutomation.takeScreenshot()?.let { bitmap ->
                java.io.File(evidence, "$name.png").outputStream().use {
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                }
                bitmap.recycle()
            }
        }

        fun nodes(): List<AccessibilityNodeInfo> {
            val result = mutableListOf<AccessibilityNodeInfo>()
            fun visit(node: AccessibilityNodeInfo?) {
                if (node == null) return
                result.add(node)
                for (index in 0 until node.childCount) visit(node.getChild(index))
            }
            if (android.os.Build.VERSION.SDK_INT >= 33) test.uiAutomation.clearCache()
            visit(test.uiAutomation.rootInActiveWindow)
            return result
        }

        fun findOrNull(label: String): AccessibilityNodeInfo? = nodes().firstOrNull {
            it.text?.toString() == label || it.contentDescription?.toString() == label
        }

        fun await(description: String, timeoutMs: Long = 8_000, condition: () -> Boolean) {
            val end = android.os.SystemClock.uptimeMillis() + timeoutMs
            while (android.os.SystemClock.uptimeMillis() < end) {
                if (condition()) return
                Thread.sleep(80)
            }
            error("Timed out: $description")
        }

        fun awaitText(label: String) = await("visible $label") { findOrNull(label) != null }

        fun click(label: String) {
            var node = findOrNull(label) ?: error("Missing clickable label $label")
            while (!node.isClickable) node = node.parent ?: error("No clickable parent for $label")
            check(node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) { "Click failed: $label" }
        }

        fun sendKey(keyCode: Int) = test.sendKeyDownUpSync(keyCode)
        fun openFocusedDetail(label: String) {
            awaitText("热门")
            sendKey(KeyEvent.KEYCODE_DPAD_CENTER)
            awaitText("搜索播放来源")
            awaitText(label)
        }

        try {
            test.runOnMainSync { activity.setContent { TvApp(homeCatalog = catalog) } }
            awaitText("首页样本3")
            awaitText("热门")
            screenshot("01-home")

            // Navigate with the same D-pad path as a TV remote, then verify the focused-card detail path.
            sendKey(KeyEvent.KEYCODE_DPAD_DOWN)
            val focusedIndex = 3
            val focusedLabel = "首页样本$focusedIndex"
            val focusedId = sampleIds[focusedIndex - 1]
            await("home synopsis request for focused subject") { catalog.detailStarted.contains(focusedId) }
            openFocusedDetail(focusedLabel)
            screenshot("02-detail")
            await("home synopsis request cancellation on detail entry") { catalog.detailCancelled.contains(focusedId) }
            sendKey(KeyEvent.KEYCODE_BACK)
            awaitText("热门")
            awaitText("选择节目查看详情")
            Thread.sleep(250)
            screenshot("03-return")

            // Remove the focused subject during detail and return to the nearest surviving card.
            openFocusedDetail(focusedLabel)
            val priorHotLoads = catalog.popularStarted.count { it == "#0" }
            catalog.setRows("", (1..12).filter { it != focusedIndex }.map(::sample))
            NetworkSettings.invalidateCatalog()
            await("catalog refresh while detail is open") { catalog.popularStarted.count { it == "#0" } > priorHotLoads }
            await("refreshed catalog response") { catalog.popularCompleted.count { it == "#0" } > priorHotLoads }
            sendKey(KeyEvent.KEYCODE_BACK)
            val fallbackIndex = focusedIndex.coerceAtMost(11)
            val fallbackIndexInOriginal = if (fallbackIndex >= focusedIndex) fallbackIndex + 1 else fallbackIndex
            val fallbackLabel = "首页样本$fallbackIndexInOriginal"
            awaitText(fallbackLabel)
            openFocusedDetail(fallbackLabel)
            sendKey(KeyEvent.KEYCODE_BACK)

            // A successful empty response must be stable and keep the category navigation usable.
            catalog.setRows("", emptyList())
            NetworkSettings.invalidateCatalog()
            awaitText("暂无节目")
            awaitText("热门")

            // Select a slow category, then immediately select a fast one. The late result must not win.
            sendKey(KeyEvent.KEYCODE_DPAD_RIGHT)
            sendKey(KeyEvent.KEYCODE_DPAD_CENTER)
            await("slow category request start") { catalog.popularStarted.contains("日常#0") }
            sendKey(KeyEvent.KEYCODE_DPAD_RIGHT)
            sendKey(KeyEvent.KEYCODE_DPAD_CENTER)
            awaitText("原创旧数据")
            await("cancelled slow category request") { catalog.popularCancelled.contains("日常#0") }
            Thread.sleep(1_150)
            check(findOrNull("日常迟到数据") == null) { "A stale category result replaced the selected category" }

            // Exercise the user-facing cache clear control and verify the refreshed page.
            catalog.setRows("原创", listOf(sample(8, "原创刷新后数据")))
            val priorOriginalLoads = catalog.popularStarted.count { it == "原创#0" }
            click("设置")
            awaitText("返回浏览")
            for (step in 0 until 36) {
                if (findOrNull("清除目录缓存") != null) break
                sendKey(KeyEvent.KEYCODE_DPAD_DOWN)
                Thread.sleep(40)
            }
            click("清除目录缓存")
            awaitText("目录缓存已清除，当前目录和搜索会重新加载。历史与收藏保留。")
            await("cache-clear catalog fetch") { catalog.popularStarted.count { it == "原创#0" } > priorOriginalLoads }
            await("cache-clear catalog completion") { catalog.popularCompleted.count { it == "原创#0" } > priorOriginalLoads }
            check(catalog.clearCalls.get() == 1) { "Cache clear callback was not called exactly once" }
            sendKey(KeyEvent.KEYCODE_BACK)
            awaitText("原创刷新后数据")
            awaitText("原创")

            return "home_hot_focus=PASS empty_catalog=PASS deleted_card_nearest_focus=PASS rapid_category_stale_result=PASS cache_refresh=PASS home_summary_cancelled_on_exit=PASS"
        } catch (failure: Exception) {
            val folder = java.io.File(test.targetContext.getExternalFilesDir(null), "p3-home-ui-${System.currentTimeMillis()}")
            if (folder.mkdirs()) {
                test.uiAutomation.takeScreenshot()?.let { screenshot ->
                    java.io.File(folder, "failure.png").outputStream().use {
                        screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                    }
                    screenshot.recycle()
                }
                java.io.File(folder, "nodes-private.txt").writeText(nodes().mapNotNull {
                    it.text?.toString() ?: it.contentDescription?.toString()
                }.take(80).joinToString("\n"))
            }
            throw failure
        } finally {
            test.runOnMainSync { activity.finish() }
            restore(settings, originalSettings)
            restore(library, originalLibrary)
        }
    }

    private class MutableCatalog : TvCatalog {
        @Volatile private var pages: Map<String, List<Subject>> = emptyMap()
        @Volatile private var delays: Map<String, Long> = emptyMap()
        val popularStarted = CopyOnWriteArrayList<String>()
        val popularCompleted = CopyOnWriteArrayList<String>()
        val popularCancelled = CopyOnWriteArrayList<String>()
        val detailStarted = CopyOnWriteArrayList<Int>()
        val detailCancelled = CopyOnWriteArrayList<Int>()
        private val detailCallCounts = ConcurrentHashMap<Int, AtomicInteger>()
        val clearCalls = AtomicInteger()

        fun setRows(tag: String, rows: List<Subject>) {
            pages = pages + (tag to rows)
        }

        fun setDelay(tag: String, millis: Long) {
            delays = delays + (tag to millis)
        }

        override suspend fun popular(tag: String, page: Int): List<Subject> {
            val key = "$tag#$page"
            popularStarted.add(key)
            try {
                delays[tag]?.let { delay(it) }
                popularCompleted.add(key)
                return if (page == 0) pages[tag].orEmpty() else emptyList()
            } catch (cancelled: CancellationException) {
                popularCancelled.add(key)
                throw cancelled
            }
        }

        override suspend fun detail(id: Int): Subject {
            detailStarted.add(id)
            val call = detailCallCounts.computeIfAbsent(id) { AtomicInteger() }.incrementAndGet()
            try {
                if (call == 1) delay(30_000)
                return (1..12).map(::sample).firstOrNull { it.id == id } ?: Subject(id, "详情样本$id", "", "")
            } catch (cancelled: CancellationException) {
                detailCancelled.add(id)
                throw cancelled
            }
        }

        override fun clearCache() {
            clearCalls.incrementAndGet()
        }
    }
}
