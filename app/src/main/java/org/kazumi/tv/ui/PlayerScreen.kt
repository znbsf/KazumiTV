@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui

import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.*
import androidx.media3.ui.PlayerView
import androidx.tv.material3.*
import kotlinx.coroutines.delay
import org.kazumi.tv.data.*
import org.kazumi.tv.playback.*

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@Composable
fun PlayerScreen(request: PlaybackRequest, subject: Subject, onPrevious: (() -> Unit)? = null,
                 onNext: (() -> Unit)? = null, episodes: List<String> = emptyList(), currentEpisode: Int = -1,
                 onEpisodeSelected: ((Int) -> Unit)? = null, episodeKeys: List<String> = emptyList(), origin: PlaybackOrigin? = null,
                 initialPosition: Long? = null, initialPlayWhenReady:Boolean=true, sessionNotice: String = "",
                 onResolveAgain: ((Long, Boolean) -> Unit)? = null, onChooseRoad: ((Long, Boolean) -> Unit)? = null, onChooseSource: ((Long,Boolean)->Unit)? = null,
                 sleepTimer: PlaybackSleepTimer = PlaybackSleepTimer.shared, displaySession:DisplayModeSession?=null, onClose: () -> Unit) {
    val displayModes=displaySession ?: rememberDisplayModeSession()
    val sleepStatus by sleepTimer.state.collectAsState()
    var sleepMinutes by remember { mutableStateOf("") }
    var sleepError by remember { mutableStateOf(false) }
    var downloadNotice by remember(request) { mutableStateOf("") }
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val engine = remember(request,sleepTimer) { NativePlayer(context, request.url,offlineId=request.offlineId,sleepTimer=sleepTimer) }
    val store = remember { LibraryStore(context) }
    val preferences = remember { TvPreferences(context) }
    val danmakuRepository = remember { DanmakuCredentialStore(context).read()?.let { DanmakuRepository(it) } }
    var danmaku by remember(request) { mutableStateOf(DanmakuTimeline(emptyList())) }
    var danmakuTitle by remember(request) { mutableStateOf("") }
    var danmakuEnabled by remember { mutableStateOf(preferences.danmakuEnabled && request.offlineId==null) }
    var danmakuStatus by remember(request) { mutableStateOf("弹幕待匹配") }
    val selections=remember { DanmakuSelectionStore(context) }
    val savedSelection=remember(request) { selections.read(subject.id,request.resumeKey) }
    var danmakuOffset by remember(request) { mutableLongStateOf(savedSelection.offset) }
    var mappingAttempt by remember(request) { mutableIntStateOf(0) }
    val latestNext by rememberUpdatedState(onNext)
    val latestOrigin by rememberUpdatedState(origin)
    var rendered by remember(request) { mutableStateOf(false) }
    var status by remember(request) { mutableStateOf("正在缓冲…") }
    var failed by remember(request) { mutableStateOf(false) }
    var playing by remember(request) { mutableStateOf(false) }
    var playIntent by remember(request) { mutableStateOf(true) }
    var position by remember(request) { mutableLongStateOf(0) }
    var duration by remember(request) { mutableLongStateOf(0) }
    var tracks by remember(request) { mutableStateOf(Tracks.EMPTY) }
    var pictureMode by remember { mutableStateOf(preferences.pictureMode) }
    var menu by remember(request) { mutableStateOf<String?>(null) }
    var visible by remember(request) { mutableStateOf(true) }
    var interaction by remember { mutableIntStateOf(0) }
    var seekFeedback by remember(request) { mutableStateOf<String?>(null) }
    var seekFeedbackRevision by remember(request) { mutableIntStateOf(0) }
    LaunchedEffect(seekFeedbackRevision) { if (seekFeedback != null) { delay(1600); seekFeedback = null } }
    var manualOverride by remember(request) { mutableStateOf(false) }
    LaunchedEffect(request, danmakuEnabled, manualOverride,mappingAttempt) {
        if(request.offlineId!=null) { danmakuStatus="离线内容暂不含弹幕"; return@LaunchedEffect }
        if (!danmakuEnabled) { danmakuStatus = "弹幕已关闭"; return@LaunchedEffect }
        if (manualOverride) return@LaunchedEffect
        if (danmaku.scheduled.isNotEmpty()) { danmakuStatus = "弹幕已加载 · $danmakuTitle"; return@LaunchedEffect }
        val number = org.kazumi.tv.domain.EpisodeNumber.parse(request.title)
        if (danmakuRepository == null) { danmakuStatus = "未配置弹幕凭证"; return@LaunchedEffect }
        val selectedMapping=selections.read(subject.id,request.resumeKey).episode
        if (number == null && selectedMapping==null) { danmakuStatus = "集数不明确，请在弹幕菜单选择"; return@LaunchedEffect }
        danmakuStatus = "正在自动匹配第 $number 集弹幕…"
        try {
            val matched = selectedMapping ?: danmakuRepository.automaticEpisode(subject.id, number!!)
            if (matched == null) danmakuStatus = "未找到唯一对应剧集，可手动选择"
            else {
                val comments = danmakuRepository.comments(matched.id)
                danmaku = DanmakuTimeline(comments); danmakuTitle = matched.title
                danmakuStatus = if (comments.isEmpty()) "本集暂无弹幕" else "弹幕 ${comments.size} 条 · ${if(selectedMapping!=null) "已恢复手选" else "已自动匹配"}"
                android.util.Log.i("KazumiDanmaku", "automatic subject=${subject.id} episode=$number comments=${comments.size}")
            }
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (_: Exception) { danmakuStatus = "自动加载失败，可在弹幕菜单重试或手动选择" }
    }
    val rootFocus = remember { FocusRequester() }
    val controlsFocus = remember { FocusRequester() }
    val menuFocus = remember { FocusRequester() }
    fun saveProgress() {
        if (rendered) store.save(HistoryEntry(request.resumeKey, subject, request.title,
            engine.player.currentPosition.coerceAtLeast(0), engine.player.duration.coerceAtLeast(0), latestOrigin,kind=if(request.offlineId!=null)HistoryKind.OFFLINE else HistoryKind.ONLINE))
    }
    SideEffect {
        engine.setEpisodeNavigation(
            onPrevious?.let { select -> { saveProgress(); engine.player.pause(); select() } },
            onNext?.let { select -> { saveProgress(); engine.player.pause(); select() } }
        )
    }
    var externalTargets by remember(request) { mutableStateOf<List<ExternalTarget>>(emptyList()) }
    var externalError by remember(request) { mutableStateOf("") }
    var externalPending by remember { mutableStateOf<Pair<PlaybackRequest,Boolean>?>(null) }
    val externalLauncher=rememberExternalLauncher { result ->
        val pending=externalPending; externalPending=null
        if(pending!=null && pending.first==request) {
            engine.player.pause()
            ExternalPlayback.returnedPosition(request,pending.second,result.resultCode,result.data)?.let { returned ->
                val end=engine.player.duration
                engine.player.seekTo(if(end>0)returned.coerceAtMost(end) else returned)
                saveProgress()
            }
            visible=true; menu=null
            downloadNotice=when(result.resultCode) {
                android.app.Activity.RESULT_OK -> "已返回内置播放器，按播放继续；未回传的外播进度不会覆盖本地记录。"
                android.app.Activity.RESULT_CANCELED -> "外部播放已取消或未回传结果；内置播放器保持暂停。"
                else -> "外部播放器报告播放失败；内置播放器保持暂停，可换应用或继续内置播放。"
            }
            android.util.Log.i("KazumiExternal","result code=${result.resultCode} mx=${pending.second}")
        }
    }
    fun toggle() { if (engine.player.playWhenReady) engine.player.pause() else engine.player.play() }
    fun handleBack() { when { menu != null -> menu = null; visible && playing -> visible = false; else -> onClose() } }
    LaunchedEffect(sleepStatus.expired) { if(sleepStatus.expired) { visible=true; menu="定时停止" } }
    BackHandler { handleBack() }
    LaunchedEffect(visible, playing, interaction, menu) {
        if (visible && playing && menu == null) { delay(preferences.controlsSeconds*1000L); visible = false }
    }
    LaunchedEffect(engine) {
        while (true) { position = engine.player.currentPosition.coerceAtLeast(0); duration = engine.player.duration.coerceAtLeast(0); delay(500) }
    }
    LaunchedEffect(engine, rendered) { if (rendered) while (true) { delay(5000); saveProgress() } }
    DisposableEffect(engine, lifecycle) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) { playing = isPlaying }
            override fun onPlayWhenReadyChanged(ready: Boolean, reason: Int) { playIntent = ready }
            override fun onTracksChanged(value: Tracks) { tracks = value }
            override fun onRenderedFirstFrame() {
                status = ""; rendered = true
                android.util.Log.i("KazumiPlayback", "first_frame position_ms=${engine.player.currentPosition} size=${engine.player.videoFormat?.width}x${engine.player.videoFormat?.height}")
            }
            override fun onPlayerError(error: PlaybackException) {
                val http = generateSequence<Throwable>(error) { it.cause }.filterIsInstance<androidx.media3.datasource.HttpDataSource.InvalidResponseCodeException>().firstOrNull()
                status = "播放失败：${error.errorCodeName}" + (http?.let { " · HTTP ${it.responseCode}" } ?: "")
                failed = true; menu = null; visible = true
            }
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_BUFFERING) status = "正在缓冲…"
                if (state == Player.STATE_READY) status = ""
                if (state == Player.STATE_ENDED) { saveProgress(); status = "播放结束"; if (preferences.autoNext && !sleepTimer.refresh().expired) latestNext?.invoke() }
            }
        }
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_STOP -> { saveProgress(); engine.setForegroundActive(false) }
                Lifecycle.Event.ON_START -> engine.setForegroundActive(true)
                else -> Unit
            }
        }
        engine.player.addListener(listener); lifecycle.addObserver(observer)
        val saved = store.history().firstOrNull { it.key == request.resumeKey }
        val resume = initialPosition ?: PlaybackStateSavers.historyResumePosition(saved?.position, saved?.duration ?: 0, preferences.resumePlayback)
        android.util.Log.i("KazumiPlayback", "open resume_ms=$resume")
        engine.open(request, resume)
        if(!initialPlayWhenReady)engine.player.pause()
        if (!lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) engine.setForegroundActive(false)
        onDispose { saveProgress(); lifecycle.removeObserver(observer); engine.player.removeListener(listener); engine.release() }
    }
    Box(Modifier.fillMaxSize().background(Color.Black).onPreviewKeyEvent { event ->
        val key = event.nativeKeyEvent
        if(key.keyCode==KeyEvent.KEYCODE_BACK) {
            // Older TV input dispatch may send BACK to the focused view before the dispatcher.
            // Consume the matching UP too so one press cannot also close the restored controls.
            if(key.action==KeyEvent.ACTION_DOWN&&key.repeatCount==0) { interaction++;handleBack() }
            true
        } else if (key.action != KeyEvent.ACTION_DOWN) false else {
            interaction++
            when (key.keyCode) {
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> { toggle(); visible = true; true }
                KeyEvent.KEYCODE_MEDIA_PLAY -> { engine.player.play(); true }
                KeyEvent.KEYCODE_MEDIA_PAUSE -> { engine.player.pause(); visible = true; true }
                KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> { engine.player.seekForward(); visible = true; true }
                KeyEvent.KEYCODE_MEDIA_REWIND -> { engine.player.seekBack(); visible = true; true }
                KeyEvent.KEYCODE_DPAD_LEFT -> if (!visible) { engine.player.seekBack(); seekFeedback="快退 · ${clockTime(engine.player.currentPosition.coerceAtLeast(0))}"; seekFeedbackRevision++; true } else false
                KeyEvent.KEYCODE_DPAD_RIGHT -> if (!visible) { engine.player.seekForward(); seekFeedback="快进 · ${clockTime(engine.player.currentPosition.coerceAtLeast(0))}"; seekFeedbackRevision++; true } else false
                KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER ->
                    if (!visible) { toggle(); visible = true; true } else false
                KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN ->
                    if (!visible) { visible = true; true } else false
                else -> false
            }
        }
    }.then(playerEntryFocus(rootFocus, request, active = !visible && menu == null)).focusable()) {
        PlaybackVideoSurface(engine.player, playing,pictureMode)
        if (danmakuEnabled && danmaku.scheduled.isNotEmpty()) AndroidView(
            factory = { DanmakuView(it) }, modifier = Modifier.fillMaxSize(),
            update = { it.player = engine.player; it.timeline = danmaku; it.offsetMs = danmakuOffset; it.invalidate() },
            onRelease = { it.player = null })
        if (!visible && seekFeedback != null) {
            Text(seekFeedback!!, style=KazumiType.title, modifier=Modifier.align(Alignment.BottomCenter)
                .padding(bottom=42.dp).background(Color.Black.copy(alpha=.78f)).padding(horizontal=20.dp, vertical=10.dp))
        }
        if (visible && menu == null) {
            Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(280.dp)
                .background(androidx.compose.ui.graphics.Brush.verticalGradient(listOf(Color.Transparent,Color.Black.copy(alpha=.70f),Color.Black.copy(alpha=.85f)))))
            Column(Modifier.align(Alignment.TopStart).fillMaxWidth()
                .background(androidx.compose.ui.graphics.Brush.verticalGradient(listOf(Color.Black.copy(alpha = .8f), Color.Transparent)))
                .padding(horizontal = 30.dp, vertical = 20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(subject.title, style = KazumiType.title, maxLines = 1)
                Text(request.title.substringAfterLast(" · "), style = KazumiType.caption, color = KazumiColors.muted)
            }
            Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                .padding(horizontal = 28.dp, vertical = 20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (status.isNotBlank()) Text(status, style = KazumiType.caption)
                if (failed) Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    PlayerAction("重新加载", playerEntryFocus(controlsFocus, request to failed)) {
                        if (onResolveAgain != null) onResolveAgain(engine.player.currentPosition.coerceAtLeast(0), playIntent)
                        else { failed = false; engine.open(request, position) }
                    }
                    if (onChooseRoad != null) PlayerAction("更换线路") { val resumePlay=engine.player.playWhenReady; engine.player.pause(); onChooseRoad(engine.player.currentPosition.coerceAtLeast(0),resumePlay) }
                    if (onChooseSource != null) PlayerAction("更换来源") { val resumePlay=engine.player.playWhenReady; engine.player.pause(); onChooseSource(engine.player.currentPosition.coerceAtLeast(0),resumePlay) }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("${clockTime(position)} / ${clockTime(duration)}", style = KazumiType.caption)
                    Text(if (danmakuEnabled) danmakuStatus else "弹幕已关闭", modifier = Modifier.weight(1f).padding(start = 24.dp), maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, style = KazumiType.caption, color = KazumiColors.muted)
                }
                PlayerProgress(position, duration, engine.player.bufferedPosition,preferences.seekSeconds*1000L) { interaction++; engine.player.seekTo(it) }
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    PlayerAction(if (playIntent) "Ⅱ 暂停" else "▷ 播放", if (failed) Modifier else playerEntryFocus(controlsFocus, request to failed)) { interaction++; toggle() }
                    if (episodes.isNotEmpty()) PlayerAction("选集") { menu = "选集" }
                    if (onNext != null) PlayerAction("下一集", onClick = onNext)
                    if (onChooseRoad != null) PlayerAction("线路") { val resumePlay=engine.player.playWhenReady; engine.player.pause(); onChooseRoad(engine.player.currentPosition.coerceAtLeast(0),resumePlay) }
                    if(onChooseSource!=null)PlayerAction("换源") { val resumePlay=engine.player.playWhenReady; engine.player.pause(); onChooseSource(engine.player.currentPosition.coerceAtLeast(0),resumePlay) }
                    if(request.offlineId==null)PlayerAction(if (danmakuEnabled) "弹幕 开" else "弹幕 关") { danmakuEnabled = !danmakuEnabled; preferences.danmakuEnabled = danmakuEnabled }
                    PlayerAction("设置") { menu="设置" }

                }
                Text("上下查看控制 · 进度条左右快进退", style = KazumiType.caption, color = KazumiColors.muted)
                if(downloadNotice.isNotBlank())Text(downloadNotice,style=KazumiType.caption,color=KazumiColors.muted)
                if (sessionNotice.isNotBlank()) Text(sessionNotice, style = KazumiType.caption, color = KazumiColors.muted)
            }
        }
        if (menu == "弹幕") DanmakuPanel(danmakuRepository, subject.title, danmakuTitle, danmakuEnabled, danmakuOffset,
            menuFocus, Modifier.align(Alignment.CenterEnd).fillMaxHeight().width(460.dp)
                .then(playerEntryFocus(menuFocus, request to menu, attachRequester = false)),
            onClose = { menu = null }, onToggle = { danmakuEnabled = !danmakuEnabled; preferences.danmakuEnabled = danmakuEnabled }, onOffset = { danmakuOffset = it; selections.save(subject.id,request.resumeKey,selections.read(subject.id,request.resumeKey).copy(offset=it)) },
            onLoaded = { selected, comments -> selections.save(subject.id,request.resumeKey,DanmakuSelection(selected,danmakuOffset)); manualOverride = true; danmakuTitle = selected.title; danmaku = DanmakuTimeline(comments); danmakuEnabled = true; preferences.danmakuEnabled = true; danmakuStatus = "弹幕 ${comments.size} 条 · 手动选择" },
            onAutomatic={ selections.clear(subject.id,request.resumeKey); danmakuOffset=0; manualOverride=false; danmaku=DanmakuTimeline(emptyList()); mappingAttempt++ })
        if(menu=="选集") {
            Column(Modifier.align(Alignment.CenterEnd).fillMaxHeight().width(650.dp).background(KazumiColors.surface).padding(24.dp)) {
                PlayerAction("返回播放",playerEntryFocus(menuFocus, request to menu)) { menu=null }
                val seen=store.history().filter { it.subject.id==subject.id && it.position>0 }.map { it.key }.toSet()
                EpisodeBrowser(episodes,currentEpisode,episodeKeys.indices.filter { episodeKeys[it] in seen }.toSet(),Modifier.weight(1f),restoreIndex=currentEpisode) {
                    onEpisodeSelected?.invoke(it); menu=null
                }
            }
        }
        if(menu=="显示模式") {
            Column(Modifier.align(Alignment.CenterEnd).fillMaxHeight().width(480.dp).background(KazumiColors.background).padding(24.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
                PlayerAction("返回播放",playerEntryFocus(menuFocus, request to menu)) { menu=null }
                DisplayModePanel(displayModes,duringPlayback=true)
            }
        }
        if (menu != null && menu != "弹幕" && menu != "选集" && menu != "显示模式") {
            LazyColumn(Modifier.align(Alignment.CenterEnd).fillMaxHeight().width(340.dp).background(Color(0xFF171D18)).padding(28.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                item { Text(menu!!) }
                item { PlayerAction("返回播放",playerEntryFocus(menuFocus, request to menu)) { menu=null } }
                if(menu=="设置") {
                    if(onPrevious!=null)item { PlayerAction("上一集",onClick=onPrevious) }
                    if(request.offlineId==null)item { PlayerAction("弹幕设置") { menu="弹幕" } }
                    item { PlayerAction("倍速 · ${engine.player.playbackParameters.speed}×") { menu="播放速度" } }
                    item { PlayerAction("画面比例 · ${pictureMode.label}") { menu="画面比例" } }
                    if(displayModes!=null)item { PlayerAction("显示模式") { menu="显示模式" } }
                    item { PlayerAction("音轨 / 字幕") { menu="音轨与字幕" } }
                    item { PlayerAction(if(sleepStatus.remainingMs>0) "定时 · ${((sleepStatus.remainingMs+59999)/60000)}分" else "定时停止") { menu="定时停止" } }
                    item { PlayerAction("播放信息") { menu="播放信息" } }
                    if(request.offlineId==null) {
                        item { PlayerAction("外部播放器") {
                            externalError=""
                            externalTargets=runCatching { ExternalPlayback.targets(context,request) }.getOrElse { externalError=it.message ?: "无法读取播放器"; emptyList() }
                            menu="外部播放器"
                        } }
                        item { PlayerAction("下载本集") {
                            downloadNotice=runCatching { org.kazumi.tv.download.OfflineDownloads.get(context).enqueue(request,subject,origin); "已加入下载，可在设置的离线下载中查看" }.getOrElse { it.message ?: "无法加入下载" }
                            menu=null
                        } }
                    }
                } else if(menu=="外部播放器") {
                    item { Text("选择后会将本集地址交给该应用。MX Player 可接收请求头与当前位置；其他播放器可能从头播放。弹幕、定时和连播由外部应用管理。",style=KazumiType.caption) }
                    if(request.headers.isNotEmpty())item { Text("本来源需要请求头，选择 MX Player 时会一并传递。",style=KazumiType.caption) }
                    if(externalTargets.isEmpty())item { Text("没有找到可用的外部播放器",style=KazumiType.body) }
                    if(externalError.isNotBlank())item { Text(externalError,style=KazumiType.caption) }
                    items(externalTargets,key={it.component.flattenToString()}) { target ->
                        PlayerAction(target.label) {
                            runCatching {
                                val intent=ExternalPlayback.intent(request,target,engine.player.currentPosition)
                                saveProgress(); engine.player.pause(); externalPending=request to target.mx
                                externalLauncher(intent)
                            }.onFailure { externalPending=null; externalError=if(it is IllegalArgumentException)it.message ?: "无法打开" else "无法打开该播放器，请选择其他应用或返回播放" }
                        }
                    }
                } else if(menu=="定时停止") {
                    item { Text(if(sleepStatus.expired) "定时时间已到，视频已暂停。" else if(sleepStatus.remainingMs>0) "剩余 ${(sleepStatus.remainingMs+999)/1000} 秒" else "尚未设置定时。",style=KazumiType.body) }
                    if(sleepStatus.expired) {
                        item { PlayerAction("继续播放") { sleepTimer.cancel(); engine.player.play(); menu=null } }
                        if(sleepStatus.lastDurationMs>0)item { PlayerAction("重新计时（保持暂停）") { sleepTimer.start(sleepStatus.lastDurationMs); menu=null } }
                    }
                    if(sleepStatus.remainingMs>0 || sleepStatus.expired)item { PlayerAction("取消定时") { sleepTimer.cancel(); menu=null } }
                    item { Text("只暂停播放，换集不会重置；应用被系统关闭后需重新设置。",style=KazumiType.caption) }
                    items(listOf(15,30,60,90,120)) { minutes -> PlayerAction("${minutes}分钟") { sleepTimer.start(minutes*60000L); menu=null } }
                    item { Text("自定义分钟",style=KazumiType.caption); TvTextInput(sleepMinutes,{ sleepMinutes=it.filter(Char::isDigit).take(4) }) }
                    item { PlayerAction("设置自定义分钟") { val minutes=sleepMinutes.toIntOrNull(); if(minutes==null || minutes !in 1..1440)sleepError=true else { sleepError=false; sleepTimer.start(minutes*60000L); menu=null } } }
                    if(sleepError)item { Text("请输入1至1440分钟",style=KazumiType.caption) }
                } else if (menu == "播放速度") items(PlaybackOptions.speeds) { speed ->
                    Button(onClick = { preferences.speed=speed; engine.player.setPlaybackSpeed(speed); menu = null }) { Text("${speed}×") }
                } else if(menu=="画面比例") {
                    items(PictureMode.entries) { mode -> Button(onClick={ preferences.pictureMode=mode; pictureMode=mode; menu=null }) { Text(mode.label) } }
                } else if (menu == "播放信息") {
                    item { Text("Media3 · ${if (rendered) "已渲染首帧" else "等待首帧"}") }
                    if(preferences.incognito) item { Text("隐身播放 · 本次不保存观看进度") }
                    item { Text("视频输出：${if (preferences.videoOutput.usesTexture(android.os.Build.DEVICE,android.os.Build.VERSION.SDK_INT)) "TextureView" else "SurfaceView"}") }
                    item { Text("${engine.resourcePolicy.label}\n播放缓冲目标 ${engine.resourcePolicy.targetBytes / 1024 / 1024}MiB · ${engine.resourcePolicy.maxBufferMs / 1000}秒\n目标不包含解码器和画面内存") }
                    item {
                        val decoder by engine.diagnostics.collectAsState()
                        Text("视频解码器 ${decoder.video ?: "尚未初始化"}\n初始化 ${decoder.videoInitMs?.let { "${it}ms" } ?: "—"}\n音频解码器 ${decoder.audio ?: "尚未初始化"}\n初始化 ${decoder.audioInitMs?.let { "${it}ms" } ?: "—"}")
                    }
                    item { Text("画面 ${engine.player.videoFormat?.width ?: 0} × ${engine.player.videoFormat?.height ?: 0}") }
                    item { Text("视频 ${engine.player.videoFormat?.sampleMimeType ?: "未知"}\n音频 ${engine.player.audioFormat?.sampleMimeType ?: "未知"}") }
                    item { Text("已渲染帧 ${engine.player.videoDecoderCounters?.renderedOutputBufferCount ?: 0}\n丢帧 ${engine.player.videoDecoderCounters?.droppedBufferCount ?: 0}") }
                    item { Text("已缓冲 ${clockTime(engine.player.totalBufferedDuration)}\n倍速 ${engine.player.playbackParameters.speed}×") }
                } else {
                    item { Button(onClick = { preferences.subtitles=false; engine.player.trackSelectionParameters=engine.player.trackSelectionParameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_TEXT,true).build(); menu = null }) { Text("关闭字幕") } }
                    item { Button(onClick = { preferences.audioLanguage=null; preferences.textLanguage=null; preferences.subtitles=true; engine.applyTrackPreferences(); menu = null }) { Text("自动选择音轨 / 字幕") } }
                    tracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO || it.type == C.TRACK_TYPE_TEXT }.forEach { group ->
                        items((0 until group.length).filter { group.isTrackSupported(it) }) { index ->
                            val format = group.getTrackFormat(index)
                            val label = (if (group.type == C.TRACK_TYPE_AUDIO) "音轨" else "字幕") + " · " + (format.label ?: format.language ?: "轨道 ${index + 1}")
                            Button(onClick = {
                                val language=PlaybackOptions.language(format.language)
                                if(group.type==C.TRACK_TYPE_TEXT) { preferences.subtitles=true; if(language!=null)preferences.textLanguage=language }
                                else if(language!=null)preferences.audioLanguage=language
                                engine.player.trackSelectionParameters = engine.player.trackSelectionParameters.buildUpon().setTrackTypeDisabled(group.type, false).setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, index)).build(); menu = null }) { Text((if (group.isTrackSelected(index)) "✓ " else "") + label) }
                        }
                    }
                }
            }
        }
    }
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@Composable
internal fun PlaybackVideoSurface(player: Player, playing: Boolean, pictureMode: PictureMode=PictureMode.FIT) {
    var subtitleCues by remember(player) { mutableStateOf(player.currentCues.cues) }
    DisposableEffect(player) {
        val listener=object: Player.Listener {
            override fun onCues(cueGroup: androidx.media3.common.text.CueGroup) { subtitleCues=cueGroup.cues }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }
    BoxWithConstraints(Modifier.fillMaxSize().background(Color.Black),contentAlignment=Alignment.Center) {
        val frame=PlaybackOptions.frame(maxWidth.value,maxHeight.value,pictureMode)
        AndroidView(factory = { createPlaybackView(it).apply {
            // Compose owns all remote controls. A native PlayerView/Surface must never steal focus
            // when a LazyColumn menu replaces the controls, even with useController=false.
            isFocusable=false;isFocusableInTouchMode=false
            descendantFocusability=android.view.ViewGroup.FOCUS_BLOCK_DESCENDANTS
        } },
            update = {
                it.player=player; it.keepScreenOn=playing
                it.subtitleView?.visibility=android.view.View.GONE
                it.resizeMode=when(pictureMode) {
                    PictureMode.FIT -> androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
                    PictureMode.CROP -> androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                    else -> androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FILL
                }
            },modifier=Modifier.width(frame.first.dp).height(frame.second.dp),onRelease={ it.player=null })
        AndroidView(factory={ androidx.media3.ui.SubtitleView(it) },
            update={ it.setCues(subtitleCues) },modifier=Modifier.width(frame.first.dp).height(frame.second.dp),
            onRelease={ it.setCues(emptyList()) })
    }
}

private fun clockTime(ms: Long): String = "%02d:%02d".format(ms / 60000, ms / 1000 % 60)

/** Focus only after this entry target is attached; a fixed frame delay is not a mount signal.
 * The effect belongs to the actual control, so removing it cancels a pending request.
 * Layout changes after a successful request must not pull focus away from remote navigation.
 */
@Composable
private fun playerEntryFocus(
    requester: FocusRequester,
    entry: Any?,
    active: Boolean = true,
    attachRequester: Boolean = true,
): Modifier {
    var coordinates by remember(requester) { mutableStateOf<LayoutCoordinates?>(null) }
    var requested by remember(requester, entry, active) { mutableStateOf(false) }
    LaunchedEffect(requester, entry, active, coordinates) {
        // No suspension between checking attachment and requesting on the UI thread.
        // A new control/menu gets its own layout callback and therefore another attempt.
        while (active && !requested && coordinates?.isAttached == true) {
            requested = requester.requestFocus()
            if (!requested) withFrameNanos { }
        }
    }
    return (if (attachRequester) Modifier.focusRequester(requester) else Modifier)
        .onGloballyPositioned { coordinates = it }
}
