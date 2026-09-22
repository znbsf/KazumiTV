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

    /** Literal bindings only; the caller must additionally compare the live own-data value. */
    fun variableReferences(script:String):Map<String,String> {
        if(script.length>262144)return emptyMap()
        val tokens=lex(script,allowMatchRegex=true)
        if(tokens.isEmpty())return emptyMap()
        fun at(index:Int,text:String)=tokens.getOrNull(index)?.text==text
        val depths=IntArray(tokens.size)
        val stack=mutableListOf<String>()
        for(i in tokens.indices) {
            depths[i]=stack.size
            when(tokens[i].text) {
                "(","[","{" -> stack.add(tokens[i].text)
                ")","]","}" -> {
                    val expected=mapOf(")" to "(","]" to "[","}" to "{")[tokens[i].text]
                    if(stack.lastOrNull()!=expected)return emptyMap()
                    stack.removeAt(stack.lastIndex)
                }
            }
        }
        if(stack.isNotEmpty())return emptyMap()
        val constructors=tokens.indices.filter { at(it,"Artplayer") }
        if(constructors.size!=1)return emptyMap()
        val constructor=constructors.single()-1
        if(constructor<0 || depths[constructor]!=0 || !at(constructor,"new") ||
            !at(constructor+2,"(") || !at(constructor+3,"{"))return emptyMap()
        fun statementStart(index:Int)=index==0 || at(index-1,";") || at(index-1,"}")
        val assigned=constructor>=3 && at(constructor-3,"var") &&
            tokens[constructor-2].text.matches(Regex("[A-Za-z_$][A-Za-z0-9_$]*")) && at(constructor-1,"=") &&
            statementStart(constructor-3)
        if(!statementStart(constructor) && !assigned)return emptyMap()
        var start=constructor+4
        var symbol:String?=null
        var reference=-1
        var closed=false
        for(i in start until tokens.size) {
            val delimiter=(depths[i]==2 && at(i,",")) || (depths[i]==2 && at(i,"}"))
            if(!delimiter)continue
            if(i>start) {
                val key=tokens[start].literal ?: tokens[start].text
                // Only simple property:value entries; accessors, spread and computed keys decline.
                if(!at(start+1,":") || tokens[start].text in listOf(".","["))return emptyMap()
                if(key=="url") {
                    if(symbol!=null || i-start!=3 || tokens[start+2].literal!=null)return emptyMap()
                    symbol=tokens[start+2].text
                    reference=start+2
                }
            }
            if(at(i,"}")) { closed=at(i+1,")") && (i+2==tokens.size || at(i+2,";"));break }
            start=i+1
        }
        val name=symbol ?: return emptyMap()
        if(!closed || !name.matches(Regex("[A-Za-z_$][A-Za-z0-9_$]*")))return emptyMap()
        val declarations=tokens.indices.filter { index ->
            depths[index]==0 && at(index,"var") && at(index+1,name) && at(index+2,"=") &&
                tokens.getOrNull(index+3)?.literal!=null && at(index+4,";") &&
                (index==0 || at(index-1,";") || at(index-1,"}"))
        }
        if(declarations.size!=1)return emptyMap()
        val declaration=declarations.single()
        if(declaration>=constructor)return emptyMap()
        val value=tokens[declaration+3].literal ?: return emptyMap()
        if(value.length !in 1..16384 || !MediaAddress.isMedia(value))return emptyMap()
        val uri=runCatching { java.net.URI(value) }.getOrNull() ?: return emptyMap()
        if(uri.scheme?.lowercase() !in listOf("http","https") || uri.host.isNullOrBlank() || uri.rawUserInfo!=null)return emptyMap()
        for(i in tokens.indices) {
            // Bracket/global property spelling could overwrite the binding indirectly.
            if(tokens[i].literal==name)return emptyMap()
            if(tokens[i].literal!=null || !at(i,name))continue
            if(i==declaration+1 || i==reference)continue
            // The observed media-type check is a pure string read. No other uses are inferred.
            if(i<=declaration || !at(i+1,".") || !at(i+2,"toLowerCase") || !at(i+3,"(") ||
                !at(i+4,")") || !at(i+5,".") || !at(i+6,"indexOf") || !at(i+7,"(") ||
                tokens.getOrNull(i+8)?.literal==null || !at(i+9,")") ||
                at(i-1,".") || at(i-1,"new") || at(i-1,"delete"))return emptyMap()
        }
        return mapOf(name to value)
    }

    private fun lex(source:String,allowMatchRegex:Boolean=false):List<Token> {
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
                c=='/' && allowMatchRegex && result.takeLast(3).map { it.text }==listOf(".","match","(") -> {
                    i++
                    var inClass=false
                    var closed=false
                    while(i<source.length) {
                        val next=source[i++]
                        if(next=='\n'||next=='\r')return emptyList()
                        if(next=='\\') { if(i>=source.length)return emptyList();i++;continue }
                        if(next=='[')inClass=true
                        else if(next==']')inClass=false
                        else if(next=='/'&&!inClass) { closed=true;break }
                    }
                    if(!closed)return emptyList()
                    val flagsStart=i
                    while(i<source.length&&source[i].isLetter())i++
                    val flags=source.substring(flagsStart,i)
                    if(flags.any { it !in "gimuy" } || flags.toSet().size!=flags.length)return emptyList()
                    while(i<source.length&&source[i].isWhitespace())i++
                    if(i>=source.length||source[i]!=')')return emptyList()
                    result.add(Token("regex"))
                }
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
