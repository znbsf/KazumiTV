package org.kazumi.tv

import android.app.Instrumentation
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.*
import org.kazumi.tv.playback.NativePlayer
import org.kazumi.tv.playback.PlaybackRequest
import org.kazumi.tv.playback.MediaResolutionFailure
import org.kazumi.tv.ui.*
import java.util.concurrent.atomic.AtomicInteger

/** Offline device regression: exercises retained AndroidView and cancellation without real sources or credentials. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object S0Regression {
    fun run(test: Instrumentation) {
        val activity = test.startActivitySync(Intent(test.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        lateinit var first: NativePlayer
        lateinit var second: NativePlayer
        val selected = mutableIntStateOf(0)
        val shown = mutableStateOf(true)
        var retained: PlayerView? = null
        fun find(view: View): PlayerView? {
            if (view is PlayerView) return view
            if (view is ViewGroup) for (i in 0 until view.childCount) find(view.getChildAt(i))?.let { return it }
            return null
        }
        fun nodesContaining(text: String): List<android.view.accessibility.AccessibilityNodeInfo> {
            if (android.os.Build.VERSION.SDK_INT >= 33) test.uiAutomation.clearCache()
            val found = mutableListOf<android.view.accessibility.AccessibilityNodeInfo>()
            fun visit(node: android.view.accessibility.AccessibilityNodeInfo?) {
                if (node == null) return
                if (node.text?.contains(text) == true) found.add(node)
                for (i in 0 until node.childCount) visit(node.getChild(i))
            }
            visit(test.uiAutomation.rootInActiveWindow)
            return found
        }
        fun settle() { Thread.sleep(600); test.waitForIdleSync() }
        val releasePending = CompletableDeferred<Unit>()
        val lateProduced = AtomicInteger()
        try {
            test.runOnMainSync {
                first = NativePlayer(activity); second = NativePlayer(activity)
                activity.setContent { if (shown.value) PlaybackVideoSurface(if (selected.intValue == 0) first.player else second.player, false) }
            }
            settle()
            test.runOnMainSync { retained = checkNotNull(find(activity.window.decorView)); check(retained!!.player === first.player); selected.intValue = 1 }
            settle()
            test.runOnMainSync {
                check(find(activity.window.decorView) === retained) { "View unexpectedly recreated: regression must exercise update" }
                check(retained!!.player === second.player) { "Retained view still bound to old engine" }
                shown.value = false
            }
            settle()
            test.runOnMainSync { check(retained!!.player == null) { "Removed view retained player" } }

            val calls = AtomicInteger()
            val delivered = AtomicInteger()
            val open = mutableStateOf(true)
            val selection = mutableStateOf("first")
            test.runOnMainSync { activity.setContent { KazumiTheme(false) {
                if (open.value) ResolvingPlayback(selection.value, "S0 解析回归", resolve = {
                    calls.incrementAndGet()
                    withContext(NonCancellable) {
                        releasePending.await()
                        lateProduced.incrementAndGet()
                        PlaybackRequest("https://example.invalid/unused.mp4", emptyMap(), "fixture")
                    }
                }, onClose = { open.value = false }) { SideEffect { delivered.incrementAndGet() } }
            } } }
            test.waitForIdleSync()
            val callDeadline=SystemClock.elapsedRealtime()+2500
            while(calls.get()==0 && SystemClock.elapsedRealtime()<callDeadline) Thread.sleep(50)
            check(calls.get()==1) { "Pending resolver did not start calls=${calls.get()} delivered=${delivered.get()}" }
            val loadingDeadline=SystemClock.elapsedRealtime()+2500
            while(nodesContaining("正在解析播放地址").isEmpty() && SystemClock.elapsedRealtime()<loadingDeadline) Thread.sleep(50)
            val rootOwned=test.uiAutomation.rootInActiveWindow?.packageName?.toString()==test.targetContext.packageName
            check(nodesContaining("正在解析播放地址").isNotEmpty()) {
                "Pending shell not visible calls=${calls.get()} delivered=${delivered.get()} open=${open.value} rootOwnedByApp=$rootOwned"
            }
            check(!releasePending.isCompleted && lateProduced.get()==0) { "Pending resolver completed before cancellation" }
            test.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
            test.waitForIdleSync()
            check(!open.value) { "Back did not close pending resolver" }
            releasePending.complete(Unit)
            val lateDeadline=SystemClock.elapsedRealtime()+1500
            while(lateProduced.get()==0 && SystemClock.elapsedRealtime()<lateDeadline) Thread.sleep(50)
            check(lateProduced.get()==1) { "Late provider result was not produced" }
            test.waitForIdleSync()
            check(delivered.get() == 0) { "Cancelled result opened media" }

            test.runOnMainSync { activity.setContent { KazumiTheme(false) {
                ResolvingPlayback("retry", "S0 错误回归", resolve = {
                    calls.incrementAndGet(); delay(150)
                    throw MediaResolutionFailure("网页加载", "域名解析失败；网络恢复后请重新解析（-2）")
                }, onClose = {}) { error("failed resolver delivered media") }
            } } }
            settle()
            check(nodesContaining("域名解析失败").isNotEmpty())
            check(nodesContaining("证书").isEmpty())
            val before = calls.get()
            // The explanatory error text also says "重新解析"; target the button label exactly.
            val nodes = nodesContaining("重新解析").filter { it.text?.toString() == "重新解析" }
            check(nodes.isNotEmpty())
            var node = nodes.first()
            while (!node.isClickable && node.parent != null) node = node.parent
            check(node.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK))
            settle()
            check(calls.get() == before + 1) { "Retry did not restart resolver" }

            // A cancelled old selection may still return from an uncooperative provider.
            // It must not replace the new selection's media after a switch.
            val selectionKey = mutableStateOf("old")
            val oldStarted = AtomicInteger()
            val oldDelivered = AtomicInteger()
            val newDelivered = AtomicInteger()
            test.runOnMainSync { activity.setContent { KazumiTheme(false) {
                ResolvingPlayback(selectionKey.value, "S0 切集回归", resolve = {
                    val requested = selectionKey.value
                    if (requested == "old") {
                        oldStarted.incrementAndGet()
                        withContext(NonCancellable) { delay(1400) }
                    }
                    PlaybackRequest("https://example.invalid/$requested.mp4",emptyMap(),requested)
                }, onClose = {}) { request -> SideEffect {
                    if (request.title == "old") oldDelivered.incrementAndGet() else newDelivered.incrementAndGet()
                } }
            } } }
            for (i in 0 until 40) { if (oldStarted.get()>0) break; Thread.sleep(25) }
            check(oldStarted.get()==1) { "Old selection did not start" }
            test.runOnMainSync { selectionKey.value="new" }
            Thread.sleep(1700);test.waitForIdleSync()
            check(oldDelivered.get()==0 && newDelivered.get()>0) { "Cancelled selection replaced current media" }
        } finally {
            releasePending.complete(Unit)
            test.runOnMainSync {
                activity.setContent {}
                first.release(); second.release(); activity.finish()
            }
        }
    }
}
