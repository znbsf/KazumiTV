@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui

import android.view.KeyEvent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.focusable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import androidx.tv.material3.*

@Composable
fun PlayerAction(label: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Button(onClick = onClick, modifier = modifier.height(38.dp), contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
        scale = ButtonDefaults.scale(focusedScale = 1f),
        shape = ButtonDefaults.shape(shape = RoundedCornerShape(6.dp)),
        colors = ButtonDefaults.colors(containerColor = Color.Transparent, focusedContainerColor = Color.White.copy(alpha = .12f),
            contentColor = KazumiColors.text, focusedContentColor = KazumiColors.accent)) { Text(label, style = KazumiType.control) }
}

@Composable
fun PlayerProgress(position: Long, duration: Long, buffered: Long, stepMs: Long=10_000, onSeek: (Long) -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val fraction = if (duration > 0) (position.toFloat() / duration).coerceIn(0f, 1f) else 0f
    Canvas(Modifier.fillMaxWidth().height(24.dp).onFocusChanged { focused = it.isFocused }
        .onPreviewKeyEvent {
            val key = it.nativeKeyEvent
            if (key.action == KeyEvent.ACTION_DOWN && duration > 0 && key.keyCode in listOf(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT)) {
                onSeek((position + if (key.keyCode == KeyEvent.KEYCODE_DPAD_RIGHT) stepMs else -stepMs).coerceIn(0, duration)); true
            } else false
        }.semantics {
            contentDescription = "播放进度，左右键调整${stepMs/1000}秒"
            progressBarRangeInfo = ProgressBarRangeInfo(fraction, 0f..1f)
        }.focusable()) {
        val y = size.height / 2f
        val thickness = (if (focused) 5.dp else 3.dp).toPx()
        drawLine(Color.White.copy(alpha = .18f), Offset(0f, y), Offset(size.width, y), thickness)
        if (duration > 0) drawLine(Color.White.copy(alpha = .4f), Offset(0f, y), Offset(size.width * (buffered.toFloat() / duration).coerceIn(0f, 1f), y), thickness)
        drawLine(KazumiColors.accent, Offset(0f, y), Offset(size.width * fraction, y), thickness)
        drawCircle(KazumiColors.accent, (if (focused) 7.dp else 4.dp).toPx(), Offset(size.width * fraction, y))
    }
}
