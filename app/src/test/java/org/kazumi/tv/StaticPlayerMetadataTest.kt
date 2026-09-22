package org.kazumi.tv

import org.junit.Assert.*
import org.junit.Test
import org.kazumi.tv.playback.PageMediaMetadata

class StaticPlayerMetadataTest {
    private fun extract(script:String)=PageMediaMetadata.extract("<script>$script</script>")
    @Test fun readsTopLevelLiteralDespiteUnavailablePlayerBundleAndNestedCallbacks() {
        val script="""
            function playM3u8(video, url, art) { video.src = url; }
            var art = new Artplayer({container: '.MacPlayer',
                url: 'https://media.example/episode.m3u8?token=a+b%2Fc', type: 'm3u8',
                customType: {m3u8: playM3u8}, setup: function() { return {url:'https://ad.example/a.mp4'}; }
            });
        """.trimIndent()
        assertEquals(listOf("https://media.example/episode.m3u8?token=a+b%2Fc"),extract(script))
        assertEquals(listOf("https://media.example/a.m3u8"),extract("""new Artplayer({"url":"https:\/\/media.example\/a.m3u8"})"""))
    }
    @Test fun ignoresCommentsStringsTemplatesAndRegexPretendingToBeConfiguration() {
        for(script in listOf(
            "// new Artplayer({url:'https://media.example/a.mp4'})",
            "/* new Artplayer({url:'https://media.example/a.mp4'}) */",
            """var text="new Artplayer({url:'https://media.example/a.mp4'})";""",
            "var text=`new Artplayer({url:'https://media.example/a.mp4'})`;",
            """var re=/new Artplayer\({url:'https:\/\/media.example\/a.mp4'}\)/;""",
            "new Artplayer({ /* url:'https://media.example/a.mp4' */ type:'mp4'})"
        ))assertTrue(script,extract(script).isEmpty())
    }
    @Test fun rejectsDynamicValuesOverridesAndNonMediaProtocols() {
        for(properties in listOf(
            "url: source", "url: 'https://media.example/a.mp4' + suffix",
            "url: build('https://media.example/a.mp4')",
            "url: `https://media.example/a.mp4`",
            "url: 'javascript:alert(1)'", "url: 'file:///a.mp4'", "url:'https://media.example/page.html'",
            "url:'https://media.example/a.mp4',url: other",
            "url:'https://media.example/a.mp4',...options",
            "url:'https://media.example/a.mp4',['url']:other",
            "url:'https://media.example/a.mp4',get url(){return other;}",
            "customType:{url:'https://media.example/a.mp4'}"
        ))assertTrue(properties,extract("new Artplayer({$properties})").isEmpty())
        assertTrue(extract("new Artplayer({url:'https://media.example/a.mp4'").isEmpty())
    }
    @Test fun retainsMacCmsCandidateAndDeduplicatesStaticPlayers() {
        assertEquals(listOf("https://media.example/a.mp4","https://media.example/b.m3u8"),extract("""
            var player_x={"url":"https://media.example/a.mp4"};
            new Artplayer({url:'https://media.example/b.m3u8'});
            new Artplayer({url:'https://media.example/b.m3u8'});
        """))
    }
    @Test fun ambiguousJavaScriptAndNestedConstructorsFallBackToWebDiscovery() {
        val config="new Artplayer({url:'https://media.example/a.mp4'})"
        for(script in listOf(
            "var template=`outer ${'$'}{`nested $config`} tail`;",
            "var ratio=left/right; var text=\"/$config\";",
            "var ratio=left/right; $config;",
            "var pattern=/sample/; $config;",
            "<!-- $config;",
            "function unused(){ $config; }",
            "var settings={factory:function(){return $config;}};"
        ))assertTrue(script,extract(script).isEmpty())
        // A preceding completed declaration does not hide the actual top-level configuration.
        assertEquals(listOf("https://media.example/a.mp4"),extract("function ready(){return true;} $config;"))
    }
}
