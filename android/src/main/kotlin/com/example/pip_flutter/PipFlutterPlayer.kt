package com.example.pip_flutter

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import android.view.Surface
import androidx.lifecycle.Observer
import androidx.media.session.MediaButtonReceiver
import androidx.work.Data
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.example.pip_flutter.DataSourceUtils.getDataSourceFactory
import com.example.pip_flutter.DataSourceUtils.getUserAgent
import com.example.pip_flutter.DataSourceUtils.isHTTP
import com.google.android.exoplayer2.*
import com.google.android.exoplayer2.C.TRACK_TYPE_AUDIO
import com.google.android.exoplayer2.Player.STATE_BUFFERING
import com.google.android.exoplayer2.audio.AudioAttributes
import com.google.android.exoplayer2.drm.*
import com.google.android.exoplayer2.ext.mediasession.MediaSessionConnector
import com.google.android.exoplayer2.extractor.DefaultExtractorsFactory
import com.google.android.exoplayer2.source.ClippingMediaSource
import com.google.android.exoplayer2.source.MediaSource
import com.google.android.exoplayer2.source.ProgressiveMediaSource
import com.google.android.exoplayer2.source.dash.DashMediaSource
import com.google.android.exoplayer2.source.dash.DefaultDashChunkSource
import com.google.android.exoplayer2.source.hls.HlsMediaSource
import com.google.android.exoplayer2.source.smoothstreaming.DefaultSsChunkSource
import com.google.android.exoplayer2.source.smoothstreaming.SsMediaSource
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector
import com.google.android.exoplayer2.trackselection.TrackSelectionOverride
import com.google.android.exoplayer2.ui.PlayerNotificationManager
import com.google.android.exoplayer2.ui.PlayerNotificationManager.BitmapCallback
import com.google.android.exoplayer2.ui.PlayerNotificationManager.MediaDescriptionAdapter
import com.google.android.exoplayer2.upstream.DataSource
import com.google.android.exoplayer2.upstream.DefaultDataSource
import com.google.android.exoplayer2.upstream.DefaultHttpDataSource
import com.google.android.exoplayer2.util.Util
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry.SurfaceTextureEntry
import java.io.File
import java.util.*
import kotlin.math.max
import kotlin.math.min


