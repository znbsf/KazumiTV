package com.example.kazumi

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.os.SystemClock
import android.webkit.WebView
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

/** Never constructed outside the explicitly built offline debug variant. */
class QaLaunchProbeHost(private val activity: ParserQaActivity) {
    private val ledger = QaLaunchLedger()
    private val started = SystemClock.elapsedRealtime()
    private var attempt: String? = null
    private var previous: Thread.UncaughtExceptionHandler? = null
    private var installed: Thread.UncaughtExceptionHandler? = null
    private var packageInfoRegistered: Boolean? = null
    private var focused = false
    private var renderer: FlutterRenderer? = null
    private var displayed = false
    private var pending: MethodChannel.Result? = null
    private val displayListener = object : FlutterUiDisplayListener {
        override fun onFlutterUiDisplayed() {
            if (!displayed) {
                displayed = true
                record("native_first_frame")
                pending?.let { pending = null; finish(it) }
            }
        }
        override fun onFlutterUiNoLongerDisplayed() {}
    }
    private fun denied() = activity.checkSelfPermission(Manifest.permission.INTERNET) == PackageManager.PERMISSION_DENIED
    private fun atomic(name: String, value: JSONObject) {
        val bytes = value.toString().toByteArray(Charsets.UTF_8)
        check(bytes.size <= QaLaunchLedger.MAX_BYTES)
        val temporary = File(activity.filesDir, "$name.tmp")
        FileOutputStream(temporary).use { it.write(bytes); it.fd.sync() }
        check(temporary.renameTo(File(activity.filesDir, name)))
    }
    @Synchronized fun record(stage: String, errorType: String? = null) {
        check(ledger.record(stage, SystemClock.elapsedRealtime() - started, Process.myPid(), errorType))
        val row = JSONObject().put("schema", 1).put("id", "qa-offline-launch-only-v1")
            .put("attempt_key", attempt ?: JSONObject.NULL).put("network_permission_denied", denied())
            .put("package_info_registered", packageInfoRegistered ?: JSONObject.NULL)
            .put("events", JSONArray(ledger.snapshot()))
        atomic("qa-launch-probe.json", row)
    }
    fun begin() {
        check(BuildConfig.DEBUG && BuildConfig.QA_LAUNCH_ONLY &&
            activity.packageName == "com.znbsf.kazumi.fluttertv.parserqa")
        previous = Thread.getDefaultUncaughtExceptionHandler()
        previous?.let { delegate ->
            val handler = Thread.UncaughtExceptionHandler { thread, error ->
                runCatching { record("native_uncaught", error.javaClass.name) }
                delegate.uncaughtException(thread, error)
            }
            installed = handler
            Thread.setDefaultUncaughtExceptionHandler(handler)
        }
        record("native_create_enter")
        check(denied()) { "qa_offline_permission_guard" }
        val file = File(activity.filesDir, "case.json")
        require(file.isFile && file.length() in 1..4096)
        val config = JSONObject(file.readText())
        val allowed = setOf("id", "group", "engine", "launch_only", "repeat", "user_agent", "launch_attempt_key")
        require(config.keys().asSequence().all { it in allowed })
        require(config.opt("id") == "qa-offline-launch-only-v1" && config.opt("group") == "offline-launch" &&
            config.opt("engine") == "app" && config.opt("launch_only") == true && config.opt("repeat") == 0 &&
            config.opt("user_agent") is String && config.getString("user_agent").length <= 256)
        val key = config.opt("launch_attempt_key") as? String
        require(key != null && Regex("^[a-f0-9]{20}$").matches(key))
        attempt = key
    }
    fun registered(value: Boolean) { packageInfoRegistered = value; record("native_super_engine_exit") }
    fun observeRenderer(value: FlutterRenderer) {
        renderer = value
        value.addIsDisplayingFlutterUiListener(displayListener)
    }
    fun focus(value: Boolean) { if (value && !focused) { focused = true; record("native_window_focus") } }
    fun dartStage(args: Map<*, *>) {
        require(args.keys.all { it == "stage" || it == "error_type" })
        val stage = args["stage"] as? String
        require(stage != null && stage.startsWith("dart_"))
        val error = args["error_type"]
        require(error == null || error is String)
        record(stage, error as? String)
    }
    fun completeWhenDisplayed(result: MethodChannel.Result) {
        check(denied() && ledger.ready() && attempt != null && pending == null)
        if (displayed) finish(result) else pending = result
    }
    private fun finish(result: MethodChannel.Result) {
        try { complete(); result.success(null) }
        catch (error: Exception) { result.error("qa_launch_result", error.javaClass.simpleName, null) }
    }
    private fun complete() {
        check(denied() && ledger.ready() && displayed && attempt != null)
        record("probe_result")
        val provider = WebView.getCurrentWebViewPackage()
        atomic("launch-only-result.json", JSONObject()
            .put("id", "qa-offline-launch-only-v1").put("engine", "app").put("launch_only", true)
            .put("attempt_key", attempt).put("stage", "launch_ready")
            .put("parser", "not_run").put("media", "not_run")
            .put("player_release", "not_created").put("resolver_release", "not_created")
            .put("cleanup", "confirmed").put("cleanup_coverage", "no parser/player created; host verifies process exit")
            .put("network_permission_denied", true).put("package_info_registered", packageInfoRegistered)
            .put("native_first_frame", true)
            .put("environment", JSONObject().put("sdk", Build.VERSION.SDK_INT)
                .put("webview", "${provider?.packageName}/${provider?.versionName}")
                .put("package", activity.packageName)))
    }
    fun detach() {
        renderer?.removeIsDisplayingFlutterUiListener(displayListener)
        renderer = null
        pending = null
        if (Thread.getDefaultUncaughtExceptionHandler() === installed && installed != null) {
            Thread.setDefaultUncaughtExceptionHandler(previous)
        }
    }
}
