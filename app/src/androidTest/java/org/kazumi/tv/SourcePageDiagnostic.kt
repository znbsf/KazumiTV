package org.kazumi.tv

import android.app.Instrumentation
import android.os.Bundle
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import org.jsoup.Jsoup
import org.kazumi.tv.data.HttpText
import org.kazumi.tv.playback.PageMediaMetadata
import org.kazumi.tv.playback.WebMediaResolver
import org.kazumi.tv.rules.*
import java.io.File
import java.net.URI

/** Opt-in diagnostic: raw pages stay in the app-specific directory, never instrumentation output. */
object SourcePageDiagnostic {
    fun run(test: Instrumentation, args: Bundle) = runBlocking {
        val source = requireNotNull(args.getString("source")) { "source required" }
        val rule = RuleStore(test.targetContext).all().firstOrNull { it.name.equals(source, true) }
            ?: error("source missing")
        val keyword = args.getString("keyword") ?: "无职转生"
        val label = rule.name.replace(Regex("[^A-Za-z0-9_-]"), "_").take(60)
        val folder = File(test.targetContext.getExternalFilesDir(null), "source-page-diagnostic-$label-${System.currentTimeMillis()}")
        check(folder.mkdirs())
        File(folder, "rule.json").writeText(rule.json.toString())
        fun safe(value: String) = value.replace(Regex("https?://\\S+"), "[url]").replace(Regex("[\\p{Cntrl}]"), " ").take(100)
        fun report(stage: String, status: String, details: JSONObject = JSONObject()) {
            val row = JSONObject().put("source", safe(rule.name)).put("stage", stage).put("status", status)
            details.keys().forEach { row.put(it, details.get(it)) }
            File(folder, "summary.jsonl").appendText(row.toString() + "\n")
            test.sendStatus(0, Bundle().apply { putString("stream", row.toString() + "\n") })
        }
        fun failure(stage: String, error: Exception) {
            if (error is CancellationException && error !is TimeoutCancellationException) throw error
            val details = JSONObject().put("class", error.javaClass.simpleName)
            Regex("HTTP[ :]+([1-5][0-9]{2})", RegexOption.IGNORE_CASE).find(error.message.orEmpty())
                ?.groupValues?.get(1)?.toIntOrNull()?.let { details.put("httpStatus", it) }
            report(stage, when (error) {
                is SourceVerificationRequired -> "needs_manual_verification"
                is TimeoutCancellationException -> "timeout"
                else -> "failed"
            }, details)
        }
        fun savePage(stage: String, page: HttpText.Page, request: ApiRequest) {
            File(folder, "$stage.html").writeText(page.body)
            File(folder, "$stage-private.json").writeText(JSONObject()
                .put("requestedUrl", request.url).put("requestedMethod", request.method).put("requestedBody", request.body)
                .put("responseUrl", page.url).put("responseMethod", page.method).put("status", page.status).toString())
            report(stage, "received", JSONObject().put("httpStatus", page.status).put("bytes", page.body.toByteArray().size)
                .put("title", safe(Jsoup.parse(page.body).title())).put("redirected", page.url != request.url))
            try { SourcePageChecks.check(rule, page.body, page.url); report("${stage}_check", "clear") }
            catch (error: Exception) { failure("${stage}_check", error) }
        }
        report("storage", "created", JSONObject().put("directory", folder.name))
        var stage = "search"
        try {
            val api = ApiRuleEngine()
            val headers = mapOf("User-Agent" to rule.userAgent, "Referer" to rule.referer)
            val isApi = rule.json.optString("searchMode") == "api"
            val request = if (isApi) api.request(rule.json.getJSONObject("searchApiConfig").getJSONObject("request"), mapOf("keyword" to keyword))
                else {
                    val uri = URI(rule.searchUrl(keyword))
                    if (rule.usePost) ApiRequest(URI(uri.scheme, uri.authority, uri.path, null, null).toString(), "POST",
                        mapOf("Content-Type" to "application/x-www-form-urlencoded"), uri.rawQuery)
                    else ApiRequest(uri.toString(), "GET", emptyMap(), null)
                }
            val page = withTimeout(60_000) { HttpText.pageAsync(request.url, request.method, headers + request.headers, request.body) }
            savePage(stage, page, request)
            val matches = if (isApi) api.search(rule.json.getJSONObject("searchApiConfig"), page.body)
                else XPathRuleEngine().search(rule, page.body)
            report("search_parse", "complete", JSONObject().put("engine", if (isApi) "api" else "xpath").put("count", matches.size))
            if (matches.isEmpty()) { report("done", "search_empty_see_private_page"); return@runBlocking }
            val match = matches.firstOrNull { keyword == "无职转生" && it.title.contains("第三季") } ?: matches.first()
            File(folder, "matches-private.json").writeText(JSONArray(matches.map { JSONObject().put("title", it.title).put("url", it.url) }).toString())
            stage = "chapters"
            val roads = withTimeout(65_000) { RuleRepository(test.targetContext).chapters(rule, match) }
            report(stage, "complete", JSONObject().put("roads", roads.size))
            File(folder, "roads-private.json").writeText(JSONArray(roads.map { road -> JSONObject().put("title", road.title)
                .put("episodes", JSONArray(road.episodes.map { JSONObject().put("title", it.title).put("url", it.pageUrl) })) }).toString())
            val roadIndex = args.getString("road")?.toIntOrNull() ?: 0
            val road = roads.getOrNull(roadIndex)
            if (road == null) { report("episode", "road_missing"); return@runBlocking }
            val episode = road.episodes.firstOrNull { Regex("(?:第)?0?12(?:集|话|$)").containsMatchIn(it.title) }
                ?: road.episodes.firstOrNull()
            if (episode == null) { report("episode", "empty"); return@runBlocking }
            stage = "episode_page"
            val episodeRequest = ApiRequest(episode.pageUrl, "GET", headers, null)
            val episodePage = withTimeout(60_000) { HttpText.pageAsync(episodeRequest.url, headers = headers) }
            savePage(stage, episodePage, episodeRequest)
            val document = Jsoup.parse(episodePage.body, episodePage.url)
            val candidates = PageMediaMetadata.extract(episodePage.body)
            val frames = document.select("iframe[src]").map { it.absUrl("src") }
            File(folder, "media-private.json").writeText(JSONObject().put("candidates", JSONArray(candidates)).put("iframes", JSONArray(frames)).toString())
            report("media_metadata", "complete", JSONObject().put("candidates", candidates.size).put("iframes", frames.size)
                .put("road", roadIndex).put("episode", safe(episode.title)))
            if (args.getString("diagnosticResolve") == "true") {
                stage = "resolve"
                // Resolver diagnostic messages may include request context; emit only a fixed allowlist.
                val resolved = withTimeout(75_000) { WebMediaResolver(test.targetContext, diagnostic = { message ->
                    val tag = when {
                        message.startsWith("metadata") -> "metadata_event"
                        message.startsWith("sorani") -> "sorani_event"
                        message.startsWith("webview") -> "webview_event"
                        else -> "resolver_event"
                    }
                    report("resolve_trace", tag)
                }).resolve(episode.pageUrl, rule, episode.title) }
                File(folder, "resolved-private.json").writeText(JSONObject().put("url", resolved.url).put("headers", JSONObject(resolved.headers)).put("mime", resolved.mimeType).toString())
                report(stage, "resolved_not_playback_test", JSONObject().put("mime", safe(resolved.mimeType.orEmpty())))
            }
            report("done", "diagnostic_complete_not_playback_acceptance")
        } catch (error: Exception) { failure(stage, error) }
    }
}
