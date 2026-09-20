package org.kazumi.tv.rules

import org.json.JSONObject

/** Rule scripts run inside the source page, with no native JavaScript bridge. ES5 for TV WebView 66. */
object VerificationScript {
    fun poll(rule:SourceRule):String {
        val config=rule.json.optJSONObject("antiCrawlerConfig")?.takeIf { it.optBoolean("enabled") }?.let {
            JSONObject(it.toString()).put("captchaType",it.optInt("captchaType",1)).put("captchaDetectType",it.optInt("captchaDetectType",1))
        } ?: JSONObject()
        return """
        (function(){
          var c=$config;
          var s=window.__kazumiVerification;
          if(!s)s=window.__kazumiVerification={acted:false,done:false,failed:false,focused:false,script:false};
          function node(x){return x?document.evaluate(x,document,null,XPathResult.FIRST_ORDERED_NODE_TYPE,null).singleNodeValue:null;}
          try {
            var html=document.documentElement?document.documentElement.outerHTML:'';
            var panels=document.querySelectorAll('.msg-jump'),throttled=false;
            for(var pi=0;pi<panels.length;pi++){
              var heading=panels[pi].querySelector('.window-title'),message=panels[pi].querySelector('.msg-content p');
              var headingText=heading?(heading.textContent||'').trim():'';
              var messageText=message?(message.textContent||'').trim():'';
              if((headingText==='系统提示'||headingText==='系統提示')&&new RegExp(${JSONObject.quote(SourcePageChecks.THROTTLE_TEXT_PATTERN)}).test(messageText))throttled=true;
            }
            if(throttled)return JSON.stringify({ready:false,throttled:true,challenge:false,acted:s.acted,done:false,failed:false,image:'',url:location.href});
            var value=c.captchaDetectValue||'', challenge=false;
            if(value){
              if(c.captchaDetectType===2)challenge=html.indexOf(value)>=0;
              else if(c.captchaDetectType===3)challenge=new RegExp(value).test(html);
              else challenge=!!node(value);
            }
            var title=(document.title||'').toLowerCase().replace(/^\s+|\s+$/g,'');
            if(/^(系统安全验证|安全验证|人机验证|just a moment\.\.\.|just a moment…|security verification)$/.test(title))challenge=true;
            var img=node(c.captchaImage), input=node(c.captchaInput), button=node(c.captchaButton);
            if(c.captchaType===1&&img)challenge=true;
            if(c.captchaType===2&&button)challenge=true;
            if(c.captchaType===1&&input&&!s.focused){s.focused=true;input.focus();input.dispatchEvent(new Event('focus',{bubbles:true}));}
            if(c.captchaType===2&&button&&!s.acted){s.acted=true;button.click();}
            if(c.captchaType===3&&c.captchaScript&&!s.script&&document.readyState!=='loading'){
              s.script=true;s.acted=true;
              window.KazumiCaptcha={log:function(){},done:function(){s.done=true;},fail:function(){s.failed=true;}};
              try {var result=(new Function(c.captchaScript)).call(window);if(result===true)s.done=true;
                if(result&&typeof result.then==='function')result.then(function(v){if(v===true)s.done=true;},function(){s.failed=true;});
              }catch(e){s.failed=true;}
            }
            var image='';
            if(img){image=img.src||'';try{if(img.complete&&img.naturalWidth&&img.naturalWidth<=2048&&img.naturalHeight<=2048){
              var canvas=document.createElement('canvas');canvas.width=img.naturalWidth;canvas.height=img.naturalHeight;
              canvas.getContext('2d').drawImage(img,0,0);image=canvas.toDataURL('image/png');}}catch(e){}}
            return JSON.stringify({ready:document.readyState==='complete'&&!!document.body&&document.body.childNodes.length>0,
              throttled:false,challenge:challenge,acted:s.acted,done:s.done,failed:s.failed,image:image,url:location.href});
          }catch(e){return JSON.stringify({failed:true,ready:false});}
        })();
        """.trimIndent()
    }
    fun submit(rule:SourceRule,code:String):String {
        val config=rule.json.optJSONObject("antiCrawlerConfig") ?: JSONObject()
        return """
        (function(){try{
          function node(x){return document.evaluate(x,document,null,XPathResult.FIRST_ORDERED_NODE_TYPE,null).singleNodeValue;}
          var input=node(${JSONObject.quote(config.optString("captchaInput"))}),button=node(${JSONObject.quote(config.optString("captchaButton"))});
          if(!input||!button)return false;
          input.focus();var setter=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
          setter.call(input,${JSONObject.quote(code)});input.dispatchEvent(new Event('input',{bubbles:true}));input.dispatchEvent(new Event('change',{bubbles:true}));
          window.__kazumiVerification.acted=true;button.click();return true;
        }catch(e){return false;}})();
        """.trimIndent()
    }
}

/** Neither navigation nor an initially empty page proves success. */
class VerificationProgress {
    private var seenChallenge=false
    private var acted=false
    private var clearSamples=0
    fun markAction() { acted=true; clearSamples=0 }
    fun observe(snapshot:JSONObject):Boolean {
        val challenge=snapshot.optBoolean("challenge")
        seenChallenge=seenChallenge||challenge
        acted=acted||snapshot.optBoolean("acted")
        val evidence=seenChallenge||acted||snapshot.optBoolean("done")
        if(snapshot.optBoolean("ready")&&!snapshot.optBoolean("throttled")&&!snapshot.optBoolean("failed")&&!challenge&&evidence)clearSamples++ else clearSamples=0
        return clearSamples>=3
    }
}
