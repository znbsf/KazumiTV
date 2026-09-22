package org.kazumi.tv

import android.app.Instrumentation
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import org.kazumi.tv.data.*
import org.kazumi.tv.ui.*
import org.kazumi.tv.rules.*

object RoadSelectionRegression {
    fun run(test: Instrumentation) {
        val original=test.targetContext.getSharedPreferences("tv_library",0).all.toMap()
        val selected=java.util.concurrent.atomic.AtomicReference<Triple<Int,Int,Long?>?>()
        val closed=java.util.concurrent.atomic.AtomicInteger()
        val current=Episode("第10集","https://fixture.invalid/current")
        val roads=listOf(Road("原线路",listOf(current)),Road("对应线路",listOf(Episode("第10集","https://fixture.invalid/matched"))),
            Road("长篇线路",List(201) { Episode("SP","https://fixture.invalid/$it") }),Road("空线路",emptyList()),
            Road("重号线路",listOf(Episode("第10集","https://fixture.invalid/a"),Episode("第10集","https://fixture.invalid/b"))))
        val activity=test.startActivitySync(Intent(test.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        val catalogue=mutableStateOf(roads)
        try {
            fun nodes():List<AccessibilityNodeInfo> {
                val result=mutableListOf<AccessibilityNodeInfo>()
                fun visit(node:AccessibilityNodeInfo?) { if(node==null)return; result.add(node); for(i in 0 until node.childCount)visit(node.getChild(i)) }
                visit(test.uiAutomation.rootInActiveWindow); return result
            }
            fun find(text:String):AccessibilityNodeInfo {
                repeat(40) { nodes().firstOrNull { it.text?.toString()==text }?.let { node -> return node }; Thread.sleep(100) }
                error("Missing $text; visible="+nodes().mapNotNull { it.text?.toString() }.joinToString(" | "))
            }
            fun click(text:String) {
                var node:AccessibilityNodeInfo?=find(text)
                while(node!=null && !node.isClickable)node=node.parent
                check(node?.performAction(AccessibilityNodeInfo.ACTION_CLICK)==true); Thread.sleep(500)
            }

            test.runOnMainSync { activity.setContent { KazumiTheme(false) {
                Box(Modifier.fillMaxSize().background(KazumiColors.background).padding(30.dp)) {
                    RoadSelectionScreen(catalogue.value,0,current,65000L,{ closed.incrementAndGet() }) { road,index,position -> selected.set(Triple(road,index,position)) }
                }
            } } }
            click("对应线路"); check(selected.get()==Triple(1,0,65000L))
            click("长篇线路")
            find("无法确认同一集，请手动选择；所选集将从头播放。")
            fun setNumber(value:String) {
                check(nodes().first { it.isEditable }.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,android.os.Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,value)
                }))
            }
            setNumber("100"); click("定位序号"); click("100. SP")
            check(selected.get()==Triple(2,99,0L))
            click("正序"); setNumber("100"); click("定位序号"); click("100. SP")
            check(selected.get()==Triple(2,99,0L))
            val longShot=test.uiAutomation.takeScreenshot()
            java.io.File(test.targetContext.getExternalFilesDir(null),"road-selection-long.png").outputStream().use { longShot.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) }; longShot.recycle()
            test.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK); find("对应线路"); check(closed.get()==0)
            click("重号线路"); click("2. 第10集"); check(selected.get()==Triple(4,1,0L))
            click("返回线路"); click("空线路"); find("这条线路没有可用集数，请选择其他线路。")
            click("返回播放"); check(closed.get()==1)
            val screenshot=test.uiAutomation.takeScreenshot()
            java.io.File(test.targetContext.getExternalFilesDir(null),"road-selection-fixture.png").outputStream().use {
                screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)
            }; screenshot.recycle()
            // The old unmatched index must not address an empty or replaced catalogue.
            // This checks the production composable reload boundary, not OS process death.
            test.runOnMainSync { catalogue.value=emptyList() }
            find("集表暂未恢复，可返回播放后重试。")
            check(nodes().none { it.text?.toString()=="无法确认同一集，请手动选择；所选集将从头播放。" })
            test.runOnMainSync { catalogue.value=listOf(roads[1],roads[0]) }
            click("✓ 对应线路"); check(selected.get()==Triple(0,0,65000L))
            check(original==test.targetContext.getSharedPreferences("tv_library",0).all)
        } finally { test.runOnMainSync { activity.finish() } }
    }
}
