package org.kazumi.tv.rules

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class SourceThrottleTest {
    private val source = SourceRule(JSONObject().put("name","fixture").put("baseURL","https://example.org/"))
    private fun page(title: String, message: String, container: String = "msg-jump") =
        "<html><title>普通站点标题</title><div class='$container'><div class='window-title'><h2>$title</h2></div><div class='msg-content'><p>$message</p><p>页面自动跳转 等待时间0</p></div></div></html>"
    @Test fun simplifiedAndTraditionalActualSystemPanelsAreRateLimits() {
        for ((title,message) in listOf("系統提示" to "親愛的：請不要頻繁操作，搜索時間間隔爲3秒前", "系统提示" to "亲爱的：请不要频繁操作，搜索时间间隔为3秒前")) {
            val error=assertThrows(SourceRateLimited::class.java) { SourcePageChecks.check(source,page(title,message),source.baseUrl) }
            assertEquals("来源限制了搜索频率，请稍候再重新加载",error.message)
            assertEquals(3000L,error.retryAfterMillis)
        }
    }
    @Test fun matchingWordsInArticleOrWrongPanelAreNotRateLimits() {
        val message="亲爱的：请不要频繁操作，搜索时间间隔为3秒前"
        for (html in listOf(page("系统提示",message,"article"),page("剧情介绍",message),page("系统提示","这部作品讲述了：$message"),"<html><p>$message</p></html>")) {
            assertEquals(html,SourcePageChecks.check(source,html,source.baseUrl))
        }
    }
    @Test fun otherSystemMessagesAreNotMisclassified() {
        for(message in listOf("请输入验证码","搜索结果为空","搜索时间间隔为3秒前","请不要频繁操作")) {
            val html=page("系统提示",message)
            assertEquals(html,SourcePageChecks.check(source,html,source.baseUrl))
        }
    }
    @Test fun rateLimitAfterActionCannotBeVerificationSuccess() {
        val state=VerificationProgress();state.markAction()
        repeat(5) { assertFalse(state.observe(JSONObject().put("ready",true).put("throttled",true))) }
        repeat(2) { assertFalse(state.observe(JSONObject().put("ready",true).put("throttled",false))) }
        assertTrue(state.observe(JSONObject().put("ready",true).put("throttled",false)))
    }
}
