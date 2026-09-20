package org.kazumi.tv

import android.app.Instrumentation
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.media3.common.Player
import androidx.media3.ui.PlayerView
import org.json.JSONObject
import org.kazumi.tv.data.*
import org.kazumi.tv.playback.PlaybackRequest
import org.kazumi.tv.rules.*
import org.kazumi.tv.ui.*
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/** Production road cancellation and resolver verification recovery, without live source requests. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object PlaybackRecoveryRegression {
    fun run(test: Instrumentation) {
        val context = test.targetContext
        // Snapshot actual stores: Dialogs can replace a CompositionLocal ContextWrapper.
        val snapshots = listOf("tv_library", "tv_settings").associateWith { context.getSharedPreferences(it, 0).all.toMap() }
        val sample = java.io.File(context.cacheDir, "playback-recovery-fixture.mp4")
        test.context.assets.open("tracks-fixture.mp4").use { input -> sample.outputStream().use { input.copyTo(it) } }
        val activity = test.startActivitySync(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        fun await(label: String, predicate: () -> Boolean) {
            val end = System.currentTimeMillis() + 15000
            while (System.currentTimeMillis() < end) { if (predicate()) return; Thread.sleep(100) }
            error("Playback recovery timeout: $label")
        }
        fun nodes(): List<AccessibilityNodeInfo> {
            val result = mutableListOf<AccessibilityNodeInfo>()
            fun visit(node: AccessibilityNodeInfo?) { if (node == null) return; result.add(node); for (i in 0 until node.childCount) visit(node.getChild(i)) }
            visit(test.uiAutomation.rootInActiveWindow)
            return result
        }
        fun click(label: String) {
            await(label) { nodes().any { it.text?.toString() == label } }
            var node: AccessibilityNodeInfo? = nodes().first { it.text?.toString() == label }
            while (node != null && !node.isClickable) node = node.parent
            check(node?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true)
            Thread.sleep(300)
        }
        fun player(): Player? {
            fun find(view: View): Player? {
                if (view is PlayerView && view.player != null) return view.player
                if (view is ViewGroup) for (i in 0 until view.childCount) find(view.getChildAt(i))?.let { return it }
                return null
            }
            return find(activity.window.decorView)
        }
        fun ready() = await("ready") {
            var value = false
            test.runOnMainSync { value = player()?.let { it.playbackState == Player.STATE_READY && it.videoSize.width > 0 } == true }
            value
        }
        fun dispose() {
            test.runOnMainSync { activity.setContent { Box(Modifier) } }
            await("player disposed") { var gone = false; test.runOnMainSync { gone = player() == null }; gone }
            test.waitForIdleSync()
        }
        try {
            TvPreferences(context).apply { danmakuEnabled = false; incognito = false; controlsSeconds = 10; speed = 1f; autoNext = false }
            val episode = Episode("第1集", "https://recovery.invalid/road-a/1")
            val roads = listOf(Road("恢复线路A", listOf(episode)), Road("恢复线路B", listOf(Episode("第1集", "https://recovery.invalid/road-b/1"))))
            val catalog = object : SourceCatalog {
                override val rules = listOf(SourceRule(JSONObject().put("name", "恢复回归源").put("baseURL", "https://recovery.invalid")))
                override suspend fun search(rule: SourceRule, keyword: String) = emptyList<SourceMatch>()
                override suspend fun chapters(rule: SourceRule, match: SourceMatch) = roads
            }
            test.runOnMainSync { activity.setContent { KazumiTheme(false) {
                PlaybackSessionScreen(Subject(99000920, "播放恢复样片", "", ""), "恢复回归源", episode, roads,
                    sourceCatalog = catalog, resolveEpisode = { _, _ -> PlaybackRequest(sample.toURI().toString(), emptyMap(), "播放恢复样片") }, onClose = {})
            } } }
            ready()
            test.runOnMainSync { player()!!.apply { pause(); seekTo(6000) } }
            Thread.sleep(500)
            click("线路"); click("返回播放"); ready()
            var before = 0L
            test.runOnMainSync { player()!!.let { check(!it.playWhenReady) { "Road cancellation lost pause" }; before = it.currentPosition; check(before in 5700..6500) { "Road cancellation lost progress" } } }
            Thread.sleep(1200)
            test.runOnMainSync { check(kotlin.math.abs(player()!!.currentPosition - before) < 150) { "Paused road recovery progressed" }; player()!!.play() }
            Thread.sleep(300)
            click("线路"); click("返回播放"); ready()
            test.runOnMainSync { check(player()!!.playWhenReady) { "Road cancellation lost play intent" }; before = player()!!.currentPosition }
            Thread.sleep(1000)
            test.runOnMainSync { check(player()!!.currentPosition > before + 500) { "Playing road recovery stalled" } }
            dispose()

            val challenge = SourceVerificationRequired("https://recovery.invalid/verify", "POST", "keyword=a%2Bb&episode=1")
            val captured = AtomicReference<SourceVerificationRequired?>()
            val attempts = AtomicInteger()
            val recovered = AtomicBoolean()
            test.runOnMainSync { activity.setContent { KazumiTheme(false) {
                ResolvingPlayback("verification-recovery", "验证恢复样片", resolve = {
                    if (attempts.incrementAndGet() == 1) throw challenge
                    PlaybackRequest(sample.toURI().toString(), emptyMap(), "验证恢复样片")
                }, verification = { received, done ->
                    LaunchedEffect(received) { captured.set(received); done() }
                }, onClose = {}) { LaunchedEffect(Unit) { recovered.set(true) } }
            } } }
            click("网页验证")
            await("verification resumes resolver") { recovered.get() }
            check(captured.get() === challenge) { "Verification challenge object was replaced" }
            check(captured.get()?.method == "POST" && captured.get()?.body == challenge.body && captured.get()?.pageUrl == challenge.pageUrl)
            check(attempts.get() == 2) { "Verification retry count is incorrect" }
        } finally {
            val disposal = runCatching { dispose() }
            test.runOnMainSync { activity.finish() }
            test.waitForIdleSync()
            for ((name, values) in snapshots) {
                val prefs = context.getSharedPreferences(name, 0)
                val edit = prefs.edit().clear()
                for ((key, value) in values) when (value) {
                    is String -> edit.putString(key, value)
                    is Boolean -> edit.putBoolean(key, value)
                    is Int -> edit.putInt(key, value)
                    is Long -> edit.putLong(key, value)
                    is Float -> edit.putFloat(key, value)
                    is Set<*> -> { @Suppress("UNCHECKED_CAST") edit.putStringSet(key, value as Set<String>) }
                }
                check(edit.commit()); check(prefs.all == values) { "User preferences not restored" }
            }
            sample.delete()
            disposal.getOrThrow()
        }
    }
}
