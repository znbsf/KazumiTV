package org.kazumi.tv.rules

import java.io.IOException
import java.net.URI
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/** One non-API chapter GET. A returned response (including an HTTP error/challenge)
 * consumes the fallback opportunity; only the initial transport IOException can upgrade.
 * Retain the effective URL so verification/throttle replays use the same actual request.
 */
internal class ChapterGetTransport(originalUrl:String,ruleBaseUrl:String) {
    private var effectiveUrl=originalUrl
    private var firstRequest=true
    private val upgrade=httpsFallback(originalUrl,ruleBaseUrl)

    suspend fun <T> load(request:suspend(String)->T):T {
        currentCoroutineContext().ensureActive()
        val fallback=if(firstRequest)upgrade else null
        firstRequest=false
        return try { request(effectiveUrl) }
        catch(cancelled:CancellationException) { throw cancelled }
        catch(failure:IOException) {
            // A cancelled socket can surface as IOException. Never start another request.
            currentCoroutineContext().ensureActive()
            if(fallback==null)throw failure
            effectiveUrl=fallback
            request(effectiveUrl)
        }
    }

    companion object {
        fun httpsFallback(originalUrl:String,ruleBaseUrl:String):String? {
            val original=runCatching { URI(originalUrl) }.getOrNull() ?: return null
            val base=runCatching { URI(ruleBaseUrl) }.getOrNull() ?: return null
            if(!original.scheme.equals("http",true) || !base.scheme.equals("https",true))return null
            if(original.rawUserInfo!=null || base.rawUserInfo!=null)return null
            if(original.port !in listOf(-1,80) || base.port !in listOf(-1,443))return null
            val host=original.host?.takeIf { it.isNotBlank() } ?: return null
            if(!host.equals(base.host,true))return null
            val authority=original.rawAuthority ?: return null
            val targetAuthority=if(original.port==80)authority.substringBeforeLast(':') else authority
            // URI's component constructor would double-encode existing percent escapes.
            return "https://"+targetAuthority+original.rawPath.orEmpty()+
                (original.rawQuery?.let { "?$it" } ?: "")+(original.rawFragment?.let { "#$it" } ?: "")
        }
    }
}
