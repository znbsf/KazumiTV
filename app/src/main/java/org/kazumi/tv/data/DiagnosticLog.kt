package org.kazumi.tv.data

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject

/** Memory-only playback diagnostics. Neither raw messages nor media/user identifiers are retained. */
class DiagnosticLog(private val capacity:Int=200, private val byteLimit:Int=64*1024,
                    private val clock:()->Long=System::currentTimeMillis) {
    enum class Kind(val label:String) {
        RESOLVE_START("开始解析"), RESOLVE_SUCCESS("解析成功"), RESOLVE_FAILURE("解析失败"),
        RESOLVE_CANCELLED("解析取消"), VERIFICATION_REQUIRED("需要网页验证"),
        WEB_MODERN("网页提前注入"), WEB_COMPATIBILITY("网页兼容模式"),
        METADATA("已读取页面信息"), INLINE_REFERENCE("当前页面播放器配置"),
        IFRAME_CANDIDATE("尝试播放器子页面"), PROBE_HEADER_RETRY("媒体请求头兼容重试"), PLAYER_ERROR("播放错误")
    }
    enum class Stage { NONE, INITIALIZATION, DISCOVERY, PROBE }
    data class Event(val time:Long,val kind:Kind,val stage:Stage,val code:Int?,val http:Int?) {
        fun json():JSONObject=JSONObject().put("time",time).put("event",kind.name).put("stage",stage.name)
            .apply { code?.let { put("code",it) }; http?.let { put("http",it) } }
    }
    init { require(capacity in 1..200);require(byteLimit in 2048..65536) }
    private val lock=Any()
    private val mutableEvents=MutableStateFlow<List<Event>>(emptyList())
    val events=mutableEvents.asStateFlow()
    private var dropped=0L

    fun record(kind:Kind,stage:Stage=Stage.NONE,code:Int?=null,http:Int?=null) = synchronized(lock) {
        val event=Event(clock().coerceAtLeast(0),kind,stage,code?.takeIf { it in 0..99999 },http?.takeIf { it in 100..599 })
        val rows=(mutableEvents.value+event).toMutableList()
        // Reserve space for JSON punctuation and the fixed, bounded report header.
        var bytes=rows.sumOf { it.json().toString().toByteArray(Charsets.UTF_8).size+1 }
        while(rows.size>capacity || bytes>byteLimit-1024) {
            bytes-=rows.removeAt(0).json().toString().toByteArray(Charsets.UTF_8).size+1
            dropped++
        }
        mutableEvents.value=rows
    }

    /** Exact known grammar only; unmatched diagnostics (including URLs/messages) are discarded. */
    fun resolver(message:String) {
        if(message.length>120)return
        val kind=when {
            message.matches(Regex("page_metadata bytes=[0-9]{1,9}")) -> Kind.METADATA
            message=="web_discovery mode=document_start" -> Kind.WEB_MODERN
            message in setOf("web_discovery mode=compatibility","web_discovery mode=compatibility forced","web_discovery mode=compatibility registration_failed") -> Kind.WEB_COMPATIBILITY
            message.matches(Regex("inline_player_reference depth=[0-2]")) -> Kind.INLINE_REFERENCE
            message.matches(Regex("iframe_fallback depth=[1-2] attempt=[1-3]")) -> Kind.IFRAME_CANDIDATE
            message=="media_probe retry=without_inferred_referer status=400" -> Kind.PROBE_HEADER_RETRY
            else -> return
        }
        record(kind)
    }

    fun clear()=synchronized(lock) { mutableEvents.value=emptyList();dropped=0 }

    fun report(appVersion:String,webViewVersion:String,androidSdk:Int):String=synchronized(lock) {
        fun version(value:String)=value.takeIf {
            it.length<=48 && it.matches(Regex("[0-9]{1,6}(\\.[0-9]{1,6}){1,3}(-preview\\.[0-9]{1,6})?"))
        } ?: "unavailable"
        JSONObject().put("schema",1).put("scope","playback_session_memory")
            .put("appVersion",version(appVersion)).put("webViewVersion",version(webViewVersion))
            .put("androidSdk",androidSdk.takeIf { it in 1..999 } ?: 0)
            .put("dropped",dropped).put("events",JSONArray().apply { mutableEvents.value.forEach { put(it.json()) } })
            .toString().also { check(it.toByteArray(Charsets.UTF_8).size<=byteLimit) }
    }

    companion object {
        val shared=DiagnosticLog()
        fun stage(value:String)=when(value) { "网页初始化" -> Stage.INITIALIZATION;"媒体发现" -> Stage.DISCOVERY;"媒体探测" -> Stage.PROBE;else -> Stage.NONE }
    }
}