internal class PipFlutterPlayer(
    context: Context,
    private val eventChannel: EventChannel,
    private val textureEntry: SurfaceTextureEntry,
    customDefaultLoadControl: CustomDefaultLoadControl?,
    result: MethodChannel.Result
) {
    private val exoPlayer: ExoPlayer?
    private var onStopCallback: (()->Unit)? = null
    internal val eventSink = QueuingEventSink()
    private val trackSelector: DefaultTrackSelector = DefaultTrackSelector(context)
    private val loadControl: LoadControl
    private var isInitialized = false
    private var surface: Surface? = null
    private var key: String? = null
    private var playerNotificationManager: PlayerNotificationManager? = null
    private var refreshHandler: Handler? = null
    private var refreshRunnable: Runnable? = null
    private var exoPlayerEventListener: Player.Listener? = null
    private var bitmap: Bitmap? = null
    private var mediaSession: MediaSessionCompat? = null
    private var drmSessionManager: DrmSessionManager? = null
    private val workManager: WorkManager
    private val workerObserverMap: HashMap<UUID, Observer<WorkInfo?>>
    private val customDefaultLoadControl: CustomDefaultLoadControl =
        customDefaultLoadControl ?: CustomDefaultLoadControl()
    private var lastSendBufferedPosition = 0L

    init {
        val loadBuilder = DefaultLoadControl.Builder()
        loadBuilder.setBufferDurationsMs(
            this.customDefaultLoadControl.minBufferMs,
            this.customDefaultLoadControl.maxBufferMs,
            this.customDefaultLoadControl.bufferForPlaybackMs,
            this.customDefaultLoadControl.bufferForPlaybackAfterRebufferMs
        )
        loadControl = loadBuilder.build()

//        val parser: XmlPullParser = context.resources.getXml(R.xml.attrs)
//        try {
//            parser.next()
//            parser.nextTag()
//        } catch (e: java.lang.Exception) {
//            e.printStackTrace()
//        }
//        val attr = Xml.asAttributeSet(parser)


        exoPlayer = ExoPlayer.Builder(context)//;SimpleExoPlayer.Builder(context)
            .setTrackSelector(trackSelector)
            .setRenderersFactory(DefaultRenderersFactory(context))
            .setLoadControl(loadControl)
            .build()
        workManager = WorkManager.getInstance(context)
        workerObserverMap = HashMap()
        setupVideoPlayer(eventChannel, textureEntry, result)
    }

    fun setDataSource(
        context: Context,
        key: String?,
        dataSource: String?,
        formatHint: String?,
        result: MethodChannel.Result,
        headers: Map<String, String>?,
        useCache: Boolean,
        maxCacheSize: Long,
        maxCacheFileSize: Long,
        overriddenDuration: Long,
        licenseUrl: String?,
        drmHeaders: Map<String, String>?,
        cacheKey: String?,
        clearKey: String?
    ) {
        this.key = key
        isInitialized = false
        val uri = Uri.parse(dataSource)
        var dataSourceFactory: DataSource.Factory
        val userAgent = getUserAgent(headers)
        if (!licenseUrl.isNullOrEmpty()) {
            val httpMediaDrmCallback =
                HttpMediaDrmCallback(licenseUrl, DefaultHttpDataSource.Factory())
            if (drmHeaders != null) {
                for ((drmKey, drmValue) in drmHeaders) {
                    httpMediaDrmCallback.setKeyRequestProperty(drmKey, drmValue)
                }
            }
            if (Util.SDK_INT < 18) {
                Log.e(TAG, "Protected content not supported on API levels below 18")
                drmSessionManager = null
            } else {
                val drmSchemeUuid = Util.getDrmUuid("widevine")
                if (drmSchemeUuid != null) {
                    drmSessionManager = DefaultDrmSessionManager.Builder()
                        .setUuidAndExoMediaDrmProvider(
                            drmSchemeUuid
                        ) { uuid: UUID? ->
                            try {
                                val mediaDrm = FrameworkMediaDrm.newInstance(uuid!!)
                                // Force L3.
                                mediaDrm.setPropertyString("securityLevel", "L3")
                                return@setUuidAndExoMediaDrmProvider mediaDrm
                            } catch (e: UnsupportedDrmException) {
                                return@setUuidAndExoMediaDrmProvider DummyExoMediaDrm()
                            }
                        }
                        .setMultiSession(false)
                        .build(httpMediaDrmCallback)
                }
            }
        } else if (!clearKey.isNullOrEmpty()) {
            drmSessionManager = if (Util.SDK_INT < 18) {
                Log.e(TAG, "Protected content not supported on API levels below 18")
                null
            } else {
                DefaultDrmSessionManager.Builder()
                    .setUuidAndExoMediaDrmProvider(
                        C.CLEARKEY_UUID,
                        FrameworkMediaDrm.DEFAULT_PROVIDER
                    ).build(LocalMediaDrmCallback(clearKey.toByteArray()))
            }
        } else {
            drmSessionManager = null
        }
        if (isHTTP(uri)) {
            dataSourceFactory = getDataSourceFactory(userAgent, headers)
            if (useCache && maxCacheSize > 0 && maxCacheFileSize > 0) {
                dataSourceFactory = CacheDataSourceFactory(
                    context,
                    maxCacheSize,
                    maxCacheFileSize,
                    dataSourceFactory
                )
            }
        } else {
            dataSourceFactory = DefaultDataSource.Factory(
                context,
                DefaultHttpDataSource.Factory().setUserAgent(userAgent)
            )
        }
        val mediaSource = buildMediaSource(uri, dataSourceFactory, formatHint, cacheKey, context)
        if (overriddenDuration != 0L) {
            val clippingMediaSource = ClippingMediaSource(mediaSource, 0, overriddenDuration * 1000)
            exoPlayer!!.setMediaSource(clippingMediaSource)
        } else {
            exoPlayer!!.setMediaSource(mediaSource)
        }
        exoPlayer.prepare()
        result.success(null)
    }

    fun setupPlayerNotification(
        context: Context, title: String, author: String?,
        imageUrl: String?, notificationChannelName: String?,
        activityName: String
    ) {
        val mediaDescriptionAdapter: MediaDescriptionAdapter = object : MediaDescriptionAdapter {
            override fun getCurrentContentTitle(player: Player): String {
                return title
            }

            @SuppressLint("UnspecifiedImmutableFlag", "InlinedApi")
            override fun createCurrentContentIntent(player: Player): PendingIntent? {
                val packageName = context.applicationContext.packageName
                val notificationIntent = Intent()
                notificationIntent.setClassName(
                    packageName,
                    "$packageName.$activityName"
                )
                notificationIntent.flags = (Intent.FLAG_ACTIVITY_CLEAR_TOP
                        or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                return PendingIntent.getActivity(
                    context, 0,
                    notificationIntent, PendingIntent.FLAG_IMMUTABLE
                )

            }

            override fun getCurrentContentText(player: Player): String? {
                return author
            }

            override fun getCurrentLargeIcon(
                player: Player,
                callback: BitmapCallback
            ): Bitmap? {
                if (imageUrl == null) {
                    return null
                }
                if (bitmap != null) {
                    return bitmap
                }
                val imageWorkRequest = OneTimeWorkRequest.Builder(ImageWorker::class.java)
                    .addTag(imageUrl)
                    .setInputData(
                        Data.Builder()
                            .putString(PipFlutterPlugin.URL_PARAMETER, imageUrl)
                            .build()
                    )
                    .build()
                workManager.enqueue(imageWorkRequest)
                val workInfoObserver = Observer { workInfo: WorkInfo? ->
                    try {
                        if (workInfo != null) {
                            val state = workInfo.state
                            if (state == WorkInfo.State.SUCCEEDED) {
                                val outputData = workInfo.outputData
                                val filePath =
                                    outputData.getString(PipFlutterPlugin.FILE_PATH_PARAMETER)
                                //Bitmap here is already processed and it's very small, so it won't
                                //break anything.
                                bitmap = BitmapFactory.decodeFile(filePath)
                                callback.onBitmap(bitmap!!)
                            }
                            if (state == WorkInfo.State.SUCCEEDED || state == WorkInfo.State.CANCELLED || state == WorkInfo.State.FAILED) {
                                val uuid = imageWorkRequest.id
                                val observer = workerObserverMap.remove(uuid)
                                if (observer != null) {
                                    workManager.getWorkInfoByIdLiveData(uuid)
                                        .removeObserver(observer)
                                }
                            }
                        }
                    } catch (exception: Exception) {
                        Log.e(TAG, "Image select error: $exception")
                    }
                }
                val workerUuid = imageWorkRequest.id
                workManager.getWorkInfoByIdLiveData(workerUuid)
                    .observeForever(workInfoObserver)
                workerObserverMap[workerUuid] = workInfoObserver
                return null
            }
        }
        val playerNotificationChannelName: String = notificationChannelName ?: run {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val importance = NotificationManager.IMPORTANCE_LOW
                val channel = NotificationChannel(
                    DEFAULT_NOTIFICATION_CHANNEL,
                    DEFAULT_NOTIFICATION_CHANNEL, importance
                )
                channel.description = DEFAULT_NOTIFICATION_CHANNEL
                val notificationManager = context.getSystemService(
                    NotificationManager::class.java
                )
                notificationManager.createNotificationChannel(channel)
                return@run DEFAULT_NOTIFICATION_CHANNEL
            } else {
                return@run ""
            }
        }

        val mediaSession = setupMediaSession(context, false)
        playerNotificationManager = PlayerNotificationManager.Builder(
            context, NOTIFICATION_ID,
            playerNotificationChannelName
        ).apply {
            setMediaDescriptionAdapter(mediaDescriptionAdapter)
        }.build().apply {
            setUseNextAction(false)
            setUsePreviousAction(false)
            setUseStopAction(false)
            setMediaSessionToken(mediaSession.sessionToken)
            setPlayer(setupControlDispatcher2(exoPlayer!!))
//            setControlDispatcher(setupControlDispatcher())
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            refreshHandler = Handler(Looper.getMainLooper())
            refreshRunnable = Runnable {
                val playbackState: PlaybackStateCompat = if (exoPlayer?.isPlaying == true) {
                    PlaybackStateCompat.Builder()
                        .setActions(PlaybackStateCompat.ACTION_SEEK_TO)
                        .setState(PlaybackStateCompat.STATE_PLAYING, position, 1.0f)
                        .build()
                } else {
                    PlaybackStateCompat.Builder()
                        .setActions(PlaybackStateCompat.ACTION_SEEK_TO)
                        .setState(PlaybackStateCompat.STATE_PAUSED, position, 1.0f)
                        .build()
                }
                mediaSession.setPlaybackState(playbackState)
                refreshHandler!!.postDelayed(refreshRunnable!!, 1000)
            }
            refreshHandler!!.postDelayed(refreshRunnable!!, 0)
        }
        exoPlayerEventListener = object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                mediaSession.setMetadata(
                    MediaMetadataCompat.Builder()
                        .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, getDuration())
                        .build()
                )
            }
        }
        exoPlayer!!.addListener(exoPlayerEventListener!!)
        exoPlayer.seekTo(0)
    }


    private fun setupControlDispatcher2(player: ExoPlayer): ForwardingPlayer {
        val forwardingPlayer = object : ForwardingPlayer(player) {
            override fun isCommandAvailable(command: Int): Boolean {
                if (
                    command == COMMAND_SET_SHUFFLE_MODE ||
                    command == COMMAND_SET_REPEAT_MODE ||
                    command == COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM
                ) {
                    return false;
                }
                return super.isCommandAvailable(command);
            }

            override fun getAvailableCommands(): Player.Commands {
                return super.getAvailableCommands()
                    .buildUpon()
                    .remove(COMMAND_SET_SHUFFLE_MODE)
                    .remove(COMMAND_SET_REPEAT_MODE)
//                    .remove(COMMAND_SEEK_TO_PREVIOUS)
                    .remove(COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
                    .build()
            }
        }.apply {
            addListener(object : Player.Listener {
                override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                    super.onPlayWhenReadyChanged(playWhenReady, reason)
                    /* ///TODO 视频流准备好时自动触发暂停和播放,看不懂是什么鬼操作
                     if (playWhenReady) {
                         sendEvent("pause")
                     } else {
                         sendEvent("play")
                     }*/
                }

                override fun onSeekBackIncrementChanged(seekBackIncrementMs: Long) {
                    super.onSeekBackIncrementChanged(seekBackIncrementMs)
                    sendSeekToEvent(player.currentPosition - 5000)
                }

                override fun onSeekForwardIncrementChanged(seekForwardIncrementMs: Long) {
                    super.onSeekForwardIncrementChanged(seekForwardIncrementMs)
//                    sendSeekToEvent(seekForwardIncrementMs)
                    sendSeekToEvent(player.currentPosition + 5000)
                }


                override fun onMaxSeekToPreviousPositionChanged(maxSeekToPreviousPositionMs: Long) {
                    super.onMaxSeekToPreviousPositionChanged(maxSeekToPreviousPositionMs)
                }

                override fun onEvents(player: Player, events: Player.Events) {
                    super.onEvents(player, events)
                    Log.wtf("${this@PipFlutterPlayer.javaClass}", "onEvents:$events")
                }

                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    super.onIsPlayingChanged(isPlaying)
                    Log.wtf("${this@PipFlutterPlayer.javaClass}", "onIsPlayingChanged:$isPlaying")
                }

            })
        }
        return forwardingPlayer
    }


    /*private fun setupControlDispatcher(): ControlDispatcher {
        return object : ControlDispatcher {
            override fun dispatchPrepare(player: Player): Boolean {
                return false
            }

            override fun dispatchSetPlayWhenReady(player: Player, playWhenReady: Boolean): Boolean {
                if (player.playWhenReady) {
                    sendEvent("pause")
                } else {
                    sendEvent("play")
                }
                return true
            }

            override fun dispatchSeekTo(
                player: Player,
                windowIndex: Int,
                positionMs: Long
            ): Boolean {
                sendSeekToEvent(positionMs)
                return true
            }

            override fun dispatchPrevious(player: Player): Boolean {
                return false
            }

            override fun dispatchNext(player: Player): Boolean {
                return false
            }

            override fun dispatchRewind(player: Player): Boolean {
                sendSeekToEvent(player.currentPosition - 5000)
                return false
            }

            override fun dispatchFastForward(player: Player): Boolean {
                sendSeekToEvent(player.currentPosition + 5000)
                return true
            }

            override fun dispatchSetRepeatMode(player: Player, repeatMode: Int): Boolean {
                return false
            }

            override fun dispatchSetShuffleModeEnabled(
                player: Player,
                shuffleModeEnabled: Boolean
            ): Boolean {
                return false
            }

            override fun dispatchStop(player: Player, reset: Boolean): Boolean {
                return false
            }

            override fun dispatchSetPlaybackParameters(
                player: Player,
                playbackParameters: PlaybackParameters
            ): Boolean {
                return false
            }

            override fun isRewindEnabled(): Boolean {
                return true
            }

            override fun isFastForwardEnabled(): Boolean {
                return true
            }
        }
    }
*/
    fun disposeRemoteNotifications() {
        if (exoPlayerEventListener != null) {
            exoPlayer!!.removeListener(exoPlayerEventListener!!)
        }
        if (refreshHandler != null) {
            refreshHandler!!.removeCallbacksAndMessages(null)
            refreshHandler = null
            refreshRunnable = null
        }
        if (playerNotificationManager != null) {
            playerNotificationManager!!.setPlayer(null)
        }
        bitmap = null
    }

    private fun buildMediaSource(
        uri: Uri,
        mediaDataSourceFactory: DataSource.Factory,
        formatHint: String?,
        cacheKey: String?,
        context: Context
    ): MediaSource {
        val type: Int
        if (formatHint == null) {
            var lastPathSegment = uri.lastPathSegment
            if (lastPathSegment == null) {
                lastPathSegment = ""
            }
            type = Util.inferContentTypeForExtension(lastPathSegment)
        } else {
            type = when (formatHint) {
                FORMAT_SS -> C.CONTENT_TYPE_SS
                FORMAT_DASH -> C.CONTENT_TYPE_DASH
                FORMAT_HLS -> C.CONTENT_TYPE_HLS
                FORMAT_OTHER -> C.CONTENT_TYPE_OTHER
                else -> -1
            }
        }
        val mediaItemBuilder = MediaItem.Builder()
        mediaItemBuilder.setUri(uri)
        if (cacheKey != null && cacheKey.isNotEmpty()) {
            mediaItemBuilder.setCustomCacheKey(cacheKey)
        }
        val mediaItem = mediaItemBuilder.build()
        var drmSessionManagerProvider: DrmSessionManagerProvider? = null
        if (drmSessionManager != null) {
            drmSessionManagerProvider = DrmSessionManagerProvider { drmSessionManager!! }
        }
        if (drmSessionManagerProvider != null) {
            return when (type) {
                C.CONTENT_TYPE_SS -> SsMediaSource.Factory(
                    DefaultSsChunkSource.Factory(mediaDataSourceFactory),
                    DefaultDataSource.Factory(context, mediaDataSourceFactory)
                )
                    .setDrmSessionManagerProvider(drmSessionManagerProvider)
                    .createMediaSource(mediaItem)
                C.CONTENT_TYPE_DASH -> DashMediaSource.Factory(
                    DefaultDashChunkSource.Factory(mediaDataSourceFactory),
                    DefaultDataSource.Factory(context, mediaDataSourceFactory)
                )
                    .setDrmSessionManagerProvider(drmSessionManagerProvider)
                    .createMediaSource(mediaItem)
                C.CONTENT_TYPE_HLS -> HlsMediaSource.Factory(mediaDataSourceFactory)
                    .setDrmSessionManagerProvider(drmSessionManagerProvider)
                    .createMediaSource(mediaItem)
                C.CONTENT_TYPE_OTHER -> ProgressiveMediaSource.Factory(
                    mediaDataSourceFactory,
                    DefaultExtractorsFactory()
                )
                    .setDrmSessionManagerProvider(drmSessionManagerProvider)
                    .createMediaSource(mediaItem)
                else -> {
                    throw IllegalStateException("Unsupported type: $type")
                }
            }
        } else {
            return when (type) {
                C.CONTENT_TYPE_SS -> SsMediaSource.Factory(
                    DefaultSsChunkSource.Factory(mediaDataSourceFactory),
                    DefaultDataSource.Factory(context, mediaDataSourceFactory)
                )
                    .createMediaSource(mediaItem)
                C.CONTENT_TYPE_DASH -> DashMediaSource.Factory(
                    DefaultDashChunkSource.Factory(mediaDataSourceFactory),
                    DefaultDataSource.Factory(context, mediaDataSourceFactory)
                )
                    .createMediaSource(mediaItem)
                C.CONTENT_TYPE_HLS -> HlsMediaSource.Factory(mediaDataSourceFactory)
                    .createMediaSource(mediaItem)
                C.CONTENT_TYPE_OTHER -> ProgressiveMediaSource.Factory(
                    mediaDataSourceFactory,
                    DefaultExtractorsFactory()
                )
                    .createMediaSource(mediaItem)
                else -> {
                    throw IllegalStateException("Unsupported type: $type")
                }
            }
        }

    }

    private fun setupVideoPlayer(
        eventChannel: EventChannel, textureEntry: SurfaceTextureEntry, result: MethodChannel.Result
    ) {
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(o: Any?, sink: EventSink) {
                    eventSink.setDelegate(sink)
                }

                override fun onCancel(o: Any?) {
                    eventSink.setDelegate(null)
                }
            })
        surface = Surface(textureEntry.surfaceTexture())
        exoPlayer!!.setVideoSurface(surface)
        setAudioAttributes(exoPlayer, true)
        exoPlayer.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        sendBufferingUpdate(true)
                        val event: MutableMap<String, Any> = HashMap()
                        event["event"] = "bufferingStart"
                        eventSink.success(event)
                    }
                    Player.STATE_READY -> {
                        if (!isInitialized) {
                            isInitialized = true
                            sendInitialized()
                        }
                        val event: MutableMap<String, Any> = HashMap()
                        event["event"] = "bufferingEnd"
                        eventSink.success(event)
                    }
                    Player.STATE_ENDED -> {
                        val event: MutableMap<String, Any?> = HashMap()
                        event["event"] = "completed"
                        event["key"] = key
                        eventSink.success(event)
                        onStopCallback?.invoke()
                    }
                    Player.STATE_IDLE -> {
                        //no-op
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                eventSink.error("VideoError", "Video player had error $error", "")
                onStopCallback?.invoke()
            }
        })
        val reply: MutableMap<String, Any> = HashMap()
        reply["textureId"] = textureEntry.id()
        result.success(reply)
    }

    fun sendBufferingUpdate(isFromBufferingStart: Boolean) {
        val bufferedPosition = exoPlayer!!.bufferedPosition
        if (isFromBufferingStart || bufferedPosition != lastSendBufferedPosition) {
            val event: MutableMap<String, Any> = HashMap()
            event["event"] = "bufferingUpdate"
            val range: List<Number?> = listOf(0, bufferedPosition)
            // iOS supports a list of buffered ranges, so here is a list with a single range.
            event["values"] = listOf(range)
            eventSink.success(event)
            lastSendBufferedPosition = bufferedPosition
        }
    }

    private fun setAudioAttributes(exoPlayer: ExoPlayer?, mixWithOthers: Boolean) {
        exoPlayer ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            exoPlayer.setAudioAttributes(
                AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
                !mixWithOthers
            )
        } else {
            exoPlayer.setAudioAttributes(
                AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(),
                !mixWithOthers
            )
        }
    }

    fun playFromStart() {
        exoPlayer?.seekTo(0)
        exoPlayer?.playWhenReady = true
    }

    fun play() {
        exoPlayer?.playWhenReady = true
    }

    fun pause() {
        exoPlayer?.playWhenReady = false
    }

    fun isPlaying(): Boolean {
        return   (exoPlayer?.isPlaying ?: false)
                || (exoPlayer?.isLoading ?: false)
    }
    fun isBuffering(): Boolean {
       return exoPlayer?.isLoading ?: false
//        return exoPlayer?.playbackState == STATE_BUFFERING
    }


    fun setLooping(value: Boolean) {
        exoPlayer?.repeatMode = if (value) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
    }

    fun setVolume(value: Double) {
        val bracketedValue = max(0.0, min(1.0, value))
            .toFloat()
        exoPlayer?.volume = bracketedValue
    }

    fun setSpeed(value: Double) {
        val bracketedValue = value.toFloat()
        val playbackParameters = PlaybackParameters(bracketedValue)
        exoPlayer?.playbackParameters = playbackParameters
    }

    fun setTrackParameters(width: Int, height: Int, bitrate: Int) {
        val parametersBuilder = trackSelector.buildUponParameters()
        if (width != 0 && height != 0) {
            parametersBuilder.setMaxVideoSize(width, height)
        }
        if (bitrate != 0) {
            parametersBuilder.setMaxVideoBitrate(bitrate)
        }
        if (width == 0 && height == 0 && bitrate == 0) {
            parametersBuilder.clearVideoSizeConstraints()
            parametersBuilder.setMaxVideoBitrate(Int.MAX_VALUE)
        }
        trackSelector.setParameters(parametersBuilder)
    }

    fun seekTo(location: Int) {
        exoPlayer?.seekTo(location.toLong())
    }

    val position: Long
        get() = exoPlayer?.currentPosition ?: 0
    val absolutePosition: Long
        get() {
            val timeline = exoPlayer?.currentTimeline
            if (timeline != null && !timeline.isEmpty) {
                val windowStartTimeMs = timeline.getWindow(0, Timeline.Window()).windowStartTimeMs
                val pos = exoPlayer!!.currentPosition
                return windowStartTimeMs + pos
            }
            return exoPlayer?.currentPosition ?: 0
        }

    val duration: Long
        get() = getDuration()

    private fun sendInitialized() {
        if (isInitialized) {
            val event: MutableMap<String, Any?> = HashMap()
            event["event"] = "initialized"
            event["key"] = key
            event["duration"] = getDuration()
            if (exoPlayer?.videoFormat != null) {
                val videoFormat = exoPlayer.videoFormat
                var width = videoFormat!!.width
                var height = videoFormat.height
                val rotationDegrees = videoFormat.rotationDegrees
                // Switch the width/height if video was taken in portrait mode
                if (rotationDegrees == 90 || rotationDegrees == 270) {
                    width = exoPlayer.videoFormat!!.height
                    height = exoPlayer.videoFormat!!.width
                }
                event["width"] = width
                event["height"] = height
            }
            eventSink.success(event)
        }
    }

    @JvmName("getDuration1")
    protected fun getDuration(): Long = exoPlayer?.duration ?: 0

    /**
     * Create media session which will be used in notifications, pip mode.
     *
     * @param context                - android context
     * @param setupControlDispatcher - should add control dispatcher to created MediaSession
     * @return - configured MediaSession instance
     */
    @SuppressLint("UnspecifiedImmutableFlag")
    fun setupMediaSession(context: Context?, setupControlDispatcher: Boolean): MediaSessionCompat {
        mediaSession?.release()
        val mediaButtonReceiver = ComponentName(context!!, MediaButtonReceiver::class.java)
        val mediaButtonIntent = Intent(Intent.ACTION_MEDIA_BUTTON)
        val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.getBroadcast(
                context,
                0, mediaButtonIntent,
                PendingIntent.FLAG_IMMUTABLE
            )
        } else {
            PendingIntent.getBroadcast(
                context,
                0, mediaButtonIntent,
                PendingIntent.FLAG_UPDATE_CURRENT
            )
        }
        val mediaSession = MediaSessionCompat(context, TAG, null, pendingIntent)
        mediaSession.setCallback(object : MediaSessionCompat.Callback() {
            override fun onSeekTo(pos: Long) {
                sendSeekToEvent(pos)
                super.onSeekTo(pos)
            }

            /*override fun onPause() {
                Log.wtf("videoEventsFor","mediaSession.setCallback pause")
                sendEvent("pause")
                super.onPause()
            }
            override fun onPlay() {
                Log.wtf("videoEventsFor","mediaSession.setCallback play")
                sendEvent("play")
                super.onPlay()
            }*/
        })
        mediaSession.isActive = true
        val mediaSessionConnector = MediaSessionConnector(mediaSession)
        /*if (setupControlDispatcher) {
            mediaSessionConnector.setControlDispatcher(setupControlDispatcher())
        }*/
        //TODO
