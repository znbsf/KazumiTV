package com.example.kazumi

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import java.util.UUID

/** The Flutter owner receives one opaque command and remains the sole business owner. */
class EpisodeBrowserBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private var activeToken: String? = null
    private var detached = false

    init {
        channel.setMethodCallHandler(::onMethodCall)
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "show" -> show(call.arguments, result)
            "cancel" -> {
                val map = call.arguments as? Map<*, *>
                val sessionId = map?.get("sessionId") as? String
                val revision = when (val value = map?.get("revision")) {
                    is Int -> value.toLong()
                    is Long -> value
                    else -> null
                }
                val token = activeToken
                if (token != null && sessionId != null && revision != null && revision >= 0) {
                    EpisodeBrowserRegistry.cancelMatching(token, sessionId, revision)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun show(arguments: Any?, result: MethodChannel.Result) {
        if (!BuildConfig.IS_TV_BUILD) {
            result.error("episode_browser_unavailable", "The component requires the TV build", null)
            return
        }
        if (detached || activity.isFinishing || activity.isDestroyed) {
            result.error("episode_browser_unavailable", "The Flutter activity is no longer available", null)
            return
        }
        val snapshot = try {
            EpisodeBrowserProtocol.parse(arguments)
        } catch (error: IllegalArgumentException) {
            result.error("episode_browser_invalid_snapshot", error.message, null)
            return
        }
        if (EpisodeBrowserRegistry.hasPendingCaller) {
            result.error("episode_browser_busy", "An episode browser request is already pending", null)
            return
        }
        val session = EpisodeBrowserRegistry.open(snapshot) { command ->
            activeToken = null
            result.success(command.toMap())
        }
        activeToken = session.launchToken
        try {
            // Snapshot data stays in memory. A restored process cannot replay this request.
            activity.startActivity(
                Intent(activity, EpisodeBrowserActivity::class.java)
                    .putExtra(EpisodeBrowserActivity.EXTRA_TOKEN, session.launchToken),
            )
        } catch (_: RuntimeException) {
            EpisodeBrowserRegistry.cancel(session.launchToken)
        }
    }

    fun detach() {
        if (detached) return
        detached = true
        activeToken?.let(EpisodeBrowserRegistry::cancel)
        activeToken = null
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val CHANNEL = "com.predidit.kazumi/episode_browser"
    }
}

/** Main-thread, process-local rendezvous; it stores no media or business state. */
internal object EpisodeBrowserRegistry {
    private val coordinator = EpisodeBrowserCoordinator { UUID.randomUUID().toString() }
    private var deliver: ((EpisodeBrowserResult) -> Unit)? = null
    private var browser: WeakReference<Activity>? = null

    val hasPendingCaller: Boolean get() = coordinator.active != null

    fun open(
        snapshot: EpisodeBrowserSnapshot,
        onComplete: (EpisodeBrowserResult) -> Unit,
    ): EpisodeBrowserCoordinator.Session {
        val session = coordinator.open(snapshot)
        deliver = onComplete
        return session
    }

    fun snapshot(token: String): EpisodeBrowserSnapshot? =
        coordinator.active?.takeIf { it.launchToken == token }?.snapshot

    fun bind(token: String, activity: Activity): Boolean {
        if (snapshot(token) == null) return false
        browser = WeakReference(activity)
        return true
    }

    fun select(token: String, revision: Long, opaqueId: String) {
        complete(coordinator.select(token, revision, opaqueId))
    }

    fun cancel(token: String) {
        complete(coordinator.cancel(token))
    }

    fun cancelMatching(token: String, sessionId: String, revision: Long) {
        complete(coordinator.cancelMatching(token, sessionId, revision))
    }

    fun rebuilt(token: String) {
        complete(coordinator.rebuilt(token))
    }

    private fun complete(result: EpisodeBrowserResult?) {
        if (result == null) return
        val callback = deliver
        val oldBrowser = browser?.get()
        deliver = null
        browser = null
        // Clear ownership before notifying Dart or finishing the old Activity.
        try {
            callback?.invoke(result)
        } catch (_: RuntimeException) {
            // A destroyed engine can no longer receive its result. Ownership is
            // already cleared, so the disposable Activity must still close.
        } finally {
            oldBrowser?.finish()
        }
    }
}
