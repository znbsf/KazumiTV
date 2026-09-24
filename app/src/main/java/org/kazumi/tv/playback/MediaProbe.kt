package org.kazumi.tv.playback

object MediaProbe {
    fun mime(bytes: ByteArray, length: Int, type: String): String? {
        if (length <= 0) return null
        val prefix = String(bytes,0,length,Charsets.UTF_8).trimStart('\uFEFF',' ','\n','\r','\t')
        return when {
            prefix.startsWith("<html",true) || prefix.startsWith("<!doctype",true) -> null
            prefix.startsWith("#EXTM3U") -> "application/x-mpegURL"
            prefix.contains("<MPD") -> "application/dash+xml"
            length >= 8 && String(bytes,4,4,Charsets.US_ASCII) == "ftyp" -> "video/mp4"
            length >= 4 && bytes.take(4).map { it.toInt() and 255 } == listOf(26,69,223,163) -> "video/x-matroska"
            type.startsWith("video/") -> type.substringBefore(';')
            else -> null
        }
    }
}

class MediaResolutionFailure(val stage: String, detail: String, val webErrorCode:Int?=null) :
    IllegalStateException("解析失败 · $stage：$detail")
