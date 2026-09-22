package org.kazumi.tv.playback

import org.json.JSONTokener
import org.kazumi.tv.rules.SourceRule

/** Reads literal Artplayer configuration only. No JavaScript is evaluated or URL expression guessed. */
internal object StaticPlayerMetadata {
    private data class Token(val text:String, val literal:String?=null)
    fun extract(script:String):List<String> {
        if(script.length>262144)return emptyList()
        val tokens=lex(script)
        val found=mutableListOf<String>()
        var attempts=0
        var nesting=0
        for(i in 0 until (tokens.size-4).coerceAtLeast(0)) {
            if(tokens[i].text in listOf("{","[","("))nesting++
            if(tokens[i].text in listOf("}","]",")"))nesting--
            if(nesting!=0)continue
            if(tokens[i].text!="new"||tokens[i+1].text!="Artplayer"||tokens[i+2].text!="("||tokens[i+3].text!="{")continue
            if(attempts++>=16)break
            var depth=0
            var start=i+4
            var url:String?=null
            var urlCount=0
            var valid=true
            var closed=false
            fun property(end:Int) {
                if(end==start)return
                val key=tokens[start].literal ?: tokens[start].text
                // Spread/computed properties could overwrite a preceding literal URL.
                if(tokens[start].text in listOf(".","[")||tokens.getOrNull(start+1)?.text!=":")valid=false
                if(key=="url") {
                    urlCount++
                    if(end-start==3&&tokens[start+1].text==":"&&tokens[start+2].literal!=null)
                        url=tokens[start+2].literal
                    else valid=false
                }
            }
            for(j in start until tokens.size) {
                val t=tokens[j].text
                if(depth==0&&(t==","||t=="}")) {
                    property(j)
                    if(t=="}") { closed=tokens.getOrNull(j+1)?.text==")";break }
                    start=j+1
                } else if(t in listOf("{","[","("))depth++
                else if(t in listOf("}","]",")")) { depth--;if(depth<0)break }
            }
            if(valid&&closed&&urlCount==1&&url!=null&&url!!.length<=16384) {
                runCatching { url!!.takeIf { MediaAddress.isMedia(it) }?.let(SourceRule::httpUrl) }
                    .getOrNull()?.let { found.add(it) }
            }
            if(found.size>=8)break
        }
        return found.distinct()
    }

    private fun lex(source:String):List<Token> {
        val result=mutableListOf<Token>()
        var i=0
        while(i<source.length) {
            val c=source[i]
            when {
                c.isWhitespace() -> i++
                source.startsWith("//",i) -> { i=source.indexOf('\n',i+2).let { if(it<0)source.length else it+1 } }
                source.startsWith("/*",i) -> { i=source.indexOf("*/",i+2).let { if(it<0)source.length else it+2 } }
                source.startsWith("<!--",i)||source.startsWith("-->",i) -> return emptyList()
                // Distinguishing division from regex and nested template interpolation needs
                // a full JS grammar. Decline this script instead of exposing quoted fake code.
                // The ordinary WebView discovery path remains available.
                c=='`'||c=='/' -> return emptyList()
                c=='\''||c=='"' -> {
                    val begin=i++
                    var closed=false
                    while(i<source.length) {
                        val next=source[i++]
                        if(next=='\\') { if(i<source.length)i++;continue }
                        if(next==c) { closed=true;break }
                        if(next=='\n'||next=='\r')return emptyList()
                    }
                    if(!closed)return emptyList()
                    val literal=runCatching {
                        JSONTokener(source.substring(begin,i)).nextValue() as? String
                    }.getOrNull() ?: return emptyList()
                    result.add(Token("literal",literal))
                }
                c.isLetterOrDigit()||c=='_'||c=='$' -> {
                    val begin=i++
                    while(i<source.length&&(source[i].isLetterOrDigit()||source[i]=='_'||source[i]=='$'))i++
                    result.add(Token(source.substring(begin,i)))
                }
                else -> { result.add(Token(c.toString()));i++ }
            }
        }
        return result
    }
}
