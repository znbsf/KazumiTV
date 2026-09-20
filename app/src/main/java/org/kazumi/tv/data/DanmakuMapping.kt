package org.kazumi.tv.data

import org.json.JSONObject
import org.kazumi.tv.domain.EpisodeNumber
import java.net.URI

/** Response from the exact bgmtv/{subjectId} endpoint only; never use search results here.
 * Mixed season IDs in the actual episode list require manual selection; a seasons navigation
 * list alone is not evidence that the returned episodes span seasons.
 */
object DanmakuMapping {
    fun automatic(json:String,subjectId:Int,number:Int):DanmakuEpisode? {
        if(subjectId<=0||number<=0)return null
        val root=JSONObject(json)
        if(!root.optBoolean("success",true)||root.optInt("errorCode",0)!=0)return null
        val bangumi=root.optJSONObject("bangumi") ?: return null
        val link=bangumi.optString("bangumiUrl").takeUnless { it=="null" }.orEmpty().trim()
        if(link.isNotEmpty()) {
            val uri=runCatching { URI(link) }.getOrNull() ?: return null
            val host=uri.host?.lowercase()?.removePrefix("www.")
            val linked=Regex("^/subject/(\\d+)/?$").matchEntire(uri.path.orEmpty())?.groupValues?.get(1)?.toIntOrNull()
            if(uri.scheme !in setOf("https","http")||host !in setOf("bgm.tv","bangumi.tv","chii.in")||linked!=subjectId)return null
        }
        val seasons=bangumi.optJSONArray("seasons")
        val episodes=bangumi.optJSONArray("episodes") ?: return null
        if(episodes.length()>20_000)return null
        val rows=(0 until episodes.length()).mapNotNull { episodes.optJSONObject(it) }
        val declared=seasons?.takeIf { it.length()==1 }?.optJSONObject(0)?.optString("id")?.takeUnless { it.isBlank()||it=="null" }
        val episodeSeasons=rows.mapNotNull { it.optString("seasonId").takeUnless { id->id.isBlank()||id=="null" } }.toSet()
        if(episodeSeasons.size>1 || (declared!=null&&episodeSeasons.any { it!=declared }))return null
        val matching=rows.filter {
            val raw=it.optString("episodeNumber")
            // EpisodeNumber also supports full playback labels; API numbers must not borrow a
            // trailing number from a title/season prefix separated by the UI delimiter.
            !raw.contains(" · ")&&EpisodeNumber.parse(raw)==number
        }
        val row=matching.singleOrNull() ?: return null
        val id=row.optLong("episodeId").takeIf { it>0 } ?: return null
        return DanmakuEpisode(id,row.optString("episodeTitle"))
    }
}
