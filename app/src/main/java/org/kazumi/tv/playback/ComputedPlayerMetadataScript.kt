package org.kazumi.tv.playback

/**
 * Narrow, read-only fallback for the observed PlayConfig/stray driver contract.
 * The caller owns one state object per document and supplies its current time.
 * A returned address remains speculative: this does not establish episode identity.
 */
object ComputedPlayerMetadataScript {
    val reader = """
        function(w,state,now) {
          try {
            var own=Object.prototype.hasOwnProperty;
            function data(object,key) {
              if(!object || (typeof object!=='object' && typeof object!=='function'))return null;
              var descriptor=Object.getOwnPropertyDescriptor(object,key);
              return descriptor && own.call(descriptor,'value') ? descriptor : null;
            }
            function plain(value) {
              if(!value || typeof value!=='object' || Array.isArray(value))return false;
              var prototype=Object.getPrototypeOf(value);
              return prototype===null || prototype===w.Object.prototype;
            }
            function bounded(value) {
              return typeof value==='string' && value.length>0 && value.length<=16384;
            }
            function address(value) {
              if(!bounded(value) || !/^https?:\/\//i.test(value) || /[\s\\]/.test(value))return null;
              var authority=value.match(/^https?:\/\/([^\/?#]+)/i);
              if(!authority || authority[1].indexOf('@')!==-1)return null;
              var link=w.document.createElement('a');
              link.href=value;
              if((link.protocol!=='http:' && link.protocol!=='https:') || !link.hostname || link.username || link.password)return null;
              return link;
            }
            if(!state || typeof state!=='object' || typeof now!=='number' || !isFinite(now))return null;
            if(!own.call(state,'startedAt')) {
              state.startedAt=now;
              state.document=w.document;
            }
            if(state.blocked || state.document!==w.document)return null;
            var configDescriptor=data(w,'PlayConfig');
            var inputDescriptor=data(w,'Vurl');
            var config=configDescriptor && configDescriptor.value;
            var input=inputDescriptor && inputDescriptor.value;
            var urlDescriptor=plain(config) ? data(config,'Url') : null;
            var pathDescriptor=plain(config) ? data(config,'Playpath') : null;
            var configured=urlDescriptor && urlDescriptor.value;
            var path=pathDescriptor && pathDescriptor.value;
            if(state.inputObserved && (input!==state.input || configured!==state.configured || path!==state.path)) {
              state.blocked=true;
              return null;
            }
            if(!bounded(input) || !bounded(configured) || !bounded(path))return null;
            if(!state.inputObserved) {
              state.inputObserved=true;
              state.input=input;
              state.configured=configured;
              state.path=path;
            }
            if(input!==configured)return null;
            if(state.emitted || now-state.startedAt<8000)return null;
            var directory=address(path);
            if(!directory || directory.search || directory.hash)return null;
            var prefix=directory.protocol+'//'+directory.host+directory.pathname.replace(/\/+$/,'')+'/';
            var scripts=w.document.getElementsByTagName('script');
            if(scripts.length>256)return null;
            var globalFound=false,playerFound=false;
            for(var i=0;i<scripts.length;i++) {
              var source=address(scripts[i].src);
              if(!source)continue;
              var canonical=source.protocol+'//'+source.host+source.pathname;
              if(canonical===prefix+'global.min.js')globalFound=true;
              if(canonical===prefix+'play.min.js')playerFound=true;
            }
            if(!globalFound || !playerFound)return null;
            var strayDescriptor=data(w,'stray');
            var stray=strayDescriptor && strayDescriptor.value;
            if(!plain(stray))return null;
            var candidateDescriptor=data(stray,'url');
            var candidate=candidateDescriptor && candidateDescriptor.value;
            if(!address(candidate))return null;
            var adDescriptor=Object.getOwnPropertyDescriptor(stray,'ad');
            if(!adDescriptor && 'ad' in stray)return null;
            if(adDescriptor) {
              if(!own.call(adDescriptor,'value'))return null;
              var ad=adDescriptor.value;
              if(!ad || typeof ad!=='object' || Array.isArray(ad))return null;
              var optionDescriptor=data(ad,'option');
              var option=optionDescriptor && optionDescriptor.value;
              if(!plain(option))return null;
              var rendererDescriptor=data(option,'url');
              if(!rendererDescriptor || rendererDescriptor.value!==candidate)return null;
            }
            state.emitted=true;
            return candidate;
          } catch(ignored) { return null; }
        }
    """.trimIndent()
}
