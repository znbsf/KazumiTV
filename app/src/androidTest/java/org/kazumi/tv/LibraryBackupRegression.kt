package org.kazumi.tv
import android.app.Instrumentation
import android.content.ContextWrapper
import android.content.Intent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalContext
import org.kazumi.tv.data.*
import org.kazumi.tv.ui.*

object LibraryBackupRegression {
    fun run(test:Instrumentation) {
        val real=test.targetContext.getSharedPreferences("tv_library",0).all.toMap()
        val folder=java.io.File(test.targetContext.cacheDir,"library-backup-fixture-${java.util.UUID.randomUUID()}")
        val context=object:ContextWrapper(test.targetContext) {
            override fun getSharedPreferences(name:String,mode:Int)=baseContext.getSharedPreferences("library_backup_test_$name",0)
            override fun getFilesDir()=folder
        }
        val prefs=context.getSharedPreferences("tv_library",0); prefs.edit().clear().commit()
        val store=LibraryStore(context); val files=LocalLibraryBackups(context)
        val a=Subject(801,"备份作品A","",""); val b=Subject(802,"新作品B","","")
        store.setCollection(a,CollectionType.WATCHED)
        store.save(HistoryEntry("fixture",a,"第10集",65000,120000,PlaybackOrigin("fixture","show","https://example.com/show","road")))
        val archive=store.exportBackup()
        repeat(7) { files.save(archive) }; check(files.list().size==5)
        check(files.list().all { LibraryArchiveCodec.read(files.read(it)).history.single().position==65000L })
        val fingerprint=store.backupFingerprint(); store.setCollection(b,CollectionType.PLANNED)
        check(runCatching { store.restoreBackup(archive,fingerprint) }.isFailure); check(store.collections().size==2)
        val old=prefs.getString("favorites",null)
        prefs.edit().putString("favorites","{\"version\":99,\"records\":[]}").commit()
        check(runCatching { store.restoreBackup(archive,store.backupFingerprint()) }.isFailure)
        prefs.edit().putString("favorites",old).commit()
        store.restoreBackup(archive,store.backupFingerprint()); store.setCollection(b,CollectionType.PLANNED)
        check(runCatching { store.undoRestore() }.isFailure); check(store.collections().size==2)
        // A damaged undo snapshot must never replace either current container or the journal.
        store.restoreBackup(archive,store.backupFingerprint())
        val undo=prefs.getString("restore_before",null)!!
        for(broken in listOf("not json","{\"version\":99,\"records\":[]}","[{\"key\":\"broken\"}]")) {
            prefs.edit().putString("restore_before",org.json.JSONObject(undo).put("history",broken).toString()).commit()
            val unchanged=prefs.all.toMap()
            check(runCatching { store.undoRestore() }.isFailure)
            check(unchanged==prefs.all)
        }
        prefs.edit().putString("restore_before",undo).commit()
        store.undoRestore(); check(store.collections().size==2)
        val activity=test.startActivitySync(Intent(test.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        try {
            fun nodes():List<AccessibilityNodeInfo> {
                val list=mutableListOf<AccessibilityNodeInfo>()
                fun walk(n:AccessibilityNodeInfo?) { if(n==null)return; list.add(n); for(i in 0 until n.childCount)walk(n.getChild(i)) }
                walk(test.uiAutomation.rootInActiveWindow); return list
            }
            fun find(text:String,prefix:Boolean=false):AccessibilityNodeInfo {
                repeat(70) {
                    nodes().firstOrNull { if(prefix)it.text?.toString()?.startsWith(text)==true else it.text?.toString()==text }?.let { return it }
                    nodes().firstOrNull { it.isScrollable }?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
                    Thread.sleep(100)
                }
                error("Missing $text")
            }
            fun click(text:String,prefix:Boolean=false) { var n:AccessibilityNodeInfo?=find(text,prefix); while(n!=null && !n.isClickable)n=n.parent; check(n?.performAction(AccessibilityNodeInfo.ACTION_CLICK)==true); Thread.sleep(400) }
            test.runOnMainSync { activity.setContent { CompositionLocalProvider(LocalContext provides context,androidx.activity.compose.LocalActivityResultRegistryOwner provides activity) { KazumiTheme(false) { LibraryBackupScreen() } } } }
            click("预览备份 1",true); find("恢复预览：1 条收藏，1 条历史")
            click("取消恢复"); check(store.collections().size==2)
            click("预览备份 1",true)
            val shot=test.uiAutomation.takeScreenshot()
            java.io.File(test.targetContext.getExternalFilesDir(null),"library-backup-preview.png").outputStream().use { shot.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) }; shot.recycle()
            click("确认替换收藏与历史"); find("恢复完成，可撤销上次恢复")
            check(store.collections().single().subject.id==801 && store.history().single().position==65000L)
            click("撤销上次恢复"); find("已撤销恢复"); check(store.collections().size==2)
            check(real==test.targetContext.getSharedPreferences("tv_library",0).all)
        } finally {
            test.runOnMainSync { activity.finish() }; prefs.edit().clear().commit()
            check(folder.canonicalPath.startsWith(test.targetContext.cacheDir.canonicalPath+java.io.File.separator)); folder.deleteRecursively()
        }
    }
}
