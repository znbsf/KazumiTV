package org.kazumi.tv.playback

/** ES5 syntax for old Android WebViews; no privileged JavaScript bridge. */
object MediaDiscoveryScript {
    val poll = """
        (function(){
          var computedPlayer=${ComputedPlayerMetadataScript.reader};
          function setup(w,depth){try{
            if(!w.__kazumiMedia){
              var q=[]; w.__kazumiMedia=q; w.__kazumiRemote=[]; w.__kazumiComputedState={};
              if(w===w.top)w.addEventListener('message',function(e){try{
                var m=e.data;if(!m||m.kind!=='kazumi-media-v1'||typeof m.url!=='string'||typeof m.referer!=='string')return;
                if(m.url.length>16384||m.referer.length>16384||!/^https?:/i.test(m.url)||!/^https?:/i.test(m.referer))return;
                if(w.__kazumiRemote.length<24)w.__kazumiRemote.push({url:m.url,referer:m.referer});
              }catch(ignore){}});
              function add(u){try{if(!u||typeof u!=='string')return;var a=w.document.createElement('a');a.href=u;
                if(/^https?:/i.test(a.href)&&q.indexOf(a.href)<0&&q.length<24){q.push(a.href);
                  if(w!==w.top)w.top.postMessage({kind:'kazumi-media-v1',url:a.href,referer:w.location.href},'*');}}catch(e){}}
              w.__kazumiAdd=add;
              if(w.Response&&w.Response.prototype.text){var text=w.Response.prototype.text;w.Response.prototype.text=function(){
                var response=this;return text.apply(this,arguments).then(function(body){if(/^\s*#EXTM3U/.test(body))add(response.url);return body;});};}
              function scan(){var n=w.document.querySelectorAll('video,audio,video source,audio source');for(var i=0;i<n.length;i++)add(n[i].currentSrc||n[i].src);}
              if(w.MutationObserver)new w.MutationObserver(scan).observe(w.document,{childList:true,subtree:true,attributes:true,attributeFilter:['src']});
              if(w.fetch){var fetch=w.fetch;w.fetch=function(){return fetch.apply(this,arguments).then(function(r){
                var t=r.headers.get('content-type')||'';if(/video|mpegurl|dash\+xml/i.test(t))add(r.url);return r;});};}
              if(w.XMLHttpRequest){var open=w.XMLHttpRequest.prototype.open;w.XMLHttpRequest.prototype.open=function(){
                this.addEventListener('load',function(){try{var t=this.getResponseHeader('content-type')||'';
                  if(/video|mpegurl|dash\+xml/i.test(t)||(!this.responseType||this.responseType==='text')&&/^\s*#EXTM3U/.test(this.responseText))add(this.responseURL);}catch(e){}});
                return open.apply(this,arguments);};}
              w.__kazumiScan=scan;
            }
            w.__kazumiScan();
            // Old providers may run a page's first XHR before onPageStarted can install hooks.
            // Resource Timing has no response type: keep its guesses separate from typed hooks
            // so JSON/analytics cannot fill the permanent confirmed-media queue.
            w.__kazumiSpeculative=[];
            if(w.performance&&w.performance.getEntriesByType){
              var entries=w.performance.getEntriesByType('resource'),count=0;
              for(var e=entries.length-1;e>=Math.max(0,entries.length-64)&&count<8;e--){var entry=entries[e];
                if(entry.initiatorType==='xmlhttprequest'||entry.initiatorType==='fetch'){
                  count++;w.__kazumiSpeculative.push(entry.name);
                }
              }
            }
            var computed=computedPlayer(w,w.__kazumiComputedState,Date.now());
            w.__kazumiComputedUrl=computed;
            if(depth<3)for(var i=0;i<w.frames.length;i++)setup(w.frames[i],depth+1);
          }catch(e){}}
          setup(window,0);
          var urls=[],speculative=[],computed=[],frames=[],seen=[],inaccessibleFrames=0;
          function collect(w,d){try{var q=w.__kazumiMedia||[];for(var i=0;i<q.length;i++)if(seen.indexOf(q[i])<0&&urls.length<24){seen.push(q[i]);urls.push({url:q[i],referer:w.location.href});}
            if(w.__kazumiComputedUrl&&computed.length<1)computed.push({url:w.__kazumiComputedUrl,referer:w.location.href,computed:true});
            var guesses=w.__kazumiSpeculative||[];for(var g=0;g<guesses.length&&speculative.length<24;g++)speculative.push({url:guesses[g],referer:w.location.href});
            var nodes=w.document.querySelectorAll('iframe[src]');for(var k=0;k<nodes.length&&frames.length<24;k++){var n=nodes[k],src=n.getAttribute('src');if(src&&src.trim()&&/^https?:/i.test(n.src)){
              var cross=false;try{var loc=n.contentWindow.location.href;}catch(blocked){cross=true;}
              var r=n.getBoundingClientRect(),p=n,player=false;for(var a=0;p&&a<3;a++,p=p.parentElement)if(/player|play|video/i.test((p.id||'')+' '+(p.className||'')+' '+(p.name||'')))player=true;
              var large=r.width>=160&&r.height>=90,visible=true;
              if(w.getComputedStyle){var style=w.getComputedStyle(n);visible=style.display!=='none'&&style.visibility!=='hidden'&&style.visibility!=='collapse';}
              frames.push({url:n.src,referer:w.location.href,crossOrigin:cross,playerLike:large&&visible&&player});}}
            if(d<3)for(var j=0;j<w.frames.length;j++)collect(w.frames[j],d+1);}catch(e){inaccessibleFrames++;}}
          collect(window,0);
          if(computed.length){if(speculative.length>=24)speculative.pop();speculative.push(computed[0]);}
          var remote=window.__kazumiRemote||[];for(var r=0;r<remote.length&&urls.length<24;r++)if(seen.indexOf(remote[r].url)<0){seen.push(remote[r].url);urls.push(remote[r]);}
          return JSON.stringify({urls:urls,speculative:speculative,frames:frames,inaccessibleFrames:inaccessibleFrames,title:document.title||'',ready:document.readyState});
        })();
    """.trimIndent()
}
