package com.example.kazumi

import android.os.Build
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
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

/** Loaded only by the opt-in parserQa/debug variant. One case per process. */
class ParserQaActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private var runtime: GeckoRuntime? = null
    private var session: GeckoSession? = null
    private var extension: WebExtension? = null
    private var generation = 0

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        check(BuildConfig.DEBUG && packageName == "com.znbsf.kazumi.fluttertv.parserqa")
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "kazumi/parser_qa")
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "config" -> result.success(File(filesDir, "case.json").readText())
                    "environment" -> {
                        val provider = WebView.getCurrentWebViewPackage()
                        result.success(mapOf("sdk" to Build.VERSION.SDK_INT,
                            "abi" to Build.SUPPORTED_ABIS.toList(),
                            "webview" to "${provider?.packageName}/${provider?.versionName}",
                            "gecko" to "146.0.20251217121356", "package" to packageName))
                    }
                    "result" -> {
                        val text = call.arguments as String
                        JSONObject(text) // Reject malformed output before atomic replacement.
                        val temporary = File(filesDir, "result.tmp")
                        temporary.writeText(text)
                        check(temporary.renameTo(File(filesDir, "result.json")))
                        result.success(null)
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
    override fun onDestroy() { closeSession(); super.onDestroy() }
}
