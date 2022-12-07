package com.example.pip_flutter

import android.app.Activity
import android.app.Application
import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.LongSparseArray
import android.util.Rational
import com.example.pip_flutter.PipFlutterPlayerCache.releaseCache
import com.google.android.exoplayer2.util.Log.LOG_LEVEL_ALL
import com.google.android.exoplayer2.util.Log.LOG_LEVEL_OFF
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.lsposed.hiddenapibypass.HiddenApiBypass
import java.lang.reflect.Field

/**
 * Android platform implementation of the VideoPlayerPlugin.
 */
class PipFlutterPlugin : FlutterPlugin, ActivityAware, MethodCallHandler,
    Application.ActivityLifecycleCallbacks, PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    private val videoPlayers = LongSparseArray<PipFlutterPlayer>()
    private val dataSources = LongSparseArray<Map<String, Any?>>()
    private var flutterState: FlutterState? = null
    private var currentNotificationTextureId: Long = -1
    private var currentNotificationDataSource: Map<String, Any?>? = null
    private var activity: Activity? = null
    private var pipHandler: Handler? = null
    private var pipRunnable: Runnable? = null


    private var texturesCount = 0.toLong()

    private fun newTextureId() :Long {
        texturesCount += 1
        return texturesCount
    }


    override fun onAttachedToEngine(binding: FlutterPluginBinding) {
        Log.e("CALLMETHOD", "onAttachedToEngine: ")
        com.google.android.exoplayer2.util.Log.setLogLevel(LOG_LEVEL_ALL)
//        com.google.android.exoplayer2.util.Log.setLogLevel(LOG_LEVEL_OFF)
        binding.platformViewRegistry.registerViewFactory("com.pipflutter/pipflutter_player",this)

        val loader = FlutterLoader()
        flutterState = FlutterState(
            binding.applicationContext,
            binding.binaryMessenger,
            object : KeyForAssetFn {
                override fun get(asset: String?): String {
                    return loader.getLookupKeyForAsset(
                        asset ?: ""
                    )
                }

            },
            object : KeyForAssetAndPackageName {
                override fun get(asset: String?, packageName: String?): String {
                    return loader.getLookupKeyForAsset(
                        asset ?: "", packageName ?: ""
                    )
                }
            },
        )
        flutterState?.startListening(this)

    }


    override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
        if (flutterState == null) {
            Log.wtf(TAG, "Detached from the engine before registering to it.")
        }
        disposeAllPlayers()
        releaseCache()
        flutterState?.stopListening()
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
            videoPlayers.valueAt(i).disposePlayer()
        }
        videoPlayers.clear()
        dataSources.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
