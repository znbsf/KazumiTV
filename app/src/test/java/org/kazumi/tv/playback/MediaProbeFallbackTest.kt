package org.kazumi.tv.playback

import org.junit.Assert.*
import org.junit.Test

class MediaProbeFallbackTest {
    private val inferred = mapOf("rEfErEr" to "https://fixture.invalid/page", "ORIGIN" to "https://fixture.invalid", "User-Agent" to "fixture-agent")
    @Test fun onlyInferredContextIsRemovedAfter400() {
        val retry = MediaProbeFallback.headers(400, "", inferred)!!
        assertEquals(mapOf("User-Agent" to "fixture-agent"), retry)
        assertNull(MediaProbeFallback.headers(400, "", retry))
        assertEquals(3, inferred.size)
    }
    @Test fun configuredRefererIsNeverRemoved() {
        assertNull(MediaProbeFallback.headers(400, "https://fixture.invalid/required", inferred))
    }
    @Test fun otherHttpStatusesNeverRetry() {
        for (status in listOf(200, 206, 301, 401, 403, 404, 416, 429, 500)) {
            assertNull(MediaProbeFallback.headers(status, "", inferred))
        }
    }
    @Test fun missingOrBlankRefererCannotTriggerRetry() {
        assertNull(MediaProbeFallback.headers(400, "", mapOf("Origin" to "https://fixture.invalid")))
        assertNull(MediaProbeFallback.headers(400, "", mapOf("Referer" to " ")))
    }
}