//        if(setupControlDispatcher){
//            mediaSessionConnector.setPlayer(setupControlDispatcher2(exoPlayer!!))
//        }else{
        mediaSessionConnector.setPlayer(exoPlayer)
//        }


        this.mediaSession = mediaSession
        return mediaSession
    }

    fun onPictureInPictureStatusChanged(inPip: Boolean) {
        val event: MutableMap<String, Any> = HashMap()
        event["event"] = if (inPip) "pipStart" else "pipStop"
        isPip = inPip
        eventSink.success(event)
    }

    private var isPip = false
    fun isPiping(): Boolean {
        return isPip
    }

    fun disposeMediaSession() {
        mediaSession?.release()
        mediaSession = null
    }

    private fun sendEvent(eventType: String) {
        val event: MutableMap<String, Any> = HashMap()
        event["event"] = eventType
        eventSink.success(event)
    }

    fun setAudioTrack(name: String, index: Int) {
        try {
            val mappedTrackInfo = trackSelector.currentMappedTrackInfo
            if (mappedTrackInfo != null) {
                for (rendererIndex in 0 until mappedTrackInfo.rendererCount) {
                    if (mappedTrackInfo.getRendererType(rendererIndex) != TRACK_TYPE_AUDIO) {
                        continue
                    }
                    val trackGroupArray = mappedTrackInfo.getTrackGroups(rendererIndex)
                    var hasElementWithoutLabel = false
                    var hasStrangeAudioTrack = false
                    for (groupIndex in 0 until trackGroupArray.length) {
                        val group = trackGroupArray[groupIndex]
                        for (groupElementIndex in 0 until group.length) {
                            val format = group.getFormat(groupElementIndex)
                            if (format.label == null) {
                                hasElementWithoutLabel = true
                            }
                            if (format.id != null && format.id == "1/15") {
                                hasStrangeAudioTrack = true
                            }
                        }
                    }
                    for (groupIndex in 0 until trackGroupArray.length) {
                        val group = trackGroupArray[groupIndex]
                        for (groupElementIndex in 0 until group.length) {
                            val label = group.getFormat(groupElementIndex).label
                            if (name == label && index == groupIndex) {
                                setAudioTrack(rendererIndex, groupIndex, groupElementIndex)
                                return
                            }

                            ///Fallback option
                            if (!hasStrangeAudioTrack && hasElementWithoutLabel && index == groupIndex) {
                                setAudioTrack(rendererIndex, groupIndex, groupElementIndex)
                                return
                            }
                            ///Fallback option
                            if (hasStrangeAudioTrack && name == label) {
                                setAudioTrack(rendererIndex, groupIndex, groupElementIndex)
                                return
                            }
                        }
                    }
                }
            }
        } catch (exception: Exception) {
            Log.e(TAG, "setAudioTrack failed$exception")
        }
    }

    private fun setAudioTrack(rendererIndex: Int, groupIndex: Int, trackIndex: Int) {
        val mappedTrackInfo = trackSelector.currentMappedTrackInfo
        if (mappedTrackInfo != null) {
            val builder = trackSelector.parameters.buildUpon()
            builder.clearOverridesOfType(TRACK_TYPE_AUDIO)
                .setRendererDisabled(rendererIndex, false)
//            builder.clearSelectionOverrides(rendererIndex)
            /* val tracks = intArrayOf(groupElementIndex)
             val override = SelectionOverride(groupIndex, *tracks)*/

            builder.addOverride(
                TrackSelectionOverride(
                    mappedTrackInfo.getTrackGroups(rendererIndex).get(groupIndex),
                    trackIndex
                )
            )

            /*builder.setSelectionOverride(
                rendererIndex,
                mappedTrackInfo.getTrackGroups(rendererIndex), override
            )*/
            trackSelector.setParameters(builder)
        }
    }

    private fun sendSeekToEvent(positionMs: Long) {
        exoPlayer!!.seekTo(positionMs)
        val event: MutableMap<String, Any> = HashMap()
        event["event"] = "seek"
        event["position"] = positionMs
        eventSink.success(event)
    }

    fun setMixWithOthers(mixWithOthers: Boolean) {
        setAudioAttributes(exoPlayer, mixWithOthers)
    }

    fun dispose() {
        disposeMediaSession()
        disposeRemoteNotifications()
        if (isInitialized) {
            exoPlayer?.stop()
        }
        textureEntry.release()
        eventChannel.setStreamHandler(null)
        surface?.release()
        exoPlayer?.release()
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || javaClass != other.javaClass) return false
        val that = other as PipFlutterPlayer
        if (if (exoPlayer != null) exoPlayer != that.exoPlayer else that.exoPlayer != null) return false
        return if (surface != null) surface == that.surface else that.surface == null
    }

    override fun hashCode(): Int {
        var result = exoPlayer?.hashCode() ?: 0
        result = 31 * result + if (surface != null) surface.hashCode() else 0
        return result
    }

    fun setOnStopListener(callback: (()->Unit)?) {
        onStopCallback = callback
    }

    companion object {
        private const val TAG = "PipFlutterPlayer"
        private const val FORMAT_SS = "ss"
        private const val FORMAT_DASH = "dash"
        private const val FORMAT_HLS = "hls"
        private const val FORMAT_OTHER = "other"
        private const val DEFAULT_NOTIFICATION_CHANNEL = "PIP_FLUTTER_PLAYER_NOTIFICATION"
        private const val NOTIFICATION_ID = 20772077

        //Clear cache without accessing PipFlutterPlayerCache.
        fun clearCache(context: Context?, result: MethodChannel.Result) {
            try {
                val file = File(context?.cacheDir ?: return, "pipFlutterPlayerCache")
                deleteDirectory(file)
                result.success(null)
            } catch (exception: Exception) {
                Log.e(TAG, exception.toString())
                result.error("", "", "")
            }
        }

        private fun deleteDirectory(file: File) {
            if (file.isDirectory) {
                val entries = file.listFiles()
                if (entries != null) {
                    for (entry in entries) {
                        deleteDirectory(entry)
                    }
                }
            }
            if (!file.delete()) {
                Log.e(TAG, "Failed to delete cache dir.")
            }
        }

        //Start pre cache of video. Invoke work manager job and start caching in background.
        fun preCache(
            context: Context?, dataSource: String?, preCacheSize: Long,
            maxCacheSize: Long, maxCacheFileSize: Long, headers: Map<String, String?>,
            cacheKey: String?, result: MethodChannel.Result
        ) {
            val dataBuilder = Data.Builder()
                .putString(PipFlutterPlugin.URL_PARAMETER, dataSource)
                .putLong(PipFlutterPlugin.PRE_CACHE_SIZE_PARAMETER, preCacheSize)
                .putLong(PipFlutterPlugin.MAX_CACHE_SIZE_PARAMETER, maxCacheSize)
                .putLong(PipFlutterPlugin.MAX_CACHE_FILE_SIZE_PARAMETER, maxCacheFileSize)
            if (cacheKey != null) {
                dataBuilder.putString(PipFlutterPlugin.CACHE_KEY_PARAMETER, cacheKey)
            }
            for (headerKey in headers.keys) {
                dataBuilder.putString(
                    PipFlutterPlugin.HEADER_PARAMETER + headerKey,
                    headers[headerKey]
                )
            }
            val cacheWorkRequest = OneTimeWorkRequest.Builder(CacheWorker::class.java)
                .addTag(dataSource!!)
                .setInputData(dataBuilder.build()).build()
            WorkManager.getInstance(context!!).enqueue(cacheWorkRequest)
            result.success(null)
        }

        //Stop pre cache of video with given url. If there's no work manager job for given url, then
        //it will be ignored.
        fun stopPreCache(context: Context?, url: String?, result: MethodChannel.Result) {
            WorkManager.getInstance(context ?: return).cancelAllWorkByTag(url ?: return)
            result.success(null)
        }
    }

}