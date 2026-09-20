package org.kazumi.tv

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.kazumi.tv.playback.MediaRequestHeaders
import org.kazumi.tv.rules.SourceRule

class MediaRequestHeadersTest {
    private fun rule(referer: String? = null) = SourceRule(JSONObject().put("name", "fixture")
        .put("baseURL", "https://source.example/").put("userAgent", "configured-session-UA")
        .apply { if (referer != null) put("referer", referer) })
    @Test fun explicitRuleRefererWinsOverBrowserAndMetadataContexts() {
        val source = rule("https://configured.example/")
        val browser = MediaRequestHeaders.forMedia(source,"https://episode.example/12", mapOf("referer" to "https://iframe.example/player", "origin" to "https://iframe.example"))
        val metadata = MediaRequestHeaders.forMedia(source,"https://episode.example/12")
        assertEquals("https://configured.example/",browser["Referer"])
        assertEquals(metadata["Referer"],browser["Referer"])
        assertEquals("https://iframe.example",browser["Origin"])
    }
    @Test fun emptyOrAbsentRuleRefererKeepsCrossOriginIframeContext() {
        for (source in listOf(rule(),rule(""),rule("   "))) {
            val headers = MediaRequestHeaders.forMedia(source,"https://episode.example/12",mapOf("REFERER" to "https://iframe.example/player?id=12"))
            assertEquals("https://iframe.example/player?id=12",headers["Referer"])
        }
    }
    @Test fun metadataUsesActualResponsePageAndStableConfiguredUserAgent() {
        val headers = MediaRequestHeaders.forMedia(rule(),"https://redirected.example/episode/12",mapOf("User-Agent" to "different-browser"))
        assertEquals("https://redirected.example/episode/12",headers["Referer"])
        assertEquals("configured-session-UA",headers["User-Agent"])
    }
    @Test fun cookiesAndUnrelatedHeadersAreNotPinnedAcrossMediaHosts() {
        val headers = MediaRequestHeaders.forMedia(rule(),"https://episode.example/12",mapOf("Cookie" to "fixture=private","Authorization" to "fixture","Range" to "bytes=10-", "Origin" to "https://iframe.example"))
        assertEquals(setOf("User-Agent","Referer","Origin"),headers.keys)
        assertFalse(headers.values.contains("fixture=private"))
    }
}
