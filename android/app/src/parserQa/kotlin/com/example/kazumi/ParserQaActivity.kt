package com.example.kazumi

import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.webkit.WebView
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import org.json.JSONObject
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.GeckoRuntimeSettings
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoSessionSettings
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.WebExtension
import org.mozilla.geckoview.WebRequestError
import java.io.File
import java.util.IdentityHashMap
import java.util.concurrent.atomic.AtomicLong

/** Opt-in parserQa/debug only. One experiment, optionally serial fixture generations. */
class ParserQaActivity : MainActivity() {
    private companion object {
        val channelOwners = IdentityHashMap<BinaryMessenger, ParserQaActivity>()
        var geckoBridgeOwner: ParserQaActivity? = null
        val nextGeckoOwner = AtomicLong(0)
        // GeckoRuntime is process-wide; Activity recreation must reuse it.
        var runtime: GeckoRuntime? = null
    }
    private lateinit var channel: MethodChannel
    private var bridgeMessenger: BinaryMessenger? = null
    private var runtimePrewarmScheduled = false
    private var session: GeckoSession? = null
    private var extension: WebExtension? = null
    private var generation = 0
    private var geckoOwner: Long? = null
    private var resultGeneration = 0
    private var resultCaseId: String? = null
    private var lifecycleSwitch = false
    private val lifecycleKeyEvents = ArrayList<Map<String, Any?>>()
    private var launchProbe: QaLaunchProbeHost? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        if (BuildConfig.QA_LAUNCH_ONLY) {
            launchProbe = QaLaunchProbeHost(this).also { it.begin() }
        }
        super.onCreate(savedInstanceState)
        launchProbe?.record("native_create_exit")
    }
    override fun onResume() { super.onResume(); launchProbe?.record("native_resume") }
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        launchProbe?.focus(hasFocus)
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        launchProbe?.record("native_engine_enter")
        super.configureFlutterEngine(engine)
        launchProbe?.registered(engine.plugins.has(dev.fluttercommunity.plus.packageinfo.PackageInfoPlugin::class.java))
        launchProbe?.observeRenderer(engine.renderer)
        check(BuildConfig.DEBUG && packageName == "com.znbsf.kazumi.fluttertv.parserqa")
        val messenger = engine.dartExecutor.binaryMessenger
        bridgeMessenger = messenger
        channelOwners[messenger] = this
        channel = MethodChannel(messenger, "kazumi/parser_qa")
        channel.setMethodCallHandler { call, result ->
            try {
                check(ownsChannel())
                when (call.method) {
                    "qaUiCapability" -> result.success(fullUiCapability())
                    "qaWarmRuntime" -> {
                        val eligible = geckoRuntimePrewarmEligible()
                        result.success(eligible)
                        if (eligible) scheduleGeckoRuntimePrewarm()
                    }
                    "launchProbeStage" -> {
                        val probe = launchProbe ?: error("qa_launch_only_disabled")
                        probe.dartStage(call.arguments as Map<*, *>)
                        result.success(null)
                    }
                    "launchProbeComplete" -> {
                        val probe = launchProbe ?: error("qa_launch_only_disabled")
                        probe.completeWhenDisplayed(result)
                    }
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
                    "geckoAcquire" -> {
                        if (geckoBridgeOwner != null || geckoOwner != null) {
                            result.error("gecko_busy", "owner_busy", null)
                        } else {
                            val owner = nextGeckoOwner.incrementAndGet()
                            geckoBridgeOwner = this@ParserQaActivity
                            geckoOwner = owner
                            result.success(owner)
                        }
                    }
                    "geckoInit" -> {
                        val owner = (call.argument<Number>("owner") ?: error("gecko_owner_missing")).toLong()
                        check(geckoBridgeOwner === this@ParserQaActivity && geckoOwner == owner)
                        val rt = getOrCreateGeckoRuntime()
                        rt.webExtensionController.ensureBuiltIn(
                            "resource://android/assets/parserqa/", "parserqa@kazumi.local"
                        ).accept({ ext ->
                            if (geckoOwner == owner && ownsChannel()) { extension = ext; result.success(null) }
                            else result.error("gecko_retired", "owner_retired", null)
                        }, { error ->
                            if (geckoOwner == owner && session == null) {
                                geckoOwner = null
                                if (geckoBridgeOwner === this@ParserQaActivity) geckoBridgeOwner = null
                            }
                            result.error("gecko_init", error?.javaClass?.simpleName, null)
                        })
                    }
                    "geckoLoad" -> {
                        val args = call.arguments as Map<*, *>
                        val owner = (args["owner"] as Number).toLong()
                        check(geckoBridgeOwner === this@ParserQaActivity)
                        check(geckoOwner == owner)
                        closeSession()
                        val epoch = ++generation
                        val url = args["url"] as String
                        require(url.startsWith("https://") || url.startsWith("http://"))
                        val s = GeckoSession(GeckoSessionSettings.Builder()
                            .usePrivateMode(true).userAgentOverride(args["ua"] as String).build())
                        session = s
                        fun diagnostic(stage: String, uri: String, detail: String) {
                            if (session === s && epoch == generation && ownsChannel()) channel.invokeMethod("geckoDiagnostic",
                                mapOf("stage" to stage, "url" to uri, "detail" to detail,
                                    "owner" to owner, "generation" to args["generation"]))
                        }
                        s.progressDelegate = object : GeckoSession.ProgressDelegate {
                            override fun onPageStart(session: GeckoSession, uri: String) {
                                diagnostic("load_start", uri, "")
                            }
                            override fun onPageStop(session: GeckoSession, success: Boolean) {
                                val stop = QaGeckoPageStop.fromCallback(success)
                                diagnostic("load_stop", stop.uri, stop.detail)
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
                                    if (sender.session !== s || session !== s || epoch != generation || !ownsChannel()) return null
                                    if (message is JSONObject) {
                                        val handler = message.optString("handler")
                                        val value = message.optString("url")
                                        if (handler == "Snapshot") diagnostic("dom_snapshot", url,
                                            "ready=${message.optString("ready")} frames=${message.optInt("frames")} videos=${message.optInt("videos")}")
                                        if (handler in setOf("JSBridgeDebug", "VideoBridgeDebug") && value.length <= 16384) {
                                            channel.invokeMethod("geckoEvent", mapOf("handler" to handler,
                                                "url" to value, "owner" to owner, "generation" to args["generation"]))
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
                    "geckoClose" -> {
                        val owner = (call.argument<Number>("owner") ?: error("gecko_owner_missing")).toLong()
                        // A stale route cannot close a newer native session.
                        check(geckoBridgeOwner == null || geckoBridgeOwner === this@ParserQaActivity)
                        check(geckoOwner == null || geckoOwner == owner)
                        if (geckoOwner == owner) {
                            closeSession()
                            if (call.argument<Boolean>("release") == true) {
                                geckoOwner = null
                                if (geckoBridgeOwner === this@ParserQaActivity) geckoBridgeOwner = null
                            }
                        }
                        // This acknowledges API retirement, not OS process/memory release.
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("qa_error", error.javaClass.simpleName, null)
            }
        }
        launchProbe?.record("native_channel_ready")
        if (BuildConfig.QA_FULL_UI && ownsChannel()) channel.invokeMethod("qaUiReady", fullUiCapability())
    }
    private fun fullUiCapability() = mapOf(
        "package" to packageName, "activity" to javaClass.name,
        "debug" to BuildConfig.DEBUG, "full_ui" to BuildConfig.QA_FULL_UI,
        "tv" to BuildConfig.IS_TV_BUILD, "offline" to BuildConfig.QA_LAUNCH_ONLY)
    private fun getOrCreateGeckoRuntime(): GeckoRuntime = runtime ?: GeckoRuntime.create(
        applicationContext, GeckoRuntimeSettings.Builder().consoleOutput(false).build()
    ).also { runtime = it }

    private fun geckoRuntimePrewarmEligible(): Boolean {
        if (!BuildConfig.DEBUG || !BuildConfig.QA_FULL_UI ||
            !BuildConfig.IS_TV_BUILD || BuildConfig.QA_LAUNCH_ONLY ||
            packageName != "com.znbsf.kazumi.fluttertv.parserqa" ||
            !ownsChannel() || isFinishing || isDestroyed) return false
        return try {
            val provider = WebView.getCurrentWebViewPackage()
            provider?.packageName in setOf("com.android.webview", "com.google.android.webview") &&
                Regex("^66\\.\\d+\\.\\d+\\.\\d+$").matches(provider?.versionName ?: "")
        } catch (error: Exception) {
            Log.w("ParserQaGecko", "prewarm_skipped ${error.javaClass.simpleName}")
            false
        }
    }

    private fun scheduleGeckoRuntimePrewarm() {
        if (runtimePrewarmScheduled) return
        runtimePrewarmScheduled = true
        // The explicit warm-up reply has already returned. Runtime creation
        // opens no Session/URL and acquires no lease.
        Handler(Looper.getMainLooper()).post {
            if (!geckoRuntimePrewarmEligible()) return@post
            try {
                val started = SystemClock.elapsedRealtime()
                val reused = runtime != null
                Log.i("ParserQaGecko", "prewarm_start reused=$reused")
                getOrCreateGeckoRuntime()
                Log.i("ParserQaGecko", "prewarm_ready reused=$reused elapsed_ms=${SystemClock.elapsedRealtime() - started}")
            } catch (error: Exception) {
                // Prewarming is optional; keep the normal geckoInit path usable.
                Log.w("ParserQaGecko", "prewarm_failed ${error.javaClass.simpleName}")
            }
        }
    }
    private fun closeSession() {
        generation++
        session?.let { it.stop(); it.close() }
        session = null
    }
    private fun ownsChannel(): Boolean {
        val messenger = bridgeMessenger ?: return false
        return channelOwners[messenger] === this
    }
    private fun retireBridge() {
        var retired = false
        try { closeSession(); retired = true }
        finally {
            if (retired) {
                geckoOwner = null
                if (geckoBridgeOwner === this) geckoBridgeOwner = null
            }
            val messenger = bridgeMessenger
            if (messenger != null && channelOwners[messenger] === this) {
                channel.setMethodCallHandler(null)
                channelOwners.remove(messenger)
            }
            bridgeMessenger = null
        }
    }
    override fun cleanUpFlutterEngine(engine: FlutterEngine) {
        try { retireBridge() }
        finally { super.cleanUpFlutterEngine(engine) }
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
    override fun onDestroy() {
        try {
            runCatching { launchProbe?.record("native_destroy") }
            retireBridge()
        }
        finally {
            try { super.onDestroy() }
            finally { launchProbe?.detach() }
        }
    }
}