//        Log.e("CALLMETHOD", "onMethodCall: call.method --> " + call.method)
//        Log.e("CALLMETHOD", "onMethodCall: result --> $result")
        if (flutterState == null ) {
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
                val flutterState = flutterState
                if (flutterState == null) {
                    result.error(
                        "flutterState null",
                        "flutterState null",
                        null
                    )
                    return
                }
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

                val textureId = newTextureId()
//                val handle = textureRegistry.createSurfaceTexture()
                val eventChannel = EventChannel(
                    flutterState.binaryMessenger, EVENTS_CHANNEL + textureId
                )
                val player = PipFlutterPlayer(
                    flutterState.applicationContext, eventChannel,textureId, //handle,
                    customDefaultLoadControl, result
                )
                videoPlayers.put(textureId, player)
            }
            PRE_CACHE_METHOD -> preCache(call, result)
            STOP_PRE_CACHE_METHOD -> stopPreCache(call, result)
            CLEAR_CACHE_METHOD -> clearCache(result)
            else -> {
                when (val textureId =
                    (call.argument<Any>(TEXTURE_ID_PARAMETER) as? Number)?.toLong()) {
                    is Long -> {
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
                    else -> {
                        result.error(
                            "Unknown textureId",
                            "No video player associated with texture id $textureId",
                            null
                        )
                        return
                    }
                }

            }
        }
    }

    override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
        val map = args as? Map<*, *>
        val textureId = (map?.get(TEXTURE_ID_PARAMETER) as? Number)?.toLong()
        Log.wtf("createForContext","textureId:${textureId}")
        if(textureId==null)return  FakePlatformView(context)
        val player = videoPlayers[textureId]
        Log.wtf("createForContext","player:${player}")
        return player ?: FakePlatformView(context)
    }

    override fun onActivityPostResumed(activity: Activity) {
        super.onActivityPostResumed(activity)
    }

    override fun onActivityPaused(activity: Activity) {

    }


    override fun onActivityPostPaused(activity: Activity) {
        super.onActivityPostPaused(activity)
        if (videoPlayers.size() != 1) return
        if (activity != this.activity || !isPictureInPictureSupported()) return
        val player = videoPlayers.valueAt(0)
        if (player.isPlaying() && !player.isPiping()) {
            Log.e(TAG, "onActivityPaused")
            flutterState?.invokeMethod("prepareToPip")
        }
    }


    /**
     * Activity mCanEnterPictureInPicture  wasn't update by performResume,should change it by private api
     */
    private fun setCanEnterPictureInPicture(activity: Activity) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val allInstanceFields: List<Field?> = HiddenApiBypass.getInstanceFields(
                    Activity::class.java
                ) as List<Field?>
                val field = allInstanceFields.stream()
                    .filter { e: Field? -> e?.name == "mCanEnterPictureInPicture" }
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

    override fun onActivityResumed(activity: Activity) {
       /* if (videoPlayers.size() != 1) return
        if (activity != this.activity || !isPictureInPictureSupported()) return
        if (activity.isInPictureInPictureMode) return
        val player = videoPlayers.valueAt(0)
        if (player.isPlaying() && player.isPiping()) {
//            flutterState?.invokeMethod("exitPip")
        }*/
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
                player.setLooping(call.argument(LOOPING_PARAMETER) ?: false)
                result.success(null)
            }
            SET_VOLUME_METHOD -> {
                player.setVolume(call.argument(VOLUME_PARAMETER) ?: 1.0)
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
                when (val location = (call.argument<Any>(LOCATION_PARAMETER) as? Number)?.toInt()) {
                    is Int -> {
                        player.seekTo(location)
                        result.success(null)
                    }
                    else -> {
                        result.error(
                            "Unknown location",
                            "No video player associated with location $location",
                            null
                        )
                        return
                    }
                }

            }
            POSITION_METHOD -> {
                result.success(player.position)
                player.sendBufferingUpdate(false)
            }
            ABSOLUTE_POSITION_METHOD -> result.success(player.absolutePosition)
            SET_SPEED_METHOD -> {
                player.setSpeed(call.argument(SPEED_PARAMETER) ?: 1.0)
                result.success(null)
            }
            SET_TRACK_PARAMETERS_METHOD -> {
                player.setTrackParameters(
                    (call.argument<Int>(WIDTH_PARAMETER) ?: 0.0).toInt(),
                    (call.argument<Int>(HEIGHT_PARAMETER) ?: 0.0).toInt(),
                    call.argument<Int>(BITRATE_PARAMETER) ?: 0
                )
                result.success(null)
            }
            ENABLE_PICTURE_IN_PICTURE_METHOD -> {
                enablePictureInPicture(player,
                    (call.argument<Double>(TOP_PARAMETER) ?: 0.0).toInt(),
                    (call.argument<Double>(LEFT_PARAMETER) ?: 0.0).toInt(),
                    (call.argument<Double>(WIDTH_PARAMETER) ?: 0.0).toInt(),
                    (call.argument<Double>(HEIGHT_PARAMETER) ?: 0.0).toInt(),
                    )
                result.success(null)
            }
            DISABLE_PICTURE_IN_PICTURE_METHOD -> {
                disablePictureInPicture(player)
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
        val dataSource = call.argument<Map<String, Any?>>(DATA_SOURCE_PARAMETER) ?: mapOf()
        val textureId = getTextureId(player)
        if (textureId == null) {
            result.error(
                "textureId null",
                "can not generate texture id",
                null
            )
            return
        }
        dataSources.put(textureId, dataSource)
        val key = getParameter(dataSource, KEY_PARAMETER, "")
        val headers: Map<String, String> = getParameter(dataSource, HEADERS_PARAMETER, HashMap())
        val overriddenDuration: Number = getParameter(dataSource, OVERRIDDEN_DURATION_PARAMETER, 0)
        val flutterState = flutterState
        if (flutterState != null) {
            if (dataSource[ASSET_PARAMETER] != null) {
                val asset = getParameter(dataSource, ASSET_PARAMETER, "")
                val assetLookupKey: String = if (dataSource[PACKAGE_PARAMETER] != null) {
                    val packageParameter = getParameter(
                        dataSource,
                        PACKAGE_PARAMETER,
                        ""
                    )
                    (flutterState.keyForAssetAndPackageName[asset, packageParameter])
                } else {
                    (flutterState.keyForAsset[asset])
                }
                player.setDataSource(
                    flutterState.applicationContext,
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
                val maxCacheSizeNumber: Number =
                    getParameter(dataSource, MAX_CACHE_SIZE_PARAMETER, 0)
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
                    flutterState.applicationContext,
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

                val flutterState = flutterState
                if (showNotification && flutterState != null) {
                    val title = getParameter(dataSource, TITLE_PARAMETER, "")
                    val author = getParameter(dataSource, AUTHOR_PARAMETER, "")
                    val imageUrl = getParameter(dataSource, IMAGE_URL_PARAMETER, "")
                    val notificationChannelName =
                        getParameter<String?>(dataSource, NOTIFICATION_CHANNEL_NAME_PARAMETER, null)

                    val activityName =
                        getParameter(dataSource, ACTIVITY_NAME_PARAMETER, "MainActivity")
                    pipFlutterPlayer.setupPlayerNotification(
                        flutterState.applicationContext,
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
        if (parameters?.containsKey(key) == true) {
            val value = parameters[key]
            if (value != null) {
                return value as T
            }
        }
        return defaultValue
    }


    private fun isPictureInPictureSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && activity != null && activity?.packageManager?.hasSystemFeature(
            PackageManager.FEATURE_PICTURE_IN_PICTURE
        ) == true
    }

    private fun enablePictureInPicture(player: PipFlutterPlayer,top:Int,left:Int,width:Int,height:Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val act = activity ?: return
            player.setupMediaSession(act.applicationContext, true)
            setCanEnterPictureInPicture(act)
//            val rational = Rational(8, 3) //这里如果设置的值太大或者太小或报异常
            val rect = Rect(left, top, width, height)
            val builder=PictureInPictureParams.Builder()
//                .setAspectRatio(rational)
//                .setSourceRectHint(rect)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setAutoEnterEnabled(true)
                builder.setSeamlessResizeEnabled(true)
            }

            val result = act.enterPictureInPictureMode(builder.build())
            startPictureInPictureListenerTimer(player)
            player.onPictureInPictureStatusChanged(true)

        }
    }

    private fun disablePictureInPicture(player: PipFlutterPlayer) {
        stopPipHandler()
        activity?.moveTaskToBack(false)
        player.onPictureInPictureStatusChanged(false)
        player.disposeMediaSession()
    }

    private fun startPictureInPictureListenerTimer(player: PipFlutterPlayer) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            Handler(Looper.getMainLooper()).apply {
                val that = this
                pipHandler = that
                Runnable {
                    val pipRunnable = pipRunnable
                    if (activity?.isInPictureInPictureMode == true) { //&&player.isPiping()
//                    if (activity==null ||  activity?.isInPictureInPictureMode == true) {
                        countingPlayer(player)
                        if(pipRunnable!=null){
                            pipHandler?.postDelayed(pipRunnable, 100)
                        }
                    } else {
                        Log.wtf("${this.javaClass}","Runnable stop")
                        player.onPictureInPictureStatusChanged(false)
                        player.disposeMediaSession()
                        stopPipHandler()
                    }
                }.apply {
                    pipRunnable = this
                    that.post(this)
                }
            }

        }
    }

    private fun countingPlayer(player: PipFlutterPlayer) {
        if (player.isPlaying()) {
            flutterState?.invokeMethod(
                "pipNotify", mapOf(
                    "position" to player.position,
                    "duration" to player.duration,
                )
            )
        }
    }

    private fun dispose(player: PipFlutterPlayer, textureId: Long) {
        player.disposePlayer()
        videoPlayers.remove(textureId)
        dataSources.remove(textureId)
        stopPipHandler()
    }

    private fun stopPipHandler() {
        pipHandler?.removeCallbacksAndMessages(null)
        pipHandler = null
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