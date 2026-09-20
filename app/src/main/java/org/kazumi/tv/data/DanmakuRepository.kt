package org.kazumi.tv.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.HttpUrl.Companion.toHttpUrl
import okio.ByteString.Companion.toByteString
import org.json.JSONObject
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

data class DanmakuEpisode(val id: Long, val title: String)
data class DanmakuComment(val timeMs: Long, val mode: Int, val color: Int, val text: String)

object DanmakuProtocol {
    fun signature(appId: String, timestamp: Long, path: String, secret: String): String {
        require(path.startsWith('/') && '?' !in path && '#' !in path)
        return MessageDigest.getInstance("SHA-256").digest("$appId$timestamp$path$secret".toByteArray(Charsets.UTF_8)).toByteString().base64()
    }
    fun comments(json: String): List<DanmakuComment> {
        val array = JSONObject(json).getJSONArray("comments")
        return (0 until minOf(array.length(), 30_000)).mapNotNull { index ->
            val item = array.optJSONObject(index) ?: return@mapNotNull null
            val p = item.optString("p").split(',')
            val seconds = p.getOrNull(0)?.toDoubleOrNull() ?: return@mapNotNull null
            val mode = p.getOrNull(1)?.toIntOrNull() ?: return@mapNotNull null
            val color = p.getOrNull(2)?.toIntOrNull() ?: return@mapNotNull null
            val text = item.optString("m").replace(Regex("[\\p{Cc}]"), " ").trim().take(120)
            if (!seconds.isFinite() || seconds !in 0.0..86400.0 || mode !in setOf(1, 4, 5) || color !in 0..0xFFFFFF || text.isEmpty()) return@mapNotNull null
            DanmakuComment((seconds * 1000).toLong(), mode, color or 0xFF000000.toInt(), text)
        }.sortedBy { it.timeMs }
    }
}

class DanmakuRepository(private val credentials: DanmakuCredentials, private val client: OkHttpClient = OkHttpClient.Builder().connectTimeout(10, TimeUnit.SECONDS).readTimeout(15, TimeUnit.SECONDS)
        .callTimeout(25, TimeUnit.SECONDS).followRedirects(false).followSslRedirects(false).build()) {
    suspend fun automaticEpisode(subjectId: Int, number: Int): DanmakuEpisode? = withContext(Dispatchers.IO) {
        if(subjectId<=0||number<=0)return@withContext null
        DanmakuMapping.automatic(get("/api/v2/bangumi/bgmtv/$subjectId"),subjectId,number)
    }
    // Manual redirects ensure signature headers never reach a CDN or another host.
    private val cache = ExpiringLruCache<Long, List<DanmakuComment>>(2, 600_000) { android.os.SystemClock.elapsedRealtime() }
    private suspend fun get(path: String, query: Map<String, String> = emptyMap()): String {
        val timestamp = System.currentTimeMillis() / 1000
        val url = ("https://api.dandanplay.net$path").toHttpUrl().newBuilder().apply { query.forEach { (key, value) -> addQueryParameter(key, value) } }.build()
        var request = Request.Builder().url(url).header("User-Agent", "KazumiTV/0.2")
            .header("X-AppId", credentials.appId).header("X-Timestamp", timestamp.toString())
            .header("X-Signature", DanmakuProtocol.signature(credentials.appId, timestamp, path, credentials.secret)).build()
        repeat(4) {
            val result:Pair<String?,okhttp3.HttpUrl?> = HttpText.exchange(client,request) { response ->
                if (response.code in listOf(301, 302, 303, 307, 308)) {
                    val next = response.header("Location")?.let { request.url.resolve(it) } ?: throw IOException("弹幕跳转地址无效")
                    check(next.isHttps && next.username.isEmpty() && next.password.isEmpty()) { "弹幕服务跳转不受支持" }
                    null to next
                } else {
                    check(response.isSuccessful) { when(response.code) {
                        401, 403 -> "弹幕鉴权失败（${response.code}），请检查凭证、审核状态与电视时间"
                        429 -> "弹幕请求过于频繁，请稍后重试"
                        else -> "弹幕服务返回 HTTP ${response.code}"
                    } }
                    BoundedText.read(response.body!!.charStream(),8_000_000) to null
                }
            }
            result.first?.let { return it }
            request=Request.Builder().url(result.second!!).header("User-Agent", "KazumiTV/0.2").build()
        }
        throw IOException("弹幕服务跳转次数过多")
    }
    suspend fun search(title: String): List<DanmakuEpisode> = withContext(Dispatchers.IO) {
        require(title.trim().length >= 2) { "请输入至少两个字的番剧名称" }
        val root = JSONObject(get("/api/v2/search/episodes", mapOf("anime" to title.trim(), "v2" to "true")))
        check(root.optBoolean("success", true) && root.optInt("errorCode") == 0) { "弹幕搜索未成功，请检查凭证和搜索词" }
        val animes = root.optJSONArray("animes") ?: return@withContext emptyList()
        buildList {
            for (i in 0 until minOf(animes.length(), 30)) {
                val anime = animes.getJSONObject(i); val episodes = anime.optJSONArray("episodes") ?: continue
                for (j in 0 until minOf(episodes.length(), 200)) {
                    val episode = episodes.getJSONObject(j)
                    val id = episode.optLong("episodeId")
                    if (id > 0 && size < 500) add(DanmakuEpisode(id, anime.optString("animeTitle") + " · " + episode.optString("episodeTitle")))
                }
            }
        }
    }
    suspend fun comments(id: Long): List<DanmakuComment> = withContext(Dispatchers.IO) {
        require(id > 0)
        cache.get(id) ?: DanmakuProtocol.comments(get("/api/v2/comment/$id", mapOf("withRelated" to "true"))).also { cache.put(id, it) }
    }
}
