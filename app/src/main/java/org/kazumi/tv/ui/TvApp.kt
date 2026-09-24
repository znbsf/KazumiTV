@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui

import android.view.KeyEvent as AndroidKey
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.runtime.*
import androidx.compose.ui.draw.alpha
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import androidx.tv.material3.*
import coil.compose.AsyncImage
import coil.request.ImageRequest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import org.kazumi.tv.data.CatalogRepository
import org.kazumi.tv.data.TvCatalog
import org.kazumi.tv.data.NetworkSettings
import org.kazumi.tv.data.Subject
import org.kazumi.tv.data.LibraryStore
import org.kazumi.tv.data.TvPreferences
import org.kazumi.tv.data.HistoryEntry
import org.kazumi.tv.domain.ChannelNumber

@Composable
fun TvApp(searchModel: SearchViewModel? = null, homeCatalog: TvCatalog? = null) {
    val context = LocalContext.current
    val preferences = remember { TvPreferences(context) }
    val recent=rememberWatchHistory().distinctBy { it.subject.id }.take(2)
    var oled by remember { mutableStateOf(preferences.oled) }
    var setup by remember { mutableStateOf(!preferences.setupComplete) }
    if (setup) {
        KazumiTheme(oled) { SetupScreen(onCancel=if(preferences.setupComplete) ({ setup=false }) else null) { preferences.setupComplete = true; setup = false } }
        return
    }
    val repository = remember(homeCatalog) { homeCatalog ?: CatalogRepository() }
    val categories = listOf("", "日常", "原创", "校园", "搞笑", "奇幻", "百合", "恋爱", "悬疑", "热血")
    var category by rememberSaveable { mutableStateOf("") }
    var page by rememberSaveable { mutableIntStateOf(0) }
    var pendingNumber by remember { mutableStateOf<Int?>(null) }
    var items by remember { mutableStateOf(emptyList<Subject>()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    var selected by rememberSaveable(stateSaver=NavigationStateSavers.subject) { mutableStateOf<Subject?>(null) }
    var resumeEntry by rememberSaveable(stateSaver=NavigationStateSavers.history) { mutableStateOf<HistoryEntry?>(null) }
    var settings by rememberSaveable { mutableStateOf(false) }
    var library by rememberSaveable { mutableStateOf<String?>(null) }
    var returningLibrary by remember { mutableStateOf(false) }
    val libraryStates = rememberSaveableStateHolder()
    var digits by remember { mutableStateOf("") }
    var reload by remember { mutableIntStateOf(0) }
    val grid = rememberLazyGridState()
    val spotlightExpanded by remember { derivedStateOf { grid.firstVisibleItemIndex < 6 } }
    val categoryStrip = rememberLazyListState()
    val hotFocus = remember { FocusRequester() }
    val favoriteFocus = remember { FocusRequester() }
    val topFocusRequesters = remember {
        mutableMapOf<String, FocusRequester>().apply {
            HomeNavAction.entries.forEach {
                put(homeActionFocusKey(it), if (it == HomeNavAction.Favorites) favoriteFocus else FocusRequester())
            }
            categories.forEach { put(homeCategoryFocusKey(it), if (it.isBlank()) hotFocus else FocusRequester()) }
        }
    }
    val cardFocus = remember { mutableMapOf<Int, FocusRequester>() }
    val recentFocus = remember { mutableMapOf<Int, FocusRequester>() }
    var returnCard by rememberSaveable { mutableStateOf<Int?>(null) }
    var returnCardIndex by rememberSaveable { mutableIntStateOf(0) }
    var returnRecentId by rememberSaveable { mutableStateOf<Int?>(null) }
    var spotlightId by rememberSaveable { mutableStateOf<Int?>(null) }
    var savedHomeFocus by rememberSaveable { mutableStateOf<String?>(null) }
    val initialSavedHomeFocus = remember { savedHomeFocus }
    var actualHomeFocus by remember { mutableStateOf<String?>(null) }
    var homeFocusRestored by remember { mutableStateOf(false) }
    var restoreHome by rememberSaveable { mutableStateOf(false) }
    var autoFocusIntent by remember { mutableStateOf<String?>(null) }
    var userFocusEpoch by remember { mutableIntStateOf(0) }
    var focusRetryToken by remember { mutableIntStateOf(0) }
    fun returnToParent() {
        resumeEntry = null
        if(selected != null && library != null) { selected = null; returningLibrary = true }
        else {
            selected = null; settings = false; library = null
            restoreHome = true
            homeFocusRestored = false
        }
    }
    var loadedCategory by remember { mutableStateOf<String?>(null) }
    var loadedPages by remember { mutableIntStateOf(0) }
    val catalogRevision by NetworkSettings.catalogRevision.collectAsState()
    var loadedRevision by remember { mutableLongStateOf(catalogRevision) }
    var endReached by remember { mutableStateOf(false) }
    val backFocus = remember { FocusRequester() }

    LaunchedEffect(category, page, reload,catalogRevision) {
        loading = true
        error = null
        notice = null
        val categoryChanged = loadedCategory != null && loadedCategory != category
        val catalogChanged = loadedRevision != catalogRevision
        if (loadedCategory != category || catalogChanged) {
            if(catalogChanged) {
                if (savedHomeFocus?.startsWith("poster:") == true || actualHomeFocus?.startsWith("poster:") == true) {
                    restoreHome = true
                    homeFocusRestored = false
                }
                page=0; returnCard=null; returnRecentId=null; spotlightId=null; pendingNumber=null
            }
            loadedRevision=catalogRevision
            digits = ""
            items = emptyList(); loadedPages = 0; endReached = false; loadedCategory = category
            if(categoryChanged || catalogChanged) grid.scrollToItem(0)
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
                returnRecentId=null; returnCard = item.id; selected = item
            } else notice = "当前分类没有 $number 号节目"
            pendingNumber = null
        }
    }
    LaunchedEffect(items.size, loading, error, endReached, selected, settings, library) {
        if (!loading && error == null && !endReached && items.isNotEmpty() && selected == null && !settings && library == null) {
            snapshotFlow { (grid.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: -1) >= items.size - 12 }.collect { nearEnd ->
                if (nearEnd) { loading = true; page = loadedPages }
            }
        }
    }
    LaunchedEffect(selected, settings, library) {
        if (selected != null || settings || library != null) {
            withFrameNanos { }
            if (!returningLibrary) backFocus.requestFocus()
            returningLibrary = false
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
                else { returnRecentId=null; returnCard = item.id; selected = item }
            }
            digits = ""
        }
    }
    val homeVisible = selected == null && !settings && library == null && resumeEntry == null
    fun recordHomeFocus(key: String, focused: Boolean = true) {
        if (focused) {
            actualHomeFocus = key
            if (autoFocusIntent == null || autoFocusIntent == key) savedHomeFocus = key
        } else if (actualHomeFocus == key) {
            // An old node may report focus loss after a new node gains focus. Clear only
            // when it still owns the current record so restoration cannot match stale state.
            actualHomeFocus = null
        }
        if (!focused) return
        when {
            key.startsWith("poster:") -> key.substringAfter(':').toIntOrNull()?.let {
                returnCard = it; returnRecentId = null; spotlightId = it
            }
            key.startsWith("recent:") -> key.substringAfter(':').toIntOrNull()?.let {
                returnRecentId = it; returnCard = null; spotlightId = it
            }
        }
    }
    suspend fun requestHomeFocus(key: String, expectedUserEpoch: Int): Boolean {
        when {
            key.startsWith("category:") -> {
                val index = categories.indexOf(key.removePrefix("category:"))
                if (index < 0) return false
                categoryStrip.scrollToItem(index)
                repeat(2) { withFrameNanos { } }
            }
            key.startsWith("poster:") -> {
                val id = key.substringAfter(':').toIntOrNull() ?: return false
                val index = items.indexOfFirst { it.id == id }
                if (index < 0) return false
                grid.scrollToItem(index / 6 * 6)
                repeat(2) { withFrameNanos { } }
            }
            key.startsWith("recent:") -> {
                val id = key.substringAfter(':').toIntOrNull() ?: return false
                if (recent.none { it.subject.id == id }) return false
                repeat(2) { withFrameNanos { } }
            }
        }
        val requester = when {
            key.startsWith("poster:") -> key.substringAfter(':').toIntOrNull()?.let { cardFocus[it] }
            key.startsWith("recent:") -> key.substringAfter(':').toIntOrNull()?.let { recentFocus[it] }
            else -> topFocusRequesters[key]
        } ?: return false
        if (expectedUserEpoch != userFocusEpoch) return false
        requester.requestFocus()
        return withTimeoutOrNull(1000L) {
            snapshotFlow { actualHomeFocus to userFocusEpoch }.first { it.first == key || it.second != expectedUserEpoch }
                .let { it.first == key && it.second == expectedUserEpoch }
        } ?: false
    }
    LaunchedEffect(homeVisible, loading, items.size, error, endReached, restoreHome, homeFocusRestored, userFocusEpoch, focusRetryToken) {
        if (!homeVisible || (homeFocusRestored && !restoreHome)) return@LaunchedEffect
        val expectedUserEpoch = userFocusEpoch
        var requested = if (restoreHome) savedHomeFocus ?: homeCategoryFocusKey(category)
            else initialSavedHomeFocus ?: homeCategoryFocusKey("")
        val requestedPosterId = requested.takeIf { it.startsWith("poster:") }
            ?.substringAfter(':')?.toIntOrNull()
        if (restoreHome && requestedPosterId != null && items.none { it.id == requestedPosterId } && error == null) {
            if (!loading && !endReached && returnCardIndex >= items.size) {
                loading = true
                page = (returnCardIndex / 48).coerceAtLeast(loadedPages)
                return@LaunchedEffect
            }
            if (!loading && (endReached || returnCardIndex < items.size)) {
                val fallback = if (items.isEmpty()) null else items[returnCardIndex.coerceIn(0, items.lastIndex)]
                if (fallback != null) {
                    returnCard = fallback.id
                    spotlightId = fallback.id
                    requested = "poster:${fallback.id}"
                    savedHomeFocus = requested
                } else requested = homeCategoryFocusKey(category)
            }
        }
        autoFocusIntent = requested
        if (requested.startsWith("poster:") && items.none { "poster:${it.id}" == requested } &&
            error == null && (loading || !endReached)) {
            // Focus navigation right away on a cold or slow load, but retain the poster
            // identity until it arrives. This temporary focus must not overwrite it.
            val categoryKey = homeCategoryFocusKey(category)
            if (actualHomeFocus != categoryKey && !requestHomeFocus(categoryKey, expectedUserEpoch)) {
                if (expectedUserEpoch == userFocusEpoch) {
                    delay(400)
                    focusRetryToken++
                }
            }
            return@LaunchedEffect
        }
        var focused = false
        val candidates = listOf(requested, homeCategoryFocusKey(category), homeCategoryFocusKey("")).distinct()
        for (candidate in candidates) {
            if (requestHomeFocus(candidate, expectedUserEpoch)) {
                if (expectedUserEpoch != userFocusEpoch) return@LaunchedEffect
                focused = true
                break
            }
        }
        if (!focused && actualHomeFocus == null && expectedUserEpoch == userFocusEpoch) {
            delay(400)
            if (expectedUserEpoch == userFocusEpoch) focusRetryToken++
            return@LaunchedEffect
        }
        if (expectedUserEpoch != userFocusEpoch) return@LaunchedEffect
        homeFocusRestored = true
        restoreHome = false
        autoFocusIntent = null
    }
    BackHandler(selected != null || settings || library != null || resumeEntry != null || digits.isNotEmpty() || notice != null || pendingNumber != null) {
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
        Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
            if (homeVisible) {
                val spotlight = recent.firstOrNull { it.subject.id == spotlightId }?.subject
                    ?: items.firstOrNull { it.id == spotlightId }
                    ?: items.firstOrNull { it.id == returnCard }
                    ?: items.firstOrNull()
                HomeBackdrop(spotlight, oled, Modifier.matchParentSize())
            }
            Column(
                Modifier.fillMaxSize().padding(
                    horizontal = if (homeVisible) 24.dp else 20.dp,
                    vertical = if (homeVisible) 8.dp else 20.dp
                ).onPreviewKeyEvent { event ->
                    val native = event.nativeKeyEvent
                    if (homeVisible && native.action == AndroidKey.ACTION_DOWN &&
                        native.keyCode in AndroidKey.KEYCODE_DPAD_UP..AndroidKey.KEYCODE_DPAD_CENTER) {
                        userFocusEpoch++
                        autoFocusIntent = null
                        restoreHome = false
                        homeFocusRestored = true
                    }
                    if (homeVisible && native.action == AndroidKey.ACTION_DOWN &&
                        native.keyCode in AndroidKey.KEYCODE_0..AndroidKey.KEYCODE_9) {
                        digits = ChannelNumber.append(digits, native.keyCode - AndroidKey.KEYCODE_0)
                        notice = null
                        userFocusEpoch++
                        autoFocusIntent = null
                        restoreHome = false
                        homeFocusRestored = true
                        true
                    } else false
                }
            ) {
                if (homeVisible) {
                    HomeNavigation(
                        categories = categories,
                        category = category,
                        selectedPage = library,
                        settingsSelected = settings,
                        categoryState = categoryStrip,
                        actionRequesters = topFocusRequesters,
                        onFocused = ::recordHomeFocus,
                        onAction = { action ->
                            userFocusEpoch++
                            autoFocusIntent = null
                            homeFocusRestored = true
                            restoreHome = false
                            digits = ""
                            pendingNumber = null
                            when (action) {
                                HomeNavAction.Settings -> { selected = null; resumeEntry = null; library = null; settings = true }
                                HomeNavAction.Search -> { selected = null; resumeEntry = null; settings = false; library = "搜索" }
                                HomeNavAction.Schedule -> { selected = null; resumeEntry = null; settings = false; library = "排期" }
                                HomeNavAction.History -> { selected = null; resumeEntry = null; settings = false; library = "历史" }
                                HomeNavAction.Favorites -> { selected = null; resumeEntry = null; settings = false; library = "收藏" }
                            }
                        },
                        onCategory = { tag ->
                            homeFocusRestored = true
                            if (category != tag) {
                                loading = true
                                pendingNumber = null
                                returnCard = null
                                returnCardIndex = 0
                                returnRecentId = null
                                spotlightId = null
                                savedHomeFocus = homeCategoryFocusKey(tag)
                                page = 0
                                category = tag
                            }
                        }
                    )
                    Spacer(Modifier.height(6.dp))
                    val spotlight = recent.firstOrNull { it.subject.id == spotlightId }?.subject
                        ?: items.firstOrNull { it.id == spotlightId }
                        ?: items.firstOrNull { it.id == returnCard }
                        ?: items.firstOrNull()
                    AnimatedVisibility(
                        visible = spotlightExpanded,
                        enter = fadeIn(tween(150)),
                        exit = fadeOut(tween(120)) + shrinkVertically(tween(160), shrinkTowards = Alignment.Top)
                    ) {
                        SpotlightHeader(spotlight, repository)
                    }
                    if (recent.isNotEmpty()) {
                        RecentWatchLinks(
                            entries = recent,
                            focusRequesters = recentFocus,
                            onFocused = { entry, focused -> recordHomeFocus("recent:" + entry.subject.id, focused) },
                            onSelect = { subject ->
                                returnRecentId = subject.id
                                spotlightId = subject.id
                                selected = subject
                            }
                        )
                    }
                    if (digits.isNotEmpty()) Text("转到 $digits 号…", color = KazumiColors.accent, fontSize = 22.sp)
                    notice?.let { Text(it, color = KazumiColors.accent, style = KazumiType.caption) }
                    if (loading && items.isEmpty()) Text("正在加载节目…", color = Color.White)
                    error?.takeIf { items.isEmpty() }?.let { message ->
                        Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(message, color = Color.White)
                            Button(onClick = { reload++ }) { Text("重试") }
                        }
                    }
                    BoxWithConstraints(Modifier.weight(1f)) {
                        val cardHeight = (maxHeight - 16.dp) / 2
                        LazyVerticalGrid(
                            columns = GridCells.Fixed(6),
                            state = grid,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalArrangement = Arrangement.spacedBy(16.dp),
                            contentPadding = PaddingValues(8.dp)
                        ) {
                            itemsIndexed(items, key = { index, subject -> index.toString() + ":" + subject.id }) { index, subject ->
                                DisposableEffect(subject.id) { onDispose { cardFocus.remove(subject.id) } }
                                Card(
                                    onClick = {
                                        returnCardIndex = index
                                        recordHomeFocus("poster:" + subject.id)
                                        selected = subject
                                    },
                                    colors = CardDefaults.colors(
                                        containerColor = KazumiColors.surface,
                                        focusedContainerColor = KazumiColors.selected,
                                        contentColor = KazumiColors.text,
                                        focusedContentColor = KazumiColors.text
                                    ),
                                    scale = CardDefaults.scale(focusedScale = 1.035f),
                                    modifier = Modifier.height(cardHeight - 8.dp)
                                        .focusRequester(cardFocus.getOrPut(subject.id) { FocusRequester() })
                                        .onFocusChanged {
                                            if (it.isFocused) returnCardIndex = index
                                            recordHomeFocus("poster:" + subject.id, it.isFocused)
                                        }
                                ) {
                                    Box(Modifier.fillMaxSize()) {
                                        CoverImage(
                                            model = subject.cover,
                                            contentDescription = subject.title,
                                            contentScale = ContentScale.Crop,
                                            modifier = Modifier.fillMaxSize()
                                        )
                                        Box(Modifier.fillMaxWidth().height(84.dp).align(Alignment.BottomCenter)
                                            .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = .94f)))))
                                        Text(
                                            (index + 1).toString(),
                                            style = KazumiType.caption,
                                            modifier = Modifier.padding(8.dp).background(Color.Black.copy(alpha = 0.62f))
                                                .padding(horizontal = 8.dp, vertical = 3.dp)
                                        )
                                        Text(
                                            subject.title,
                                            maxLines = 2,
                                            minLines = 2,
                                            overflow = TextOverflow.Ellipsis,
                                            color = Color.White,
                                            modifier = Modifier.align(Alignment.BottomStart).padding(10.dp),
                                            style = KazumiType.body
                                        )
                                    }
                                }
                            }
                            item(span = { GridItemSpan(maxLineSpan) }) {
                                Row(
                                    Modifier.fillMaxWidth().padding(vertical = 8.dp),
                                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    if (loading && items.isNotEmpty()) Text("正在加载后续节目…", color = KazumiColors.muted)
                                    else if (error != null && items.isNotEmpty()) {
                                        Text("后续节目加载失败，已加载的节目仍可浏览", color = KazumiColors.muted)
                                        Button(onClick = { reload++ }) { Text("重试") }
                                    } else if (endReached) Text(
                                        if (items.isEmpty()) "暂无节目" else "已显示全部可浏览节目",
                                        color = KazumiColors.muted
                                    )
                                }
                            }
                        }
                    }
                } else {
                    if (selected != null || settings || library != null || resumeEntry != null) {
                        PlayerAction(
                            if (selected != null && library != null) "返回$library" else "返回浏览",
                            Modifier.focusRequester(backFocus)
                        ) { returnToParent() }
                        Spacer(Modifier.height(12.dp))
                    }
                    when {
                        settings -> SettingsScreen(oled, { oled = it; preferences.oled = it }, { setup = true }) {
                            repository.clearCache()
                            NetworkSettings.invalidateCatalog()
                        }
                        resumeEntry != null -> ResumeScreen(resumeEntry!!) { resumeEntry = null }
                        selected != null -> DetailScreen(selected!!, loadDetail = { repository.detail(it) })
                        library == "排期" -> libraryStates.SaveableStateProvider("排期") { CalendarScreen { selected = it } }
                        library == "搜索" -> SearchScreen(searchModel ?: androidx.lifecycle.viewmodel.compose.viewModel()) {
                            selected = it
                        }
                        library != null -> libraryStates.SaveableStateProvider(library!!) {
                            LibraryScreen(library!!, onResume = { resumeEntry = it; selected = it.subject }) { selected = it }
                        }
                    }
                }
            }
        }
    }
}

}

