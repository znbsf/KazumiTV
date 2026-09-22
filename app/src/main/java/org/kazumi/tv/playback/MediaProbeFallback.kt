package org.kazumi.tv.playback

/** Match upstream's UA-only playback only after an inferred Referer gets HTTP 400. */
internal object MediaProbeFallback {
    fun headers(status: Int, explicitReferer: String, headers: Map<String, String>): Map<String, String>? {
        if (status != 400 || explicitReferer.isNotBlank()) return null
        if (headers.none { it.key.equals("Referer", true) && it.value.isNotBlank() }) return null
        return headers.filterKeys { !it.equals("Referer", true) && !it.equals("Origin", true) }
    }
}
