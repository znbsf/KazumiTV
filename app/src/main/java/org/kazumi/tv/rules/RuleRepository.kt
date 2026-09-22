package org.kazumi.tv.rules

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.kazumi.tv.data.HttpText
import java.net.URI

class RuleRepository(context: Context,
    // Temporary diagnostic rules bypass persistent RuleStore reads and repairs; normal callers use the store.
    rulesOverride: List<SourceRule>? = null,
    private val responseObserver: ((SourceRule, HttpText.Page) -> Unit)? = null
):SourceCatalog {
    private val appContext=context.applicationContext
    override val rules = rulesOverride?.toList() ?: RuleStore(context).enabled()
    private val engine = XPathRuleEngine()
    private val api = ApiRuleEngine()
    override suspend fun search(rule: SourceRule, keyword: String) = withContext(Dispatchers.IO) {
        rule.checkSupported()
        if (rule.json.optString("searchMode") == "api") {
            val config = rule.json.getJSONObject("searchApiConfig")
            val request = api.request(config.getJSONObject("request"), mapOf("keyword" to keyword))
            api.search(config, page(rule,request.url,request.method,headers(rule)+request.headers,request.body))
        } else {
            rule.checkSupported()
            val uri = URI(rule.searchUrl(keyword))
            val url = if (rule.usePost) URI(uri.scheme, uri.authority, uri.path, null, null).toString() else uri.toString()
            engine.search(rule, page(rule,url,if(rule.usePost)"POST" else "GET",headers(rule)+if(rule.usePost)mapOf("Content-Type" to "application/x-www-form-urlencoded") else emptyMap(),if(rule.usePost)uri.rawQuery else null))
        }
    }
    override suspend fun chapters(rule: SourceRule, match: SourceMatch) = withContext(Dispatchers.IO) {
        rule.checkSupported()
        if (rule.json.optString("chapterMode") == "api") {
            val config = rule.json.getJSONObject("chapterApiConfig")
            val request = api.request(config.getJSONObject("request"), mapOf("source" to match.url))
            api.chapters(rule, config, page(rule,request.url,request.method,headers(rule)+request.headers,request.body), match.url)
        } else engine.chapters(rule,page(rule,rule.resolve(match.url),chapterGet=true))
    }
    private suspend fun page(rule:SourceRule,url:String,method:String="GET",requestHeaders:Map<String,String> = headers(rule),body:String?=null,chapterGet:Boolean=false):String {
        val retryBudget = SourceRequestThrottle.RetryBudget()
        val chapterTransport=if(chapterGet && method=="GET" && body==null)ChapterGetTransport(url,rule.baseUrl) else null
        val origin = URI(rule.baseUrl).let { "${it.scheme}://${it.rawAuthority}" }
        suspend fun load():String = SourceRequestThrottle.shared.execute(origin,retryBudget) {
            // Keep response classification outside the IO-only transport fallback.
            val response=chapterTransport?.load { actualUrl -> HttpText.pageAsync(actualUrl,method,requestHeaders,body) }
                ?: HttpText.pageAsync(url,method,requestHeaders,body)
            // Opt-in, instance-local diagnostics observe the actual response without replaying it.
            responseObserver?.let { observer -> runCatching { observer(rule,response) } }
            try { SourcePageChecks.check(rule,response.body,response.url) }
            catch(challenge:SourceVerificationRequired) { throw SourceVerificationRequired(challenge.pageUrl,response.method,if(response.method=="POST")body else null) }
            check(response.status in 200..299) { "服务返回 HTTP ${response.status}" }
            response.body
        }
        return try { load() } catch(challenge:SourceVerificationRequired) {
            if(!AutomaticVerification.run(appContext,rule,challenge.pageUrl,challenge.method,challenge.body))throw challenge
            load()
        }
    }
    private fun headers(rule: SourceRule) = mapOf("User-Agent" to rule.userAgent, "Referer" to rule.referer)
}
