package org.kazumi.tv.playback

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.FlagSet
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaMetadata
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.session.MediaSession
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.UUID
import androidx.media3.datasource.okhttp.OkHttpDataSource
import org.kazumi.tv.data.AppHttp
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory

interface PlaybackEngine {
    val player: Player
    fun open(request: PlaybackRequest, positionMs: Long = 0)
    fun release()
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class NativePlayer(context: Context, sourceUri: String? = null,
    private val offlineId:String?=null,
    val resourcePolicy: ResourcePolicy = DeviceResourcePolicy.read(context, if(offlineId!=null) "file:///offline" else sourceUri),
    private val sleepTimer: PlaybackSleepTimer = PlaybackSleepTimer.shared) : PlaybackEngine {
    private val preferences=org.kazumi.tv.data.TvPreferences(context)
    private val appContext = context.applicationContext
    private val sessionId = "kazumitv-${UUID.randomUUID()}"
    private var released = false
    private var foregroundActive = false
    private var session: MediaSession? = null
    private val mutableDiagnostics = MutableStateFlow(DecoderDiagnostics())
    val diagnostics = mutableDiagnostics.asStateFlow()
    private val http = OkHttpDataSource.Factory(AppHttp.streamingClient)
    override val player = ExoPlayer.Builder(context, DefaultRenderersFactory(context).setEnableDecoderFallback(true))
        .setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true)
        .setHandleAudioBecomingNoisy(true)
        .setSeekBackIncrementMs(preferences.seekSeconds*1000L).setSeekForwardIncrementMs(preferences.seekSeconds*1000L)
        .setLoadControl(DefaultLoadControl.Builder()
            .setBufferDurationsMs(resourcePolicy.minBufferMs, resourcePolicy.maxBufferMs, resourcePolicy.startMs, resourcePolicy.rebufferMs)
            .setTargetBufferBytes(resourcePolicy.targetBytes).setPrioritizeTimeOverSizeThresholds(false).build())
        .setMediaSourceFactory(DefaultMediaSourceFactory(context).setDataSourceFactory((if(offlineId!=null)org.kazumi.tv.download.OfflineDownloads.get(context).offlineFactory(offlineId) else DefaultDataSource.Factory(context, http)))).build()
    private val detachSleep = sleepTimer.attach { player.pause() }
    private val sessionPlayer = EpisodeSessionPlayer()
    /** Catalogue ownership stays in PlaybackSessionScreen; MediaSession only requests selection. */
    fun setEpisodeNavigation(previous: (() -> Unit)?, next: (() -> Unit)?) {
        if(!released)sessionPlayer.update(previous,next)
    }
    private inner class EpisodeSessionPlayer : ForwardingPlayer(player) {
        private var previous: (() -> Unit)? = null
        private var next: (() -> Unit)? = null
        private var pending = false
        private val listeners = mutableMapOf<Player.Listener, Player.Listener>()
        private fun canNavigate() = foregroundActive && !released && !pending
        override fun getAvailableCommands(): Player.Commands = super.getAvailableCommands().buildUpon()
            .remove(Player.COMMAND_SEEK_TO_PREVIOUS).remove(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
            .remove(Player.COMMAND_SEEK_TO_NEXT).remove(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
            .addIf(Player.COMMAND_SEEK_TO_PREVIOUS,canNavigate()&&previous!=null)
            .addIf(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,canNavigate()&&previous!=null)
            .addIf(Player.COMMAND_SEEK_TO_NEXT,canNavigate()&&next!=null)
            .addIf(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,canNavigate()&&next!=null).build()
        override fun isCommandAvailable(command: Int) = availableCommands.contains(command)
        override fun seekToPrevious() = navigate(previous)
        override fun seekToPreviousMediaItem() = navigate(previous)
        override fun seekToNext() = navigate(next)
        override fun seekToNextMediaItem() = navigate(next)
        private fun navigate(action: (() -> Unit)?) {
            if(!canNavigate()||action==null)return
            pending=true
            notifyCommands()
            this@NativePlayer.player.pause()
            action()
        }
        fun update(previous: (() -> Unit)?, next: (() -> Unit)?) {
            val before=availableCommands
            this.previous=previous;this.next=next
            if(before!=availableCommands)notifyCommands()
        }
        fun notifyCommands() {
            val commands=availableCommands
            val events=Player.Events(FlagSet.Builder().add(Player.EVENT_AVAILABLE_COMMANDS_CHANGED).build())
            listeners.keys.toList().forEach { it.onAvailableCommandsChanged(commands);it.onEvents(this,events) }
        }
        override fun addListener(listener: Player.Listener) {
            if(listeners.containsKey(listener))return
            val forwarding=object : Player.Listener by listener {
                override fun onAvailableCommandsChanged(availableCommands: Player.Commands) {
                    listener.onAvailableCommandsChanged(this@EpisodeSessionPlayer.availableCommands)
                }
            }
            listeners[listener]=forwarding
            super.addListener(forwarding)
        }
        override fun removeListener(listener: Player.Listener) {
            listeners.remove(listener)?.let { super.removeListener(it) }
        }
        fun detach() {
            previous=null;next=null
            listeners.values.toList().forEach { super.removeListener(it) }
            listeners.clear()
        }
    }
    fun applyTrackPreferences() {
        player.trackSelectionParameters=player.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_AUDIO).clearOverridesOfType(C.TRACK_TYPE_TEXT)
            .setPreferredAudioLanguage(preferences.audioLanguage).setPreferredTextLanguage(preferences.textLanguage)
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT,!preferences.subtitles).build()
    }
    init {
        player.setPlaybackSpeed(preferences.speed)
        applyTrackPreferences()
        player.addListener(object: Player.Listener {
            override fun onPlayWhenReadyChanged(ready:Boolean,reason:Int) {
                // Open never auto-plays after expiry; an explicit play command acknowledges it.
                if(ready && sleepTimer.state.value.expired)sleepTimer.cancel()
            }
            override fun onTracksChanged(tracks: androidx.media3.common.Tracks) {
                val preferred=preferences.textLanguage
                val parameters=player.trackSelectionParameters
                if(!preferences.subtitles || C.TRACK_TYPE_TEXT in parameters.disabledTrackTypes ||
                    parameters.overrides.keys.any { it.type==C.TRACK_TYPE_TEXT })return
                val formats=tracks.groups.filter { it.type==C.TRACK_TYPE_TEXT }.flatMap { group ->
                    (0 until group.length).filter { group.isTrackSupported(it) }.map { group.getTrackFormat(it) }
                }
                if(formats.isEmpty())return
                val audio=tracks.groups.filter { it.type==C.TRACK_TYPE_AUDIO }.flatMap { group ->
                    (0 until group.length).filter { group.isTrackSelected(it) }.map { group.getTrackFormat(it).language }
                }.firstOrNull()
                val chosen=formats.firstOrNull { PlaybackOptions.sameLanguage(preferred,it.language) }
                    ?: formats.firstOrNull { it.selectionFlags and C.SELECTION_FLAG_DEFAULT != 0 }
                    ?: formats.firstOrNull { PlaybackOptions.sameLanguage(audio,it.language) }
                    ?: formats.first()
                val desired=PlaybackOptions.language(chosen.language)?.let { androidx.media3.common.util.Util.normalizeLanguageCode(it) }
                val undetermined=desired==null
                if(parameters.preferredTextLanguages.firstOrNull()!=desired || parameters.selectUndeterminedTextLanguage!=undetermined)
                    player.trackSelectionParameters=parameters.buildUpon().setPreferredTextLanguage(desired)
                        .setSelectUndeterminedTextLanguage(undetermined).build()
                // The saved language remains intact for the next media item.
            }
        })
        player.addAnalyticsListener(object : AnalyticsListener {
            override fun onVideoDecoderInitialized(eventTime: AnalyticsListener.EventTime, decoderName: String, initializedTimestampMs: Long, initializationDurationMs: Long) {
                mutableDiagnostics.value = mutableDiagnostics.value.copy(video = decoderName, videoInitMs = initializationDurationMs)
            }
            override fun onAudioDecoderInitialized(eventTime: AnalyticsListener.EventTime, decoderName: String, initializedTimestampMs: Long, initializationDurationMs: Long) {
                mutableDiagnostics.value = mutableDiagnostics.value.copy(audio = decoderName, audioInitMs = initializationDurationMs)
            }
        })
        setForegroundActive(true)
    }
    /** Foreground-only playback: a stopped screen must not remain remotely playable. */
    fun setForegroundActive(active: Boolean) {
        if (released) return
        foregroundActive=active
        sessionPlayer.notifyCommands()
        if (active) {
            sleepTimer.refresh()
            if (session == null) session = MediaSession.Builder(appContext, sessionPlayer).setId(sessionId).build()
        } else {
            player.pause()
            session?.release()
            session = null
        }
    }
    val sessionToken get() = session?.token
    override fun open(request: PlaybackRequest, positionMs: Long) {
        check(!released)
        mutableDiagnostics.value = DecoderDiagnostics()
        applyTrackPreferences()
        http.setDefaultRequestProperties(request.headers)
        player.setMediaItem(MediaItem.Builder().setMediaId(UUID.randomUUID().toString()).setUri(request.url).setMimeType(request.mimeType)
            .setMediaMetadata(MediaMetadata.Builder().setTitle(request.title).build()).build(), positionMs)
        player.prepare()
        player.playWhenReady = !sleepTimer.refresh().expired
    }
    override fun release() {
        if (released) return
        released = true
        foregroundActive=false
        detachSleep()
        session?.release()
        session = null
        sessionPlayer.detach()
        player.release()
    }
}

data class DecoderDiagnostics(val video: String? = null, val videoInitMs: Long? = null,
    val audio: String? = null, val audioInitMs: Long? = null)
