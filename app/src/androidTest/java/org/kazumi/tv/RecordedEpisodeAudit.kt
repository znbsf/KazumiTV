package org.kazumi.tv

import android.app.Instrumentation
import android.os.Bundle
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.jsoup.Jsoup
import org.kazumi.tv.data.HttpText
import org.kazumi.tv.playback.PageMediaMetadata
import org.kazumi.tv.playback.WebMediaResolver
import org.kazumi.tv.rules.RuleStore
import org.kazumi.tv.rules.SourcePageChecks
import org.kazumi.tv.rules.SourceVerificationRequired
import java.io.File
import java.net.URI

/** One previously observed same-origin episode, without solving/replaying a search challenge.
 * Never accepts akianime or an arbitrary parser URL. Any episode-page challenge stops the test. */
object RecordedEpisodeAudit {
    fun run(test:Instrumentation,args:Bundle)=runBlocking {
        val source=requireNotNull(args.getString("source"))
        require(source in setOf("mutefun","mgnacg"))
        val name=requireNotNull(args.getString("episodeFile"))
        require(name.matches(Regex("[A-Za-z0-9_-]+\\.json")))
        val root=requireNotNull(test.targetContext.getExternalFilesDir(null))
        val input=File(root,name)
        require(input.length() in 1..65536)
        val recorded=JSONObject(input.readText())
        val rule=RuleStore(test.targetContext).all().single { it.name==source }
        val url=recorded.getString("url")
        val uri=URI(url);val origin=URI(rule.baseUrl)
        fun effectivePort(value:URI)=if(value.port>=0)value.port else when(value.scheme?.lowercase()) {
            "https" -> 443;"http" -> 80;else -> -1
        }
        fun sameOrigin(value:URI)=value.scheme.equals(origin.scheme,true)&&value.host.equals(origin.host,true)&&
            effectivePort(value)==effectivePort(origin)&&value.userInfo==null
        require(sameOrigin(uri))
        val folder=File(root,"recorded-episode-$source-${System.currentTimeMillis()}").apply { check(mkdirs()) }
        fun report(stage:String,status:String,details:JSONObject=JSONObject()) {
            val row=details.put("source",source).put("stage",stage).put("status",status)
                .put("sample","previously_observed_episode").put("search_verified_this_run",false)
            File(folder,"summary.jsonl").appendText(row.toString()+"\n")
            test.sendStatus(0,Bundle().apply { putString("stream",row.toString()+"\n") })
        }
        var stage="page"
        try {
            val page=withTimeout(30_000) { HttpText.pageAsync(url,headers=mapOf("User-Agent" to rule.userAgent,"Referer" to rule.referer)) }
            File(folder,"page-private.html").writeText(page.body)
            require(sameOrigin(URI(page.url))) { "Recorded page redirected outside the source origin" }
            SourcePageChecks.check(rule,page.body,page.url)
            check(page.status in 200..299)
            report(stage,"received",JSONObject().put("httpStatus",page.status)
                .put("metadataCandidates",PageMediaMetadata.extract(page.body).size)
                .put("iframes",Jsoup.parse(page.body).select("iframe[src]").size))
            stage="resolve"
            val request=withTimeout(75_000) { WebMediaResolver(test.targetContext,privateConsoleDiagnostic={ record ->
                File(folder,"console-private.jsonl").appendText(record.toString()+"\n")
            }).resolve(url,rule,recorded.optString("episode","recorded episode")) }
            report(stage,"resolved",JSONObject().put("mime",request.mimeType))
            stage="play"
            withTimeout(65_000) { FullSourceAudit.play(test,request) { check,status -> report(check,status) } }
            report("done","short_playback_passed")
        } catch(cancelled:kotlinx.coroutines.CancellationException) {
            if(cancelled !is kotlinx.coroutines.TimeoutCancellationException)throw cancelled
            report(stage,"timeout")
        } catch(challenge:SourceVerificationRequired) { report(stage,"needs_manual_verification") }
        catch(error:Exception) {
            report(stage,"failed",JSONObject().put("class",error.javaClass.simpleName))
        }
    }
}