private enum class HomeNavAction(val label: String, val glyph: HomeNavGlyph) {
    Settings("设置", HomeNavGlyph.Settings),
    Search("搜索", HomeNavGlyph.Search),
    Schedule("排期", HomeNavGlyph.Schedule),
    History("历史", HomeNavGlyph.History),
    Favorites("收藏", HomeNavGlyph.Favorites)
}

private enum class HomeNavGlyph { Settings, Search, Schedule, History, Favorites }

private fun homeActionFocusKey(action: HomeNavAction) = "menu:" + action.name
private fun homeCategoryFocusKey(category: String) = "category:" + category

@Composable
private fun HomeNavigation(
    categories: List<String>,
    category: String,
    selectedPage: String?,
    settingsSelected: Boolean,
    categoryState: androidx.compose.foundation.lazy.LazyListState,
    actionRequesters: Map<String, FocusRequester>,
    onFocused: (String, Boolean) -> Unit,
    onAction: (HomeNavAction) -> Unit,
    onCategory: (String) -> Unit
) {
    Row(
        Modifier.fillMaxWidth().height(48.dp).focusGroup(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            Modifier.weight(4f).fillMaxHeight(),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            HomeNavAction.entries.forEach { action ->
                val focusKey = homeActionFocusKey(action)
                val requester = actionRequesters.getValue(focusKey)
                val selected = when (action) {
                    HomeNavAction.Settings -> settingsSelected
                    HomeNavAction.Search -> selectedPage == "搜索"
                    HomeNavAction.Schedule -> selectedPage == "排期"
                    HomeNavAction.History -> selectedPage == "历史"
                    HomeNavAction.Favorites -> selectedPage == "收藏"
                }
                HomeNavigationButton(
                    label = action.label,
                    selected = selected,
                    modifier = Modifier.weight(1f).fillMaxHeight()
                        .focusRequester(requester)
                        .onFocusChanged { onFocused(focusKey, it.isFocused) }
                        .onPreviewKeyEvent { event ->
                            val native = event.nativeKeyEvent
                            if (action == HomeNavAction.Favorites &&
                                native.action == AndroidKey.ACTION_DOWN &&
                                native.keyCode == AndroidKey.KEYCODE_DPAD_RIGHT) {
                                actionRequesters.getValue(homeCategoryFocusKey("")).requestFocus()
                                true
                            } else false
                        },
                    glyph = action.glyph,
                    onClick = { onAction(action) }
                )
            }
        }
        Box(
            Modifier.padding(horizontal = 10.dp).width(1.dp).fillMaxHeight(.58f)
                .background(Color.White.copy(alpha = .32f))
        )
        LazyRow(
            Modifier.weight(6.2f).fillMaxHeight(),
            state = categoryState,
            contentPadding = PaddingValues(horizontal = 4.dp, vertical = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            items(categories, key = { homeCategoryFocusKey(it) }) { tag ->
                val focusKey = homeCategoryFocusKey(tag)
                val requester = actionRequesters.getValue(focusKey)
                HomeNavigationButton(
                    label = tag.ifBlank { "热门" },
                    selected = category == tag,
                    modifier = Modifier.height(42.dp)
                        .focusRequester(requester)
                        .onFocusChanged { onFocused(focusKey, it.isFocused) }
                        .onPreviewKeyEvent { event ->
                            val native = event.nativeKeyEvent
                            if (tag.isBlank() &&
                                native.action == AndroidKey.ACTION_DOWN &&
                                native.keyCode == AndroidKey.KEYCODE_DPAD_LEFT) {
                                actionRequesters.getValue(homeActionFocusKey(HomeNavAction.Favorites)).requestFocus()
                                true
                            } else false
                        },
                    glyph = null,
                    onClick = { onCategory(tag) }
                )
            }
        }
    }
}

@Composable
private fun HomeNavigationButton(
    label: String,
    selected: Boolean,
    modifier: Modifier = Modifier,
    glyph: HomeNavGlyph?,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(10.dp)
    val borderColor = when {
        focused -> KazumiColors.accent
        selected -> KazumiColors.accent.copy(alpha = .62f)
        else -> Color.Transparent
    }
    val backgroundColor = when {
        focused -> KazumiColors.selected.copy(alpha = .84f)
        selected -> KazumiColors.selected.copy(alpha = .54f)
        else -> Color.Transparent
    }
    Button(
        onClick = onClick,
        modifier = modifier.clip(shape).border(1.5.dp, borderColor, shape)
            .onFocusChanged { focused = it.isFocused },
        contentPadding = PaddingValues(horizontal = if (glyph == null) 8.dp else 4.dp),
        scale = ButtonDefaults.scale(focusedScale = 1.015f),
        colors = ButtonDefaults.colors(
            containerColor = backgroundColor,
            focusedContainerColor = KazumiColors.selected.copy(alpha = .84f),
            contentColor = if (selected) KazumiColors.accent else KazumiColors.text,
            focusedContentColor = KazumiColors.text
        )
    ) {
        if (glyph == null) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text(
                    label,
                    maxLines = 1,
                    softWrap = false,
                    style = KazumiType.title.copy(
                        fontSize = 15.sp,
                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium
                    )
                )
                Box(
                    Modifier.padding(top = 2.dp).width(16.dp).height(2.dp)
                        .background(if (selected) KazumiColors.accent else Color.Transparent)
                )
            }
        } else {
            Row(
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                HomeNavigationGlyph(glyph, if (focused || selected) KazumiColors.accent else KazumiColors.muted)
                Text(
                    label,
                    maxLines = 1,
                    softWrap = false,
                    style = KazumiType.caption.copy(fontSize = 12.sp, fontWeight = FontWeight.Normal)
                )
            }
        }
    }
}

