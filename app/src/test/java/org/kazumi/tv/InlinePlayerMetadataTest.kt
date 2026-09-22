package org.kazumi.tv

import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import org.kazumi.tv.playback.InlinePlayerMetadata

class InlinePlayerMetadataTest {
    private val script="var episode='https://media.example/episode.m3u8';new Artplayer({url:episode});"
    @Test fun acceptsOneAssociatedDeclarationButRejectsTwoDocumentsWorthOfCandidates() {
        assertEquals("episode" to "https://media.example/episode.m3u8",InlinePlayerMetadata.reference(JSONArray(listOf(script))))
        assertNull(InlinePlayerMetadata.reference(JSONArray(listOf(script,script))))
        assertNull(InlinePlayerMetadata.reference(JSONArray(listOf(script,"new Artplayer({url:'https://media.example/ad.mp4'});"))))
        assertNull(InlinePlayerMetadata.reference(JSONArray(listOf(script,"new Artplayer(dynamicOptions);"))))
    }
    @Test fun rejectsOversizedMalformedOrExcessiveScriptCollections() {
        assertNull(InlinePlayerMetadata.reference(JSONArray(List(65) { "" })))
        assertNull(InlinePlayerMetadata.reference(JSONArray(listOf(" ".repeat(262144),script))))
        assertNull(InlinePlayerMetadata.reference(JSONArray().put(42).put(script)))
    }
}
