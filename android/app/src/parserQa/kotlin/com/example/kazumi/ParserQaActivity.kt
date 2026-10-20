package com.example.kazumi

import android.os.Build
import android.webkit.WebView
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.GeckoRuntimeSettings
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoSessionSettings
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.WebExtension
import org.mozilla.geckoview.WebRequestError
import java.io.File

/** Opt-in parserQa/debug only. One experiment, optionally serial fixture generations. */
class ParserQaActivity : MainActivity() {
    private lateinit var channel: MethodChannel
    private var runtime: GeckoRuntime? = null
    private var session: GeckoSession? = null
    private var extension: WebExtension? = null
    private var generation = 0
    private var resultGeneration = 0
    private var resultCaseId: String? = null
    private var lifecycleSwitch = false
    private val lifecycleKeyEvents = ArrayList<Map<String, Any?>>()

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        check(BuildConfig.DEBUG && packageName == "com.znbsf.kazumi.fluttertv.parserqa")
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "kazumi/parser_qa")
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "config" -> {
                        val text = File(filesDir, "case.json").readText()
                        lifecycleSwitch = JSONObject(text).optJSONObject("qa_lifecycle")?.optString("action") == "switch"
                        result.success(text)
                    }
                    "qaKeyState" -> result.success(lifecycleKeyEvents)
                    "environment" -> {
                        val provider = WebView.getCurrentWebViewPackage()
                        result.success(mapOf("sdk" to Build.VERSION.SDK_INT,
                            "abi" to Build.SUPPORTED_ABIS.toList(),
                            "webview" to "${provider?.packageName}/${provider?.versionName}",
                            "gecko" to "146.0.20251217121356", "package" to packageName))
                    }
                    "qaBegin" -> {
                        val args = call.arguments as Map<*, *>
                        val epoch = (args["generation"] as Number).toInt()
                        val id = args["case_id"] as String
                        require(epoch > resultGeneration && id.length in 1..100)
                        resultGeneration = epoch
                        resultCaseId = id
                        result.success(null)
                    }
                    "qaInvalidate" -> {
                        val args = call.arguments as Map<*, *>
                        if ((args["generation"] as Number).toInt() == resultGeneration) resultCaseId = null
                        result.success(null)
                    }
                    "qaState" -> {
                        val args = call.arguments as Map<*, *>
                        if ((args["generation"] as Number).toInt() == resultGeneration && args["case_id"] == resultCaseId) {
                            File(filesDir, "lifecycle-state.json").writeText(JSONObject(args).toString())
                        }
                        result.success(null)
                    }
                    "result" -> {
                        val text = call.arguments as String
                        val row = JSONObject(text)
                        if (row.optInt("qa_generation") != resultGeneration || row.optString("qa_case_id") != resultCaseId) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val temporary = File(filesDir, "result.tmp")
                        temporary.writeText(text)
                        check(temporary.renameTo(File(filesDir, "result.json")))
                        result.success(true)
                    }
                    "geckoInit" -> {
                        val rt = runtime ?: GeckoRuntime.create(applicationContext,
                            GeckoRuntimeSettings.Builder().consoleOutput(false).build()).also { runtime = it }
                        rt.webExtensionController.ensureBuiltIn(
                            "resource://android/assets/parserqa/", "parserqa@kazumi.local"
                        ).accept({ ext -> extension = ext; result.success(null) },
                            { error -> result.error("gecko_init", error?.javaClass?.simpleName, null) })
                    }
                    "geckoLoad" -> {
                        closeSession()
                        val epoch = ++generation
                        val args = call.arguments as Map<*, *>
                        val url = args["url"] as String
                        require(url.startsWith("https://") || url.startsWith("http://"))
                        val s = GeckoSession(GeckoSessionSettings.Builder()
                            .usePrivateMode(true).userAgentOverride(args["ua"] as String).build())
                        session = s
                        fun diagnostic(stage: String, uri: String, detail: String) {
                            if (session === s && epoch == generation) channel.invokeMethod("geckoDiagnostic",
                                mapOf("stage" to stage, "url" to uri, "detail" to detail, "generation" to args["generation"]))
                        }
                        s.progressDelegate = object : GeckoSession.ProgressDelegate {
                            override fun onPageStart(session: GeckoSession, uri: String) {
                                diagnostic("load_start", uri, "")
                            }
                            override fun onPageStop(session: GeckoSession, success: Boolean) {
                                diagnostic("load_stop", url, "success=$success")
                            }
                        }
                        s.navigationDelegate = object : GeckoSession.NavigationDelegate {
                            override fun onLoadError(session: GeckoSession, uri: String?, error: WebRequestError): GeckoResult<String>? {
                                diagnostic("resource_error", uri ?: "", "code=${error.code} category=${error.category}")
                                return null
                            }
                        }
                        s.webExtensionController.setMessageDelegate(extension!!,
                            object : WebExtension.MessageDelegate {
                                override fun onMessage(nativeApp: String, message: Any,
                                    sender: WebExtension.MessageSender): GeckoResult<Any>? {
                                    if (sender.session !== s || session !== s || epoch != generation) return null
                                    if (message is JSONObject) {
                                        val handler = message.optString("handler")
                                        val value = message.optString("url")
                                        if (handler == "Snapshot") diagnostic("dom_snapshot", url,
                                            "ready=${message.optString("ready")} frames=${message.optInt("frames")} videos=${message.optInt("videos")}")
                                        if (handler in setOf("JSBridgeDebug", "VideoBridgeDebug") && value.length <= 16384) {
                                            channel.invokeMethod("geckoEvent", mapOf("handler" to handler,
                                                "url" to value, "generation" to args["generation"]))
                                        }
                                    }
                                    return null
                                }
                            }, "kazumi_parser")
                        s.open(runtime!!)
                        s.setActive(true)
                        s.loadUri(url)
                        result.success(null)
                    }
                    "geckoClose" -> { closeSession(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("qa_error", error.javaClass.simpleName, null)
            }
        }
    }
    private fun closeSession() {
        generation++
        session?.let { it.stop(); it.close() }
        session = null
    }
    private fun findQaFlutterView(view: View): FlutterView? {
        if (view is FlutterView) return view
        if (view is ViewGroup) for (i in 0 until view.childCount) {
            findQaFlutterView(view.getChildAt(i))?.let { return it }
        }
        return null
    }
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // Only the explicitly enabled QA fixture switch restores focus from a
        // headless platform view. Activation still goes through the real key
        // event, Flutter focus/shortcuts and the visible fixture button.
        if (lifecycleSwitch && resultGeneration == 1 && resultCaseId != null &&
            event.keyCode == KeyEvent.KEYCODE_DPAD_CENTER && event.action == KeyEvent.ACTION_DOWN) {
            val before = currentFocus?.javaClass?.simpleName
            val target = findQaFlutterView(window.decorView)
            target?.isFocusableInTouchMode = true
            val focused = target?.requestFocus() == true
            if (lifecycleKeyEvents.size < 4) lifecycleKeyEvents.add(mapOf(
                "keycode" to event.keyCode, "generation" to resultGeneration,
                "before_focus_class" to before, "after_focus_class" to currentFocus?.javaClass?.simpleName,
                "flutter_focus_requested" to focused, "epoch_ms" to System.currentTimeMillis()))
        }
        return super.dispatchKeyEvent(event)
    }
    override fun onDestroy() { closeSession(); super.onDestroy() }
}
