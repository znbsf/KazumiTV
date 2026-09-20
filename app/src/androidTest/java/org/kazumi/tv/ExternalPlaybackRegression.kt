package org.kazumi.tv

import android.app.Instrumentation
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import android.view.KeyEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalContext
import org.kazumi.tv.data.*
import org.kazumi.tv.playback.*
import org.kazumi.tv.ui.*

object ExternalPlaybackRegression {
    fun run(test:Instrumentation) {
        val original=test.targetContext
        val beforeSettings=original.getSharedPreferences("tv_settings",0).all.toMap()
        val beforeLibrary=original.getSharedPreferences("tv_library",0).all.toMap()
        val context=object:ContextWrapper(original) { override fun getSharedPreferences(name:String,mode:Int)=baseContext.getSharedPreferences("external_fixture_$name",mode) }
        context.getSharedPreferences("tv_settings",0).edit().clear().commit()
        TvPreferences(context).incognito=true; TvPreferences(context).danmakuEnabled=false
        val bytes=test.context.assets.open("tracks-fixture.mp4").use { it.readBytes() }
        val server=AdaptiveDownloadRegression.Server(mapOf("/external.mp4" to bytes),0)
        val request=PlaybackRequest("http://127.0.0.1:${server.port}/external.mp4",mapOf("X-Fixture" to "external-test"),"KazumiTV external fixture",mimeType="video/mp4")
        val activity=test.startActivitySync(Intent(original,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        fun nodes():List<AccessibilityNodeInfo> {
            val result=mutableListOf<AccessibilityNodeInfo>()
            fun visit(node:AccessibilityNodeInfo?) { if(node==null)return; result+=node; for(i in 0 until node.childCount)visit(node.getChild(i)) }
            visit(test.uiAutomation.rootInActiveWindow); return result
        }
        fun await(label:String,predicate:()->Boolean) { repeat(150) { if(predicate())return; Thread.sleep(100) }; error("timeout $label") }
        fun click(label:String) {
            await(label) { nodes().any { it.text?.toString()==label } }
            var node=nodes().first { it.text?.toString()==label }
            node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SHOW_ON_SCREEN.id)
            while(!node.isClickable && node.parent!=null)node=node.parent
            check(node.performAction(AccessibilityNodeInfo.ACTION_CLICK)); test.waitForIdleSync()
        }
        fun screenshot(name:String) { test.uiAutomation.takeScreenshot()?.let { bitmap->java.io.File(original.getExternalFilesDir(null),name).outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) }; bitmap.recycle() } }
        try {
            val targets=ExternalPlayback.targets(context,request)
            val mx=targets.first { it.component.packageName=="com.mxtech.videoplayer.pro" }
            val intent=ExternalPlayback.intent(request,mx,3000)
            check(intent.getIntExtra("position",-1)==3000)
            check(intent.getStringArrayExtra("headers")!!.contentEquals(arrayOf("X-Fixture","external-test")))
            check(intent.component==mx.component && intent.flags==0)
            val generic=mx.copy(mx=false)
            check(runCatching { ExternalPlayback.intent(request,generic,0) }.isFailure)
            check(ExternalPlayback.intent(request.copy(headers=emptyMap()),generic,0).getStringArrayExtra("headers")==null)
            check(runCatching { ExternalPlayback.validate(request.copy(offlineId="fixture")) }.isFailure)
            check(runCatching { ExternalPlayback.validate(request.copy(url="file:///secret")) }.isFailure)
            check(runCatching { ExternalPlayback.validate(request.copy(headers=mapOf("X" to "x\r\ny"))) }.isFailure)
            val result=Intent("com.mxtech.intent.result.VIEW",Uri.parse(request.url)).putExtra("position",4500)
            check(ExternalPlayback.returnedPosition(request,true,android.app.Activity.RESULT_OK,result)==4500L)
            check(ExternalPlayback.returnedPosition(request,true,android.app.Activity.RESULT_CANCELED,result)==null)
            check(ExternalPlayback.returnedPosition(request.copy(url=request.url+"other"),true,android.app.Activity.RESULT_OK,result)==null)
            test.runOnMainSync { activity.setContent { CompositionLocalProvider(LocalContext provides context) { KazumiTheme(false) {
                PlayerScreen(request,Subject(19000920,"外播测试","",""),initialPosition=3000,initialPlayWhenReady=false,onClose={})
            } } } }
            click("设置"); click("外部播放器")
            await("target list") { nodes().any { it.text?.toString()==mx.label } }
            screenshot("external-player-list.png")
            click(mx.label)
            await("MX foreground") { test.uiAutomation.rootInActiveWindow?.packageName?.toString()==mx.component.packageName }
            Thread.sleep(7000); screenshot("external-mx-player.png")
            if(test.uiAutomation.rootInActiveWindow?.packageName?.toString()==mx.component.packageName)check(test.uiAutomation.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK))
            await("returned paused") { nodes().any { it.text?.toString()?.let { text->text.startsWith("已返回内置播放器") || text.startsWith("外部播放已取消") || text.startsWith("外部播放器报告播放失败") } == true } }
            check(nodes().any { it.text?.toString()=="▷ 播放" })
            screenshot("external-player-return.png")
            check(original.getSharedPreferences("tv_settings",0).all==beforeSettings)
            check(original.getSharedPreferences("tv_library",0).all==beforeLibrary)
        } catch(error:Throwable) { android.util.Log.e("ExternalPlaybackTest","external regression",error); throw error }
        finally {
            server.close()
            test.runOnMainSync { activity.setContent { }; activity.finish() }
            context.getSharedPreferences("tv_settings",0).edit().clear().commit()
        }
    }
}
