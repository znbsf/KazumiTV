@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui

import android.view.KeyEvent as AndroidKey
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.*
import coil.compose.AsyncImage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import org.kazumi.tv.data.CatalogRepository
import org.kazumi.tv.data.NetworkSettings
import org.kazumi.tv.data.Subject
import org.kazumi.tv.data.LibraryStore
import org.kazumi.tv.data.TvPreferences
import org.kazumi.tv.data.HistoryEntry
import org.kazumi.tv.R
import org.kazumi.tv.domain.ChannelNumber

@Composable
fun TvApp(searchModel: SearchViewModel? = null) {
    val context = LocalContext.current
    val preferences = remember { TvPreferences(context) }
    var oled by remember { mutableStateOf(preferences.oled) }
    var setup by remember { mutableStateOf(!preferences.setupComplete) }
    if (setup) {
        KazumiTheme(oled) { SetupScreen(onCancel=if(preferences.setupComplete) ({ setup=false }) else null) { preferences.setupComplete = true; setup = false } }
        return
    }
    val repository = remember { CatalogRepository() }
    var category by rememberSaveable { mutableStateOf("") }
    var page by rememberSaveable { mutableIntStateOf(0) }
    var pendingNumber by remember { mutableStateOf<Int?>(null) }
    var items by remember { mutableStateOf(emptyList<Subject>()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    var selected by rememberSaveable { mutableStateOf<Subject?>(null) }
    var resumeEntry by rememberSaveable { mutableStateOf<HistoryEntry?>(null) }
    var settings by rememberSaveable { mutableStateOf(false) }
    var library by rememberSaveable { mutableStateOf<String?>(null) }
    var returningLibrary by remember { mutableStateOf(false) }
    val libraryStates = rememberSaveableStateHolder()
    var digits by remember { mutableStateOf("") }
    var reload by remember { mutableIntStateOf(0) }
    val grid = rememberLazyGridState()
    val firstFocus = remember { FocusRequester() }
    val cardFocus = remember { mutableMapOf<Int, FocusRequester>() }
    var returnCard by rememberSaveable { mutableStateOf<Int?>(null) }
    var restoreHome by remember { mutableStateOf(false) }
    fun returnToParent() {
        resumeEntry = null
        if(selected != null && library != null) { selected = null; returningLibrary = true }
        else { selected = null; settings = false; library = null; restoreHome = true }
    }
    var loadedCategory by remember { mutableStateOf<String?>(null) }
    var loadedPages by remember { mutableIntStateOf(0) }
    val catalogRevision by NetworkSettings.catalogRevision.collectAsState()
    var loadedRevision by remember { mutableLongStateOf(catalogRevision) }
    var endReached by remember { mutableStateOf(false) }
    val backFocus = remember { FocusRequester() }
    val categories = listOf("", "日常", "原创", "校园", "搞笑", "奇幻", "百合", "恋爱", "悬疑", "热血")

    LaunchedEffect(category, page, reload,catalogRevision) {
        loading = true
        error = null
        notice = null
        if (loadedCategory != category || loadedRevision != catalogRevision) {
            if(loadedRevision != catalogRevision) { page=0; returnCard=null; pendingNumber=null }
            loadedRevision=catalogRevision
            digits = ""
            items = emptyList(); loadedPages = 0; endReached = false; loadedCategory = category
            grid.scrollToItem(0)
        }
        try {
            while (loadedPages <= page && !endReached && loadedPages <= 20) {
                val batch = repository.popular(category, loadedPages)
                items = items + batch
                loadedPages++
                endReached = batch.size < 48 || loadedPages > 20
            }
        }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { error = failure.message ?: "节目加载失败" }
        finally { loading = false }
    }
    LaunchedEffect(pendingNumber, loading, items) {
        val number = pendingNumber
        if (number != null && !loading) {
            val item = items.getOrNull(number - 1)
            if (item != null) {
                returnCard = item.id; selected = item
                resumeEntry = LibraryStore(context).history().firstOrNull { it.subject.id == item.id }
            } else notice = "当前分类没有 $number 号节目"
            pendingNumber = null
        }
    }
    LaunchedEffect(Unit) { firstFocus.requestFocus() }
    LaunchedEffect(items.size, loading, error, endReached, selected, settings, library) {
        if (!loading && error == null && !endReached && items.isNotEmpty() && selected == null && !settings && library == null) {
            snapshotFlow { (grid.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: -1) >= items.size - 12 }.collect { nearEnd ->
                if (nearEnd) { loading = true; page = loadedPages }
            }
        }
    }
    LaunchedEffect(selected, settings, library, restoreHome) {
        if (selected != null || settings || library != null) {
            withFrameNanos { }
            if (!returningLibrary) backFocus.requestFocus()
            returningLibrary = false
        } else if (restoreHome) {
            val index = items.indexOfFirst { it.id == returnCard }
            if (index >= 0) {
                grid.scrollToItem(index / 6 * 6)
                withFrameNanos { }
                cardFocus[returnCard]?.requestFocus()
            } else firstFocus.requestFocus()
            restoreHome = false
        }
    }
    LaunchedEffect(digits, selected, settings, library) {
        if (selected != null || settings || library != null) { digits = ""; return@LaunchedEffect }
        if (digits.isNotEmpty()) {
            delay(1800)
            val number = digits.toIntOrNull()
            if (number == null || number !in 1..999) notice = "请输入 1–999 的节目编号"
            else if (number > items.size && !endReached) {
                loading = true; page = (number - 1) / 48; pendingNumber = number
            } else {
                val item = items.getOrNull(number - 1)
                if (item == null) notice = "当前分类没有 $number 号节目"
                else { returnCard = item.id; selected = item; resumeEntry = LibraryStore(context).history().firstOrNull { it.subject.id == item.id } }
            }
            digits = ""
        }
    }
    BackHandler(selected != null || settings || library != null || digits.isNotEmpty() || notice != null || pendingNumber != null) {
        when {
            digits.isNotEmpty() -> digits = ""
            pendingNumber != null -> pendingNumber = null
            resumeEntry != null -> resumeEntry = null
            notice != null -> notice = null
            else -> returnToParent()
        }
    }
    KazumiTheme(oled) {
        CompositionLocalProvider(LocalContentColor provides Color(0xFFE4EEE1)) {
        Row(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)
            .onPreviewKeyEvent { event ->
                val native = event.nativeKeyEvent
                if (selected == null && !settings && library == null && native.action == AndroidKey.ACTION_DOWN &&
                    native.keyCode in AndroidKey.KEYCODE_0..AndroidKey.KEYCODE_9) {
                    digits = ChannelNumber.append(digits, native.keyCode - AndroidKey.KEYCODE_0)
                    notice = null
                    true
                } else false
            }) {
            Column(Modifier.width(82.dp).fillMaxHeight().background(Color(0xFF0B110D)).padding(horizontal = 6.dp, vertical = 20.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Image(painterResource(R.drawable.kazumitv_mark), "KazumiTV", Modifier.size(32.dp).clip(CircleShape))
                Text("KazumiTV", style = KazumiType.caption, color = KazumiColors.muted)
                Spacer(Modifier.height(16.dp))
                SidebarItem("浏览", selected == null && !settings && library == null, Modifier.focusRequester(firstFocus)) { pendingNumber = null; digits = ""; resumeEntry = null; selected = null; settings = false; library = null; restoreHome = true }
                SidebarItem("搜索", library == "搜索") { pendingNumber = null; digits = ""; resumeEntry = null; selected = null; settings = false; library = "搜索" }
                SidebarItem("排期", library == "排期") { pendingNumber=null; digits=""; resumeEntry=null; selected=null; settings=false; library="排期" }
                SidebarItem("历史", library == "历史") { pendingNumber = null; digits = ""; resumeEntry = null; selected = null; settings = false; library = "历史" }
                SidebarItem("收藏", library == "收藏") { pendingNumber = null; digits = ""; resumeEntry = null; selected = null; settings = false; library = "收藏" }
                Spacer(Modifier.weight(1f))
                SidebarItem("设置", settings) { pendingNumber = null; digits = ""; resumeEntry = null; selected = null; library = null; settings = !settings; if (!settings) restoreHome = true }
            }
            Column(Modifier.weight(1f).fillMaxHeight().padding(start = 20.dp, end = 28.dp, top = 20.dp, bottom = 12.dp)) {
            if (selected != null || settings || library != null) {
                PlayerAction(if(selected != null && library != null) "返回$library" else "返回浏览",Modifier.focusRequester(backFocus)) { returnToParent() }
                Spacer(Modifier.height(12.dp))
            }
            when {
                settings -> SettingsScreen(oled, { oled = it; preferences.oled = it }, { setup = true }) { repository.clearCache(); NetworkSettings.invalidateCatalog() }
                resumeEntry != null -> ResumeScreen(resumeEntry!!) { resumeEntry = null }
                selected != null -> DetailScreen(selected!!)
                library == "排期" -> libraryStates.SaveableStateProvider("排期") { CalendarScreen { selected=it } }
                library == "搜索" -> SearchScreen(searchModel ?: androidx.lifecycle.viewmodel.compose.viewModel()) { selected = it }
                library != null -> libraryStates.SaveableStateProvider(library!!) {
                    LibraryScreen(library!!, onResume = { resumeEntry = it; selected = it.subject }) { selected = it }
                }
                else -> {
                    val spotlight = items.firstOrNull { it.id == returnCard } ?: items.firstOrNull()
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    LazyRow(Modifier.weight(1f), contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(categories) { tag ->
                            TextNavigationItem(tag.ifBlank { "热门" }, category == tag, Modifier.width(52.dp)) {
                                if (category != tag) { loading = true; pendingNumber = null; returnCard = null; page = 0; category = tag }
                            }
                        }
                    }
                    }
                    Spacer(Modifier.height(6.dp))
                    SpotlightHeader(spotlight, repository)
                    if (digits.isNotEmpty()) Text("转到 $digits 号…", color = Color(0xFFB8E8A4), fontSize = 24.sp)
                    notice?.let { Text(it) }
                    if (loading && items.isEmpty()) Text("正在加载节目…")
                    error?.takeIf { items.isEmpty() }?.let { message ->
                        Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(message)
                            Button(onClick = { reload++ }) { Text("重试") }
                        }
                    }
                    BoxWithConstraints(Modifier.weight(1f)) {
                        val cardHeight = (maxHeight - 16.dp) / 2
                        LazyVerticalGrid(columns = GridCells.Fixed(6), state = grid,
                            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(16.dp),
                            contentPadding = PaddingValues(8.dp)) {
                            itemsIndexed(items, key = { index, subject -> "$index:${subject.id}" }) { index, subject ->
                                DisposableEffect(subject.id) { onDispose { cardFocus.remove(subject.id) } }
                                Card(onClick = { returnCard = subject.id; selected = subject },
                                    colors = CardDefaults.colors(containerColor = KazumiColors.surface, focusedContainerColor = KazumiColors.selected,
                                        contentColor = KazumiColors.text, focusedContentColor = KazumiColors.text),
                                    scale = CardDefaults.scale(focusedScale = 1.035f), modifier = Modifier.height(cardHeight - 8.dp)
                                    .focusRequester(cardFocus.getOrPut(subject.id) { FocusRequester() })
                                    .onFocusChanged { if (it.isFocused) returnCard = subject.id }) {
                                    Box(Modifier.fillMaxSize()) {
                                        CoverImage(model = subject.cover, contentDescription = subject.title,
                                            contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                                        Box(Modifier.fillMaxWidth().height(84.dp).align(Alignment.BottomCenter)
                                            .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = .94f)))))
                                        Text("${index + 1}", style = KazumiType.caption, modifier = Modifier.padding(8.dp)
                                            .background(Color.Black.copy(alpha = 0.55f)).padding(horizontal = 8.dp, vertical = 3.dp))
                                        Text(subject.title, maxLines = 2, minLines = 2, overflow = TextOverflow.Ellipsis,
                                            color = Color.White, modifier = Modifier.align(Alignment.BottomStart).padding(10.dp), style = KazumiType.body)
                                    }
                                }
                            }
                            item(span = { GridItemSpan(maxLineSpan) }) {
                                Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                                    if (loading && items.isNotEmpty()) Text("正在加载后续节目…", color = KazumiColors.muted)
                                    else if (error != null && items.isNotEmpty()) {
                                        Text("后续节目加载失败，已加载的节目仍可浏览", color = KazumiColors.muted)
                                        Button(onClick = { reload++ }) { Text("重试") }
                                    } else if (endReached) Text(if (items.isEmpty()) "暂无节目" else "已显示全部可浏览节目", color = KazumiColors.muted)
                                }
                            }
                        }
                    }
                }
            }
        }
        }
        }
    }
}

