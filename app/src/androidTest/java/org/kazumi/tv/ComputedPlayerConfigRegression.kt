package org.kazumi.tv

import android.content.Context
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlinx.coroutines.*
import org.json.JSONObject
import org.json.JSONTokener
import org.kazumi.tv.playback.ComputedPlayerMetadataScript
import org.kazumi.tv.playback.MediaDiscoveryScript
import org.kazumi.tv.rules.VerificationSession

/** Synthetic own-data objects only. External script tags are inert and all network is intercepted. */
object ComputedPlayerConfigRegression {
    fun run(context: Context): String = runBlocking {
        withContext(Dispatchers.Main) {
            val web=WebView(context)
            try {
                web.settings.javaScriptEnabled=true
                web.webViewClient=object:WebViewClient() {
                    override fun shouldInterceptRequest(view:WebView?,request:WebResourceRequest?):WebResourceResponse =
                        WebResourceResponse("text/plain","UTF-8",byteArrayOf().inputStream())
                }
                suspend fun evaluate(script:String)=VerificationSession.evaluate(web,script)
                val media="https://media.invalid/no-suffix"
                val option="stray.ad={option:{url:stray.url}};"
                fun getter(owner:String,key:String)="Object.defineProperty($owner,${JSONObject.quote(key)},{configurable:true,get:function(){window.getterCalls++;return null;}});"
                val cases=linkedMapOf(
                    "valid" to "",
                    "matching-option" to option,
                    "matching-player-instance" to "function Player(){};stray.ad=new Player();stray.ad.option={url:stray.url};",
                    "root-getter" to getter("window","stray"),
                    "url-getter" to getter("stray","url"),
                    "ad-getter" to getter("stray","ad"),
                    "option-getter" to option+getter("stray.ad","option"),
                    "option-url-getter" to option+getter("stray.ad.option","url"),
                    "config-getter" to getter("window","PlayConfig"),
                    "config-url-getter" to getter("PlayConfig","Url"),
                    "config-path-getter" to getter("PlayConfig","Playpath"),
                    "input-getter" to getter("window","Vurl"),
                    "inherited-url" to "stray=Object.create({url:stray.url});",
                    "inherited-config" to "PlayConfig=Object.create({Url:'input',Playpath:'https://fixture.invalid/Play'});",
                    "array-root" to "var old=stray.url;stray=[];stray.url=old;",
                    "array-config" to "PlayConfig=[];PlayConfig.Url='input';PlayConfig.Playpath='https://fixture.invalid/Play';",
                    "array-option" to "stray.ad={option:[]};stray.ad.option.url=stray.url;",
                    "inherited-option-url" to "stray.ad={option:Object.create({url:stray.url})};",
                    "long-url" to "stray.url='https://media.invalid/'+new Array(20000).join('x');",
                    "input-mismatch" to "PlayConfig.Url='different';",
                    "missing-script" to "document.head.removeChild(document.head.lastChild);",
                    "wrong-directory" to "document.head.innerHTML='<script src=\"https://fixture.invalid/Other/global.min.js\"></script><script src=\"https://fixture.invalid/Other/play.min.js\"></script>';",
                    "script-text-only" to "document.head.innerHTML='<script>/* global.min.js play.min.js */</script>';",
                    "option-conflict" to "stray.ad={option:{url:'https://media.invalid/different'}};",
                    "userinfo" to "stray.url='https://user:pass@media.invalid/no-suffix';",
                    "data-url" to "stray.url='data:video/mp4;base64,AA==';",
                    "changed-input" to "",
                    "changed-path" to ""
                )
                var index=0
                for((name,change) in cases) {
                    index++
                    web.loadDataWithBaseURL("https://fixture.invalid/", "<html><head></head><body>fixture<script>window.fixtureToken=$index;</script></body></html>","text/html","UTF-8",null)
                    withTimeout(8000) {
                        while(evaluate("window.fixtureToken===$index&&document.readyState==='complete'")!="true")delay(50)
                    }
                    evaluate("""
                        window.getterCalls=0;window.readerState={};window.Vurl='input';
                        window.PlayConfig={Url:'input',Playpath:'https://fixture.invalid/Play'};
                        document.head.innerHTML='<script src="https://fixture.invalid/Play/global.min.js"></script><script src="https://fixture.invalid/Play/play.min.js"></script>';
                        window.stray={url:${JSONObject.quote(media)}};
                        $change
                        void 0;
                    """.trimIndent())
                    suspend fun read(now:Int)=evaluate("(${ComputedPlayerMetadataScript.reader})(window,window.readerState,$now)")
                    val first=read(0)
                    check(first=="null") { "computed config emitted before grace period: $name" }
                    check(read(7999)=="null") { "computed config grace period shorter than eight seconds: $name" }
                    if(name=="changed-input")evaluate("window.Vurl='new-input';PlayConfig.Url='new-input';")
                    if(name=="changed-path")evaluate("PlayConfig.Playpath='https://fixture.invalid/Other';document.head.innerHTML='<script src=\"https://fixture.invalid/Other/global.min.js\"></script><script src=\"https://fixture.invalid/Other/play.min.js\"></script>';")
                    val later=read(9000)
                    val expected:Any=if(name in listOf("valid","matching-option","matching-player-instance"))media else JSONObject.NULL
                    if(JSONTokener(later).nextValue()!=expected)return@withContext "computed_player_config=FAIL case=$name observed=$later"
                    check(read(18000)=="null") { "computed config repeated or stale output became eligible: $name" }
                    val getterCalls=evaluate("window.getterCalls")
                    if(getterCalls!="0")return@withContext "computed_player_config=FAIL case=$name getterCalls=$getterCalls"
                }
                // Exercise the real collector: earlier frames must not consume the computed slot.
                index++
                web.loadDataWithBaseURL("https://fixture.invalid/", "<html><head></head><body><script>window.fixtureToken=$index;</script></body></html>","text/html","UTF-8",null)
                withTimeout(8000) {
                    while(evaluate("window.fixtureToken===$index&&document.readyState==='complete'")!="true")delay(50)
                }
                evaluate("""
                    (function(){
                      function resources(w,prefix,count){
                        var entries=[];
                        for(var i=0;i<count;i++)entries.push({initiatorType:'xmlhttprequest',name:'https://fixture.invalid/'+prefix+i});
                        Object.defineProperty(w.performance,'getEntriesByType',{configurable:true,value:function(){return entries;}});
                      }
                      resources(window,'root-',8);
                      for(var i=0;i<3;i++){
                        var frame=document.createElement('iframe');document.body.appendChild(frame);
                        var w=frame.contentWindow;
                        w.document.open();w.document.write('<html><head></head><body>local frame</body></html>');w.document.close();
                        resources(w,'frame-'+i+'-',i<2?8:0);
                      }
                      var target=window.frames[2];
                      target.eval("window.Vurl='input';window.PlayConfig={Url:'input',Playpath:'https://fixture.invalid/Play'};window.stray={url:'https://media.invalid/no-suffix'};");
                      target.document.head.innerHTML='<script src="https://fixture.invalid/Play/global.min.js"></script><script src="https://fixture.invalid/Play/play.min.js"></script>';
                    })();void 0;
                """.trimIndent())
                suspend fun poll():JSONObject=JSONObject(JSONTokener(evaluate(MediaDiscoveryScript.poll)).nextValue().toString())
                val initial=poll()
                check(initial.getJSONArray("speculative").length()==24) { "saturation fixture did not produce 24 preceding resources" }
                evaluate("window.frames[2].__kazumiComputedState.startedAt=Date.now()-9000;window.__kazumiAdd('https://media.invalid/typed.mp4');void 0;")
                val saturated=poll()
                val guesses=saturated.getJSONArray("speculative")
                check(guesses.length()==24) { "computed collector failed bounded saturated output" }
                check((0 until guesses.length()).count {
                    guesses.getJSONObject(it).optBoolean("computed") && guesses.getJSONObject(it).optString("url")==media
                }==1) { "saturated collector lost or duplicated computed candidate" }
                val typed=saturated.getJSONArray("urls")
                check(typed.length()==1 && typed.getJSONObject(0).getString("url")=="https://media.invalid/typed.mp4") {
                    "computed saturation altered independent typed discoveries"
                }
                val repeated=poll().getJSONArray("speculative")
                check((0 until repeated.length()).none { repeated.getJSONObject(it).optBoolean("computed") }) {
                    "computed collector emitted more than once"
                }
                "computed_player_config=PASS cases=${cases.size} grace_period=true own_data_only=true getter_calls=0 changed_input_rejected=true saturated_collector=true network=false"
            } finally { web.stopLoading();web.destroy() }
        }
    }
}