@Composable
private fun HomeNavigationGlyph(glyph: HomeNavGlyph, color: Color) {
    Canvas(Modifier.size(16.dp)) {
        val center = Offset(size.width / 2, size.height / 2)
        val strokeWidth = 1.6.dp.toPx()
        when (glyph) {
            HomeNavGlyph.Settings -> {
                for (spoke in 0 until 8) {
                    rotate(spoke * 45f, pivot = center) {
                        drawLine(
                            color,
                            Offset(center.x, size.height * .12f),
                            Offset(center.x, size.height * .29f),
                            strokeWidth,
                            StrokeCap.Round
                        )
                    }
                }
                drawCircle(color, size.minDimension * .28f, center, style = Stroke(strokeWidth))
                drawCircle(color, size.minDimension * .075f, center)
            }
            HomeNavGlyph.Search -> {
                drawCircle(color, size.minDimension * .29f, Offset(size.width * .42f, size.height * .42f), style = Stroke(strokeWidth))
                drawLine(
                    color,
                    Offset(size.width * .63f, size.height * .63f),
                    Offset(size.width * .90f, size.height * .90f),
                    strokeWidth,
                    StrokeCap.Round
                )
            }
            HomeNavGlyph.Schedule -> {
                drawRect(
                    color,
                    Offset(size.width * .13f, size.height * .18f),
                    Size(size.width * .74f, size.height * .68f),
                    style = Stroke(strokeWidth)
                )
                drawLine(color, Offset(size.width * .13f, size.height * .40f), Offset(size.width * .87f, size.height * .40f), strokeWidth)
                drawLine(color, Offset(size.width * .36f, size.height * .18f), Offset(size.width * .36f, size.height * .33f), strokeWidth, StrokeCap.Round)
                drawLine(color, Offset(size.width * .64f, size.height * .18f), Offset(size.width * .64f, size.height * .33f), strokeWidth, StrokeCap.Round)
            }
            HomeNavGlyph.History -> {
                drawCircle(color, size.minDimension * .37f, center, style = Stroke(strokeWidth))
                drawLine(color, center, Offset(center.x, size.height * .28f), strokeWidth, StrokeCap.Round)
                drawLine(color, center, Offset(size.width * .70f, center.y * 1.12f), strokeWidth, StrokeCap.Round)
            }
            HomeNavGlyph.Favorites -> {
                val heart = Path().apply {
                    moveTo(size.width * .5f, size.height * .86f)
                    cubicTo(size.width * .39f, size.height * .75f, size.width * .10f, size.height * .54f, size.width * .10f, size.height * .34f)
                    cubicTo(size.width * .10f, size.height * .09f, size.width * .39f, size.height * .07f, size.width * .5f, size.height * .30f)
                    cubicTo(size.width * .61f, size.height * .07f, size.width * .90f, size.height * .09f, size.width * .90f, size.height * .34f)
                    cubicTo(size.width * .90f, size.height * .54f, size.width * .61f, size.height * .75f, size.width * .5f, size.height * .86f)
                }
                drawPath(heart, color, style = Stroke(strokeWidth, cap = StrokeCap.Round))
            }
        }
    }
}

