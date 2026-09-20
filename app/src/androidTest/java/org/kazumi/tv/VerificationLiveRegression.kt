package org.kazumi.tv

import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import kotlinx.coroutines.runBlocking
import org.kazumi.tv.rules.*
import org.kazumi.tv.ui.*

object VerificationLiveRegression {
    fun run(test:Instrumentation,args:Bundle=Bundle())=runBlocking {
        val sourceName=args.getString("source") ?: "mutefun"
        val repo=RuleRepository(test.targetContext)
        val rule=repo.rules.first { it.name.equals(sourceName,true) }
        val challenge=try {
            val matches=repo.search(rule,"无职转生")
            check(matches.isNotEmpty()) { "Search empty; verification success not established" }
            test.sendStatus(0,Bundle().apply { putString("stream","${rule.name} already verified results=${matches.size}\n") })
            return@runBlocking
        } catch(e:SourceVerificationRequired) { e }
        // Real sites may reject an immediate repeat of the exact search as a rapid request.
        // This is a test pacing interval, not an application-wide retry or source-rule override.
        Thread.sleep(3500)
        val activity=test.startActivitySync(Intent(test.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        val done=java.util.concurrent.atomic.AtomicBoolean()
        val inputFile=java.io.File(test.targetContext.getExternalFilesDir(null),"verification-fixture-input.txt")
        inputFile.delete()
        test.runOnMainSync { activity.setContent { KazumiTheme(false) { VerificationScreen(rule,challenge.pageUrl,challenge) { done.set(true) } } } }
        test.uiAutomation.serviceInfo=test.uiAutomation.serviceInfo.apply {
            flags=flags or android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        test.sendStatus(0,Bundle().apply { putString("stream","${rule.name} verification UI open; awaiting configured verification\n") })
        try {
            val deadline=System.currentTimeMillis()+(args.getString("waitMs")?.toLongOrNull() ?: 300000).coerceIn(1000,300000)
            var nextSnapshot=0L
            while(!done.get()&&System.currentTimeMillis()<deadline) {
                if(System.currentTimeMillis()>=nextSnapshot) {
                    nextSnapshot=System.currentTimeMillis()+30000
                    fun find(view:android.view.View):android.webkit.WebView? {
                        if(view is android.webkit.WebView)return view
                        if(view is android.view.ViewGroup)for(i in 0 until view.childCount)find(view.getChildAt(i))?.let { return it }
                        return null
                    }
                    test.runOnMainSync {
                        find(activity.window.decorView)?.evaluateJavascript("JSON.stringify({url:location.href,html:document.documentElement.outerHTML})") { raw ->
                            // Private local diagnostic only; never included in public test output.
                            java.io.File(test.targetContext.getExternalFilesDir(null),"verification-live-${rule.name}.private.json").writeText(raw)
                        }
                    }
                }
                if(inputFile.exists()) {
                    val code=inputFile.readText().trim();inputFile.delete()
                    val nodes=mutableListOf<android.view.accessibility.AccessibilityNodeInfo>()
                    fun walk(node:android.view.accessibility.AccessibilityNodeInfo?) { if(node==null)return;nodes.add(node);for(i in 0 until node.childCount)walk(node.getChild(i)) }
                    fun readAppWindow() {
                        nodes.clear()
                        val roots=test.uiAutomation.windows.mapNotNull { it.root }.filter { it.packageName?.toString()==test.targetContext.packageName }
                        roots.forEach { walk(it) }
                    }
                    readAppWindow()
                    check(nodes.any { it.text?.contains("${rule.name} · 网页验证")==true }) { "verification window is not active" }
                    check(nodes.first { it.isEditable }.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_SET_TEXT,Bundle().apply { putCharSequence(android.view.accessibility.AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,code) }))
                    Thread.sleep(300)
                    readAppWindow()
                    var button=nodes.first { it.text?.toString()=="提交验证码" }
                    while(!button.isClickable)button=button.parent
                    check(button.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK))
                }
                Thread.sleep(200)
            }
            check(done.get()) { "manual verification not completed" }
            val matches=repo.search(rule,"无职转生")
            check(matches.isNotEmpty()) { "verification did not restore original search" }
            test.sendStatus(0,Bundle().apply { putString("stream","${rule.name} real verification and original search retry results=${matches.size}=OK\n") })
        } finally { inputFile.delete();test.runOnMainSync { activity.finish() } }
    }
}
