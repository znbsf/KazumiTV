package org.kazumi.tv

import org.junit.Assert.*
import org.junit.Test
import org.kazumi.tv.playback.StaticPlayerMetadata

class StaticPlayerVariableReferencesTest {
    private val media="https://media.invalid/episode.m3u8?token=fixture"
    private fun script(before:String="",options:String="url: Vurl",after:String="")=
        "$before var Vurl='$media'; var art=new Artplayer({$options}); $after"
    private fun parse(value:String)=StaticPlayerMetadata.variableReferences(value)

    @Test fun literalBindingAndPureReadSurviveTheObservedRegex() {
        val text=script("var mobile=navigator.userAgent.match(/Android|[a-z\\/]Phone/i)!=null;",
            "url:Vurl, type:'m3u8', callback:function(){return true;}")
            .replace("var art=", "var kind=Vurl.toLowerCase().indexOf('.m3u8')>-1; var art=")
        assertEquals(mapOf("Vurl" to media),parse(text))
        assertTrue(StaticPlayerMetadata.extract(text).isEmpty())
    }

    @Test fun commentsAndRegexCannotInjectAConstructor() {
        assertEquals(mapOf("Vurl" to media),parse(script("/* new Artplayer({url:Bad}); */")))
        assertTrue(parse("var x='new Artplayer({url:Vurl})'; var Vurl='$media';").isEmpty())
        assertTrue(parse("var x=navigator.userAgent.match(/new Artplayer({url:Vurl})/); var Vurl='$media';").isEmpty())
    }

    @Test fun ambiguousSlashAndMalformedRegexDecline() {
        for(prefix in listOf("var n=8/2;", "var n=/fake/;", "var n=x.match(/broken[)/);",
            "var n=x.match(/abc/ii);", "var n=x.match(/abc/g,other);"))
            assertTrue(prefix,parse(script(prefix)).isEmpty())
    }

    @Test fun mutationAndUnknownReferencesDecline() {
        for(after in listOf("Vurl='other';", "Vurl+='x';", "Vurl++;", "var Vurl='other';",
            "window.Vurl='other';", "window['Vurl']='other';", "consume(Vurl);",
            "var alias=Vurl;", "function changed(Vurl){return true;}"))
            assertTrue(after,parse(script(after=after)).isEmpty())
    }

    @Test fun ambiguousOrOverriddenConfigurationDeclines() {
        for(options in listOf("url:Vurl,url:Vurl", "url:Vurl,...extra", "url:Vurl,[key]:other",
            "url:Vurl+'extra'", "get url(){return Vurl;}", "url:other"))
            assertTrue(options,parse(script(options=options)).isEmpty())
        assertTrue(parse(script(after="new Artplayer({url:'https://media.invalid/ad.mp4'});")).isEmpty())
        assertTrue(parse(script().replace("new Artplayer", "new UnknownPlayer")).isEmpty())
    }

    @Test fun onlyEarlierStandaloneTopLevelDeclarationQualifies() {
        assertTrue(parse("new Artplayer({url:Vurl}); var Vurl='$media';").isEmpty())
        assertTrue(parse("function hidden(){${script()}}").isEmpty())
        assertTrue(parse(script().replace("var Vurl=", "var other=1,Vurl=")).isEmpty())
        assertTrue(parse(script().replace("var Vurl=", "if(ok)var Vurl=")).isEmpty())
        assertTrue(parse(script().replace("var Vurl=", "let Vurl=")).isEmpty())
    }

    @Test fun addressesAndSizeAreBounded() {
        for(value in listOf("https://user:pass@media.invalid/a.m3u8", "data:video/mp4,abc",
            "https://media.invalid/opaque", "https://media.invalid/"+"a".repeat(16400)+".m3u8"))
            assertTrue(parse(script().replace(media,value)).isEmpty())
        assertTrue(parse(" ".repeat(262145)+script()).isEmpty())
    }

    @Test fun legacyLiteralExtractionRemainsUnchanged() {
        assertEquals(listOf(media),StaticPlayerMetadata.extract("new Artplayer({url:'$media'});"))
        assertTrue(StaticPlayerMetadata.extract("var x=y.match(/ok/); new Artplayer({url:'$media'});").isEmpty())
        assertTrue(parse("new Artplayer({url:'$media'});").isEmpty())
    }
}
