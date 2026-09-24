package org.kazumi.tv

import android.webkit.WebViewClient
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.kazumi.tv.playback.WebLoadFailure

class WebLoadFailureTest {
    @Test fun hostLookupDoesNotClaimCertificateFailureAndKeepsExplicitRetry() {
        val detail=WebLoadFailure.detail(WebViewClient.ERROR_HOST_LOOKUP)
        assertTrue(detail.contains("域名解析失败"))
        assertTrue(detail.contains("重新解析"))
        assertTrue(detail.endsWith("（-2）"))
        assertFalse(detail.contains("证书"))
    }

    @Test fun connectionTimeoutSslAndUnknownCodesRemainDistinctAndBounded() {
        val connection=WebLoadFailure.detail(WebViewClient.ERROR_CONNECT)
        val timeout=WebLoadFailure.detail(WebViewClient.ERROR_TIMEOUT)
        val ssl=WebLoadFailure.detail(WebViewClient.ERROR_FAILED_SSL_HANDSHAKE)
        val unknown=WebLoadFailure.detail(-999)
        assertTrue(connection.contains("无法连接服务器"))
        assertTrue(timeout.contains("连接超时"))
        assertTrue(ssl.contains("安全连接失败"))
        assertTrue(unknown.contains("网页连接失败"))
        assertTrue(listOf(connection,timeout,ssl,unknown).all {
            it.length<80 && (it.contains("重新解析") || it.contains("重试"))
        })
    }
}
