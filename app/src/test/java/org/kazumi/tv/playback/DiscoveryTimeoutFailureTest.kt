package org.kazumi.tv.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class DiscoveryTimeoutFailureTest {
    @Test fun unavailablePreflightAndUnfinishedWebViewRemainUncertain() {
        val failure=DiscoveryTimeoutFailure.fromEvidence(preflightUnavailable=true,mainPageFinished=false,candidateCount=0)
        assertEquals("网页与媒体发现",failure.stage)
        assertFalse(failure.message.orEmpty().contains("未找到可用媒体"))
        assertFalse(failure.message.orEmpty().contains("域名解析失败"))
    }

    @Test fun loadedWebViewWithNoMediaIsNotClassifiedAsNetworkEvenWhenPreflightFails() {
        val failure=DiscoveryTimeoutFailure.fromEvidence(preflightUnavailable=true,mainPageFinished=true,candidateCount=0)
        assertEquals("媒体发现",failure.stage)
        assertFalse(failure.message.orEmpty().contains("网络连接"))
    }
}
