package org.kazumi.tv.playback

import org.json.JSONObject
import org.json.JSONTokener
import org.jsoup.Jsoup
import org.kazumi.tv.rules.SourceRule
import okio.ByteString.Companion.decodeBase64

/** MacCMS's published player metadata. Parse data only; never evaluate page JavaScript on the host. */
object PageMediaMetadata {
    fun extract(html:String):List<String> = Jsoup.parse(html).select("script:not([src])").take(64).flatMap { script ->
        val text=script.data()
        val artplayer=StaticPlayerMetadata.extract(text)
        val assignment=Regex("(?:^|[;\\s])(?:var\\s+)?player_[a-zA-Z0-9_]+\\s*=\\s*(?=\\{)").find(text) ?: return@flatMap artplayer
        val mac=runCatching {
            val data=JSONTokener(text.substring(assignment.range.last+1)).nextValue() as JSONObject
            val raw=data.optString("url").takeIf { it.length<=16384 } ?: return@runCatching null
            val value=when(data.optInt("encrypt")) {
                0 -> raw
                1 -> unescape(raw)
                2 -> unescape(raw.decodeBase64()?.utf8() ?: return@runCatching null)
                else -> return@runCatching null
            }
            value.takeIf { MediaAddress.isMedia(it) }?.let(SourceRule::httpUrl)
        }.getOrNull()
        listOfNotNull(mac)+artplayer
    }.distinct().take(8)
    /** JavaScript unescape preserves '+' and decodes percent once (including legacy %uXXXX). */
    private fun unescape(value:String)=Regex("%u([0-9a-fA-F]{4})|%([0-9a-fA-F]{2})").replace(value) {
        (it.groups[1]?.value ?: it.groups[2]!!.value).toInt(16).toChar().toString()
    }
}
