package org.kazumi.tv.playback

import org.json.JSONArray
import org.json.JSONObject

/** Observe a loaded document's bounded inline data, never execute fetched script text. */
object InlinePlayerMetadata {
    val snapshotScript="""
        (function(){
          var nodes=document.querySelectorAll('script:not([src])'),scripts=[],bytes=0;
          if(nodes.length>64)return JSON.stringify({scripts:[]});
          for(var i=0;i<nodes.length;i++) {
            var text=nodes[i].textContent||'';bytes+=text.length;
            if(bytes>262144)return JSON.stringify({scripts:[]});
            scripts.push(text);
          }
          window.__kazumiInlineDocument=document;
          return JSON.stringify({page:location.href,title:document.title||'',scripts:scripts});
        })();
    """.trimIndent()

    fun reference(scripts:JSONArray):Pair<String,String>? {
        if(scripts.length()>64)return null
        var size=0
        var playerScripts=0
        val matches=mutableListOf<Pair<String,String>>()
        for(i in 0 until scripts.length()) {
            val text=scripts.opt(i) as? String ?: return null
            size+=text.length
            if(size>262144)return null
            // Unknown second configurations remain ambiguous, including unsupported syntax.
            // A mention in a comment may conservatively decline this optional fallback.
            if(text.contains("Artplayer") && ++playerScripts>1)return null
            matches+=StaticPlayerMetadata.variableReferences(text).map { it.key to it.value }
            if(matches.size>1)return null
        }
        return matches.singleOrNull()
    }

    fun matchesCurrentScript(name:String,value:String,page:String):String = """
        (function(){try {
          if(window.__kazumiInlineDocument!==document||location.href!==${JSONObject.quote(page)})return false;
          var descriptor=Object.getOwnPropertyDescriptor(window,${JSONObject.quote(name)});
          return !!descriptor&&Object.prototype.hasOwnProperty.call(descriptor,'value')&&
            typeof descriptor.value==='string'&&descriptor.value===${JSONObject.quote(value)};
        }catch(ignored){return false;}})();
    """.trimIndent()
}
