package org.kazumi.tv.rules

import org.jsoup.Jsoup
import org.jsoup.helper.W3CDom
import org.w3c.dom.Node
import org.w3c.dom.NodeList
import javax.xml.xpath.XPathConstants
import javax.xml.xpath.XPathFactory

/** HTML is parsed as HTML, never as an external-entity-capable XML document. */
class XPathRuleEngine {
    private fun nodes(node: Node, expression: String): List<Node> {
        // xpath_selector 3.0.2 starts every query at the supplied HTML element,
        // including /self:: and // descendant paths. Keep its attached DOM so
        // following-sibling/parent axes work; cloning the row loses those axes.
        val context = if (node is org.w3c.dom.Document) node.documentElement else node
        // Upstream parser yields zero selector steps for bare //, so execute()
        // returns the supplied root unchanged. aafun uses this as its only road.
        if (expression.trim() == "//") return listOf(context)
        val result = XPathFactory.newInstance().newXPath()
            .evaluate(scopedExpression(expression), context, XPathConstants.NODESET) as NodeList
        return List(result.length) { result.item(it) }
    }
    private fun scopedExpression(expression: String): String {
        val result = StringBuilder()
        var quote: Char? = null
        var previous: Char? = null
        expression.forEach { char ->
            if (quote != null) {
                result.append(char)
                if (char == quote) quote = null
            } else {
                if (char == '\'' || char == '"') quote = char
                // Prefix each independent path, including parenthesized unions;
                // don't rewrite URL/string literals or later / path separators.
                if (char == '/' && (previous == null || previous == '(' || previous == '|')) result.append('.')
                result.append(char)
            }
            if (!char.isWhitespace()) previous = char
        }
        return result.toString()
    }
    private fun document(html: String) = W3CDom().namespaceAware(false).fromJsoup(Jsoup.parse(html))
    private fun href(node: Node?): String = node?.attributes?.getNamedItem("href")?.nodeValue.orEmpty().trim()
    fun search(rule: SourceRule, html: String): List<SourceMatch> {
        rule.checkSupported()
        return nodes(document(html), rule.selector("searchList")).mapNotNull { row ->
            val title = nodes(row, rule.selector("searchName")).firstOrNull()?.textContent.orEmpty().trim()
            val link = href(nodes(row, rule.selector("searchResult")).firstOrNull())
            if (title.isBlank() || link.isBlank()) null else runCatching { SourceMatch(title, rule.resolve(link)) }.getOrNull()
        }.distinctBy { it.url }
    }
    fun chapters(rule: SourceRule, html: String): List<Road> {
        rule.checkSupported()
        return nodes(document(html), rule.selector("chapterRoads")).mapNotNull { row ->
            val episodes = nodes(row, rule.selector("chapterResult")).mapNotNull { item ->
                val link = href(item)
                if (link.isBlank()) null else runCatching {
                    Episode(item.textContent.trim().ifBlank { "未命名集数" }, rule.resolve(link))
                }.getOrNull()
            }.distinctBy { it.pageUrl }
            episodes.takeIf { it.isNotEmpty() }
        }.mapIndexed { index, episodes -> Road("播放线路 ${index + 1}", episodes) }
    }
}
