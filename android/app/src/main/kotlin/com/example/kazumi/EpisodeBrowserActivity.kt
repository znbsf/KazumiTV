@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)

package com.example.kazumi

import android.os.Bundle
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.addCallback
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.tv.material3.Button
import androidx.tv.material3.ButtonDefaults
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import androidx.tv.material3.darkColorScheme

/** A disposable view over a Dart snapshot. It cannot launch or mutate playback. */
class EpisodeBrowserActivity : ComponentActivity() {
    private var launchToken: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val token = intent.getStringExtra(EXTRA_TOKEN)
        launchToken = token
        if (token == null || !BuildConfig.IS_TV_BUILD) {
            token?.let(EpisodeBrowserRegistry::cancel)
            finish()
            return
        }
        if (savedInstanceState != null) {
            EpisodeBrowserRegistry.rebuilt(token)
            finish()
            return
        }
        val snapshot = EpisodeBrowserRegistry.snapshot(token)
        if (snapshot == null || !EpisodeBrowserRegistry.bind(token, this)) {
            finish()
            return
        }
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowCompat.getInsetsController(window, window.decorView).apply {
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
        onBackPressedDispatcher.addCallback(this) { cancelAndFinish() }
        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                EpisodeBrowserView(
                    snapshot = snapshot,
                    onSelect = { opaqueId ->
                        EpisodeBrowserRegistry.select(token, snapshot.revision, opaqueId)
                    },
                    onCancel = ::cancelAndFinish,
                )
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        cancelAndFinish()
    }

    override fun onStop() {
        super.onStop()
        // HOME and interruptions discard this request; returning cannot replay it.
        cancelAndFinish()
    }

    override fun onDestroy() {
        launchToken?.let(EpisodeBrowserRegistry::cancel)
        launchToken = null
        super.onDestroy()
    }

    private fun cancelAndFinish() {
        launchToken?.let(EpisodeBrowserRegistry::cancel)
        if (!isFinishing) finish()
    }

    companion object {
        const val EXTRA_TOKEN = "episode_browser_launch_token"
    }
}

private val BrowserBackground = Color(0xFF11151C)
private val BrowserSurface = Color(0xFF222A36)
private val BrowserText = Color(0xFFEAF0FA)
private val BrowserAccent = Color(0xFF8BC8FF)

