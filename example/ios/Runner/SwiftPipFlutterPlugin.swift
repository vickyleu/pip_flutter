//
//  SwiftPipFlutterPlugin.swift
//  Runner
//
//  Created by vicky Leu on 2022/12/1.
//

import Foundation
import MediaPlayer
import Aspects
import AVKit
import AVFoundation
import GLKit


class SwiftPipFlutterPlugin : NSObject, FlutterPlugin, FlutterPlatformViewFactory {

    
    private var players = Dictionary<Int,PipFlutter>.init(minimumCapacity: 1)
    
    private var registrar:FlutterPluginRegistrar
    private var messenger:FlutterBinaryMessenger
   
    private lazy var channel = FlutterMethodChannel.init(name: "pipflutter_player_channel", binaryMessenger:registrar.messenger())
    
    private var bgTask:UIBackgroundTaskIdentifier?
    private var isInPipMode:Bool = false
    private var aspect:AspectToken?

    static var _sharedInstance:SwiftPipFlutterPlugin?

    var _dataSourceDict:Dictionary<Int,Dictionary<String,AnyObject>>()
    var _timeObserverIdDict = Dictionary<String,AnyObject>()
    var _artworkImageDict = Dictionary<String,MPMediaItemArtwork>()
    var _cacheManager:PipCacheManager?
    var texturesCount:Int = -1
    var _notificationPlayer:PipFlutter?
    var _remoteCommandsInitialized:bool = false


    class func shareInstance() -> Self {
        return _sharedInstance
    }

    // MARK: - FlutterPlugin protocol

    static class func registerWithRegistrar(registrar:FlutterPluginRegistrar) {
        let instance:PipFlutterPlugin! = PipFlutterPlugin(registrar:registrar)
        let channel:FlutterMethodChannel! = FlutterMethodChannel.methodChannelWithName("pipflutter_player_channel",
                                    binaryMessenger:registrar.messenger())
        instance.channel = channel
        instance.isInPipMode = false
        _sharedInstance = instance
        registrar.addMethodCallDelegate(instance, channel:channel)
        registrar.addApplicationDelegate(instance)


        registrar.registerViewFactory(instance, withId:"com.pipflutter/pipflutter_player")
    }

    func aaa() {
        if (self.aspect != nil)
            {return}
        self.aspect = FlutterViewController.aspect_hookSelector(Selector("viewDidLayoutSubviews"), withOptions:AspectPositionAfter, usingBlock:{ (aspectInfo:AspectInfo!) in
            if !self.isInPipMode {
                let controller:FlutterViewController! = UIApplication.sharedApplication().keyWindow().rootViewController()
                if self.players.count() != 1 {return}
                if !controller.dynamicType.isEqual(FlutterViewController.self) {return}
                let player:PipFlutter! = self.players.allValues().lastObject()
                if player.isPlaying()&& !player.isPiping()  {
                    self.channel.invokeMethod("preparePipFrame", arguments:nil)
                    self.isInPipMode = true
                }
            }
        }, error:nil)
    }

    func bbb() {
        if (self.aspect != nil) {
            self.aspect.remove()
        }
    }

    func applicationWillEnterForeground(application:UIApplication!) {

        let app:UIApplication! = UIApplication.sharedApplication()
        app.endBackgroundTask(self.bgTask)
        if _players.count() != 1 {return}
        let player:PipFlutter! = _players.allValues().lastObject()
        if player.isPlaying() && player.isPiping() {
            self.channel.invokeMethod("exitPip", arguments:nil)
        }
        self.bgTask = UIBackgroundTaskInvalid

        self.isInPipMode = false

        NSLog("applicationWillEnterForeground exitPip")
    }

    func applicationDidEnterBackground(application:UIApplication!) {
        if _players.count() != 1 {return}
        let player:PipFlutter! = _players.allValues().lastObject()
        if player.isPlaying() && !player.isPiping() {
            self.channel.invokeMethod("prepareToPip", arguments:nil)
            self.backgroundHandler(player)
        }
    }


