package org.kazumi.tv.rules

import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test

class SourceRequestThrottleTest {
    @Test fun explicitLimitRetriesExactClosureOnceAndNormalEmptyNeverWaits() = runBlocking {
        var time=0L;val waits=mutableListOf<Long>();var calls=0
        val throttle=SourceRequestThrottle({time}) { waits+=it;time+=it }
        val body="keyword=example&value=unchanged"
        val result=throttle.execute("source",SourceRequestThrottle.RetryBudget()) { calls++;if(calls==1)throw SourceRateLimited(3000);body }
        assertEquals(body,result);assertEquals(2,calls);assertEquals(listOf(3250L),waits)
        waits.clear()
        assertEquals("",throttle.execute("source",SourceRequestThrottle.RetryBudget()) { "" })
        assertTrue(waits.isEmpty())
    }
    @Test fun secondLimitStopsAndSharesKnownCooldownOnlyWithSameOrigin() = runBlocking {
        var time=0L;val waits=mutableListOf<Long>();var calls=0
        val throttle=SourceRequestThrottle({time}) { waits+=it;time+=it }
        try { throttle.execute("source",SourceRequestThrottle.RetryBudget()) { calls++;throw SourceRateLimited(3000) };fail("expected") }
        catch(_:SourceRateLimited) { }
        assertEquals(2,calls);assertEquals(listOf(3250L),waits)
        waits.clear()
        throttle.execute("other",SourceRequestThrottle.RetryBudget()) { "ok" }
        assertTrue(waits.isEmpty())
        throttle.execute("source",SourceRequestThrottle.RetryBudget()) { "ok" }
        assertEquals(listOf(3250L),waits)
    }
    @Test fun excessiveDelaysAndUnrelatedFailuresDoNotRetry() = runBlocking {
        var pauses=0;var calls=0
        val throttle=SourceRequestThrottle({0}) { pauses++ }
        for (failure in listOf(SourceRateLimited(60_000),IllegalStateException("HTTP 500"),SourceVerificationRequired("https://example.org"))) {
            try { throttle.execute("source",SourceRequestThrottle.RetryBudget()) { calls++;throw failure };fail("expected") }
            catch(actual:Exception) { assertSame(failure,actual) }
        }
        assertEquals(3,calls);assertEquals(0,pauses)
    }
    @Test fun onePageBudgetAlsoCoversPostVerificationReload() = runBlocking {
        var time=0L;var calls=0
        val throttle=SourceRequestThrottle({time}) { time+=it }
        val budget=SourceRequestThrottle.RetryBudget()
        throttle.execute("source",budget) { calls++;if(calls==1)throw SourceRateLimited();"verified" }
        try { throttle.execute("source",budget) { calls++;throw SourceRateLimited() };fail("expected") }
        catch(_:SourceRateLimited) { }
        assertEquals(3,calls)
    }
    @Test fun cancellationDuringCooldownDoesNotSendRetry() = runBlocking {
        var calls=0
        val throttle=SourceRequestThrottle()
        val result=withTimeoutOrNull(50) { throttle.execute("source",SourceRequestThrottle.RetryBudget()) { calls++;throw SourceRateLimited() } }
        assertNull(result);assertEquals(1,calls)
    }
}
