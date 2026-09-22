@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui

import android.annotation.SuppressLint
import android.webkit.*
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.Alignment
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import kotlinx.coroutines.*
import org.kazumi.tv.rules.VerificationScript
import org.kazumi.tv.rules.VerificationSession
import org.kazumi.tv.rules.VerificationWebLifetime
import androidx.tv.material3.Button
import androidx.tv.material3.Text
import org.kazumi.tv.rules.SourceRule

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun VerificationScreen(rule: SourceRule, startUrl: String = rule.baseUrl, challenge:org.kazumi.tv.rules.SourceVerificationRequired?=null, onDone: () -> Unit) {
    val context=LocalContext.current
    val scope=rememberCoroutineScope()
    val currentDone by rememberUpdatedState(onDone)
    val pointerFocus=remember { FocusRequester() }
    val keyboard=LocalSoftwareKeyboardController.current
    var operating by remember { mutableStateOf(false) }
    var view by remember { mutableStateOf<WebView?>(null) }
    BackHandler(operating) {
        (view as? VerificationWebView)?.pointerEnabled=false
        operating=false
    }
    var generation by remember { mutableIntStateOf(0) }
    var browserGeneration by remember { mutableIntStateOf(0) }
    var lifetime by remember { mutableStateOf<VerificationWebLifetime?>(null) }
    var code by remember { mutableStateOf("") }
    var image by remember { mutableStateOf("") }
    var submittedImage by remember { mutableStateOf("") }
    var inputNotice by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("正在检测验证页面…") }
    var loadFailed by remember { mutableStateOf(false) }
    var delivered by remember { mutableStateOf(false) }
    var progress by remember { mutableStateOf(org.kazumi.tv.rules.VerificationProgress()) }
    val config=rule.json.optJSONObject("antiCrawlerConfig")
    val imageMode=config?.optBoolean("enabled")==true && config.optInt("captchaType",1)==1
    LaunchedEffect(view,generation) {
        val web=view ?: return@LaunchedEffect
        val owner=lifetime ?: return@LaunchedEffect
        try {
            withTimeout(60000) {
                VerificationSession.await(web,rule,progress,failure={ owner.failure ?: if(owner.released||loadFailed) "验证页面加载失败" else null }) { snapshot ->
                    val nextImage=snapshot.optString("image")
                    if(submittedImage.isNotEmpty()&&nextImage.isNotEmpty()&&nextImage!=submittedImage&&snapshot.optBoolean("challenge")) {
                        code="";submittedImage="";inputNotice="验证码已更新，请重新输入"
                    }
                    image=nextImage
                    status=when {
                        loadFailed -> "验证页面加载失败，请重试"
                        snapshot.optBoolean("throttled") -> "来源限制了请求频率，请稍候再重新加载验证页面"
                        snapshot.optBoolean("failed") -> "验证规则执行失败，可在网页中操作或重试"
                        inputNotice.isNotBlank() -> inputNotice
                        imageMode && image.isNotBlank() -> "输入图中验证码后提交；通过后会自动继续"
                        snapshot.optBoolean("acted") -> "已执行验证操作，正在确认结果…"
                        else -> "正在检测验证页面，可使用网页完成验证"
                    }
                }
            }
            if(owner===lifetime&&!owner.released&&!loadFailed&&!delivered) { delivered=true; currentDone() }
        } catch(_:TimeoutCancellationException) { status="验证尚未通过，可继续操作网页后重新检测，或重新加载" }
        catch(cancelled:CancellationException) { throw cancelled }
        catch(_:RuntimeException) { loadFailed=true;status="验证页面不可用，请重新加载后重试" }
    }
    Column(Modifier.fillMaxSize().background(Color(0xFF111713)).imePadding().padding(if(operating) 8.dp else 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if(operating) {
            Text("网页操作 · 方向键移动，确定点击，长按拖动 · 返回恢复工具栏",style=KazumiType.caption)
        } else {
        Text("${rule.name} · 网页验证")
        Text(status)
        FlowRow(horizontalArrangement=Arrangement.spacedBy(12.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Button(enabled=!loadFailed&&view!=null,onClick = { generation++ }) { Text("重新检测") }
            Button(onClick = {
                lifetime?.release();view=null;lifetime=null
                loadFailed=false;image="";inputNotice="";submittedImage="";code=""
                progress=org.kazumi.tv.rules.VerificationProgress();delivered=false
                status="正在重新加载验证页面…";browserGeneration++
            }) { Text("重新加载") }
            Button(enabled=!loadFailed&&view!=null,onClick = { keyboard?.hide();operating=true;(view as? VerificationWebView)?.pointerEnabled=true },modifier=Modifier.focusRequester(pointerFocus)) { Text("操作网页") }
            if(imageMode) {
                if(image.isNotBlank()) {
                    val model=remember(image) {
                        if(image.startsWith("data:image/")) runCatching { android.util.Base64.decode(image.substringAfter(','),android.util.Base64.DEFAULT) }.getOrNull()
                        else runCatching { coil.request.ImageRequest.Builder(context).data(SourceRule.httpUrl(image))
                            .addHeader("User-Agent",rule.userAgent).addHeader("Referer",startUrl)
                            .addHeader("Cookie",CookieManager.getInstance().getCookie(image).orEmpty()).build() }.getOrNull()
                    }
                    coil.compose.AsyncImage(model,contentDescription="验证码图片",modifier=Modifier.size(140.dp,52.dp))
                }
                TvTextInput(code,{ code=it.take(32);inputNotice="" },modifier=Modifier.width(180.dp).semantics { contentDescription="验证码输入框" })
                Button(enabled=code.isNotBlank()&&!loadFailed&&view!=null,onClick={ scope.launch {
                    val web=view ?: return@launch
                    val owner=lifetime ?: return@launch
                    try {
                    submittedImage=image;inputNotice=""
                    val result=withTimeoutOrNull(3000) { VerificationSession.evaluate(web,VerificationScript.submit(rule,code)) }
                    if(owner.released||owner!==lifetime||loadFailed)return@launch
                    if(result=="true") { progress.markAction();status="已提交，正在确认验证结果…";generation++ }
                    else { inputNotice="未找到验证码输入框或提交按钮，请重新加载";status=inputNotice;submittedImage="" }
                    } catch(cancelled:CancellationException) { throw cancelled }
                    catch(_:RuntimeException) { if(owner===lifetime) { loadFailed=true;status="提交失败，请重新加载验证页面" } }
                } }) { Text("提交验证码") }
            }
        }
        Text("网页操作：方向键移动 · 确定点击 · 长按确定拖动，再按确定松开 · 返回退出光标",style=KazumiType.caption)
        }
        key(browserGeneration) { AndroidView(factory = { hostContext -> android.widget.FrameLayout(hostContext).apply {
            var owned:VerificationWebLifetime?=null
            try {
            val browser=VerificationWebView(hostContext)
            val owner=VerificationWebLifetime(browser);owned=owner;tag=owner
            browser.apply {
            onExitPointer={ operating=false }
            VerificationSession.configure(this,rule)
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = request.url.scheme !in listOf("http", "https")
                override fun onReceivedError(view:WebView,request:WebResourceRequest,error:WebResourceError) { if(request.isForMainFrame) { owner.fail("验证页面加载失败");loadFailed=true;status="验证页面加载失败，请重新加载" } }
                override fun onReceivedHttpError(view:WebView,request:WebResourceRequest,response:WebResourceResponse) { if(request.isForMainFrame&&response.statusCode !in listOf(403,429)) { owner.fail("验证页面加载失败");loadFailed=true;status="验证页面加载失败，请重新加载" } }
                override fun onRenderProcessGone(view:WebView,detail:RenderProcessGoneDetail):Boolean {
                    owner.fail("验证页面渲染进程已退出",rendererGone=true)
                    loadFailed=true;status="验证页面已退出，请重新加载后继续";return true
                }
            }
            if(challenge?.method=="POST")postUrl(SourceRule.httpUrl(startUrl),challenge.body.orEmpty().toByteArray(Charsets.UTF_8))
            else loadUrl(SourceRule.httpUrl(startUrl), mapOf("Referer" to rule.referer))
            }
            addView(browser,android.widget.FrameLayout.LayoutParams(-1,-1))
            lifetime=owner;view=browser
            } catch(_:RuntimeException) {
                owned?.release();view=null;lifetime=null;loadFailed=true;status="WebView 无法启动，请检查系统 WebView 后重新加载"
            }
        } }, modifier = Modifier.fillMaxWidth().weight(1f), onRelease = { host ->
            val owner=host.tag as? VerificationWebLifetime
            owner?.release()
            if(lifetime===owner) { view=null;lifetime=null }
        }) }
    }
    LaunchedEffect(operating) {
        withFrameNanos { }; withFrameNanos { }
        if(operating)view?.requestFocus() else runCatching { pointerFocus.requestFocus() }
    }
}
