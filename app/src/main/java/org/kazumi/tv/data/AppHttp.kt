package org.kazumi.tv.data

import android.webkit.CookieManager
import okhttp3.*
import java.util.concurrent.TimeUnit

/** Cookies are selected for each target URL, including redirected and HLS segment requests. */
object AppHttp {
    // Media bodies may remain open for minutes. Keep connect/read limits and cookies,
    // but do not cancel healthy streams at the text client's whole-call deadline.
    val streamingClient: OkHttpClient by lazy { client.newBuilder().callTimeout(0, TimeUnit.SECONDS).build() }
    val client: OkHttpClient by lazy {
        OkHttpClient.Builder().connectTimeout(12, TimeUnit.SECONDS).readTimeout(15, TimeUnit.SECONDS)
            .callTimeout(30, TimeUnit.SECONDS).cookieJar(object : CookieJar {
                override fun loadForRequest(url: HttpUrl): List<Cookie> = CookieManager.getInstance().getCookie(url.toString()).orEmpty()
                    .split(';').mapNotNull { Cookie.parse(url, it.trim()) }
                override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
                    val manager = CookieManager.getInstance()
                    cookies.forEach { manager.setCookie(url.toString(), it.toString()) }
                }
            }).build()
    }
}
