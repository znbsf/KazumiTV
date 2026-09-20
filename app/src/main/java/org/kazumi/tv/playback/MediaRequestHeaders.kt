package org.kazumi.tv.playback

import org.kazumi.tv.rules.SourceRule

/** Playback headers, distinct from the headers used to fetch source HTML/API pages. */
object MediaRequestHeaders {
    fun forMedia(rule: SourceRule, pageUrl: String, captured: Map<String, String> = emptyMap()): Map<String, String> {
        fun header(name: String) = captured.entries.firstOrNull { it.key.equals(name, true) }?.value
        // Upstream VideoPageController explicitly supplies a nonempty rule Referer
        // to the native player. SourceRule.referer's baseUrl fallback is NOT such
        // an override: without a configured value preserve the actual iframe page.
        val explicitReferer = rule.json.optString("referer").trim().takeIf { it.isNotEmpty() }
        val referer = explicitReferer ?: header("Referer")?.takeIf { it.isNotBlank() } ?: pageUrl
        return linkedMapOf("User-Agent" to rule.userAgent, "Referer" to referer).apply {
            header("Origin")?.let { put("Origin", it) }
        }
        // Never copy Cookie/Authorization or arbitrary page headers. AppHttp's
        // CookieJar selects cookies separately for each actual request target.
    }
}
