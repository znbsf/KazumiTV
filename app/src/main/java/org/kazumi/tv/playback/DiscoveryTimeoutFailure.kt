package org.kazumi.tv.playback

/** Preserve uncertainty when neither the preflight request nor the WebView page completed. */
internal object DiscoveryTimeoutFailure {
    fun fromEvidence(preflightUnavailable:Boolean, mainPageFinished:Boolean, candidateCount:Int):MediaResolutionFailure {
        if(preflightUnavailable && !mainPageFinished) {
            return MediaResolutionFailure("网页与媒体发现", "请求或加载等待超时；请检查网络或来源后重试")
        }
        return MediaResolutionFailure("媒体发现", "等待超时，未找到可用媒体（候选 $candidateCount）")
    }
}