@Composable
private fun SidebarItem(label: String, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    TextNavigationItem(label, selected, modifier.fillMaxWidth(), onClick)
}

@Composable
private fun TextNavigationItem(label: String, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    Button(onClick = onClick, modifier = modifier.height(36.dp).onFocusChanged { focused = it.isFocused },
        contentPadding = PaddingValues(horizontal = 4.dp, vertical = 2.dp),
        scale = ButtonDefaults.scale(focusedScale = 1f),
        colors = ButtonDefaults.colors(containerColor = Color.Transparent, focusedContainerColor = Color.Transparent,
            contentColor = if (selected) KazumiColors.text else KazumiColors.muted, focusedContentColor = KazumiColors.accent)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(label, style = KazumiType.caption)
            Box(Modifier.width(18.dp).height(if (focused) 2.dp else 1.dp)
                .background(if (focused) KazumiColors.accent else if (selected) KazumiColors.muted else Color.Transparent))
        }
    }
}

@Composable
private fun SpotlightHeader(subject: Subject?, repository: CatalogRepository) {
    var summary by remember(subject?.id) { mutableStateOf(subject?.summary.orEmpty()) }
    val catalogRevision by NetworkSettings.catalogRevision.collectAsState()
    LaunchedEffect(subject?.id,catalogRevision) {
        if (subject != null && summary.isBlank()) {
            delay(450)
            try { summary = repository.detail(subject.id).summary }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) { android.util.Log.w("KazumiNetwork", "summary error=${error.javaClass.simpleName}") }
        }
    }
    Column(Modifier.fillMaxWidth().height(64.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(subject?.title ?: "探索番组", maxLines = 1, overflow = TextOverflow.Ellipsis,
            style = KazumiType.heading, color = KazumiColors.text)
        Text(summary.replace(Regex("\\s+"), " ").ifBlank { "选择节目查看详情" },
            maxLines = 1, overflow = TextOverflow.Ellipsis, style = KazumiType.caption, color = KazumiColors.muted)
    }
}

