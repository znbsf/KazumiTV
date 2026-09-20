package org.kazumi.tv.rules

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class SourceChallengeFallbackTest {
    private fun rule(config: JSONObject) = SourceRule(JSONObject().put("name", "fixture").put("baseURL", "https://example.org/").put("antiCrawlerConfig", config))
    private fun imageRule() = rule(JSONObject().put("enabled", true).put("captchaType", 1)
        .put("captchaImage", "//img[@class='ds-verify-img']").put("captchaButton", "//button[@class='button verify-submit top20']"))
    @Test fun giriAndMgnOrdinaryTitleImageChallengesAreNotEmptyResults() {
        for (title in listOf("girigiri愛動漫｜高清动漫線上觀看｜彈幕番劇平台", "搜索-橘子动漫")) {
            val page = "<html><head><title>$title</title></head><body><input name='verify'><img class='ds-verify-img' src='/verify'><input type='button' value='提交验证'></body></html>"
            assertThrows(SourceVerificationRequired::class.java) { SourcePageChecks.check(imageRule(), page, "https://example.org/search") }
        }
    }
    @Test fun configuredAutomaticButtonDetectsWithoutSeparateDetectionValue() {
        val source = rule(JSONObject().put("enabled", true).put("captchaType", 2).put("captchaButton", "//button[@id='verify']"))
        assertThrows(SourceVerificationRequired::class.java) { SourcePageChecks.check(source, "<html><button id='verify'>立即验证</button></html>", source.baseUrl) }
    }
    @Test fun normalResultsAndDisabledConfigurationsDoNotFalseMatch() {
        val normal = "<html><title>搜索结果</title><img src='/poster'><button>搜索</button></html>"
        assertEquals(normal, SourcePageChecks.check(imageRule(), normal, "https://example.org/search"))
        val source = imageRule().also { it.json.getJSONObject("antiCrawlerConfig").put("enabled", false) }
        val image = "<html><img class='ds-verify-img'></html>"
        assertEquals(image, SourcePageChecks.check(source, image, source.baseUrl))
    }
    @Test fun explicitDetectionRemainsAuthoritativeOverFallback() {
        val source = imageRule().also { it.json.getJSONObject("antiCrawlerConfig").put("captchaDetectType", 2).put("captchaDetectValue", "CHALLENGE_PRESENT") }
        val page = "<html><img class='ds-verify-img'></html>"
        assertEquals(page, SourcePageChecks.check(source, page, source.baseUrl))
    }
    @Test fun malformedFallbackFailsExplicitlyRatherThanReportingEmptySearch() {
        val source = rule(JSONObject().put("enabled", true).put("captchaImage", "[["))
        assertThrows(IllegalArgumentException::class.java) { SourcePageChecks.check(source, "<html>page</html>", source.baseUrl) }
    }
}
