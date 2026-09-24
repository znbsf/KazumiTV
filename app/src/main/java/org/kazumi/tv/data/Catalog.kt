package org.kazumi.tv.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder

data class Subject(val id: Int, val title: String, val cover: String, val summary: String,
    val metadata: SubjectMetadata = SubjectMetadata()) : java.io.Serializable

interface TvCatalog {
    suspend fun detail(id: Int): Subject
    suspend fun popular(tag: String, page: Int = 0): List<Subject>
    fun clearCache()
}

/** Bounded process cache; no account data or playback URLs are persisted here. */
class CatalogRepository : TvCatalog {
    private val cache = ExpiringLruCache<String, List<Subject>>(5, 600_000) { android.os.SystemClock.elapsedRealtime() }
    private val details = ExpiringLruCache<String, Subject>(24, 600_000) { android.os.SystemClock.elapsedRealtime() }
    override fun clearCache() { cache.clear(); details.clear() }
    private fun subject(value: JSONObject) = CatalogCodec.subject(value)
    override suspend fun detail(id: Int): Subject = withContext(Dispatchers.IO) {
        val key="${NetworkSettings.catalogRevision.value}|${NetworkSettings.apiBase}|$id"
        details.get(key) ?: subject(JSONObject(HttpText.requestAsync("${NetworkSettings.apiBase}/v0/subjects/$id"))).also { details.put(key, it) }
    }
    suspend fun search(keyword: String, offset: Int = 0, sort: String = "match"): List<Subject> = withContext(Dispatchers.IO) {
        require(offset >= 0 && offset % 20 == 0 && sort in listOf("match","score"))
        val body = JSONObject().put("keyword", keyword).put("sort", sort).put("filter", JSONObject().put("type", JSONArray().put(2)))
        val root = JSONObject(HttpText.requestAsync("${NetworkSettings.apiBase}/v0/search/subjects?limit=20&offset=$offset", "POST", mapOf("Content-Type" to "application/json"), body.toString()))
        val list = root.getJSONArray("data")
        List(minOf(list.length(), 20)) { subject(list.getJSONObject(it)) }
    }
    override suspend fun popular(tag: String, page: Int): List<Subject> = withContext(Dispatchers.IO) {
        require(page in 0..20)
        val key = "${NetworkSettings.catalogRevision.value}|$tag|$page"
        cache.get(key)?.let { return@withContext it }
        val query = URLEncoder.encode(tag, "UTF-8")
        val text=HttpText.requestAsync("https://api.kazumi.fyi/kazumi/v1/popular/subjects?limit=48&offset=${page * 48}&tag=$query")
        val array=if(text.trimStart().startsWith("[")) JSONArray(text) else JSONObject(text).getJSONArray("data")
        val items=List(minOf(array.length(),48)) { subject(array.getJSONObject(it)) }
        cache.put(key, items)
        items
    }
}