@Composable
private fun SettingsScreen(oled: Boolean, onOled: (Boolean) -> Unit, onSetup: () -> Unit, onClearCache: () -> Unit) {
    val context = LocalContext.current
    val preferences = remember { TvPreferences(context) }
    var autoNext by remember { mutableStateOf(preferences.autoNext) }
    var incognito by remember { mutableStateOf(preferences.incognito) }
    var memoryMode by remember { mutableStateOf(preferences.memoryMode) }
    var videoOutput by remember { mutableStateOf(preferences.videoOutput) }
    var rules by remember { mutableStateOf(false) }
    BackHandler(rules) { rules = false }
    if (rules) { RulesScreen(); return }
    var panel by remember { mutableStateOf<String?>(null) }
    BackHandler(panel != null) { panel = null }
    if (panel != null) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Button(onClick = { panel = null }) { Text("返回设置") }
            if (panel == "licenses") LicensesScreen(Modifier.weight(1f)) else if (panel == "network") NetworkOptions(onClearCache) else if(panel=="playback") PlaybackPreferencesPanel(Modifier.weight(1f)) else if(panel=="backup") LibraryBackupScreen() else if(panel=="webdav") WebDavSettings() else if(panel=="display") DisplayModePanel() else if(panel=="capabilities") DeviceCapabilitiesPanel() else if(panel=="downloads") DownloadsScreen() else DanmakuSettings()
        }
        return
    }
    var cleared by remember { mutableStateOf(false) }
    Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("电视设置", style = MaterialTheme.typography.headlineLarge)
        Button(onClick = onSetup) { Text("重新进行初始设置") }
        Button(onClick = { panel = "network" }) { Text("网络与镜像") }
        PlayerAction("播放偏好") { panel="playback" }
        PlayerAction("显示模式") { panel="display" }
        PlayerAction("设备与音画能力") { panel="capabilities" }
        PlayerAction("离线下载") { panel="downloads" }
        PlayerAction("收藏与历史备份") { panel="backup" }
        PlayerAction("WebDAV 收藏同步") { panel="webdav" }
        Button(onClick = { panel = "danmaku" }) { Text("弹幕服务与凭证") }
        Text("遥控方向键移动，确认进入，返回逐级退出。首页支持数字编号跳转。")
        Button(onClick = { rules = true }) { Text("规则管理与导入") }
        Button(onClick = { autoNext = !autoNext; preferences.autoNext = autoNext }) { Text("自动播放下一集：${if (autoNext) "开启" else "关闭"}") }
        PlayerAction("隐身播放：${if(incognito) "开启" else "关闭"}") { incognito=!incognito; preferences.incognito=incognito }
        Text("隐身播放开启后不更新本地观看进度，已有历史保留。搜索历史仍由搜索页单独管理。",style=KazumiType.caption)
        Button(onClick = {
            val modes = org.kazumi.tv.playback.MemoryMode.entries
            memoryMode = modes[(memoryMode.ordinal + 1) % modes.size]
            preferences.memoryMode = memoryMode
        }) { Text("内存策略：${memoryMode.label}") }
        Text("自动模式根据设备能力降低内存占用。低内存模式减少播放与封面缓存，网络不稳时可能更频繁缓冲。\n播放策略下次打开视频生效，封面缓存重启应用后生效。计费网络会减少预先缓冲。")
        Button(onClick = { onOled(!oled) }) { Text("OLED 纯黑背景：${if (oled) "开启" else "关闭"}") }
        Button(onClick = {
            val outputs = org.kazumi.tv.playback.VideoOutput.entries
            videoOutput = outputs[(videoOutput.ordinal + 1) % outputs.size]
            preferences.videoOutput = videoOutput
        }) { Text("视频输出：${videoOutput.label}") }
        Text("有声音但画面异常时可尝试兼容输出，下次打开视频生效。自动模式仅对已验证机型选择兼容输出；HDR 和耗电表现需按设备验证。")
        Text("目录缓存保留 10 分钟，最多保存 5 页、240 个节目。")
        Button(onClick = { onClearCache(); cleared = true }) { Text("清除目录缓存") }
        if (cleared) Text("目录缓存已清除，当前目录和搜索会重新加载。历史与收藏保留。")
        Text("播放支持选集、倍速、音轨与字幕选择；进入后台自动暂停并保存进度。")
        Text("本地保存最多 100 条播放进度和 200 个收藏；选择历史记录可直接续播。")
        val installedVersion = remember { context.packageManager.getPackageInfo(context.packageName, 0).versionName.orEmpty() }
        Text("KazumiTV · 原生电视版 $installedVersion\n基于 Kazumi · GPL-3.0 · 独立设计的应用图标与电视横幅")
        Button(onClick = { panel = "licenses" }) { Text("开源许可与对应源码") }
    }
}
