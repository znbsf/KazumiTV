package org.kazumi.tv.rules

import org.jsoup.Jsoup
import org.jsoup.helper.W3CDom
import javax.xml.xpath.XPathConstants
import javax.xml.xpath.XPathFactory
import org.w3c.dom.NodeList

class SourceVerificationRequired(val pageUrl: String, val method:String="GET", val body:String?=null) : IllegalStateException("来源需要网页验证，请完成后重试")

class SourceRateLimited(val retryAfterMillis: Long = 3000L) : IllegalStateException("来源限制了搜索频率，请稍候再重新加载")

object SourcePageChecks {
    // Deliberately narrow: a MacCMS system-message panel and its first message,
    // not arbitrary article text mentioning search limits.
    const val THROTTLE_TEXT_PATTERN = "^(?:[亲親][爱愛]的[：:]\\s*)?[请請]不要[频頻]繁操作[，,]?\\s*(?:搜索|搜尋)[时時][间間][间間]隔[为為爲]?\\s*([0-9]{1,4})\\s*秒(?:[后後前])?[。.!！]?$"
    private fun throttleDelay(document: org.jsoup.nodes.Document): Long? = document.select(".msg-jump").firstNotNullOfOrNull { panel ->
        val title = panel.selectFirst(".window-title")?.text()?.trim().orEmpty()
        val message = panel.selectFirst(".msg-content p")?.text()?.trim().orEmpty()
        if (title !in listOf("系统提示", "系統提示")) null
        else Regex(THROTTLE_TEXT_PATTERN).matchEntire(message)?.groupValues?.get(1)?.toLongOrNull()?.times(1000L)
    }
    fun looksLikeChallengeTitle(title: String): Boolean = title.trim().lowercase().let { value ->
        value in listOf("系统安全验证", "安全验证", "人机验证", "just a moment...", "just a moment…", "security verification")
    }
    fun check(rule: SourceRule, html: String, pageUrl: String): String {
        if (!html.trimStart().startsWith("<")) return html
        val doc = Jsoup.parse(html)
        throttleDelay(doc)?.let { throw SourceRateLimited(it) }
        var challenge = looksLikeChallengeTitle(doc.title())
        val config = rule.json.optJSONObject("antiCrawlerConfig")
        if (config?.optBoolean("enabled") == true) {
            val xml by lazy { W3CDom().namespaceAware(false).fromJsoup(doc) }
            fun matchesXPath(expression: String): Boolean = try {
                (XPathFactory.newInstance().newXPath().evaluate(expression, xml, XPathConstants.NODESET) as NodeList).length > 0
            } catch (_: Exception) { throw IllegalArgumentException("验证检测 XPath 无效") }
            val value = config.optString("captchaDetectValue")
            if (value.isNotBlank()) challenge = challenge || when (config.optInt("captchaDetectType",1)) {
                1 -> matchesXPath(value)
                2 -> html.contains(value)
                3 -> try { Regex(value).containsMatchIn(html) } catch (_: Exception) { throw IllegalArgumentException("验证检测正则无效") }
                else -> throw IllegalArgumentException("此规则的验证检测方式尚未适配")
            } else {
                // Upstream XPathRuleStrategy falls back to configured controls when
                // detectValue is absent. Ordinary site titles can still be challenges.
                challenge = challenge || listOf("captchaImage", "captchaButton").any { field ->
                    config.optString(field).trim().let { it.isNotEmpty() && matchesXPath(it) }
                }
            }
        }
        if (challenge) throw SourceVerificationRequired(pageUrl)
        return html
    }
}