    func notifyDart(player:PipFlutter!) {
        let position:Int = player.position.integerValue()
        let duration:Int = player.duration.integerValue()
        self.channel.invokeMethod("pipNotify", arguments:["position": position, "duration": duration])
    }


    func backgroundHandler(player:PipFlutter!) {
        NSLog("### -->backgroundinghandler")
        let app:UIApplication! = UIApplication.sharedApplication()
        self.bgTask = app.beginBackgroundTaskWithExpirationHandler({
            dispatch_async(dispatch_get_main_queue(), {
                if self.bgTask != UIBackgroundTaskInvalid {
                    //                bgTask = UIBackgroundTaskInvalid;
                }
            })
            NSLog("====任务完成了。。。。。。。。。。。。。。。===>")
            // [app endBackgroundTask:bgTask];

        })
        // Start the long-running task
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), {
            //[self.channel invokeMethod:@"prepareToPip" arguments:nil];
            while  true && self.bgTask != UIBackgroundTaskInvalid {
                NSLog("后台不停")
                self.notifyDart(player)
                NSThread.sleepForTimeInterval(1)
            }
            self.notifyDart(player)
        })
    }


    init(registrar:NSObject!) {
        self = super.init()
        NSAssert(self, "super init cannot be nil")
        _messenger = registrar.messenger()
        _registrar = registrar
        _players = NSMutableDictionary.dictionaryWithCapacity(1)
        _timeObserverIdDict = NSMutableDictionary.dictionary()
        _artworkImageDict = NSMutableDictionary.dictionary()
        _dataSourceDict = NSMutableDictionary.dictionary()
        _cacheManager = PipCacheManager()
        _cacheManager.setup()
        return self
    }

    func detachFromEngineForRegistrar(registrar:NSObject!) {
        for textureId:NSNumber! in _players.allKeys {
            let player:PipFlutter! = _players[textureId]
            player.disposeSansEventChannel()
         }
        _players.removeAllObjects()
    }

    // MARK: - FlutterPlatformViewFactory protocol

    func createWithFrame(frame:CGRect, viewIdentifier viewId:int64_t, arguments args:AnyObject?) -> NSObject! {
        let textureId:NSNumber! = args!.objectForKey("textureId")
        let player:PipFlutter! = _players.objectForKey(textureId.intValue)
        return player
    }

    func createArgsCodec() -> NSObject! {
        return FlutterStandardMessageCodec.sharedInstance()
    }

    // MARK: - PipFlutterPlugin class

    func newTextureId() -> Int {
        texturesCount += 1
        return texturesCount
    }

    func onPlayerSetup(player:PipFlutter!, result:FlutterResult) {
        let textureId:int64_t = self.newTextureId()
        let eventChannel:FlutterEventChannel! = FlutterEventChannel.eventChannelWithName(String(format:"pipflutter_player_channel/videoEvents%lld",
                                                                   textureId),
                                             binaryMessenger:_messenger)
        player.mixWithOthers = false
        eventChannel.streamHandler = player
        player.eventChannel = eventChannel

        player.onBackgroundCountingListener = { ($(TypeName)) in
            self.bgTask = UIBackgroundTaskInvalid
        }

        _players[textureId] = player

        result(["textureId": textureId])
    }

    func setupRemoteNotification(player:PipFlutter!) {
        _notificationPlayer = player
        self.stopOtherUpdateListener(player)
        let dataSource:NSDictionary! = _dataSourceDict.objectForKey(self.getTextureId(player))
        var showNotification:Bool = false
        let showNotificationObject:AnyObject! = dataSource.objectForKey("showNotification")
        if showNotificationObject != NSNull.null() {
            showNotification = dataSource.objectForKey("showNotification").boolValue()
        }
        let title:String! = dataSource["title"]
        let author:String! = dataSource["author"]
        let imageUrl:String! = dataSource["imageUrl"]

        if showNotification {
            self.setRemoteCommandsNotificationActive()
            self.setupRemoteCommands(player)
            self.setupRemoteCommandNotification(player, withTitle:title, withAuthor:author, withImageUrl:imageUrl)
            self.setupUpdateListener(player, withTitle:title, withAuthor:author, withImageUrl:imageUrl)
        }
    }

    func setRemoteCommandsNotificationActive() {
        AVAudioSession.sharedInstance().setActive(true, error:nil)
        UIApplication.sharedApplication().beginReceivingRemoteControlEvents()
    }

    func setRemoteCommandsNotificationNotActive() {
        if _players.count() == 0 {
            AVAudioSession.sharedInstance().setActive(false, error:nil)
        }

        UIApplication.sharedApplication().endReceivingRemoteControlEvents()
    }


    func setupRemoteCommands(player:PipFlutter!) {
        if _remoteCommandsInitialized {
            return
        }
        let commandCenter:MPRemoteCommandCenter! = MPRemoteCommandCenter.sharedCommandCenter()
        commandCenter.togglePlayPauseCommand.enabled = true
        commandCenter.playCommand.enabled = true
        commandCenter.pauseCommand.enabled = true
        commandCenter.nextTrackCommand.enabled = false
        commandCenter.previousTrackCommand.enabled = false
        if #available(iOS 9.1, *) {
            commandCenter.changePlaybackPositionCommand.enabled = true
        }

        commandCenter.togglePlayPauseCommand.addTargetWithHandler({ (event:MPRemoteCommandEvent) in
            if _notificationPlayer != NSNull.null() {
                if _notificationPlayer.isPlaying {
                    _notificationPlayer.eventSink(["event": "play"])
                } else {
                    _notificationPlayer.eventSink(["event": "pause"])
                }
            }
            return MPRemoteCommandHandlerStatusSuccess
        })

        commandCenter.playCommand.addTargetWithHandler({ (event:MPRemoteCommandEvent) in
            if _notificationPlayer != NSNull.null() {
                _notificationPlayer.eventSink(["event": "play"])
            }
            return MPRemoteCommandHandlerStatusSuccess
        })

        commandCenter.pauseCommand.addTargetWithHandler({ (event:MPRemoteCommandEvent) in
            if _notificationPlayer != NSNull.null() {
                _notificationPlayer.eventSink(["event": "pause"])
            }
            return MPRemoteCommandHandlerStatusSuccess
        })


        if #available(iOS 9.1, *) {
            commandCenter.changePlaybackPositionCommand.addTargetWithHandler({ (event:MPRemoteCommandEvent) in
                if _notificationPlayer != NSNull.null() {
                    let playbackEvent:MPChangePlaybackPositionCommandEvent! = event
                    let time:CMTime = CMTimeMake(playbackEvent.positionTime, 1)
                    let millis:int64_t = PipFlutterTimeUtils.FLTCMTimeToMillis((time))
                    _notificationPlayer.seekTo(millis)
                    _notificationPlayer.eventSink(["event": "seek", "position": millis])
                }
                return MPRemoteCommandHandlerStatusSuccess
            })
        }
        _remoteCommandsInitialized = true
    }

    func setupRemoteCommandNotification(player:PipFlutter!, withTitle title:String!, withAuthor author:String!, withImageUrl imageUrl:String!) {
        let positionInSeconds:Float = player.position / 1000
        let durationInSeconds:Float = player.duration / 1000


        let nowPlayingInfoDict:NSMutableDictionary! = [MPMediaItemPropertyArtist: author,
                                                     MPMediaItemPropertyTitle: title,
                                                     MPNowPlayingInfoPropertyElapsedPlaybackTime: NSNumber.numberWithFloat(positionInSeconds),
                                                     MPMediaItemPropertyPlaybackDuration: NSNumber.numberWithFloat(durationInSeconds),
                                                     MPNowPlayingInfoPropertyPlaybackRate: 1,
                                                   ].mutableCopy()

        if imageUrl != NSNull.null() {
            let key:String! = self.getTextureId(player)
            let artworkImage:MPMediaItemArtwork! = _artworkImageDict.objectForKey(key)

            if key != NSNull.null() {
                if (artworkImage != nil) {
                    nowPlayingInfoDict.setObject(artworkImage, forKey:MPMediaItemPropertyArtwork)
                    MPNowPlayingInfoCenter.defaultCenter().nowPlayingInfo = nowPlayingInfoDict

                } else {
                    let queue:dispatch_queue_t = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
                    dispatch_async(queue, {
                        @try {
                            var tempArtworkImage:UIImage! = nil
                            if imageUrl.rangeOfString("http").location == NSNotFound {
                                tempArtworkImage = UIImage.imageWithContentsOfFile(imageUrl)
                            } else {
                                let nsImageUrl:NSURL! = NSURL.URLWithString(imageUrl)
                                tempArtworkImage = UIImage.imageWithData(NSData.dataWithContentsOfURL(nsImageUrl))
                            }
                            if (tempArtworkImage != nil) {
                                let artworkImage:MPMediaItemArtwork! = MPMediaItemArtwork(image:tempArtworkImage)
                                _artworkImageDict.setObject(artworkImage, forKey:key)
                                nowPlayingInfoDict.setObject(artworkImage, forKey:MPMediaItemPropertyArtwork)
                            }
                            MPNowPlayingInfoCenter.defaultCenter().nowPlayingInfo = nowPlayingInfoDict
                        }
                        @catch (exception:NSException!) {

                        }
                    })
                }
            }
        } else {
            MPNowPlayingInfoCenter.defaultCenter().nowPlayingInfo = nowPlayingInfoDict
        }
    }


    func getTextureId(player:PipFlutter!) -> String! {
        let temp:[AnyObject]! = _players.allKeysForObject(player)
        let key:String! = temp.lastObject()
        return key
    }

    func setupUpdateListener(player:PipFlutter!, withTitle title:String!, withAuthor author:String!, withImageUrl imageUrl:String!) {
        let _timeObserverId:AnyObject! = player.player.addPeriodicTimeObserverForInterval(CMTimeMake(1, 1), queue:nil, usingBlock:{ (time:CMTime) in
            self.setupRemoteCommandNotification(player, withTitle:title, withAuthor:author, withImageUrl:imageUrl)
        })

        let key:String! = self.getTextureId(player)
        _timeObserverIdDict.setObject(_timeObserverId, forKey:key)
    }


    func disposeNotificationData(player:PipFlutter!) {
        if player == _notificationPlayer {
            _notificationPlayer = nil
            _remoteCommandsInitialized = false
        }
        let key:String! = self.getTextureId(player)
        var _timeObserverId:AnyObject! = _timeObserverIdDict[key]
        _timeObserverIdDict.removeObjectForKey(key)
        _artworkImageDict.removeObjectForKey(key)
        if (_timeObserverId != nil) {
            player.player.removeTimeObserver(_timeObserverId)
            _timeObserverId = nil
        }
        MPNowPlayingInfoCenter.defaultCenter().nowPlayingInfo = []
    }

    func stopOtherUpdateListener(player:PipFlutter!) {
        let currentPlayerTextureId:String! = self.getTextureId(player)
        for textureId:String! in _timeObserverIdDict.allKeys {
            if currentPlayerTextureId == textureId {
                continue
            }

            let timeObserverId:AnyObject! = _timeObserverIdDict.objectForKey(textureId)
            let playerToRemoveListener:PipFlutter! = _players.objectForKey(textureId)
            playerToRemoveListener.player.removeTimeObserver(timeObserverId)
         }
        _timeObserverIdDict.removeAllObjects()

    }


    func handleMethodCall(call:FlutterMethodCall!, result:FlutterResult) {


        if ("init" == call.method) {
            // Allow audio playback when the Ring/Silent switch is set to silent
            for textureId:NSNumber! in _players {
                _players[textureId].dispose()
             }

            _players.removeAllObjects()
            result(nil)
        } else if ("create" == call.method) {
            let player:PipFlutter! = PipFlutter(frame:CGRectZero)
            self.onPlayerSetup(player, result:result)
        } else {
            let argsMap:NSDictionary! = call.arguments
            let textureId:int64_t = (argsMap["textureId"] as! NSNumber).unsignedIntegerValue
            let player:PipFlutter! = _players[textureId]
            if ("setDataSource" == call.method) {
                player.clear()
                // This call will clear cached frame because we will return transparent frame

                let dataSource:NSDictionary! = argsMap["dataSource"]
                _dataSourceDict.setObject(dataSource, forKey:self.getTextureId(player))
                let assetArg:String! = dataSource["asset"]
                let uriArg:String! = dataSource["uri"]
                let key:String! = dataSource["key"]
                let certificateUrl:String! = dataSource["certificateUrl"]
                let licenseUrl:String! = dataSource["licenseUrl"]
                var headers:NSDictionary! = dataSource["headers"]
                let cacheKey:String! = dataSource["cacheKey"]
                let maxCacheSize:NSNumber! = dataSource["maxCacheSize"]
                let videoExtension:String! = dataSource["videoExtension"]

                var overriddenDuration:Int = 0
                if dataSource.objectForKey("overriddenDuration") != NSNull.null() {
                    overriddenDuration = dataSource["overriddenDuration"].intValue()
                }

                var useCache:Bool = false
                let useCacheObject:AnyObject! = dataSource.objectForKey("useCache")
                if useCacheObject != NSNull.null() {
                    useCache = dataSource.objectForKey("useCache").boolValue()
                    if useCache {
                        _cacheManager.maxCacheSize = maxCacheSize
                    }
                }

                if headers == NSNull.null() || headers == nil {
                    headers = []
                }

                if (assetArg != nil) {
                    var assetPath:String!
                    let package:String! = dataSource["package"]
                    if !package.isEqual(NSNull.null()) {
                        assetPath = _registrar.lookupKeyForAsset(assetArg, fromPackage:package)
                    } else {
                        assetPath = _registrar.lookupKeyForAsset(assetArg)
                    }
                    player.setDataSourceAsset(assetPath, withKey:key, withCertificateUrl:certificateUrl, withLicenseUrl:licenseUrl, cacheKey:cacheKey, cacheManager:_cacheManager, overriddenDuration:overriddenDuration)
                } else if (uriArg != nil) {
                    player.setDataSourceURL(NSURL.URLWithString(uriArg), withKey:key, withCertificateUrl:certificateUrl, withLicenseUrl:licenseUrl, withHeaders:headers, withCache:useCache, cacheKey:cacheKey, cacheManager:_cacheManager, overriddenDuration:overriddenDuration, videoExtension:videoExtension)
                } else {
                    result(FlutterMethodNotImplemented)
                }
                result(nil)
            } else if ("dispose" == call.method) {
                self.bbb()
                player.clear()
                self.disposeNotificationData(player)
                self.setRemoteCommandsNotificationNotActive()

                player.onBackgroundCountingListener = nil

                _players.removeObjectForKey(textureId)
                // If the Flutter contains https://github.com/flutter/engine/pull/12695,
                // the `player` is disposed via `onTextureUnregistered` at the right time.
                // Without https://github.com/flutter/engine/pull/12695, there is no guarantee that the
                // texture has completed the un-reregistration. It may leads a crash if we dispose the
                // `player` before the texture is unregistered. We add a dispatch_after hack to make sure the
                // texture is unregistered before we dispose the `player`.
                //
                // TODO(cyanglaz): Remove this dispatch block when
                // https://github.com/flutter/flutter/commit/8159a9906095efc9af8b223f5e232cb63542ad0b is in
                // stable And update the min flutter version of the plugin to the stable version.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, ((1 * NSEC_PER_SEC) as! int64_t)),
                               dispatch_get_main_queue(), {
                    if !player.disposed {
                        player.dispose()
                    }
                })
                if _players.count() == 0 {
                    AVAudioSession.sharedInstance().setActive(false, withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation, error:nil)
                }
                result(nil)
            } else if ("setLooping" == call.method) {
                player.isLooping = argsMap["looping"].boolValue()
                result(nil)
            } else if ("setVolume" == call.method) {
                player.volume = argsMap["volume"].doubleValue()
                result(nil)
            } else if ("play" == call.method) {
                self.setupRemoteNotification(player)
                player.play()
                self.aaa()
                result(nil)
            } else if ("position" == call.method) {
                result(player.position())
            } else if ("absolutePosition" == call.method) {
                result(player.absolutePosition())
            } else if ("seekTo" == call.method) {
                player.seekTo(argsMap["location"].intValue())
                result(nil)
            } else if ("pause" == call.method) {
                player.pause()
                result(nil)
            } else if ("setSpeed" == call.method) {
                player.setSpeed(argsMap.objectForKey("speed").doubleValue(), result:result)
            } else if ("setTrackParameters" == call.method) {
                let width:Int = argsMap["width"].intValue()
                let height:Int = argsMap["height"].intValue()
                let bitrate:Int = argsMap["bitrate"].intValue()

                player.setTrackParameters(width, :height, :bitrate)
                result(nil)
            } else if ("enablePictureInPicture" == call.method) {
                let left:Double = argsMap["left"].doubleValue()
                let top:Double = argsMap["top"].doubleValue()
                let width:Double = argsMap["width"].doubleValue()
                let height:Double = argsMap["height"].doubleValue()
                player.enablePictureInPicture(CGRectMake(left, top, width, height))
            }  else if ("enablePictureInPictureFrame" == call.method) {
                let left:Double = argsMap["left"].doubleValue()
                let top:Double = argsMap["top"].doubleValue()
                let width:Double = argsMap["width"].doubleValue()
                let height:Double = argsMap["height"].doubleValue()
                player.playerLayerSetup(CGRectMake(left, top, width, height))
            } else if ("isPictureInPictureSupported" == call.method) {
                if #available(iOS 9.0, *) {
                    if AVPictureInPictureController.isPictureInPictureSupported() {
                        result(NSNumber.numberWithBool(true))
                        return
                    }
                }

                result(NSNumber.numberWithBool(false))
            } else if ("disablePictureInPicture" == call.method) {

                player.disablePictureInPicture()
                player.pictureInPicture = false
            } else if ("setAudioTrack" == call.method) {
                let name:String! = argsMap["name"]
                let index:Int = argsMap["index"].intValue()
                player.setAudioTrack(name, index:index)
            } else if ("setMixWithOthers" == call.method) {
                player.mixWithOthers = argsMap["mixWithOthers"].boolValue()
            } else if ("preCache" == call.method) {
                let dataSource:NSDictionary! = argsMap["dataSource"]
                let urlArg:String! = dataSource["uri"]
                let cacheKey:String! = dataSource["cacheKey"]
                var headers:NSDictionary! = dataSource["headers"]
                let maxCacheSize:NSNumber! = dataSource["maxCacheSize"]
                var videoExtension:String! = dataSource["videoExtension"]

                if headers == NSNull.null() {
                    headers = []
                }
                if videoExtension == NSNull.null() {
                    videoExtension = nil
                }

                if urlArg != NSNull.null() {
                    let url:NSURL! = NSURL.URLWithString(urlArg)
                    if _cacheManager.isPreCacheSupportedWithUrl(url, videoExtension:videoExtension) {
                        _cacheManager.maxCacheSize = maxCacheSize
                        _cacheManager.preCacheURL(url, cacheKey:cacheKey, videoExtension:videoExtension, withHeaders:headers, completionHandler:{ (success:Bool) in
                        })
                    } else {
                        NSLog("Pre cache is not supported for given data source.")
                    }
                }
                result(nil)
            } else if ("clearCache" == call.method) {
                _cacheManager.clearCache()
                result(nil)
            } else if ("stopPreCache" == call.method) {
                let urlArg:String! = argsMap["url"]
                let cacheKey:String! = argsMap["cacheKey"]
                let videoExtension:String! = argsMap["videoExtension"]
                if urlArg != NSNull.null() {
                    let url:NSURL! = NSURL.URLWithString(urlArg)
                    if _cacheManager.isPreCacheSupportedWithUrl(url, videoExtension:videoExtension) {
                        _cacheManager.stopPreCache(url, cacheKey:cacheKey,
                                  completionHandler:{ (success:Bool) in
                        })
                    } else {
                        NSLog("Stop pre cache is not supported for given data source.")
                    }
                }
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
