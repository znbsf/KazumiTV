package org.kazumi.tv.rules

/** Narrow DS/MacCMS adapter for a known bundle that cannot parse on old providers.
 * This only submits a user's code to the original server; it never declares verification success.
 */
internal object MacCmsVerificationCompat {
    val script="""
        function compatEndpoint(input,button,img) {
          try {
            if(!c.enabled||(c.captchaType||1)!==1||document.readyState!=='complete')return '';
            if(typeof EC!=='undefined'||typeof ds_cms!=='object'||!ds_cms)return '';
            try { new Function('var value={};return value.user?.name;'); return ''; }
            catch(unsupported) { if(!unsupported||unsupported.name!=='SyntaxError')return ''; }
            if(typeof maccms!=='object'||!maccms||typeof maccms.path!=='string'||!/^([/][a-zA-Z0-9_-]+)*$/.test(maccms.path))return '';
            var path=maccms.path,origin=location.protocol+'//'+location.host;
            if(ds_cms.path_tpl!==path+'/template/dsn2/')return '';
            if(location.protocol!=='http:'&&location.protocol!=='https:')return '';
            if(!input||input.tagName!=='INPUT'||input.name!=='verify'||input.type!=='text'||
               !input.classList.contains('ds-verify')||input.disabled||input.readOnly)return '';
            if(!button||button.tagName!=='BUTTON'||!button.classList.contains('verify-submit')||
               button.getAttribute('data-type')!=='search'||button.disabled||button.onclick||button.hasAttribute('onclick'))return '';
            if(!img||img.tagName!=='IMG'||!img.classList.contains('ds-verify-img'))return '';
            if(document.querySelectorAll('input.ds-verify[name="verify"]').length!==1||
               document.querySelectorAll('button.verify-submit[data-type="search"]').length!==1||
               document.querySelectorAll('img.ds-verify-img').length!==1)return '';
            var imageUrl=document.createElement('a');imageUrl.href=img.src;
            if(imageUrl.protocol+'//'+imageUrl.host!==origin)return '';
            var scripts=document.querySelectorAll('script[src]'),known=false;
            for(var n=0;n<scripts.length;n++) {
              var scriptUrl=document.createElement('a');scriptUrl.href=scripts[n].src;
              if(scriptUrl.protocol+'//'+scriptUrl.host===origin&&scriptUrl.pathname===path+'/template/dsn2/static/js/script.js')known=true;
            }
            if(!known||!window.jQuery||typeof window.jQuery._data!=='function')return '';
            // Refuse both direct and delegated handlers: do not submit twice alongside site code.
            for(var owner=button;owner;owner=owner.parentNode) {
              var events=window.jQuery._data(owner,'events');
              if(events&&events.click&&events.click.length)return '';
            }
            return origin+path+'/index.php/ajax/verify_check?type=search';
          }catch(ignored){return '';}
        }
        function compatSubmit(endpoint,input,img) {
          if(s.submitting)return false;
          var value=input.value||'';
          if(!value.trim())return false;
          s.submitting=true;s.submitError='';s.serverRejected=false;s.acted=true;
          var xhr=new XMLHttpRequest(),finished=false;
          function fail(message,rejected) {
            if(finished)return;finished=true;s.submitting=false;s.submitError=message;s.serverRejected=!!rejected;
            input.value='';input.dispatchEvent(new Event('input',{bubbles:true}));input.dispatchEvent(new Event('change',{bubbles:true}));
            // Refresh the same image resource, without copying server messages or inventing a result.
            var imageUrl=document.createElement('a');imageUrl.href=img.src;
            imageUrl.search=(imageUrl.search?imageUrl.search+'&':'?')+'kazumi_refresh='+new Date().getTime();img.src=imageUrl.href;
          }
          xhr.onload=function(){
            if(finished)return;
            if(xhr.status<200||xhr.status>=300){fail('验证请求失败，请重试');return;}
            try {
              var response=JSON.parse(xhr.responseText);
              if(!response||!Object.prototype.hasOwnProperty.call(response,'code')||
                 !/^-?[0-9]+$/.test(String(response.code))){fail('验证响应无效，请重试');return;}
              if(Number(response.code)===1){finished=true;location.reload();}
              else fail('验证码未通过，请重新输入',true);
            }catch(invalid){fail('验证响应无效，请重试');}
          };
          xhr.onerror=function(){fail('验证请求失败，请重试');};
          xhr.ontimeout=function(){fail('验证请求超时，请重试');};
          xhr.onabort=function(){fail('验证请求已取消，请重试');};
          try { xhr.open('POST',endpoint+'&verify='+encodeURIComponent(value),true);xhr.timeout=8000;
            xhr.setRequestHeader('Content-Type','application/x-www-form-urlencoded; charset=UTF-8');
            xhr.setRequestHeader('X-Requested-With','XMLHttpRequest');xhr.send('');
          }catch(network){fail('验证请求失败，请重试');}
          return true;
        }
    """.trimIndent()
}
