package com.example.pip_flutter

import android.annotation.SuppressLint
import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.LongSparseArray
import androidx.annotation.RequiresApi
import com.example.pip_flutter.PipFlutterPlayerCache.releaseCache
import com.google.android.exoplayer2.ui.PlayerNotificationManager.ACTION_PAUSE
import com.google.android.exoplayer2.ui.PlayerNotificationManager.ACTION_PLAY
import com.google.android.exoplayer2.util.Log.LOG_LEVEL_OFF
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.view.TextureRegistry
import org.lsposed.hiddenapibypass.HiddenApiBypass
import java.lang.reflect.Field


/**
 * Android platform implementation of the VideoPlayerPlugin.
 */
class PipFlutterPlugin : FlutterPlugin, ActivityAware, MethodCallHandler,
    Application.ActivityLifecycleCallbacks {
    private val videoPlayers = LongSparseArray<PipFlutterPlayer>()
    private val dataSources = LongSparseArray<Map<String, Any?>>()
    private var flutterState: FlutterState? = null
    private var currentNotificationTextureId: Long = -1
    private var currentNotificationDataSource: Map<String, Any?>? = null
    private var activity: Activity? = null
    private var pipHandler: Handler? = null
    private var pipRunnable: Runnable? = null


    override fun onAttachedToEngine(binding: FlutterPluginBinding) {
        Log.e("CALLMETHOD", "onAttachedToEngine: ")
        com.google.android.exoplayer2.util.Log.setLogLevel(LOG_LEVEL_OFF)
        val loader = FlutterLoader()
        flutterState = FlutterState(
            binding.applicationContext,
            binding.binaryMessenger, object : KeyForAssetFn {
                override fun get(asset: String?): String {
                    return loader.getLookupKeyForAsset(
                        asset!!
                    )
                }

            }, object : KeyForAssetAndPackageName {
                override fun get(asset: String?, packageName: String?): String {
                    return loader.getLookupKeyForAsset(
                        asset!!, packageName!!
                    )
                }
            },
            binding.textureRegistry
        )
        flutterState!!.startListening(this)
    }


    override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
        if (flutterState == null) {
            Log.wtf(TAG, "Detached from the engine before registering to it.")
        }
        disposeAllPlayers()
        releaseCache()
        flutterState!!.stopListening()
        flutterState = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        Log.e("CALLMETHOD", "onAttachedToActivity: ")
        activity = binding.activity.apply {
            this.application.registerActivityLifecycleCallbacks(this@PipFlutterPlugin)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}

    override fun onDetachedFromActivity() {
        activity?.apply {
            this.application.unregisterActivityLifecycleCallbacks(this@PipFlutterPlugin)
        }
        activity = null
    }

    private fun disposeAllPlayers() {
        for (i in 0 until videoPlayers.size()) {
            videoPlayers.valueAt(i).dispose()
        }
        videoPlayers.clear()
        dataSources.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
//        Log.e("CALLMETHOD", "onMethodCall: call.method --> " + call.method)
//        Log.e("CALLMETHOD", "onMethodCall: result --> $result")
        if (flutterState == null || flutterState!!.textureRegistry == null) {
            result.error(
                "no_activity",
                "pipflutter_player plugin requires a foreground activity",
                null
            )
            return
        }
        when (call.method) {
            INIT_METHOD -> disposeAllPlayers()
            CREATE_METHOD -> {
                val handle = flutterState!!.textureRegistry!!.createSurfaceTexture()
                val eventChannel = EventChannel(
                    flutterState!!.binaryMessenger, EVENTS_CHANNEL + handle.id()
                )
                var customDefaultLoadControl: CustomDefaultLoadControl? = null
                if (call.hasArgument(MIN_BUFFER_MS) && call.hasArgument(MAX_BUFFER_MS) &&
                    call.hasArgument(BUFFER_FOR_PLAYBACK_MS) &&
                    call.hasArgument(BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS)
                ) {
                    customDefaultLoadControl = CustomDefaultLoadControl(
                        call.argument(MIN_BUFFER_MS),
                        call.argument(MAX_BUFFER_MS),
                        call.argument(BUFFER_FOR_PLAYBACK_MS),
                        call.argument(BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS)
                    )
                }
                val player = PipFlutterPlayer(
                    flutterState!!.applicationContext, eventChannel, handle,
                    customDefaultLoadControl, result
                )
                videoPlayers.put(handle.id(), player)
            }
            PRE_CACHE_METHOD -> preCache(call, result)
            STOP_PRE_CACHE_METHOD -> stopPreCache(call, result)
            CLEAR_CACHE_METHOD -> clearCache(result)
            else -> {
                val textureId = (call.argument<Any>(TEXTURE_ID_PARAMETER) as Number?)!!.toLong()
                val player = videoPlayers[textureId]
                if (player == null) {
                    result.error(
                        "Unknown textureId",
                        "No video player associated with texture id $textureId",
                        null
                    )
                    return
                }
                onMethodCall(call, result, textureId, player)
            }
        }
    }


    override fun onActivityPostResumed(activity: Activity) {
        super.onActivityPostResumed(activity)
        val flag=isFromPipStartEventFlag
        isFromPipStartEventFlag=false
        if(flag){
            if (videoPlayers.size() != 1) return
            if (activity != this.activity || !isPictureInPictureSupported()) return
            Thread{
                Thread.sleep(500)
                activity.runOnUiThread {
                    val player = videoPlayers.valueAt(0)
                    Log.wtf(TAG, "这里需要恢复了????")
                    player.play()
                }
            }.start()
        }
    }

    override fun onActivityPaused(activity: Activity) {

    }


    private var isFromPipStartEventFlag=false
    override fun onActivityPrePaused(activity: Activity) {
        if (videoPlayers.size() != 1) return
        if (activity != this.activity || !isPictureInPictureSupported()) return
        val player = videoPlayers.valueAt(0)
        if ((player.isPlaying()
                    || player.isBuffering()
                    )
            && !player.isPiping()) {
            Log.e(TAG, "onActivityPaused")
            if(player.isPlaying()||player.isBuffering()) {
                Log.wtf(TAG, "这里需要暂停了????")
                isFromPipStartEventFlag=true
            }
            flutterState!!.invokeMethod("prepareToPip")
        }
        super.onActivityPrePaused(activity)
    }

    override fun onActivityPreResumed(activity: Activity) {
        if (videoPlayers.size() != 1) return
        if (activity != this.activity || !isPictureInPictureSupported()) return
        if (activity.isInPictureInPictureMode) return
        val player = videoPlayers.valueAt(0)
        if ((player.isPlaying()
                    || player.isBuffering()
                    ) && player.isPiping()) {
            flutterState!!.invokeMethod("exitPip")
        }
        super.onActivityPreResumed(activity)
    }

    override fun onActivityResumed(activity: Activity) {


    }

    /**
     * Activity mCanEnterPictureInPicture  wasn't update by performResume,should change it by private api
     */
    @SuppressLint("SoonBlockedPrivateApi")
    private fun setCanEnterPictureInPicture(activity: Activity) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val allInstanceFields: List<Field?> = HiddenApiBypass.getInstanceFields(
                    Activity::class.java
                ) as List<Field?>
                val field = allInstanceFields.stream()
                    .filter { e: Field? -> e!!.name == "mCanEnterPictureInPicture" }
                    .findFirst().get()
                field.isAccessible = true
                field[activity] = true
            } else {
                val field = Activity::class.java.getDeclaredField("mCanEnterPictureInPicture")
                field.isAccessible = true
                field.set(activity, true)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }


    private fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
        textureId: Long,
        player: PipFlutterPlayer
    ) {
        when (call.method) {
            SET_DATA_SOURCE_METHOD -> {
                setDataSource(call, result, player)
            }
            SET_LOOPING_METHOD -> {
                player.setLooping(call.argument(LOOPING_PARAMETER)!!)
                result.success(null)
            }
            SET_VOLUME_METHOD -> {
                player.setVolume(call.argument(VOLUME_PARAMETER)!!)
                result.success(null)
            }
            PLAY_METHOD -> {
                setupNotification(player)
                player.play()
                result.success(null)
            }
            PAUSE_METHOD -> {
                player.pause()
                result.success(null)
            }
            SEEK_TO_METHOD -> {
                val location = (call.argument<Any>(LOCATION_PARAMETER) as Number?)!!.toInt()
                player.seekTo(location)
                result.success(null)
            }
            POSITION_METHOD -> {
                result.success(player.position)
                player.sendBufferingUpdate(false)
            }
            ABSOLUTE_POSITION_METHOD -> result.success(player.absolutePosition)
            SET_SPEED_METHOD -> {
                player.setSpeed(call.argument(SPEED_PARAMETER)!!)
                result.success(null)
            }
            SET_TRACK_PARAMETERS_METHOD -> {
                player.setTrackParameters(
                    call.argument(WIDTH_PARAMETER)!!,
                    call.argument(HEIGHT_PARAMETER)!!,
                    call.argument(BITRATE_PARAMETER)!!
                )
                result.success(null)
            }
            ENABLE_PICTURE_IN_PICTURE_METHOD -> {
                enablePictureInPicture(player, textureId)
                result.success(null)
            }
            DISABLE_PICTURE_IN_PICTURE_METHOD -> {
                disablePictureInPicture(player, textureId)
                result.success(null)
            }
            IS_PICTURE_IN_PICTURE_SUPPORTED_METHOD -> result.success(
                isPictureInPictureSupported()
            )
            SET_AUDIO_TRACK_METHOD -> {
                val name = call.argument<String?>(NAME_PARAMETER)
                val index = call.argument<Int?>(INDEX_PARAMETER)
                if (name != null && index != null) {
                    player.setAudioTrack(name, index)
                }
                result.success(null)
            }
            SET_MIX_WITH_OTHERS_METHOD -> {
                val mixWitOthers = call.argument<Boolean?>(
                    MIX_WITH_OTHERS_PARAMETER
                )
                if (mixWitOthers != null) {
                    player.setMixWithOthers(mixWitOthers)
                }
            }
            DISPOSE_METHOD -> {
                dispose(player, textureId)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun setDataSource(
        call: MethodCall,
        result: MethodChannel.Result,
        player: PipFlutterPlayer
    ) {
        val dataSource = call.argument<Map<String, Any?>>(DATA_SOURCE_PARAMETER)!!
        dataSources.put(getTextureId(player)!!, dataSource)
        val key = getParameter(dataSource, KEY_PARAMETER, "")
        val headers: Map<String, String> = getParameter(dataSource, HEADERS_PARAMETER, HashMap())
        val overriddenDuration: Number = getParameter(dataSource, OVERRIDDEN_DURATION_PARAMETER, 0)
        if (dataSource[ASSET_PARAMETER] != null) {
            val asset = getParameter(dataSource, ASSET_PARAMETER, "")
            val assetLookupKey: String = if (dataSource[PACKAGE_PARAMETER] != null) {
                val packageParameter = getParameter(
                    dataSource,
                    PACKAGE_PARAMETER,
                    ""
                )
                flutterState!!.keyForAssetAndPackageName[asset, packageParameter]
            } else {
                flutterState!!.keyForAsset[asset]
            }
            player.setDataSource(
                flutterState!!.applicationContext,
                key,
                "asset:///$assetLookupKey",
                null,
                result,
                headers,
                false,
                0L,
                0L,
                overriddenDuration.toLong(),
                null,
                null, null, null
            )
        } else {
            val useCache = getParameter(dataSource, USE_CACHE_PARAMETER, false)
            val maxCacheSizeNumber: Number = getParameter(dataSource, MAX_CACHE_SIZE_PARAMETER, 0)
            val maxCacheFileSizeNumber: Number =
                getParameter(dataSource, MAX_CACHE_FILE_SIZE_PARAMETER, 0)
            val maxCacheSize = maxCacheSizeNumber.toLong()
            val maxCacheFileSize = maxCacheFileSizeNumber.toLong()
            val uri = getParameter(dataSource, URI_PARAMETER, "")
            val cacheKey = getParameter<String?>(dataSource, CACHE_KEY_PARAMETER, null)
            val formatHint = getParameter<String?>(dataSource, FORMAT_HINT_PARAMETER, null)
            val licenseUrl = getParameter<String?>(dataSource, LICENSE_URL_PARAMETER, null)
            val clearKey = getParameter<String?>(dataSource, DRM_CLEARKEY_PARAMETER, null)
            val drmHeaders: Map<String, String> =
                getParameter(dataSource, DRM_HEADERS_PARAMETER, HashMap())
            player.setDataSource(
                flutterState!!.applicationContext,
                key,
                uri,
                formatHint,
                result,
                headers,
                useCache,
                maxCacheSize,
                maxCacheFileSize,
                overriddenDuration.toLong(),
                licenseUrl,
                drmHeaders,
                cacheKey,
                clearKey
            )
        }
    }

    /**
     * Start pre cache of video.
     *
     * @param call   - invoked method data
     * @param result - result which should be updated
     */
    private fun preCache(call: MethodCall, result: MethodChannel.Result) {
        val dataSource = call.argument<Map<String, Any?>>(DATA_SOURCE_PARAMETER)
        if (dataSource != null) {
            val maxCacheSizeNumber: Number =
                getParameter(dataSource, MAX_CACHE_SIZE_PARAMETER, 100 * 1024 * 1024)
            val maxCacheFileSizeNumber: Number =
                getParameter(dataSource, MAX_CACHE_FILE_SIZE_PARAMETER, 10 * 1024 * 1024)
            val maxCacheSize = maxCacheSizeNumber.toLong()
            val maxCacheFileSize = maxCacheFileSizeNumber.toLong()
            val preCacheSizeNumber: Number =
                getParameter(dataSource, PRE_CACHE_SIZE_PARAMETER, 3 * 1024 * 1024)
            val preCacheSize = preCacheSizeNumber.toLong()
            val uri = getParameter(dataSource, URI_PARAMETER, "")
            val cacheKey = getParameter<String?>(dataSource, CACHE_KEY_PARAMETER, null)
            val headers: Map<String, String> =
                getParameter(dataSource, HEADERS_PARAMETER, HashMap())
            PipFlutterPlayer.preCache(
                flutterState?.applicationContext,
                uri,
                preCacheSize,
                maxCacheSize,
                maxCacheFileSize,
                headers,
                cacheKey,
                result
            )
        }
    }

    /**
     * Stop pre cache video process (if exists).
     *
     * @param call   - invoked method data
     * @param result - result which should be updated
     */
    private fun stopPreCache(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>(URL_PARAMETER)
        PipFlutterPlayer.stopPreCache(flutterState?.applicationContext, url, result)
    }

    private fun clearCache(result: MethodChannel.Result) {
        PipFlutterPlayer.clearCache(flutterState?.applicationContext, result)
    }

    private fun getTextureId(pipFlutterPlayer: PipFlutterPlayer): Long? {
        for (index in 0 until videoPlayers.size()) {
            if (pipFlutterPlayer === videoPlayers.valueAt(index)) {
                return videoPlayers.keyAt(index)
            }
        }
        return null
    }

    private fun setupNotification(pipFlutterPlayer: PipFlutterPlayer) {
        try {
            val textureId = getTextureId(pipFlutterPlayer)
            if (textureId != null) {
                val dataSource = dataSources[textureId]
                //Don't setup notification for the same source.
                if (textureId == currentNotificationTextureId && currentNotificationDataSource != null && dataSource != null && currentNotificationDataSource === dataSource) {
                    return
                }
                currentNotificationDataSource = dataSource
                currentNotificationTextureId = textureId
                removeOtherNotificationListeners()
                val showNotification = getParameter(dataSource, SHOW_NOTIFICATION_PARAMETER, false)
                if (showNotification) {
                    val title = getParameter(dataSource, TITLE_PARAMETER, "")
                    val author = getParameter(dataSource, AUTHOR_PARAMETER, "")
                    val imageUrl = getParameter(dataSource, IMAGE_URL_PARAMETER, "")
                    val notificationChannelName =
                        getParameter<String?>(dataSource, NOTIFICATION_CHANNEL_NAME_PARAMETER, null)

                    val activityName =
                        getParameter(dataSource, ACTIVITY_NAME_PARAMETER, "MainActivity")
                    pipFlutterPlayer.setupPlayerNotification(
                        flutterState!!.applicationContext,
                        title, author, imageUrl, notificationChannelName, activityName
                    )
                }
            }
        } catch (exception: Exception) {
            Log.e(TAG, "SetupNotification failed", exception)
        }
    }

    private fun removeOtherNotificationListeners() {
        for (index in 0 until videoPlayers.size()) {
            videoPlayers.valueAt(index).disposeRemoteNotifications()
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun <T> getParameter(parameters: Map<String, Any?>?, key: String, defaultValue: T): T {
        if (parameters!!.containsKey(key)) {
            val value = parameters[key]
            if (value != null) {
                return value as T
            }
        }
        return defaultValue
    }


    private fun isPictureInPictureSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && activity != null && activity!!.packageManager
            .hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private val REQUEST_PLAY = 1008610
    private val REQUEST_PAUSE = 1008611
    private val REQUEST_REPLAY = 1008612

    // Create a BroadcastReceiver to handle the pause action.
    private val mReceiver = object : BroadcastReceiver() {
        @RequiresApi(Build.VERSION_CODES.O)
        override fun onReceive(context: Context, intent: Intent) {
            if (arrayListOf(ACTION_PAUSE, ACTION_PLAY, ACTION_REPLAY).contains(intent.action)) {
                val textureId = intent.extras?.getLong(TEXTURE_ID_PARAMETER, -1) ?: -1
                val act = activity ?: return
                val applicationContext = act.applicationContext
                if (textureId == (-1).toLong()) return
                val player = videoPlayers[textureId] ?: return
                val event: MutableMap<String, Any> = java.util.HashMap()
                if (intent.action == ACTION_REPLAY) {
                    // Handle the replay action.
                    player.playFromStart()
                    event["event"] = "play"
                    player.eventSink.success(event)
                    act.setPictureInPictureParams(
                        getPictureInPictureParams(
                            applicationContext,
                            textureId,
                            true
                        )
                    )

                } else if (intent.action == ACTION_PAUSE) {
                    // Handle the pause action.
                    player.pause()
                    event["event"] = "pause"
                    player.eventSink.success(event)
                    act.setPictureInPictureParams(
                        getPictureInPictureParams(
                            applicationContext,
                            textureId,
                            false
                        )
                    )

                } else if (intent.action == ACTION_PLAY) {
                    // Handle the play action.
                    player.play()
                    event["event"] = "play"
                    player.eventSink.success(event)
                    act.setPictureInPictureParams(
                        getPictureInPictureParams(
                            applicationContext,
                            textureId,
                            true
                        )
                    )

                }
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun getPictureInPictureParams(
        applicationContext: Context,
        textureId: Long, isPlaying: Boolean, restart: Boolean = false
    ): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setSeamlessResizeEnabled(false)
        }
        val str = if (restart) {
            "Replay"
        } else {
            if (isPlaying) {
                "Pause"
            } else {
                "Play"
            }
        }

        Log.wtf("getPictureInPictureParams","$str the video, ${Log.getStackTraceString(Throwable())}")

        return builder.setActions(
            arrayListOf<RemoteAction>().apply {
                add(
                    RemoteAction(
                        Icon.createWithResource(
                            applicationContext,
                            if (restart) {
                                R.mipmap.ic_pip_replay
                            } else {
                                if (isPlaying) {
                                    R.mipmap.ic_pip_pause
                                } else {
                                    R.mipmap.ic_pip_play
                                }
                            },
                        ),
                        str,
                        "${str} the video",
                        PendingIntent.getBroadcast(
                            applicationContext,
                            if (restart) {
                                REQUEST_REPLAY
                            } else {
                                if (isPlaying) {
                                    REQUEST_PAUSE
                                } else {
                                    REQUEST_PLAY
                                }
                            },
                            Intent(
                                if (restart) {
                                    ACTION_REPLAY
                                } else {
                                    if (isPlaying) {
                                        ACTION_PAUSE
                                    } else {
                                        ACTION_PLAY
                                    }
                                }
                            )
                                .apply {
                                    putExtra(TEXTURE_ID_PARAMETER, textureId)
                                },
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                    )
                )
            })
            .build()

    }


    private fun enablePictureInPicture(player: PipFlutterPlayer, textureId: Long) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val act = activity ?: return
            player.setupMediaSession(flutterState!!.applicationContext, true)
            setCanEnterPictureInPicture(act)
            val applicationContext = act.applicationContext

            val result = act.enterPictureInPictureMode(
                getPictureInPictureParams(applicationContext, textureId, true)
            )

            startPictureInPictureListenerTimer(player)
            player.onPictureInPictureStatusChanged(true)

            player.setOnStopListener {
                act.setPictureInPictureParams(
                    getPictureInPictureParams(
                        applicationContext,
                        textureId,
                        false,
                        restart = true
                    )
                )
            }
            // Register the receiver to receive the specified broadcasts.
            applicationContext.registerReceiver(mReceiver, IntentFilter().apply {
                addAction(ACTION_PAUSE)
                addAction(ACTION_PLAY)
                addAction(ACTION_REPLAY)
            })
        }
    }


    private fun disablePictureInPicture(player: PipFlutterPlayer, textureId: Long) {
        stopPipHandler()
        val act = activity ?: return
        val applicationContext = act.applicationContext
        act.moveTaskToBack(false)
        player.onPictureInPictureStatusChanged(false)
        player.disposeMediaSession()
        player.setOnStopListener(null)
        applicationContext.unregisterReceiver(mReceiver)
    }

    private fun startPictureInPictureListenerTimer(player: PipFlutterPlayer) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            pipHandler = Handler(Looper.getMainLooper())
            pipRunnable = Runnable {
                if (activity!!.isInPictureInPictureMode) {
                    countingPlayer(player)
                    pipHandler!!.postDelayed(pipRunnable!!, 100)
                } else {
                    player.onPictureInPictureStatusChanged(false)
                    player.disposeMediaSession()
                    stopPipHandler()
                }
            }
            pipHandler!!.post(pipRunnable!!)
        }
    }

    private fun countingPlayer(player: PipFlutterPlayer) {
        if (player.isPlaying()) {
            flutterState!!.invokeMethod(
                "pipNotify", mapOf(
                    "position" to player.position,
                    "duration" to player.duration,
                )
            )
        }
    }

    private fun dispose(player: PipFlutterPlayer, textureId: Long) {
        Log.wtf("mother fucker dispose", "dispose: ${Log.getStackTraceString(Throwable())}")
        player.dispose()
        videoPlayers.remove(textureId)
        dataSources.remove(textureId)
        stopPipHandler()
    }

    private fun stopPipHandler() {
        if (pipHandler != null) {
            pipHandler!!.removeCallbacksAndMessages(null)
            pipHandler = null
        }
        pipRunnable = null
    }

    private interface KeyForAssetFn {
        operator fun get(asset: String?): String
    }

    private interface KeyForAssetAndPackageName {
        operator fun get(asset: String?, packageName: String?): String
    }

    private class FlutterState(
        val applicationContext: Context,
        val binaryMessenger: BinaryMessenger,
        val keyForAsset: KeyForAssetFn,
        val keyForAssetAndPackageName: KeyForAssetAndPackageName,
        val textureRegistry: TextureRegistry?
    ) {
        private val methodChannel: MethodChannel = MethodChannel(binaryMessenger, CHANNEL)

        fun startListening(methodCallHandler: PipFlutterPlugin?) {
            methodChannel.setMethodCallHandler(methodCallHandler)
        }

        fun stopListening() {
            methodChannel.setMethodCallHandler(null)
        }

        fun invokeMethod(method: String, arg: Any? = null) {
            methodChannel.invokeMethod(method, arg)
        }

    }

    companion object {
        private const val TAG = "PipFlutterPlayerPlugin"
        private const val CHANNEL = "pipflutter_player_channel"
        private const val ACTION_REPLAY = "pip_action_replay"
        private const val EVENTS_CHANNEL = "pipflutter_player_channel/videoEvents"
        private const val DATA_SOURCE_PARAMETER = "dataSource"
        private const val KEY_PARAMETER = "key"
        private const val HEADERS_PARAMETER = "headers"
        private const val USE_CACHE_PARAMETER = "useCache"
        private const val ASSET_PARAMETER = "asset"
        private const val PACKAGE_PARAMETER = "package"
        private const val URI_PARAMETER = "uri"
        private const val FORMAT_HINT_PARAMETER = "formatHint"
        private const val TEXTURE_ID_PARAMETER = "textureId"
        private const val LOOPING_PARAMETER = "looping"
        private const val VOLUME_PARAMETER = "volume"
        private const val LOCATION_PARAMETER = "location"
        private const val SPEED_PARAMETER = "speed"
        private const val LEFT_PARAMETER = "left"
        private const val TOP_PARAMETER = "top"
        private const val WIDTH_PARAMETER = "width"
        private const val HEIGHT_PARAMETER = "height"
        private const val BITRATE_PARAMETER = "bitrate"
        private const val SHOW_NOTIFICATION_PARAMETER = "showNotification"
        private const val TITLE_PARAMETER = "title"
        private const val AUTHOR_PARAMETER = "author"
        private const val IMAGE_URL_PARAMETER = "imageUrl"
        private const val NOTIFICATION_CHANNEL_NAME_PARAMETER = "notificationChannelName"
        private const val OVERRIDDEN_DURATION_PARAMETER = "overriddenDuration"
        private const val NAME_PARAMETER = "name"
        private const val INDEX_PARAMETER = "index"
        private const val LICENSE_URL_PARAMETER = "licenseUrl"
        private const val DRM_HEADERS_PARAMETER = "drmHeaders"
        private const val DRM_CLEARKEY_PARAMETER = "clearKey"
        private const val MIX_WITH_OTHERS_PARAMETER = "mixWithOthers"
        const val URL_PARAMETER = "url"
        const val PRE_CACHE_SIZE_PARAMETER = "preCacheSize"
        const val MAX_CACHE_SIZE_PARAMETER = "maxCacheSize"
        const val MAX_CACHE_FILE_SIZE_PARAMETER = "maxCacheFileSize"
        const val HEADER_PARAMETER = "header_"
        const val FILE_PATH_PARAMETER = "filePath"
        const val ACTIVITY_NAME_PARAMETER = "activityName"
        const val MIN_BUFFER_MS = "minBufferMs"
        const val MAX_BUFFER_MS = "maxBufferMs"
        const val BUFFER_FOR_PLAYBACK_MS = "bufferForPlaybackMs"
        const val BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS = "bufferForPlaybackAfterRebuffedMs"
        const val CACHE_KEY_PARAMETER = "cacheKey"
        private const val INIT_METHOD = "init"
        private const val CREATE_METHOD = "create"
        private const val SET_DATA_SOURCE_METHOD = "setDataSource"
        private const val SET_LOOPING_METHOD = "setLooping"
        private const val SET_VOLUME_METHOD = "setVolume"
        private const val PLAY_METHOD = "play"
        private const val PAUSE_METHOD = "pause"
        private const val SEEK_TO_METHOD = "seekTo"
        private const val POSITION_METHOD = "position"
        private const val ABSOLUTE_POSITION_METHOD = "absolutePosition"
        private const val SET_SPEED_METHOD = "setSpeed"
        private const val SET_TRACK_PARAMETERS_METHOD = "setTrackParameters"
        private const val SET_AUDIO_TRACK_METHOD = "setAudioTrack"
        private const val ENABLE_PICTURE_IN_PICTURE_METHOD = "enablePictureInPicture"
        private const val DISABLE_PICTURE_IN_PICTURE_METHOD = "disablePictureInPicture"
        private const val IS_PICTURE_IN_PICTURE_SUPPORTED_METHOD = "isPictureInPictureSupported"
        private const val SET_MIX_WITH_OTHERS_METHOD = "setMixWithOthers"
        private const val CLEAR_CACHE_METHOD = "clearCache"
        private const val DISPOSE_METHOD = "dispose"
        private const val PRE_CACHE_METHOD = "preCache"
        private const val STOP_PRE_CACHE_METHOD = "stopPreCache"
    }

    override fun onActivityStopped(activity: Activity) {
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
    }

    override fun onActivityStarted(activity: Activity) {
    }

    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {
    }

    override fun onActivityDestroyed(activity: Activity) {
    }

}