@Composable
private fun HomeBackdrop(subject: Subject?, oled: Boolean, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val source = subject?.takeIf { !oled && it.cover.isNotBlank() }?.let {
        HomeArtworkSource(it.id, it.cover)
    }
    var backdrop by remember { mutableStateOf(HomeBackdropState()) }
    val latestSource = rememberUpdatedState(source)
    LaunchedEffect(source) {
        backdrop = backdrop.select(source)
        val candidate = backdrop.desired ?: return@LaunchedEffect
        if (candidate.source != source || backdrop.displayed?.identity == candidate) return@LaunchedEffect
        delay(260)
        if (latestSource.value == candidate.source && backdrop.desired == candidate) {
            backdrop = backdrop.begin(candidate)
        }
    }
    val displayed = backdrop.displayed
    val activeRequest = remember(displayed?.identity, displayed?.landscape) {
        displayed?.takeIf { it.landscape }?.let { ImageRequest.Builder(context).data(it.identity.source.url).build() }
    }
    val ambientRequest = remember(displayed?.identity, displayed?.landscape) {
        displayed?.takeIf { !it.landscape }?.let {
            ImageRequest.Builder(context)
                .data(it.identity.source.url)
                .size(480, 720)
                .transformations(HomeBackdropBlurTransformation())
                .build()
        }
    }
    val pending = backdrop.pending
    val pendingRequest = remember(pending) {
        pending?.let { ImageRequest.Builder(context).data(it.source.url).build() }
    }
    Box(modifier.fillMaxSize().background(if (oled) Color.Black else Color(0xFF0B100C))) {
        if (!oled && ambientRequest != null) {
            AsyncImage(
                model = ambientRequest,
                contentDescription = null,
                modifier = Modifier.fillMaxSize().alpha(.84f),
                contentScale = ContentScale.Crop,
                onSuccess = {
                    if (org.kazumi.tv.BuildConfig.DEBUG) {
                        android.util.Log.d("HomeBackdrop", "ambient ready subject=${displayed?.identity?.source?.subjectId}")
                    }
                },
                onError = { android.util.Log.w("HomeBackdrop", "cached low-resolution ambient image unavailable") }
            )
        }
        if (!oled && activeRequest != null && displayed?.landscape == true) {
            AsyncImage(
                model = activeRequest,
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )
        }
        if (!oled && pendingRequest != null && pending != null && backdrop.desired == pending) {
            AsyncImage(
                model = pendingRequest,
                contentDescription = null,
                modifier = Modifier.fillMaxSize().alpha(0f),
                contentScale = ContentScale.Crop,
                onSuccess = { result ->
                    if (latestSource.value == pending.source) {
                        val drawable = result.result.drawable
                        val landscape = drawable.intrinsicWidth > 0 && drawable.intrinsicHeight > 0 &&
                            drawable.intrinsicWidth.toFloat() / drawable.intrinsicHeight.toFloat() >= 1.35f
                        if (org.kazumi.tv.BuildConfig.DEBUG) {
                            android.util.Log.d(
                                "HomeBackdrop",
                                "cover ready subject=${pending.source.subjectId} size=${drawable.intrinsicWidth}x${drawable.intrinsicHeight} layout=${if (landscape) "full" else "portrait-blurred-fullscreen"}"
                            )
                        }
                        backdrop = backdrop.succeed(pending, landscape)
                    }
                },
                onError = {
                    if (latestSource.value == pending.source) backdrop = backdrop.fail(pending)
                }
            )
        }
        if (!oled) {
            Box(
                Modifier.fillMaxSize().background(
                    Brush.horizontalGradient(
                        listOf(Color(0x66101611), Color(0x50101611), Color(0x28101611), Color(0x10101611))
                    )
                )
            )
            Box(
                Modifier.fillMaxSize().background(
                    Brush.verticalGradient(
                        colorStops = arrayOf(
                            0f to Color(0xCC101611),
                            .20f to Color(0xA8101611),
                            .38f to Color(0x70101611),
                            .70f to Color(0x30101611),
                            1f to Color(0x78101611)
                        )
                    )
                )
            )
        }
    }
}