@Composable
private fun EpisodeBrowserView(
    snapshot: EpisodeBrowserSnapshot,
    onSelect: (String) -> Unit,
    onCancel: () -> Unit,
) {
    val count = snapshot.items.size
    var descending by remember { mutableStateOf(false) }
    var page by remember { mutableIntStateOf(EpisodeBrowserWindow.pageOf(snapshot.initialIndex, count, false)) }
    var number by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var locateKeyHeld by remember { mutableStateOf(false) }
    var focusTarget by remember { mutableStateOf<Int?>(snapshot.initialIndex) }
    var focusedIndex by remember { mutableStateOf<Int?>(snapshot.initialIndex) }
    val requesters = remember { mutableMapOf<Int, FocusRequester>() }
    val grid = rememberLazyGridState()
    val keyboard = LocalSoftwareKeyboardController.current
    val indices = remember(count, page, descending) {
        EpisodeBrowserWindow.indices(count, page, descending)
    }

    fun locate(index: Int) {
        keyboard?.hide()
        page = EpisodeBrowserWindow.pageOf(index, count, descending)
        focusTarget = index
    }

    fun locateNumber() {
        val index = EpisodeBrowserWindow.locate(number, count)
        if (index == null) {
            error = "请输入 1 到 $count 的原始列表序号"
        } else {
            error = null
            number = ""
            locate(index)
        }
    }

    LaunchedEffect(focusTarget, page, descending) {
        val index = focusTarget ?: return@LaunchedEffect
        val position = indices.indexOf(index)
        if (position >= 0) {
            grid.scrollToItem(position)
            // Lazy items must be measured before their focus targets exist.
            withFrameNanos { }
            withFrameNanos { }
            requesters[index]?.requestFocus()
            focusTarget = null
        }
    }

    Column(
        Modifier.fillMaxSize().background(BrowserBackground).padding(horizontal = 32.dp, vertical = 20.dp)
            .onPreviewKeyEvent { event ->
                val key = event.nativeKeyEvent
                val digit = when (key.keyCode) {
                    in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9 -> key.keyCode - KeyEvent.KEYCODE_0
                    in KeyEvent.KEYCODE_NUMPAD_0..KeyEvent.KEYCODE_NUMPAD_9 -> key.keyCode - KeyEvent.KEYCODE_NUMPAD_0
                    else -> null
                }
                val confirm = key.keyCode == KeyEvent.KEYCODE_DPAD_CENTER ||
                    key.keyCode == KeyEvent.KEYCODE_ENTER || key.keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER
                if (confirm && (number.isNotEmpty() || locateKeyHeld)) {
                    if (key.action == KeyEvent.ACTION_DOWN) {
                        locateKeyHeld = true
                        if (key.repeatCount == 0) locateNumber()
                    } else if (key.action == KeyEvent.ACTION_UP) {
                        locateKeyHeld = false
                    }
                    // The first OK locates; a separate OK selects the focused item.
                    true
                } else if (digit != null && key.action == KeyEvent.ACTION_DOWN) {
                    if (key.repeatCount == 0) {
                        number = (number + digit).take(4)
                        error = null
                    }
                    true
                } else false
            },
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("选集", color = BrowserText, fontSize = 25.sp)
            Text("共 $count 项 · 第 ${page + 1}/${EpisodeBrowserWindow.pageCount(count)} 段 · 每段最多 50 项",
                color = BrowserText, fontSize = 16.sp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            BrowserAction(if (descending) "倒序" else "正序") {
                val anchor = focusedIndex?.takeIf { it in indices } ?: indices.first()
                descending = !descending
                locate(anchor)
            }
            val currentIndex = snapshot.items.indexOfFirst { it.current }
            BrowserAction("定位当前", enabled = currentIndex >= 0) {
                if (currentIndex >= 0) locate(currentIndex)
            }
            BrowserAction("上一段", enabled = page > 0) {
                page--
                focusTarget = EpisodeBrowserWindow.indices(count, page, descending).first()
            }
            BrowserAction("下一段", enabled = page + 1 < EpisodeBrowserWindow.pageCount(count)) {
                page++
                focusTarget = EpisodeBrowserWindow.indices(count, page, descending).first()
            }
            BrowserAction("取消", onClick = onCancel)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NumberInput(number, { number = it.filter { char -> char in '0'..'9' }.take(4); error = null }, ::locateNumber)
            BrowserAction("定位序号", onClick = ::locateNumber)
            BrowserAction("清空") { number = ""; error = null }
        }
        Text(error ?: "序号按原始列表计算（包括特别篇）。数字键输入后按确定定位，再按确定选集。",
            color = if (error == null) BrowserText.copy(alpha = .7f) else Color(0xFFFFC4A8), fontSize = 14.sp)
        LazyVerticalGrid(
            columns = GridCells.Fixed(4), state = grid,
            modifier = Modifier.weight(1f),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = PaddingValues(5.dp),
        ) {
            items(indices, key = { snapshot.items[it].opaqueId }) { index ->
                val item = snapshot.items[index]
                val requester = remember(item.opaqueId) { FocusRequester() }
                DisposableEffect(index) {
                    requesters[index] = requester
                    onDispose { requesters.remove(index) }
                }
                val markers = listOfNotNull(
                    "当前".takeIf { item.current }, "已看".takeIf { item.seen },
                ).joinToString(" · ")
                Button(
                    onClick = { onSelect(item.opaqueId) },
                    modifier = Modifier.fillMaxWidth().height(64.dp).focusRequester(requester)
                        .onFocusChanged { if (it.isFocused) focusedIndex = index }
                        .semantics { contentDescription = "${index + 1}. $markers ${item.label}" },
                    scale = ButtonDefaults.scale(focusedScale = 1f),
                    colors = ButtonDefaults.colors(
                        containerColor = if (item.current) BrowserAccent.copy(alpha = .12f) else BrowserSurface,
                        focusedContainerColor = BrowserAccent,
                        contentColor = BrowserText,
                        focusedContentColor = BrowserBackground,
                    ),
                ) {
                    Text("${index + 1}. ${if (markers.isEmpty()) "" else "$markers · "}${item.label}",
                        fontSize = 17.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

@Composable
private fun BrowserAction(
    label: String,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick, enabled = enabled,
        modifier = Modifier.height(40.dp),
        scale = ButtonDefaults.scale(focusedScale = 1f),
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp),
        colors = ButtonDefaults.colors(
            containerColor = BrowserSurface,
            focusedContainerColor = BrowserAccent,
            contentColor = BrowserText,
            focusedContentColor = BrowserBackground,
        ),
    ) { Text(label, fontSize = 16.sp) }
}

@Composable
private fun NumberInput(value: String, onChange: (String) -> Unit, onLocate: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val focus = LocalFocusManager.current
    BasicTextField(
        value = value, onValueChange = onChange, singleLine = true,
        textStyle = TextStyle(color = BrowserText, fontSize = 17.sp),
        cursorBrush = SolidColor(BrowserAccent),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { onLocate() }),
        modifier = Modifier.width(220.dp).height(40.dp)
            .onFocusChanged { focused = it.isFocused }
            .onPreviewKeyEvent { event ->
                val key = event.nativeKeyEvent
                if (key.action != KeyEvent.ACTION_DOWN) return@onPreviewKeyEvent false
                when (key.keyCode) {
                    KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> { onLocate(); true }
                    KeyEvent.KEYCODE_DPAD_UP -> focus.moveFocus(FocusDirection.Up)
                    KeyEvent.KEYCODE_DPAD_DOWN -> focus.moveFocus(FocusDirection.Down)
                    KeyEvent.KEYCODE_DPAD_RIGHT -> focus.moveFocus(FocusDirection.Right)
                    else -> false
                }
            }
            .background(BrowserSurface, RoundedCornerShape(6.dp))
            .border(2.dp, if (focused) BrowserAccent else Color.Transparent, RoundedCornerShape(6.dp))
            .padding(horizontal = 12.dp, vertical = 9.dp)
            .semantics { contentDescription = "原始列表序号输入框" },
        decorationBox = { field ->
            if (value.isEmpty()) Text("输入原始序号", color = BrowserText.copy(alpha = .5f), fontSize = 17.sp)
            field()
        },
    )
}
