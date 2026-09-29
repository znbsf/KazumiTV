package org.kazumi.tv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text
import coil.compose.AsyncImage
import coil.request.ImageRequest
import coil.imageLoader
import coil.memory.MemoryCache
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.painter.BitmapPainter
import org.kazumi.tv.data.NetworkSettings

@Composable
fun CoverImage(model: String, contentDescription: String?, modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop, allowRetry: Boolean = false, alignment: Alignment = Alignment.Center, emptyLabel: String = "暂无封面",
    placeholderModel: String? = null) {
    val context=LocalContext.current
    val revision by NetworkSettings.catalogRevision.collectAsState()
    val mirrored=remember(revision) { NetworkSettings.catalogMirror }
    var retry by remember(model,mirrored) { mutableIntStateOf(0) }
    var failed by remember(model,mirrored,retry) { mutableStateOf(false) }
    var loaded by remember(model,mirrored,retry) { mutableStateOf(false) }
    // A larger detail request may miss Coil's size check even for the same URL.
    // Draw the already decoded card immediately, while the full-size request runs.
    val cached = remember(model,placeholderModel,mirrored,retry) {
        val cache = context.imageLoader.memoryCache
        (cache?.get(MemoryCache.Key("$mirrored:$model:$retry"))
            ?: placeholderModel?.takeIf { it.isNotBlank() }?.let {
                cache?.get(MemoryCache.Key("$mirrored:$it:0"))
            })?.bitmap?.asImageBitmap()?.let(::BitmapPainter)
    }
    val request=remember(model,placeholderModel,mirrored,retry) {
        ImageRequest.Builder(context).data(model)
            .memoryCacheKey("$mirrored:$model:$retry")
            .diskCacheKey("$mirrored:$model")
            .crossfade(if (placeholderModel != null) 180 else 0).build()
    }
    Box(modifier.background(KazumiColors.surface),contentAlignment=Alignment.Center) {
        if(model.isNotBlank()) AsyncImage(request,contentDescription,Modifier.fillMaxSize(),contentScale=contentScale,alignment=alignment,
            placeholder=cached,error=cached,
            onSuccess={ loaded=true; failed=false },onError={ failed=true })
        if(!loaded && (cached == null || failed)) Column(Modifier.padding(8.dp),horizontalAlignment=Alignment.CenterHorizontally) {
            Text(if(model.isBlank()) emptyLabel else if(failed) "封面加载失败" else "封面加载中…",style=KazumiType.caption,color=KazumiColors.muted)
            if(failed && allowRetry)PlayerAction("重试封面") { retry++ }
        }
    }
}
