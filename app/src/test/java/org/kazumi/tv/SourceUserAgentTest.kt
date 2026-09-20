package org.kazumi.tv

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.kazumi.tv.rules.SourceRule

class SourceUserAgentTest {
    private fun rule(ua:String="")=SourceRule(JSONObject().put("name","fixture").put("baseURL","https://example.org/").put("userAgent",ua))
    @Test fun unspecifiedIdentityIsStableAcrossRuleReloads() {
        assertEquals(rule().userAgent,rule().userAgent)
        assertTrue(rule().userAgent.contains("AppleWebKit/"))
        assertTrue(rule().userAgent.contains("Chrome/"))
    }
    @Test fun explicitIdentityIsRetainedForEveryStage() {
        val first=rule("Source-required UA")
        assertEquals("Source-required UA",first.userAgent)
        assertEquals(first.userAgent,SourceRule(JSONObject(first.json.toString())).userAgent)
    }
}
