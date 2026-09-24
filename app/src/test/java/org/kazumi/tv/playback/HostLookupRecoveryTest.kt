package org.kazumi.tv.playback

import android.webkit.WebViewClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class HostLookupRecoveryTest {
    private fun hostFailure()=MediaResolutionFailure("网页加载","域名解析失败",WebViewClient.ERROR_HOST_LOOKUP)

    @Test fun oneUserResolveRetriesOnlyHostLookupAndStopsAfterSuccess()=runBlocking {
        var calls=0
        val retries=mutableListOf<Int>()
        val result=HostLookupRecovery.run(hostFailure(),listOf(1,1,1),retry={
            calls++
            if(calls==1)throw hostFailure()
            "recovered"
        },onRetry={ retries.add(it) })
        assertEquals("recovered",result)
        assertEquals(2,calls)
        assertEquals(listOf(1,2),retries)
    }

    @Test fun finiteBudgetAndDifferentFailureDoNotLoop()=runBlocking {
        var calls=0
        try {
            HostLookupRecovery.run(hostFailure(),listOf(1,1),retry={ calls++;throw hostFailure() })
            fail("Unresolved host lookup must surface")
        } catch(failure:MediaResolutionFailure) {
            assertEquals(WebViewClient.ERROR_HOST_LOOKUP,failure.webErrorCode)
        }
        assertEquals(2,calls)
        calls=0
        try {
            HostLookupRecovery.run(hostFailure(),listOf(1,1),retry={
                calls++
                throw MediaResolutionFailure("网页加载","安全连接失败",WebViewClient.ERROR_FAILED_SSL_HANDSHAKE)
            })
            fail("SSL failure must not retry")
        } catch(failure:MediaResolutionFailure) {
            assertEquals(WebViewClient.ERROR_FAILED_SSL_HANDSHAKE,failure.webErrorCode)
        }
        assertEquals(1,calls)
    }

    @Test fun cancelledSelectionStopsBeforeAnotherPageStarts()=runBlocking {
        var calls=0
        val task=launch {
            try {
                HostLookupRecovery.run(hostFailure(),listOf(10_000),retry={ calls++;"stale" })
                fail("Cancelled resolve must not complete")
            } catch(_:CancellationException) { }
        }
        yield()
        withTimeout(1000) { task.cancelAndJoin() }
        assertTrue(task.isCancelled)
        assertEquals(0,calls)
    }
}
