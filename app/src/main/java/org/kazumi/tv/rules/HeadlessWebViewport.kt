package org.kazumi.tv.rules

import android.view.View
import android.webkit.WebView

/** Main thread only: an unattached WebView has no parent to size responsive page content. */
object HeadlessWebViewport {
    fun prepare(web: WebView, diagnostic: (String) -> Unit = {}) {
        val metrics = web.context.resources.displayMetrics
        val width = metrics.widthPixels.takeIf { it > 0 } ?: (360 * metrics.density).toInt().coerceAtLeast(1)
        val height = metrics.heightPixels.takeIf { it > 0 } ?: (640 * metrics.density).toInt().coerceAtLeast(1)
        web.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
        web.layout(0, 0, width, height)
        diagnostic("web_viewport width=${web.width} height=${web.height}")
    }
}
