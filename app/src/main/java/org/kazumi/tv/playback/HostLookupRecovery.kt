package org.kazumi.tv.playback

import android.webkit.WebViewClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withTimeoutOrNull

/** One user-started resolve may rebuild its page after a transient host lookup failure. */
internal object HostLookupRecovery {
    private val waitsMs=listOf(750L,1500L,3000L,5000L,7000L)

    suspend fun <T:Any> run(initial:MediaResolutionFailure, waits:List<Long> = waitsMs,
        retry:suspend ()->T, onRetry:(Int)->Unit = {}):T {
        require(initial.webErrorCode==WebViewClient.ERROR_HOST_LOOKUP)
        var last=initial
        val recovered=withTimeoutOrNull(25_000) {
            for((index,pause) in waits.withIndex()) {
                delay(pause)
                currentCoroutineContext().ensureActive()
                onRetry(index+1)
                try { return@withTimeoutOrNull retry() }
                catch(cancelled:CancellationException) { throw cancelled }
                catch(failure:MediaResolutionFailure) {
                    if(failure.webErrorCode!=WebViewClient.ERROR_HOST_LOOKUP)throw failure
                    last=failure
                }
            }
            null
        }
        return recovered ?: throw last
    }
}