@Composable
private fun SpotlightHeader(subject: Subject?, repository: TvCatalog) {
    var summary by remember(subject?.id) { mutableStateOf(subject?.summary.orEmpty()) }
    val catalogRevision by NetworkSettings.catalogRevision.collectAsState()
    LaunchedEffect(subject?.id, catalogRevision) {
        if (subject != null && summary.isBlank()) {
            delay(450)
            try {
                summary = repository.detail(subject.id).summary
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                android.util.Log.w("KazumiNetwork", "summary error=" + error.javaClass.simpleName)
            }
        }
    }
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 2.dp).heightIn(max = 70.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(subject?.title ?: "探索番组", maxLines = 1, overflow = TextOverflow.Ellipsis,
            style = KazumiType.heading, color = Color.White)
        Text(
            summary.replace(Regex("\\s+"), " ").ifBlank { "选择节目查看详情" },
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            style = KazumiType.caption,
            color = Color.White.copy(alpha = .90f)
        )
    }
}

@Composable
internal fun RecentWatchLinks(
    entries: List<HistoryEntry>,
    focusRequesters: MutableMap<Int, FocusRequester>? = null,
    onFocused: (HistoryEntry, Boolean) -> Unit = { _, _ -> },
    onSelect: (Subject) -> Unit
) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 36.dp).padding(horizontal = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("最近观看", style = KazumiType.caption, color = Color.White.copy(alpha = .82f))
        entries.distinctBy { it.subject.id }.take(2).forEach { entry ->
            val requester = focusRequesters?.getOrPut(entry.subject.id) { FocusRequester() }
            DisposableEffect(entry.subject.id) { onDispose { focusRequesters?.remove(entry.subject.id) } }
            Button(
                onClick = { onSelect(entry.subject) },
                modifier = Modifier.height(32.dp).widthIn(max = 270.dp)
                    .then(if (requester != null) Modifier.focusRequester(requester) else Modifier)
                    .onFocusChanged { onFocused(entry, it.isFocused) },
                contentPadding = PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                scale = ButtonDefaults.scale(focusedScale = 1f),
                colors = ButtonDefaults.colors(
                    containerColor = KazumiColors.selected.copy(alpha = .82f),
                    focusedContainerColor = KazumiColors.selected,
                    contentColor = Color.White,
                    focusedContentColor = KazumiColors.accent
                )
            ) {
                Text(
                    entry.subject.title + " · " + entry.episode.substringAfterLast(" · "),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = KazumiType.caption
                )
            }
        }
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
            if (panel == "licenses") LicensesScreen(Modifier.weight(1f)) else if (panel == "network") NetworkOptions(onClearCache) else if(panel=="playback") PlaybackPreferencesPanel(Modifier.weight(1f)) else if(panel=="backup") LibraryBackupScreen() else if(panel=="webdav") WebDavSettings() else if(panel=="display") DisplayModePanel() else if(panel=="capabilities") DeviceCapabilitiesPanel() else if(panel=="downloads") DownloadsScreen() else if(panel=="diagnostics") DiagnosticsScreen() else DanmakuSettings()
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
        PlayerAction("播放诊断") { panel="diagnostics" }
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
