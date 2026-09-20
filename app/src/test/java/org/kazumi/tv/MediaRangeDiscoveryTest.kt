package org.kazumi.tv

import org.junit.Assert.*
import org.junit.Test
import org.kazumi.tv.playback.WebMediaResolver

class MediaRangeDiscoveryTest {
    @Test fun extensionlessRangeFromCrossOriginFrameIsCandidate() {
        assertTrue(WebMediaResolver.isMediaCandidate("https://media.example/stream?id=12", mapOf("range" to "bytes=0-")))
        assertTrue(WebMediaResolver.isMediaCandidate("https://media.example/stream?id=12", mapOf("Range" to "bytes=0-1023")))
    }
    @Test fun rangeDoesNotPromotePageScriptsOrImagesIncludingQueryStrings() {
        for (path in listOf("/code.js?v=12", "/page.html", "/image.png?sig=abc", "/font.woff2", "/data.json")) {
            assertFalse(path, WebMediaResolver.isMediaCandidate("https://media.example$path", mapOf("Range" to "bytes=0-")))
        }
    }
    @Test fun unmarkedRequestsAndNonHttpSchemesAreNotCandidates() {
        assertFalse(WebMediaResolver.isMediaCandidate("https://media.example/stream", emptyMap()))
        assertFalse(WebMediaResolver.isMediaCandidate("https://media.example/stream", mapOf("Range" to "invalid")))
        assertFalse(WebMediaResolver.isMediaCandidate("file:///stream", mapOf("Range" to "bytes=0-")))
        assertFalse(WebMediaResolver.isMediaCandidate("https://user:password@media.example/stream", mapOf("Range" to "bytes=0-")))
    }
    @Test fun ordinaryMediaDiscoveryDoesNotRequireRange() {
        assertTrue(WebMediaResolver.isMediaCandidate("https://media.example/movie.m3u8?sig=abc", emptyMap()))
    }
}
