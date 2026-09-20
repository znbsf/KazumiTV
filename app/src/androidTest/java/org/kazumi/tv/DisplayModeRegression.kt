package org.kazumi.tv
import android.app.Instrumentation
import android.content.ContextWrapper
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.media3.common.Player
import androidx.media3.ui.PlayerView
import org.kazumi.tv.data.*
import org.kazumi.tv.playback.*
import org.kazumi.tv.ui.*
import java.util.concurrent.atomic.AtomicReference

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object DisplayModeRegression {
    fun run(test:Instrumentation) {
        val realSettings=test.targetContext.getSharedPreferences("tv_settings",0).all.toMap()
        val realLibrary=test.targetContext.getSharedPreferences("tv_library",0).all.toMap()
        val context=object:ContextWrapper(test.targetContext) { override fun getSharedPreferences(name:String,mode:Int)=baseContext.getSharedPreferences("display_mode_test_$name",mode) }
        val prefs=context.getSharedPreferences("tv_settings",0); prefs.edit().clear().commit()
        val settings=TvPreferences(context); settings.incognito=true; settings.danmakuEnabled=false; settings.controlsSeconds=10
        val sample=java.io.File(test.targetContext.cacheDir,"display-mode-fixture.mp4")
        test.context.assets.open("tracks-fixture.mp4").use { input -> sample.outputStream().use { input.copyTo(it) } }
        val activity=test.startActivitySync(Intent(test.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        var session:DisplayModeSession?=null; var original=0
        try {
            var snapshot=DisplaySnapshot(); var flags=0
            test.runOnMainSync { snapshot=DisplaySnapshot.read(activity.window.decorView); original=activity.window.attributes.preferredDisplayModeId; flags=activity.window.attributes.flags }
            check(snapshot.modes.isNotEmpty()); val choice=snapshot.active!!.preference
            val id=DisplayModePolicy.requestedId(choice,snapshot.modes); check(id>0)
            test.runOnMainSync {
                val ids={ snapshot.modes.map { it.id }.toSet() }
                val outer=WindowModeRequests.acquire(activity.window,ids); outer.request(id)
                val inner=WindowModeRequests.acquire(activity.window,ids); inner.request(0)
                outer.close(); check(activity.window.attributes.preferredDisplayModeId==0)
                inner.close(); check(activity.window.attributes.preferredDisplayModeId==original)
                val first=WindowModeRequests.acquire(activity.window,ids); first.request(id)
                val second=WindowModeRequests.acquire(activity.window,ids); second.request(0); second.close()
                check(activity.window.attributes.preferredDisplayModeId==id); first.close()
                check(activity.window.attributes.preferredDisplayModeId==original && activity.window.attributes.flags==flags)
                session=DisplayModeSession(context,activity.window,activity.window.decorView,probe={ snapshot })
                session!!.start(); session!!.preview(choice); session!!.confirm()
                check(TvPreferences(context).displayMode==choice && activity.window.attributes.preferredDisplayModeId==id)
                val actual=snapshot; snapshot=DisplaySnapshot(emptyList(),actual.active); session!!.refresh()
                check(activity.window.attributes.preferredDisplayModeId==0 && session!!.state.value.status.contains("不可用"))
                snapshot=actual; session!!.refresh(); check(activity.window.attributes.preferredDisplayModeId==id)
                session!!.preview(null); session!!.stop()
                check(activity.window.attributes.preferredDisplayModeId==original && TvPreferences(context).displayMode==choice)
                session!!.start(); check(activity.window.attributes.preferredDisplayModeId==id)
                session!!.preview(null); session!!.confirm(); check(TvPreferences(context).displayMode==null)
            }
            fun nodes():List<AccessibilityNodeInfo> {
                val result=mutableListOf<AccessibilityNodeInfo>(); fun walk(n:AccessibilityNodeInfo?) { if(n==null)return; result.add(n); for(i in 0 until n.childCount)walk(n.getChild(i)) }; walk(test.uiAutomation.rootInActiveWindow); return result
            }
            fun find(text:String,timeout:Int=100):AccessibilityNodeInfo {
                repeat(timeout) { nodes().firstOrNull { it.text?.toString()==text }?.let { return it }; nodes().firstOrNull { it.isScrollable }?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD); Thread.sleep(100) }; error("Missing $text")
            }
            fun click(text:String) { var n:AccessibilityNodeInfo?=find(text); while(n!=null && !n.isClickable)n=n.parent; check(n?.performAction(AccessibilityNodeInfo.ACTION_CLICK)==true); Thread.sleep(300) }
            fun shot(name:String) { val image=test.uiAutomation.takeScreenshot(); java.io.File(test.targetContext.getExternalFilesDir(null),name).outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) }; image.recycle() }
            test.runOnMainSync { activity.setContent { CompositionLocalProvider(LocalContext provides context,LocalActivity provides activity) { KazumiTheme(false) {
                Box(Modifier.fillMaxSize().background(KazumiColors.background).padding(30.dp)) { DisplayModePanel(session) }
            } } } }
            click(choice.label); find("保留显示选择"); shot("display-mode-trial.png")
            find("试用超时，已恢复原选择",220)
            check(TvPreferences(context).displayMode==null)
            test.runOnMainSync { check(activity.window.attributes.preferredDisplayModeId==0) }
            click(choice.label); click("保留显示选择"); find("显示选择已保存，实际模式由系统决定")
            click("系统默认"); find("保留显示选择"); test.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
            find("已恢复原选择"); check(TvPreferences(context).displayMode==choice)
            test.runOnMainSync { session!!.stop(); check(activity.window.attributes.preferredDisplayModeId==original) }
            val dialogWindow=AtomicReference<Window?>(); val dialogOriginal=java.util.concurrent.atomic.AtomicInteger()
            val dialogSession=AtomicReference<DisplayModeSession?>()
            test.runOnMainSync { activity.setContent { CompositionLocalProvider(LocalContext provides context,LocalActivity provides activity) { KazumiTheme(false) {
                Dialog(onDismissRequest={},properties=DialogProperties(usePlatformDefaultWidth=false,decorFitsSystemWindows=false)) {
                    CompositionLocalProvider(LocalContext provides context,LocalActivity provides activity) {
                    val view=LocalView.current; val window=remember { displayWindow(view,activity.window)!! }
                    remember { dialogWindow.set(window); dialogOriginal.set(window.attributes.preferredDisplayModeId); true }
                    val controller=rememberDisplayModeSession(); SideEffect { dialogSession.set(controller) }
                    PlayerScreen(PlaybackRequest(sample.toURI().toString(),emptyMap(),"显示模式样片"),Subject(981,"显示模式样片","",""),displaySession=controller,onClose={})
                    }
                }
            } } } }
            fun player(view:View):Player? { if(view is PlayerView && view.player!=null)return view.player; if(view is ViewGroup)for(i in 0 until view.childCount)player(view.getChildAt(i))?.let { return it }; return null }
            var ready=false; val deadline=System.nanoTime()+10_000_000_000L
            while(!ready && System.nanoTime()<deadline) { test.runOnMainSync { val window=dialogWindow.get(); val p=window?.let { player(it.decorView) }; ready=p?.playbackState==Player.STATE_READY && p.videoSize.width>0; if(ready)p?.pause() }; if(!ready)Thread.sleep(100) }
            check(ready && dialogWindow.get()!==activity.window && dialogSession.get()!=null)
            test.runOnMainSync { check(dialogWindow.get()!!.attributes.preferredDisplayModeId==id); check(activity.window.attributes.preferredDisplayModeId==original) }
            click("设置"); click("显示模式"); click("系统默认"); find("保留显示选择"); shot("display-mode-player.png")
            test.runOnMainSync { check(dialogWindow.get()!!.attributes.preferredDisplayModeId==0) }
            click("恢复原选择")
            test.runOnMainSync { check(dialogWindow.get()!!.attributes.preferredDisplayModeId==id); activity.setContent { Box(Modifier) } }
            var restored=false; val stopDeadline=System.nanoTime()+5_000_000_000L
            while(!restored && System.nanoTime()<stopDeadline) { test.runOnMainSync { restored=dialogWindow.get()!!.attributes.preferredDisplayModeId==dialogOriginal.get() }; if(!restored)Thread.sleep(50) }
            check(restored)
            check(realSettings==test.targetContext.getSharedPreferences("tv_settings",0).all)
            check(realLibrary==test.targetContext.getSharedPreferences("tv_library",0).all)
        } catch(e:Exception) { android.util.Log.e("DisplayModeTest","${e.message}; ${e.stackTrace.take(5).joinToString()}"); throw e }
        finally { test.runOnMainSync { session?.stop(); activity.window.attributes=activity.window.attributes.apply { preferredDisplayModeId=original }; activity.finish() }; prefs.edit().clear().commit(); sample.delete() }
    }
}
