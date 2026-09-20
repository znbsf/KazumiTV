package org.kazumi.tv.rules

import org.json.JSONObject
import java.net.URI
import java.net.URLEncoder

/** Retains original JSON including fields not executed by this migration yet. */
class SourceRule(val json: JSONObject) {
    val name = json.getString("name")
    val baseUrl = httpUrl(json.getString("baseURL"))
    val userAgent = json.optString("userAgent").ifBlank { DEFAULT_USER_AGENT }
    val referer = json.optString("referer").ifBlank { baseUrl }
    val usePost = json.optBoolean("usePost")
    fun selector(field: String) = json.getString(field).also { require(it.isNotBlank()) { "$field 为空" } }
    fun checkSupported() {
        val api = json.optString("api", "1").toIntOrNull()
        require(api != null && api in 1..8) { "规则 API 版本不兼容（本客户端最高识别 8）" }
        require(listOf("searchMode", "chapterMode").all { json.optString(it).let { mode -> mode.isBlank() || mode in listOf("xpath", "api") } }) {
            "此来源使用不支持的规则模式"
        }
    }
    fun validateImport() {
        require(name.isNotBlank() && name.length <= 80) { "规则名称为空或过长" }
        checkSupported()
        listOf("search", "chapter").forEach { stage ->
            if (json.optString("${stage}Mode") == "api") {
                val config = json.getJSONObject("${stage}ApiConfig")
                ApiRuleEngine().request(config.getJSONObject("request"), mapOf("keyword" to "test", "source" to baseUrl))
                config.keys().forEach { field ->
                    if (field.endsWith("Path") && config.optString(field).isNotBlank()) JsonPath.read(JSONObject(), config.getString(field))
                }
            } else {
                val fields = if (stage == "search") listOf("searchURL", "searchList", "searchName", "searchResult") else listOf("chapterRoads", "chapterResult")
                fields.forEach { require(json.optString(it).isNotBlank()) { "缺少 $it" } }
                if (stage == "search") searchUrl("test")
            }
        }
    }
    fun searchUrl(keyword: String) = httpUrl(json.getString("searchURL").replace("@keyword", URLEncoder.encode(keyword, "UTF-8")))
    fun resolve(url: String) = httpUrl(URI(baseUrl).resolve(url.trim()).toString())
    companion object {
        // Stable browser identity, matching an upstream UA option. HTTP, verification and media
        // requests use the same value; never randomize between challenge and original retry.
        const val DEFAULT_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
        fun httpUrl(url: String): String {
            val uri = URI(url)
            require(uri.scheme in listOf("http", "https") && !uri.host.isNullOrBlank() && uri.userInfo == null) { "来源 URL 无效" }
            return uri.toString()
        }
    }
}

data class SourceMatch(val title: String, val url: String)
data class Episode(val title: String, val pageUrl: String)
data class Road(val title: String, val episodes: List<Episode>)
