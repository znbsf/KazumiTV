package org.kazumi.tv

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import android.view.KeyEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import org.kazumi.tv.data.Subject
import org.kazumi.tv.data.TvCatalog
import org.kazumi.tv.data.TvPreferences
import org.kazumi.tv.ui.TvApp
import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/** Pixel/geometry regression against production composables, using only local artwork. */
object ArtworkContinuityRegression {
    fun run(test: Instrumentation): String {
        val context = test.targetContext
        val checkpoint = "p3four-artwork-${System.currentTimeMillis()}"
        UserDataCheckpoint.run(test, "user-data-backup", checkpoint)
        val evidence = File(context.getExternalFilesDir(null), checkpoint).apply { mkdirs() }
        fun png(color: Int): ByteArray {
            val bitmap = Bitmap.createBitmap(320, 480, Bitmap.Config.ARGB_8888).apply { eraseColor(color) }
            return java.io.ByteArrayOutputStream().use { out ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out); bitmap.recycle(); out.toByteArray()
            }
        }
        val red = png(Color.rgb(240, 40, 40))
        val blue = png(Color.rgb(40, 40, 240))
        val served = CountDownLatch(1)
        val release = CountDownLatch(1)
        val server = ServerSocket(0, 4, InetAddress.getByName("127.0.0.1"))
        val worker = thread(isDaemon = true, name = "artwork-fixture") {
            try {
                server.accept().use { socket ->
                    socket.soTimeout = 10000
                    val input = socket.getInputStream().bufferedReader()
                    while (!input.readLine().isNullOrEmpty()) { }
                    served.countDown()
                    check(release.await(15, TimeUnit.SECONDS))
                    socket.getOutputStream().apply {
                        write("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: ${blue.size}\r\nConnection: close\r\n\r\n".toByteArray())
                        write(blue); flush()
                    }
                }
            } catch (_: Exception) { /* Main assertions report missing/failed fixture requests. */ }
        }
        val rows = (1..12).map { index ->
            val file = File(evidence, "cover-$index.png").apply { writeBytes(if(index % 2 == 1) red else blue) }
            Subject(99290000 + index, "连续性样本$index", file.toURI().toString(),
                if(index == 1) "简短介绍。" else "这是一段用于验证简介换行的较长介绍。".repeat(30))
        }
        val catalog = object : TvCatalog {
            override suspend fun popular(tag: String, page: Int) = rows
            override suspend fun detail(id: Int): Subject = rows.single { it.id == id }.let {
                if(id == rows[0].id) it.copy(cover = "http://127.0.0.1:${server.localPort}/large.png") else it
            }
            override fun clearCache() { }
        }
        var activity: MainActivity? = null
        fun nodes(): List<AccessibilityNodeInfo> {
            if(android.os.Build.VERSION.SDK_INT >= 33) test.uiAutomation.clearCache()
            val result = mutableListOf<AccessibilityNodeInfo>()
            fun visit(node: AccessibilityNodeInfo?) {
                if(node == null) return
                result.add(node)
                for(index in 0 until node.childCount) visit(node.getChild(index))
            }
            visit(test.uiAutomation.rootInActiveWindow)
            return result
        }
        fun await(label: String, predicate: () -> Boolean) {
            val end = android.os.SystemClock.uptimeMillis() + 10000
            while(android.os.SystemClock.uptimeMillis() < end) {
                if(predicate()) return
                Thread.sleep(50)
            }
            error("Artwork timeout: $label")
        }
        fun cover(index: Int) = nodes().firstOrNull { it.contentDescription?.toString() == rows[index-1].title }
        fun bounds(node: AccessibilityNodeInfo) = Rect().also { node.getBoundsInScreen(it) }
        fun focusFirst() {
            var node = checkNotNull(cover(1))
            while(!node.isFocusable) node = checkNotNull(node.parent)
            check(node.performAction(AccessibilityNodeInfo.ACTION_FOCUS))
            Thread.sleep(100)
        }
        fun shot(name: String? = null): Bitmap = checkNotNull(test.uiAutomation.takeScreenshot()).also { bitmap ->
            if(name != null) File(evidence, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
        fun background(): Int = shot().let { bitmap -> bitmap.getPixel(6, bitmap.height / 2).also { bitmap.recycle() } }
        fun isRed(color: Int) = Color.red(color) > Color.blue(color) + 25
        fun isBlue(color: Int) = Color.blue(color) > Color.red(color) + 25
        try {
            TvPreferences(context).apply { setupComplete = true; oled = false }
            check(context.getSharedPreferences("tv_library", 0).edit().clear().commit())
            activity = test.startActivitySync(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            test.runOnMainSync { activity.setContent { TvApp(homeCatalog = catalog) } }
            await("cards") { cover(4) != null }
            focusFirst()
            await("red backdrop ready") { isRed(background()) }
            Thread.sleep(700)
            val firstBounds = bounds(checkNotNull(cover(4)))
            shot("01-short-summary").recycle()
            val before = background()
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_RIGHT)
            val colors = mutableListOf<Int>()
            repeat(16) { colors.add(background()); Thread.sleep(45) }
            await("blue backdrop ready") { isBlue(background()) }
            check(bounds(checkNotNull(cover(4))) == firstBounds) { "Poster row moved between short and long summaries" }
            val after = background()
            check(colors.any { Color.red(it) < Color.red(before)-3 && Color.red(it) > Color.red(after)+3 && Color.blue(it) > Color.blue(before)+3 }) {
                "No intermediate crossfade pixels observed"
            }
            File(evidence, "background-pixels.txt").writeText((listOf(before)+colors+after).joinToString("\n") { Integer.toHexString(it) })
            shot("02-long-summary").recycle()

            test.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_LEFT)
            Thread.sleep(120)
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_CENTER)
            await("detail") { nodes().any { it.text?.toString() == "搜索播放来源" } }
            check(served.await(6, TimeUnit.SECONDS)) { "High-resolution detail image was not requested" }
            repeat(4) { index ->
                val rect = bounds(checkNotNull(cover(1)))
                val bitmap = shot("03-detail-pending-$index")
                val pixel = bitmap.getPixel(rect.centerX(), rect.centerY()); bitmap.recycle()
                check(isRed(pixel)) { "Cached cover disappeared while detail image was pending: ${Integer.toHexString(pixel)}" }
                check(nodes().none { it.text?.toString() == "封面加载中…" }) { "Loading label covered the cached image" }
                Thread.sleep(80)
            }
            release.countDown()
            await("detail high-resolution upgrade") {
                val rect = bounds(checkNotNull(cover(1)))
                shot().let { bitmap -> isBlue(bitmap.getPixel(rect.centerX(), rect.centerY())).also { bitmap.recycle() } }
            }
            Thread.sleep(250)
            shot("04-detail-ready").recycle()
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
            await("return card") { cover(4) != null }
            check(bounds(checkNotNull(cover(4))) == firstBounds) { "Returning from detail moved poster row" }
            shot("05-return").recycle()
            return "summary_row_stable=PASS backdrop_intermediate_pixels=PASS cached_detail_pending=PASS detail_upgrade=PASS return_layout=PASS evidence=${evidence.name}"
        } finally {
            release.countDown(); server.close(); worker.join(1000)
            activity?.let { test.runOnMainSync { it.finish() } }
            UserDataCheckpoint.run(test, "user-data-restore", checkpoint)
            UserDataCheckpoint.run(test, "user-data-verify", checkpoint)
        }
    }
}
