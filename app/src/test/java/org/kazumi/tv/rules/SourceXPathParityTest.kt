package org.kazumi.tv.rules

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class SourceXPathParityTest {
    private fun rule(roads: String, episodes: String) = SourceRule(JSONObject().apply {
        put("name", "parity"); put("baseURL", "https://example.org/"); put("api", "8")
        put("chapterRoads", roads); put("chapterResult", episodes)
        put("searchURL", "https://example.org/search?wd=@keyword")
        put("searchList", "//li"); put("searchName", "(//a/text() | //b/text())[1]"); put("searchResult", ".//a")
    })
    @Test fun ezdmwActualSiblingUnionPreservesAttachedContext() {
        val source = rule("//section[@class='anthology'][1]/div[contains(@class,'line_button')]",
            "/self::*[@class='line_button_ban']/following-sibling::a[@class='circuit_switch_ban'] | /self::*[@class='line_button1']/following-sibling::a[@class='circuit_switch1'] | /self::*[@class='line_button3']/following-sibling::a[@class='circuit_switch3'] | /self::*[@class='line_button2']/following-sibling::a[@class='circuit_switch2']")
        val roads = XPathRuleEngine().chapters(source, """
            <section class='anthology'>
              <div class='line_button_ban'>版权</div><a class='circuit_switch_ban' href='/ban12'>第12集</a>
              <div class='line_button1'>线路1</div><a class='circuit_switch1' href='/a1'>第1集</a><a class='circuit_switch1' href='/a12'>第12集</a>
              <div class='line_button2'>线路2</div><a class='circuit_switch2' href='/b12'>第12集</a>
            </section><section class='anthology'><div class='line_button1'></div><a class='circuit_switch1' href='/outside'>不属于首区</a></section>
        """.trimIndent())
        assertEquals(3, roads.size)
        assertEquals(listOf("https://example.org/ban12"), roads[0].episodes.map { it.pageUrl })
        assertEquals(listOf("https://example.org/a1", "https://example.org/a12"), roads[1].episodes.map { it.pageUrl })
        assertEquals(listOf("https://example.org/b12"), roads[2].episodes.map { it.pageUrl })
    }
    @Test fun aafunBareSlashReturnsOneRootRoadNotEveryNode() {
        val roads = XPathRuleEngine().chapters(rule("//", "//ul[@id='episodes']/li/a"),
            "<aside><a href='/ad'>广告</a></aside><ul id='episodes'><li><a href='/1'>一</a></li><li><a href='/2'>二</a></li></ul>")
        assertEquals(1, roads.size)
        assertEquals(listOf("https://example.org/1", "https://example.org/2"), roads.single().episodes.map { it.pageUrl })
    }
    @Test fun scopedUnionAndDotDescendantDoNotLeakAcrossSearchRows() {
        val matches = XPathRuleEngine().search(rule("//", "//a"),
            "<li><a href='/a'>甲</a></li><li><b>乙</b><a href='/b'></a></li>")
        assertEquals(listOf("甲", "乙"), matches.map { it.title })
        assertEquals(listOf("https://example.org/a", "https://example.org/b"), matches.map { it.url })
    }
    @Test fun slashAndPipeInsideQuotedAttributeAreNotRewritten() {
        val roads = XPathRuleEngine().chapters(rule("//ul", "//a[@data-key='(/|https://x)']"),
            "<ul><a data-key='(/|https://x)' href='/yes'>正确</a><a href='/no'>错误</a></ul>")
        assertEquals("https://example.org/yes", roads.single().episodes.single().pageUrl)
    }
}
