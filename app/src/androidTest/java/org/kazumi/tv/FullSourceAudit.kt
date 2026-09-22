package org.kazumi.tv

import android.app.Instrumentation
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.TextureView
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import org.kazumi.tv.playback.NativePlayer
import org.kazumi.tv.playback.PlaybackRequest
import org.kazumi.tv.playback.WebMediaResolver
import org.kazumi.tv.rules.*
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Explicit full-list device audit. Output excludes URLs, cookies, page bodies and exception messages. */
object FullSourceAudit {
    fun run(test: Instrumentation, mode: String, nameFilter: String? = null, runName: String = "default", candidateFile: String? = null) = runBlocking {
        require(mode in setOf("source-inventory", "source-import", "source-audit"))
        require(candidateFile == null || mode == "source-audit") { "candidateFile only supported for source-audit" }
        val candidateRule = candidateFile?.let {
            require(!nameFilter.isNullOrBlank() && '|' !in nameFilter) { "candidate requires one explicit source" }
            CandidateRuleFile.read(test.targetContext, it, nameFilter)
        }
        val folder = requireNotNull(test.targetContext.getExternalFilesDir(null))
        val input = candidateRule?.let { JSONArray().put(it.json) }
            ?: JSONArray(File(folder, "source-audit-rules.json").readText())
        val label = runName.replace(Regex("[^A-Za-z0-9_-]"), "_").take(80).ifBlank { "default" }
        val output = File(folder, "source-audit-$label.jsonl")
        fun safe(value: String) = value.replace(Regex("https?://\\S+"), "[url]").replace(Regex("[\\p{Cntrl}]"), " ").take(160)
        fun report(source: String, stage: String, status: String, details: JSONObject = JSONObject()) {
            val row = JSONObject().put("run", label).put("timeMs", System.currentTimeMillis())
                .put("source", safe(source)).put("stage", stage).put("status", status)
            if (candidateRule != null) row.put("candidate", true).put("fixedSnapshotTested", false)
            details.keys().forEach { key -> row.put(key, details.get(key)) }
            output.appendText(row.toString() + "\n")
            test.sendStatus(0, Bundle().apply { putString("stream", row.toString() + "\n") })
        }
        fun failure(source: String, stage: String, error: Exception, road: Int? = null) {
            if (error is CancellationException && error !is TimeoutCancellationException) throw error
            val details = JSONObject().put("class", error.javaClass.simpleName)
            if (road != null) details.put("road", road)
            if(error is org.kazumi.tv.playback.MediaResolutionFailure) details.put("resolutionStage",safe(error.stage))
            // Extract only a status number; never retain arbitrary exception text.
            Regex("HTTP[ :]+([1-5][0-9]{2})", RegexOption.IGNORE_CASE)
                .find(error.message.orEmpty())?.groupValues?.get(1)?.toIntOrNull()?.let { details.put("httpStatus", it) }
            val status = when (error) {
                is SourceVerificationRequired -> "needs_manual_verification"
                is TimeoutCancellationException -> "timeout"
                else -> "failed"
            }
            report(source, stage, status, details)
        }
        val store = RuleStore(test.targetContext)
        val prefs = test.targetContext.getSharedPreferences("tv_rules", Context.MODE_PRIVATE)
        // Back up before even calling all(), which can quarantine malformed imported rules.
        if (mode == "source-import") {
            val backup = JSONObject()
            prefs.all.forEach { (key, value) ->
                backup.put(key, JSONObject().put("type", when (value) {
                    is Set<*> -> "stringSet"; is String -> "string"; is Boolean -> "boolean"
                    is Int -> "int"; is Long -> "long"; is Float -> "float"; else -> "unknown"
                }).put("value", if (value is Set<*>) JSONArray(value.toList()) else value))
            }
            val file = File(folder, "source-audit-rules-backup-${System.currentTimeMillis()}.json")
            file.writeText(backup.toString())
            check(JSONObject(file.readText()).toString() == backup.toString())
            report("", "backup", "saved", JSONObject().put("file", file.name).put("keys", backup.length()))
        }
        val installed = if (candidateRule == null) store.all().associateBy { it.name.lowercase() } else emptyMap()
        val filter = nameFilter?.split('|')?.filter { it.isNotBlank() }?.map { it.lowercase() }?.toSet()
        fun hash(json: JSONObject): String = java.security.MessageDigest.getInstance("SHA-256").digest(json.toString().toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
        val canonical = mutableListOf<SourceRule>()
        for (index in 0 until input.length()) {
            try {
                val rule = SourceRule(input.getJSONObject(index))
                if (filter != null && rule.name.lowercase() !in filter) continue
                canonical += rule
                if (candidateRule != null) {
                    report(rule.name, "candidate_inventory", "loaded_without_import", JSONObject()
                        .put("candidateHash", hash(rule.json)).put("candidateVersion", safe(rule.json.optString("version")))
                        .put("api", safe(rule.json.optString("api"))).put("playbackVerified", false))
                    continue
                }
                val existing = installed[rule.name.lowercase()]
                report(rule.name, "inventory", if (existing == null) "missing" else "installed", JSONObject()
                    .put("enabled", existing?.let { store.isEnabled(it) } ?: JSONObject.NULL)
                    .put("canonicalEqualsInstalled", existing?.json?.toString() == rule.json.toString())
                    .put("canonicalHash", hash(rule.json)).put("installedHash", existing?.let { hash(it.json) } ?: JSONObject.NULL)
                    .put("canonicalVersion", safe(rule.json.optString("version"))).put("installedVersion", safe(existing?.json?.optString("version").orEmpty()))
                    .put("api", safe(rule.json.optString("api")))
                    .put("searchMode", safe(rule.json.optString("searchMode", "xpath"))))
            } catch (error: Exception) { failure("rule-index-$index", "inventory", error) }
        }
        val canonicalNames = (0 until input.length()).mapNotNull { input.optJSONObject(it)?.optString("name")?.lowercase() }.toSet()
        installed.values.filter { it.name.lowercase() !in canonicalNames }.forEach {
            report(it.name, "inventory_extra", "installed_not_canonical", JSONObject().put("enabled", store.isEnabled(it)).put("installedHash", hash(it.json)).put("installedVersion", safe(it.json.optString("version"))))
        }
        if (candidateRule == null) report("", "inventory_summary", "complete", JSONObject().put("canonicalCount", input.length())
            .put("selectedCount", canonical.size).put("installedCount", installed.size))
        else report(candidateRule.name, "candidate_summary", "single_candidate_only", JSONObject().put("selectedCount", canonical.size).put("imported", false))
        if (mode == "source-inventory") return@runBlocking
        if (mode == "source-import") {
            val disabled = prefs.getStringSet("disabled", emptySet()).orEmpty().toSet()
            val hidden = prefs.getStringSet("hidden", emptySet()).orEmpty().toSet()
            for (rule in canonical.filter { it.name.lowercase() !in installed }) {
                try {
                    val result = store.importReport(JSONArray().put(rule.json).toString())
                    report(rule.name, "import", if (result.rules.size == 1) "added" else "rejected",
                        JSONObject().put("importedCount", result.rules.size).put("rejectedCount", result.failures.size))
                } catch (error: Exception) { failure(rule.name, "import", error) }
            }
            check(prefs.edit().putStringSet("disabled", disabled).putStringSet("hidden", hidden).commit())
            check(prefs.getStringSet("disabled", emptySet()) == disabled)
            check(prefs.getStringSet("hidden", emptySet()) == hidden)
            report("", "import_summary", "complete_preserved_disabled_and_hidden")
            return@runBlocking
        }
        // Explicit canonical rules are tested even when disabled or locally customized. Never write library data.
        val repository = RuleRepository(test.targetContext, rulesOverride = candidateRule?.let { listOf(it) })
        val power=test.targetContext.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        fun requireInteractive() {
            if(!power.isInteractive) {
                report("", "device_state", "not_interactive_audit_cancelled")
                throw CancellationException("TV is asleep; device playback evidence is unavailable")
            }
        }
        for (rule in canonical) {
            ensureActive()
            requireInteractive()
            var stage = "search"
            try {
                var matches = emptyList<SourceMatch>()
                var keyword = ""
                for (candidate in listOf("无职转生", "海贼王", "柯南")) {
                    keyword = candidate
                    matches = withTimeout(65_000) { repository.search(rule, candidate) }
                    requireInteractive()
                    report(rule.name, "search", if (matches.isEmpty()) "empty" else "found",
                        JSONObject().put("keyword", candidate).put("count", matches.size))
                    if (matches.isNotEmpty()) break
                }
                if (matches.isEmpty()) { report(rule.name, "source_done", "no_matching_content"); continue }
                val preferred = if (keyword == "无职转生") matches.firstOrNull {
                    it.title.contains("第三季") || it.title.contains("Ⅲ") || Regex("(?i)(?<![a-z])III(?![a-z])").containsMatchIn(it.title)
                } else null
                val match = preferred ?: matches.first()
                stage = "chapters"
                val roads = withTimeout(65_000) { repository.chapters(rule, match) }
                requireInteractive()
                report(rule.name, stage, if (roads.isEmpty()) "empty" else "found", JSONObject()
                    .put("title", safe(match.title)).put("fallbackTitle", preferred == null).put("roads", roads.size))
                for ((roadIndex, road) in roads.withIndex()) {
                    ensureActive()
                    requireInteractive()
                    val episode12 = if (preferred != null) road.episodes.firstOrNull {
                        org.kazumi.tv.domain.EpisodeNumber.parse(it.title) == 12
                    } else null
                    val episode = episode12 ?: road.episodes.firstOrNull()
                    report(rule.name, "road", if (episode == null) "no_episodes" else "selected", JSONObject()
                        .put("road", roadIndex).put("episodeCount", road.episodes.size)
                        .put("episode", safe(episode?.title.orEmpty())).put("fallbackEpisode", episode12 == null))
                    if (episode == null) continue
                    var roadStage = "resolve"
                    try {
                        // Raw console source IDs/messages stay in app-specific external debug
                        // storage. They may contain signed URLs: never put them in report/stream.
                        val sourceLabel=rule.name.replace(Regex("[^A-Za-z0-9_-]"),"_").take(64).ifBlank { "source" }
                        val consoleFile=File(File(folder,"source-audit-private"),"console-$sourceLabel-$label-road$roadIndex-${System.currentTimeMillis()}.jsonl")
                        val request = withTimeout(75_000) {
                            WebMediaResolver(test.targetContext,
                                diagnostic={ message -> report(rule.name,"diagnostic","observed",JSONObject().put("road",roadIndex).put("detail",safe(message))) },
                                privateConsoleDiagnostic={ record ->
                                    consoleFile.parentFile?.mkdirs()
                                    consoleFile.appendText(record.toString()+"\n",Charsets.UTF_8)
                                }).resolve(episode.pageUrl, rule, episode.title)
                        }
                        report(rule.name, "resolve", "resolved", JSONObject().put("road", roadIndex).put("mime", safe(request.mimeType.orEmpty())))
                        roadStage = "play"
                        withTimeout(65_000) { play(test, request) { checkName, status ->
                            report(rule.name, checkName, status, JSONObject().put("road", roadIndex))
                        } }
                        report(rule.name, "road_done", "short_playback_passed", JSONObject().put("road", roadIndex))
                    } catch (error: Exception) { requireInteractive(); failure(rule.name, roadStage, error, roadIndex) }
                }
                report(rule.name, "source_done", "inspected_not_universal_acceptance")
            } catch (error: Exception) { requireInteractive(); failure(rule.name, stage, error); report(rule.name, "source_done", "incomplete") }
        }
        report("", "audit_summary", "finished_see_each_result_not_all_pass", JSONObject().put("selectedCount", canonical.size))
    }

    private suspend fun play(test: Instrumentation, request: PlaybackRequest, report: (String, String) -> Unit) {
        val power=test.targetContext.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        fun requireInteractive() {
            if(!power.isInteractive) {
                report("device_state", "not_interactive_audit_cancelled")
                throw CancellationException("TV is asleep; device playback evidence is unavailable")
            }
        }
        requireInteractive()
        val activity = test.startActivitySync(Intent(test.targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        val rendered = AtomicBoolean()
        val errorCode = AtomicInteger()
        var engine: NativePlayer? = null
        suspend fun await(limit: Long, predicate: () -> Boolean) = withTimeout(limit) {
            while (true) {
                requireInteractive()
                check(errorCode.get() == 0) { "player_error" }
                if (predicate()) break
                delay(100)
            }
        }
        fun position(): Long { var result = 0L; test.runOnMainSync { result = engine!!.player.currentPosition }; return result }
        try {
            test.runOnMainSync {
                activity.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                val view = TextureView(activity)
                activity.setContentView(view)
                engine = NativePlayer(activity, request.url)
                engine!!.player.addListener(object : Player.Listener {
                    override fun onRenderedFirstFrame() { rendered.set(true) }
                    override fun onPlayerError(error: PlaybackException) { errorCode.set(error.errorCode) }
                })
                engine!!.player.setVideoTextureView(view)
                engine!!.open(request)
            }
            await(30_000) { rendered.get() }
            report("first_frame", "passed")
            await(15_000) { position() > 5000 }
            report("playback_advance", "passed")
            var seekable = false
            var duration = C.TIME_UNSET
            test.runOnMainSync { seekable = engine!!.player.isCurrentMediaItemSeekable; duration = engine!!.player.duration }
            if (seekable && (duration == C.TIME_UNSET || duration > 15000)) {
                val target = if (duration == C.TIME_UNSET) 10000 else minOf(60000L, duration / 2)
                test.runOnMainSync { engine!!.player.seekTo(target) }
                await(12_000) { position() >= target + 500 }
                report("seek", "passed")
            } else report("seek", "not_applicable")
            test.runOnMainSync { engine!!.player.pause() }
            val paused = position()
            delay(800)
            check(kotlin.math.abs(position() - paused) < 300) { "pause_moved" }
            test.runOnMainSync { engine!!.player.play() }
            await(8_000) { position() > paused + 1000 }
            report("pause_resume", "passed")
        } finally {
            if (errorCode.get() != 0) report("player_error", "code_${errorCode.get()}")
            test.runOnMainSync { try { engine?.release() } finally { activity.finish() } }
        }
    }
}
