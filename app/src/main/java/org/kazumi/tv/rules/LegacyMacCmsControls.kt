package org.kazumi.tv.rules

/** Discovers an existing legacy MacCMS form; never manufactures a verification endpoint. */
internal object LegacyMacCmsControls {
    val script = """
      function verificationControls(){
        var found={input:node(c.captchaInput),button:node(c.captchaButton),img:node(c.captchaImage),legacy:false};
        if(found.input||found.button||found.img)return found;
        if(c.enabled!==true||c.captchaType!==1||document.readyState!=='complete')return found;
        if(typeof MAC!=='object'||!MAC||!MAC.Verify||typeof MAC.Verify.Init!=='function'||typeof MAC.Verify.Refresh!=='function')return found;
        if(typeof maccms!=='object'||!maccms)return found;
        var inputs=document.querySelectorAll('input[type="text"][name="verify"]');
        var buttons=document.querySelectorAll('input[type="button"].verify_submit');
        if(inputs.length!==1||buttons.length!==1||inputs[0].disabled||buttons[0].disabled)return found;
        found.input=inputs[0];found.button=buttons[0];found.legacy=true;
        var images=document.querySelectorAll('img.mac_verify_img');
        if(images.length===1){
          var address=document.createElement('a');address.href=images[0].src||'';
          if((address.protocol==='http:'||address.protocol==='https:')&&address.protocol===location.protocol&&address.host===location.host)found.img=images[0];
        }
        return found;
      }
    """.trimIndent()
}
