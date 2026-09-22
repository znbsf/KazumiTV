package org.kazumi.tv.rules

import java.io.IOException
import java.net.SocketTimeoutException
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test

class ChapterGetTransportTest {
    private val original="http://example.org:80/show/a%2Fb?x=a%2Bb&empty=#ep%2F12"
    private val secure="https://example.org/show/a%2Fb?x=a%2Bb&empty=#ep%2F12"
    private val base="https://example.org/"

    @Test fun retainsRawEncodingQueryFragmentAndOnlyChangesDefaultTransport() {
        assertEquals(secure,ChapterGetTransport.httpsFallback(original,base))
        assertEquals("https://EXAMPLE.org/?#",ChapterGetTransport.httpsFallback("http://EXAMPLE.org/?#","https://example.org:443/base"))
        assertEquals("https://example.org?x=%252F",ChapterGetTransport.httpsFallback("http://example.org?x=%252F",base))
        assertEquals("https://[::1]/a%2Fb#part",ChapterGetTransport.httpsFallback("http://[::1]:80/a%2Fb#part","https://[::1]:443/"))
    }

    @Test fun rejectsAlreadySecureCrossHostCredentialsAndNonstandardPorts() {
        for((url,ruleBase) in listOf(
            "https://example.org/a" to base,
            "http://other.example/a" to base,
            "http://example.org:8080/a" to base,
            "http://example.org/a" to "https://example.org:8443/",
            "http://user@example.org/a" to base,
            "http://example.org/a" to "https://user@example.org/",
            "http://example.org/a" to "http://example.org/",
            "/a" to base,
            "http://example.org.evil/a" to base,
            "http://example.org/%bad space" to base
        ))assertNull(ChapterGetTransport.httpsFallback(url,ruleBase))
    }

    @Test fun firstTransportFailureUpgradesOnceAndVerificationReplayRetainsHttps() = runBlocking {
        val transport=ChapterGetTransport(original,base)
        val seen=mutableListOf<String>()
        suspend fun request(url:String):String {
            seen.add(url)
            if(seen.size==1)throw SocketTimeoutException("fixture")
            return "response"
        }
        assertEquals("response",transport.load(::request))
        assertEquals("response",transport.load(::request))
        assertEquals(listOf(original,secure,secure),seen)
    }

    @Test fun failedHttpsDoesNotLoopOrDowngradeOnLaterExplicitReplay() = runBlocking {
        val transport=ChapterGetTransport(original,base)
        val seen=mutableListOf<String>()
        val failed=IOException("fixture")
        repeat(2) {
            try { transport.load<String> { url -> seen.add(url);throw failed };fail("expected") }
            catch(actual:IOException) { assertSame(failed,actual) }
        }
        assertEquals(listOf(original,secure,secure),seen)
    }

    @Test fun returnedHttpErrorOrChallengeDoesNotUpgradeEvenIfLaterReplayHasIoFailure() = runBlocking {
        for(status in listOf(200,403,429,500)) {
            val transport=ChapterGetTransport(original,base)
            val seen=mutableListOf<String>()
            assertEquals(status,transport.load { url -> seen.add(url);status })
            try { transport.load<Int> { url -> seen.add(url);throw IOException("later replay") };fail("expected") }
            catch(_:IOException) { }
            assertEquals(listOf(original,original),seen)
        }
    }

    @Test fun verificationThrottleAndValidationExceptionsNeverTriggerFallback() = runBlocking {
        for(failure in listOf(SourceVerificationRequired(original),SourceRateLimited(),IllegalStateException("HTTP 503"))) {
            val seen=mutableListOf<String>()
            try { ChapterGetTransport(original,base).load<String> { seen.add(it);throw failure };fail("expected") }
            catch(actual:Exception) { assertSame(failure,actual) }
            assertEquals(listOf(original),seen)
        }
    }

    @Test fun ineligibleHttpIoRemainsSingleRequest() = runBlocking {
        var calls=0
        try { ChapterGetTransport("http://other.example/a",base).load<String> { calls++;throw IOException() };fail("expected") }
        catch(_:IOException) { }
        assertEquals(1,calls)
    }

    @Test fun directCancellationNeverStartsHttps() = runBlocking {
        val seen=mutableListOf<String>()
        val cancelled=CancellationException("fixture")
        try { ChapterGetTransport(original,base).load<String> { seen.add(it);throw cancelled };fail("expected") }
        catch(actual:CancellationException) { assertSame(cancelled,actual) }
        assertEquals(listOf(original),seen)
    }

    @Test fun cancelledSocketReportedAsIoDoesNotStartHttps() = runBlocking {
        val seen=mutableListOf<String>()
        val task=launch(start=CoroutineStart.UNDISPATCHED) {
            ChapterGetTransport(original,base).load<String> { url ->
                seen.add(url)
                currentCoroutineContext().cancel()
                throw IOException("cancelled socket")
            }
        }
        task.join()
        assertTrue(task.isCancelled)
        assertEquals(listOf(original),seen)
    }

    @Test fun fallbackRequestRemainsCancellableWithoutAnotherAttempt() = runBlocking {
        val seen=mutableListOf<String>()
        val entered=CompletableDeferred<Unit>()
        val task=launch {
            ChapterGetTransport(original,base).load<String> { url ->
                seen.add(url)
                if(seen.size==1)throw IOException("fixture")
                entered.complete(Unit)
                awaitCancellation()
            }
        }
        entered.await();task.cancelAndJoin()
        assertEquals(listOf(original,secure),seen)
    }
}
