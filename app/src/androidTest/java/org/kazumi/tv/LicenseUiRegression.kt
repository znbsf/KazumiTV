package org.kazumi.tv

import android.app.Instrumentation
import android.content.Intent
import android.view.KeyEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.kazumi.tv.ui.KazumiTheme
import org.kazumi.tv.ui.LicensesScreen

/** Reads packaged local documents only; never follows the displayed repository links. */
object LicenseUiRegression {
    fun run(test:Instrumentation) {
        val context=test.targetContext
        val beforeSettings=context.getSharedPreferences("tv_settings",0).all.toMap()
        val beforeLibrary=context.getSharedPreferences("tv_library",0).all.toMap()
        val expected=mapOf("GPL-3.0.txt" to "GNU GENERAL PUBLIC LICENSE","Apache-2.0.txt" to "Apache License",
            "jsoup-MIT.txt" to "Jonathan Hedley","MPL-2.0.txt" to "Mozilla Public License",
            "OkHttp-publicsuffix-NOTICE.txt" to "public_suffix_list.dat","THIRD_PARTY_NOTICES.md" to "Predidit/Kazumi")
        for((name,marker) in expected) {
            val text=context.assets.open("licenses/$name").bufferedReader().use { it.readText() }
            check(text.length>100&&text.contains(marker)) { "Packaged license missing/incomplete: $name" }
        }
        val activity=test.startActivitySync(Intent(context,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        fun nodes():List<AccessibilityNodeInfo> { val out=mutableListOf<AccessibilityNodeInfo>();fun walk(n:AccessibilityNodeInfo?) { if(n==null)return;out+=n;for(i in 0 until n.childCount)walk(n.getChild(i)) };walk(test.uiAutomation.rootInActiveWindow);return out }
        fun texts()=nodes().filter { it.isVisibleToUser }.mapNotNull { it.text?.toString() }
        fun await(label:String,predicate:()->Boolean) { repeat(100) { if(predicate())return;Thread.sleep(100) };error("timeout $label") }
        fun click(label:String) {
            await(label) { nodes().any { it.text?.toString()==label } }
            var node=nodes().first { it.text?.toString()==label }
            node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SHOW_ON_SCREEN.id)
            while(!node.isClickable&&node.parent!=null)node=node.parent
            check(node.performAction(AccessibilityNodeInfo.ACTION_CLICK));test.waitForIdleSync()
        }
        fun shot(name:String) { test.uiAutomation.takeScreenshot()?.let { b->java.io.File(context.getExternalFilesDir(null),name).outputStream().use { b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) };b.recycle() } }
        try {
            test.runOnMainSync { activity.setContent { KazumiTheme(false) { LicensesScreen(Modifier.fillMaxSize().padding(28.dp)) } } }
            await("license directory") { texts().any { it=="开源许可与对应源码" } }
            shot("licenses-directory.png")
            click("GNU GPL 3.0")
            await("local GPL body") { texts().any { it.contains("GNU GENERAL PUBLIC LICENSE") } }
            Thread.sleep(300)
            val initial=texts().filter { it.length>80 }.toSet()
            repeat(12) { test.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_DOWN);Thread.sleep(120) }
            await("D-pad scrolls actual license body") { texts().filter { it.length>80 }.toSet()!=initial }
            shot("licenses-gpl-scrolled.png")
            test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
            await("back to license directory") { texts().any { it=="开源许可与对应源码" }&&texts().none { it=="返回许可目录" } }
            shot("licenses-directory-return.png")
        } catch(failure:Throwable) { runCatching { shot("licenses-failure.png") };throw failure }
        finally {
            test.runOnMainSync { activity.setContent { };activity.finish() };test.waitForIdleSync()
            check(beforeSettings==context.getSharedPreferences("tv_settings",0).all)
            check(beforeLibrary==context.getSharedPreferences("tv_library",0).all)
        }
    }
}
