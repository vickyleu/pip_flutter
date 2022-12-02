//
//  PipFlutter2.swift
//  Runner
//
//  Created by vicky Leu on 2022/12/2.
//

import AVKit
import Foundation
import Flutter
import AVFoundation
import GLKit
import pip_flutter


 private var timeRangeContextRef = UnsafeRawPointer(bitPattern: 1)!
 private var statusContextRef = UnsafeRawPointer(bitPattern: 1)!
 private var playbackLikelyToKeepUpContextRef = UnsafeRawPointer(bitPattern: 1)!
 private var playbackBufferEmptyContextRef = UnsafeRawPointer(bitPattern: 1)!
 private var playbackBufferFullContextRef = UnsafeRawPointer(bitPattern: 1)!
 private var presentationSizeContextRef = UnsafeRawPointer(bitPattern: 1)!

 private let timeRangeContext = withUnsafeMutablePointer(to: &timeRangeContextRef) { UnsafeMutablePointer($0) }
 private let statusContext = withUnsafeMutablePointer(to: &statusContextRef) { UnsafeMutablePointer($0) }
 private let playbackLikelyToKeepUpContext = withUnsafeMutablePointer(to: &playbackLikelyToKeepUpContextRef) { UnsafeMutablePointer($0) }
 private let playbackBufferEmptyContext = withUnsafeMutablePointer(to: &playbackBufferEmptyContextRef) { UnsafeMutablePointer($0) }
 private let playbackBufferFullContext = withUnsafeMutablePointer(to: &playbackBufferFullContextRef) { UnsafeMutablePointer($0) }
 private let presentationSizeContext = withUnsafeMutablePointer(to: &presentationSizeContextRef) { UnsafeMutablePointer($0) }




private var _restoreUserInterfaceForPIPStopCompletionHandler:((Bool)->Void)?

private var _pipController:AVPictureInPictureController?


public class PipFlutter2 : NSObject, FlutterPlatformView, FlutterStreamHandler, AVPictureInPictureControllerDelegate {
    
    private(set) var player = AVPlayer()
    private(set) var loaderDelegate:PipFlutterEzDrmAssetsLoaderDelegate?
    var eventChannel:FlutterEventChannel?
    var preferredTransform:CGAffineTransform?
    private(set) var disposed:Bool=false
    private var eventSink:FlutterEventSink?
    
    private(set) var isPlaying=false
    private(set) var isPiping=false
    var isLooping=false
    private(set)var isInitialized=false
    private(set) var key:String?
    private(set) var failedCount:Int=0
    var playerLayer:AVPlayerLayer?
    var pictureInPicture=false
    var observersAdded=false
    
     var stalledCount:Int = 0
     var isStalledCheckStarted=false
     var playerRate:Float = 1
    
     var overriddenDuration=0
    var _lastAvPlayerTimeControlStatus:AVPlayer.TimeControlStatus?
    
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        // TODO(@recastrodiaz): remove the line below when the race condition is resolved:
        // https://github.com/flutter/flutter/issues/21483
        // This line ensures the 'initialized' event is sent when the event
        // 'AVPlayerItemStatusReadyToPlay' fires before _eventSink is set (this function
        // onListenWithArguments is called)
        self.onReadyToPlay()
        return nil
    }
    
    public  func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
    
    
    
    
   
   
    var lis:(()->Void)?
    

    init(frame:CGRect) {
        super.init()
        self.player.actionAtItemEnd = .none
        ///Fix for loading large videos
        if #available(iOS 10.0, *) {
            self.player.automaticallyWaitsToMinimizeStalling = false
        }
        self.observersAdded = false
    }

    public func view() -> UIView {
        let playerView:PipFlutterView! = PipFlutterView(frame:CGRectZero)
        playerView.player = self.player
        return playerView
    }

    func addObservers(item:AVPlayerItem!) {
        if !self.observersAdded {
            player.addObserver(self, forKeyPath:"rate", options:.new, context:nil)
            item.addObserver(self, forKeyPath:"loadedTimeRanges", options:.new, context:timeRangeContext)
            item.addObserver(self, forKeyPath:"status", options:.new, context:statusContext)
            item.addObserver(self, forKeyPath:"presentationSize", options:.new, context:presentationSizeContext)
            item.addObserver(self,
                   forKeyPath:"playbackLikelyToKeepUp",
                      options:.new,
                      context:playbackLikelyToKeepUpContext)
            item.addObserver(self,
                   forKeyPath:"playbackBufferEmpty",
                      options:.new,
                      context:playbackBufferEmptyContext)
            item.addObserver(self,
                   forKeyPath:"playbackBufferFull",
                      options:.new,
                      context:playbackBufferFullContext)
            NotificationCenter.default.addObserver(self,
                                                     selector:Selector("itemDidPlayToEndTime:"),
                                                     name:NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                                       object:item)
            self.observersAdded = true
        }
    }

    func clear() {
        isInitialized = false
        isPlaying = false
        disposed = false
        failedCount = 0
        key = nil
        if player.currentItem == nil {
            return
        }
        self.removeObservers()
        let asset = player.currentItem?.asset
        asset?.cancelLoading()
    }

    func removeObservers() {
        if self.observersAdded {
            player.removeObserver(self, forKeyPath:"rate", context:nil)
            player.currentItem?.removeObserver(self, forKeyPath:"status", context:statusContext)
            player.currentItem?.removeObserver(self, forKeyPath:"presentationSize", context:presentationSizeContext)
            player.currentItem?.removeObserver(self,
                                       forKeyPath:"loadedTimeRanges",
                                          context:timeRangeContext)
            player.currentItem?.removeObserver(self,
                                       forKeyPath:"playbackLikelyToKeepUp",
                                          context:playbackLikelyToKeepUpContext)
            player.currentItem?.removeObserver(self,
                                       forKeyPath:"playbackBufferEmpty",
                                          context:playbackBufferEmptyContext)
            player.currentItem?.removeObserver(self,
                                       forKeyPath:"playbackBufferFull",
                                          context:playbackBufferFullContext)
            NotificationCenter.default.removeObserver(self)
            self.observersAdded = false
        }
    }

    func itemDidPlayToEndTime(notification:NSNotification) {
        if self.isLooping {
            let p = notification.object as! AVPlayerItem
            p.seek(to: CMTime.zero, completionHandler:nil)
        } else {
            if (eventSink != nil) {
                eventSink!(["event" : "completed", "key" : self.key])
                self.removeObservers()
            }
            self.completed()
        }
    }

    func completed() {
        lis?()
    }


    func radiansToDegrees(radians:Float) -> Float {
        // Input range [-pi, pi] or [-180, 180]
        let degrees = GLKMathRadiansToDegrees(radians)
        if degrees < 0 {
            // Convert -90 to 270 and -180 to 180
            return degrees + 360
        }
        // Output degrees in between [0, 360[
        return degrees
    };

    func getVideoCompositionWithTransform(transform:CGAffineTransform, withAsset asset:AVAsset!, withVideoTrack videoTrack:AVAssetTrack!) -> AVMutableVideoComposition! {
        let instruction:AVMutableVideoCompositionInstruction! = AVMutableVideoCompositionInstruction.videoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration())
        let layerInstruction:AVMutableVideoCompositionLayerInstruction! = AVMutableVideoCompositionLayerInstruction.videoCompositionLayerInstructionWithAssetTrack(videoTrack)
        layerInstruction.setTransform(_preferredTransform, atTime:kCMTimeZero)

        let videoComposition:AVMutableVideoComposition! = AVMutableVideoComposition.videoComposition()
        instruction.layerInstructions = [ layerInstruction ]
        videoComposition.instructions = [ instruction ]

        // If in portrait mode, switch the width and height of the video
        var width:CGFloat = videoTrack.naturalSize.width
        var height:CGFloat = videoTrack.naturalSize.height
        let rotationDegrees:Int = round(radiansToDegrees(atan2(_preferredTransform.b, _preferredTransform.a)))
        if rotationDegrees == 90 || rotationDegrees == 270 {
            width = videoTrack.naturalSize.height
            height = videoTrack.naturalSize.width
        }
        videoComposition.renderSize = CGSizeMake(width, height)

        let nominalFrameRate:Float = videoTrack.nominalFrameRate
        var fps:Int = 30
        if nominalFrameRate > 0 {
            fps = (ceil(nominalFrameRate) as! int)
        }
        videoComposition.frameDuration = CMTimeMake(1, fps)

        return videoComposition
    }

    func fixTransform(videoTrack:AVAssetTrack!) -> CGAffineTransform {
      let transform:CGAffineTransform = videoTrack.preferredTransform
      // TODO(@recastrodiaz): why do we need to do this? Why is the preferredTransform incorrect?
      // At least 2 user videos show a black screen when in portrait mode if we directly use the
      // videoTrack.preferredTransform Setting tx to the height of the video instead of 0, properly
      // displays the video https://github.com/flutter/flutter/issues/17606#issuecomment-413473181
      let rotationDegrees:Int = round(radiansToDegrees(atan2(transform.b, transform.a)))
      if rotationDegrees == 90 {
        transform.tx = videoTrack.naturalSize.height
        transform.ty = 0
      } else if rotationDegrees == 180 {
        transform.tx = videoTrack.naturalSize.width
        transform.ty = videoTrack.naturalSize.height
      } else if rotationDegrees == 270 {
        transform.tx = 0
        transform.ty = videoTrack.naturalSize.width
      }
      return transform
    }

    func setDataSourceAsset(asset:String, withKey key:String, withCertificateUrl certificateUrl:String?, withLicenseUrl licenseUrl:String?, cacheKey:String?, cacheManager:PipCacheManager, overriddenDuration:Int) {
        let path:String! = NSBundle.mainBundle().pathForResource(asset, ofType:nil)
        return self.setDataSourceURL(NSURL.fileURLWithPath(path), withKey:key, withCertificateUrl:certificateUrl, withLicenseUrl:(licenseUrl as! NSString), withHeaders: [], withCache: false, cacheKey:cacheKey, cacheManager:cacheManager, overriddenDuration:overriddenDuration, videoExtension: nil)
    }

    func setDataSourceURL(url:NSURL, withKey key:String, withCertificateUrl certificateUrl:String?, withLicenseUrl licenseUrl:String?, withHeaders headers:NSDictionary?, withCache useCache:Bool, cacheKey:String?, cacheManager:PipCacheManager, overriddenDuration:Int, videoExtension:String?) {
        _overriddenDuration = 0
        if headers == NSNull.null() || headers == nil {
            headers = []
        }

        var item:AVPlayerItem!
        if useCache {
            if cacheKey == NSNull.null() {
                cacheKey = nil
            }
            if videoExtension == NSNull.null() {
                videoExtension = nil
            }
            item = cacheManager.getCachingPlayerItemForNormalPlayback(url, cacheKey:cacheKey, videoExtension: videoExtension, headers:headers)
        } else {
            let asset:AVURLAsset! = AVURLAsset.URLAssetWithURL(url,
                                                    options:["AVURLAssetHTTPHeaderFieldsKey" : headers])
            if (certificateUrl != nil) && certificateUrl != NSNull.null() && certificateUrl!.length() > 0 {
                let certificateNSURL:NSURL! = NSURL(string:certificateUrl)
                let licenseNSURL:NSURL! = NSURL(string:licenseUrl)
                _loaderDelegate = PipFlutterEzDrmAssetsLoaderDelegate.init(certificateNSURL, withLicenseURL:licenseNSURL)
    //            dispatch_queue_attr_t qos = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, -1);
                let qos:dispatch_queue_attr_t = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_DEFAULT, -1)
                let streamQueue:dispatch_queue_t = dispatch_queue_create("streamQueue", qos)
                asset.resourceLoader.setDelegate(_loaderDelegate, queue:streamQueue)
            }
            item = AVPlayerItem.playerItemWithAsset(asset)
        }

        if #available(iOS 10.0, *) && overriddenDuration > 0 {
            _overriddenDuration = overriddenDuration
        }
        return self.setDataSourcePlayerItem(item, withKey:key)
    }

    func setDataSourcePlayerItem(item:AVPlayerItem!, withKey key:String!) {
        _key = key
        _stalledCount = 0
        _isStalledCheckStarted = false
        _playerRate = 1
        _player.replaceCurrentItemWithPlayerItem(item)

        let asset:AVAsset! = item.asset()
        let assetCompletionHandler:(Void)->Void = {
            if asset.statusOfValueForKey("tracks", error:nil) == AVKeyValueStatusLoaded {
                let tracks:[AnyObject]! = asset.tracksWithMediaType(AVMediaTypeVideo)
                if tracks.count() > 0 {
                    let videoTrack:AVAssetTrack! = tracks[0]
                    let trackCompletionHandler:(Void)->Void = {
                        if self->_disposed {return}
                        if videoTrack.statusOfValueForKey("preferredTransform",
                                                      error:nil) == AVKeyValueStatusLoaded {
                            // Rotate the video by using a videoComposition and the preferredTransform
                            self->_preferredTransform = self.fixTransform(videoTrack)
                            // Note:
                            // https://developer.apple.com/documentation/avfoundation/avplayeritem/1388818-videocomposition
                            // Video composition can only be used with file-based media and is not supported for
                            // use with media served using HTTP Live Streaming.
                            let videoComposition:AVMutableVideoComposition! = self.getVideoCompositionWithTransform(self->_preferredTransform,
                                                         withAsset:asset,
                                                    withVideoTrack:videoTrack)
                            item.videoComposition = videoComposition
                        }
                    }
                    videoTrack.loadValuesAsynchronouslyForKeys([ "preferredTransform" ],
                                              completionHandler:trackCompletionHandler)
                }
            }
        }

        asset.loadValuesAsynchronouslyForKeys([ "tracks" ], completionHandler:assetCompletionHandler)
        self.addObservers(item)
    }

    func handleStalled() {
        if _isStalledCheckStarted {
            return
        }
       _isStalledCheckStarted = true
        self.startStalledCheck()
    }

    func startStalledCheck() {
        if _player.currentItem.playbackLikelyToKeepUp ||
            self.availableDuration() - CMTimeGetSeconds(_player.currentItem.currentTime) > 10.0 {
            self.play()
        } else {
            _stalledCount++
            if _stalledCount > 60 {
                if _eventSink != nil {
                    _eventSink(FlutterError.errorWithCode("VideoError",
                            message:"Failed to load video: playback stalled",
                            details:nil))
                }
                return
            }
            self.performSelector(Selector("startStalledCheck"), withObject:nil, afterDelay:1)

        }
    }

    func availableDuration() -> NSTimeInterval {
        let loadedTimeRanges:[AnyObject]! = _player.currentItem().loadedTimeRanges()
        if loadedTimeRanges.count > 0 {
            let timeRange:CMTimeRange = loadedTimeRanges.objectAtIndex(0).CMTimeRangeValue()
            let startSeconds:Float64 = CMTimeGetSeconds(timeRange.start)
            let durationSeconds:Float64 = CMTimeGetSeconds(timeRange.duration)
            let result:NSTimeInterval = startSeconds + durationSeconds
            return result
        } else {
            return 0
        }

    }

    func observeValueForKeyPath(path:String!, ofObject object:AnyObject!, change:NSDictionary!, context:Void!) {

        if (path == "rate") {
            if #available(iOS 10.0, *) {
                if _pipController.pictureInPictureActive == true {
                    if _lastAvPlayerTimeControlStatus != NSNull.null() && _lastAvPlayerTimeControlStatus == _player.timeControlStatus {
                        return
                    }

                    if _player.timeControlStatus == AVPlayerTimeControlStatusPaused {
                        _lastAvPlayerTimeControlStatus = _player.timeControlStatus
                        if _eventSink != nil {
                          _eventSink(["event" : "pause"])
                        }
                        return

                    }
                    if _player.timeControlStatus == AVPlayerTimeControlStatusPlaying {
                        _lastAvPlayerTimeControlStatus = _player.timeControlStatus
                        if _eventSink != nil {
                          _eventSink(["event" : "play"])
                        }
                    }
                }
            }

            if _player.rate == 0 && //if player rate dropped to 0
                //CMTIME_COMPARE_INLINE(_player.currentItem.currentTime, >, kCMTimeZero) && //if video was started
                //CMTIME_COMPARE_INLINE(_player.currentItem.currentTime, <, _player.currentItem.duration) && //but not yet finished
                _isPlaying { //instance variable to handle overall state (changed to YES when user triggers playback)
                self.handleStalled()
            }
        }

        if context == timeRangeContext {
            if _eventSink != nil {
                let values:NSMutableArray! = NSMutableArray()
                for rangeValue:NSValue! in object.loadedTimeRanges() {
                    let range:CMTimeRange = rangeValue.CMTimeRangeValue()
                    let start:int64_t = PipFlutterTimeUtils.FLTCMTimeToMillis((range.start))
                    var end:int64_t = start + PipFlutterTimeUtils.FLTCMTimeToMillis((range.duration))
                    if !CMTIME_IS_INVALID(_player.currentItem.forwardPlaybackEndTime) {
                        let endTime:int64_t = PipFlutterTimeUtils.FLTCMTimeToMillis((_player.currentItem.forwardPlaybackEndTime))
                        if end > endTime {
                            end = endTime
                        }
                    }

                    values.addObject([ start, end ])
                 }
                _eventSink(["event" : "bufferingUpdate", "values" : values, "key" : _key])
            }
        }
        else if context == presentationSizeContext {
            self.onReadyToPlay()
        }

        else if context == statusContext {
            let item:AVPlayerItem! = object
            switch (item.status) {
                case AVPlayerItemStatusFailed:
                    NSLog("Failed to load video:")
                    NSLog(item.error.debugDescription)

                    if _eventSink != nil {
                        _eventSink(FlutterError.errorWithCode("VideoError",
                                    message:"Failed to load video: ".stringByAppendingString(item.error.localizedDescription()),
                                    details:nil))
                    }
                    break
                case AVPlayerItemStatusUnknown:
                    break
                case AVPlayerItemStatusReadyToPlay:
                    self.onReadyToPlay()
                    break
            }
        } else if context == playbackLikelyToKeepUpContext {
            if _player.currentItem().isPlaybackLikelyToKeepUp() {
                self.updatePlayingState()
                if _eventSink != nil {
                    _eventSink(["event" : "bufferingEnd", "key" : _key])
                }
            }
        } else if context == playbackBufferEmptyContext {
            if _eventSink != nil {
                _eventSink(["event" : "bufferingStart", "key" : _key])
            }
        } else if context == playbackBufferFullContext {
            if _eventSink != nil {
                _eventSink(["event" : "bufferingEnd", "key" : _key])
            }
        }
    }

    func updatePlayingState() {
        if !_isInitialized || (_key == nil) {
            return
        }
        if !self._observersAdded {
            self.addObservers(_player.currentItem())
        }

        if _isPlaying {
            if #available(iOS 10.0, *) {
                _player.playImmediatelyAtRate(1.0)
                _player.rate = _playerRate
            } else {
                _player.play()
                _player.rate = _playerRate
            }
        } else {
            _player.pause()
        }
    }

    func onReadyToPlay() {
        if (_eventSink != nil) && !_isInitialized && _key {
            if !_player.currentItem {
                return
            }
            if _player.status != AVPlayerStatusReadyToPlay {
                return
            }

            let size:CGSize = _player.currentItem().presentationSize
            let width:CGFloat = size.width
            let height:CGFloat = size.height


            let asset:AVAsset! = _player.currentItem.asset
            let onlyAudio:bool = asset.tracksWithMediaType(AVMediaTypeVideo).count() == 0

            // The player has not yet initialized.
            if !onlyAudio && height == CGSizeZero.height && width == CGSizeZero.width {
                return
            }
            let isLive:Bool = CMTIME_IS_INDEFINITE(_player.currentItem().duration)
            // The player may be initialized but still needs to determine the duration.
            if isLive == false && self.duration() == 0 {
                return
            }

            //Fix from https://github.com/flutter/flutter/issues/66413
            let track:AVPlayerItemTrack! = self.player.currentItem().tracks.firstObject
            let naturalSize:CGSize = track.assetTrack.naturalSize
            let prefTrans:CGAffineTransform = track.assetTrack.preferredTransform
            let realSize:CGSize = CGSizeApplyAffineTransform(naturalSize, prefTrans)

            let duration:int64_t = PipFlutterTimeUtils.FLTCMTimeToMillis((_player.currentItem.asset.duration))
            if _overriddenDuration > 0 && duration > _overriddenDuration {
                _player.currentItem.forwardPlaybackEndTime = CMTimeMake(_overriddenDuration/1000, 1)
            }

            _isInitialized = true
            self.updatePlayingState()
            _eventSink([
                "event" : "initialized",
                "duration" : self.duration(),
                "width" : fabs(realSize.width) ? fabs(realSize.width): width,
                "height" : fabs(realSize.height) ? fabs(realSize.height): height,
                "key" : _key
            ])
        }
    }

    func play() {
        _stalledCount = 0
        _isStalledCheckStarted = false
        _isPlaying = true
        self.updatePlayingState()
    }

    func pause() {
        _isPlaying = false
        self.updatePlayingState()
    }

    func position() -> int64_t {
        return PipFlutterTimeUtils.FLTCMTimeToMillis((_player.currentTime()))
    }

    func absolutePosition() -> int64_t {
        return PipFlutterTimeUtils.FLTNSTimeIntervalToMillis((_player.currentItem().currentDate().timeIntervalSince1970()))
    }

    func duration() -> int64_t {
        var time:CMTime
        if #available(iOS 13, *) {
            time =  _player.currentItem().duration()
        } else {
            time =  _player.currentItem().asset().duration()
        }
        if !CMTIME_IS_INVALID(_player.currentItem.forwardPlaybackEndTime) {
            time = _player.currentItem().forwardPlaybackEndTime()
        }

        return PipFlutterTimeUtils.FLTCMTimeToMillis((time))
    }

    func seekTo(location:Int) {
        ///When player is playing, pause video, seek to new position and start again. This will prevent issues with seekbar jumps.
        let wasPlaying:bool = _isPlaying
        if wasPlaying {
            _player.pause()
        }

        _player.seekToTime(CMTimeMake(location, 1000),
            toleranceBefore:kCMTimeZero,
             toleranceAfter:kCMTimeZero,
          completionHandler:{ (finished:Bool) in
            if wasPlaying {
                self->_player.rate = self->_playerRate
            }
        })
    }

    // `setIsLooping:` has moved as a setter.

    func setVolume(volume:Double) {
        _player.volume = (((volume < 0.0) ? 0.0 : ((volume > 1.0) ? 1.0 : volume)) as! float)
    }

    func setSpeed(speed:Double, result:FlutterResult) {
        if speed == 1.0 || speed == 0.0 {
            _playerRate = 1
            result(nil)
        } else if speed < 0 || speed > 2.0 {
            result(FlutterError.errorWithCode("unsupported_speed",
                                       message:"Speed must be >= 0.0 and <= 2.0",
                                       details:nil))
        } else if (speed > 1.0 && _player.currentItem.canPlayFastForward) ||
                   (speed < 1.0 && _player.currentItem.canPlaySlowForward) {
            _playerRate = speed
            result(nil)
        } else {
            if speed > 1.0 {
                result(FlutterError.errorWithCode("unsupported_fast_forward",
                                           message:"This video cannot be played fast forward",
                                           details:nil))
            } else {
                result(FlutterError.errorWithCode("unsupported_slow_forward",
                                           message:"This video cannot be played slow forward",
                                           details:nil))
            }
        }

        if _isPlaying {
            _player.rate = _playerRate
        }
    }


    func setTrackParameters(width:Int, height:Int, bitrate:Int) {
        _player.currentItem.preferredPeakBitRate = bitrate
        if #available(iOS 11.0, *) {
            if width == 0 && height == 0 {
                _player.currentItem.preferredMaximumResolution = CGSizeZero
            } else {
                _player.currentItem.preferredMaximumResolution = CGSizeMake(width, height)
            }
        }
    }

    func isPiping() -> bool {
        return self._pictureInPicture
    }

    func setPictureInPicture(pictureInPicture:Bool) {
        self._pictureInPicture = pictureInPicture
        if #available(iOS 9.0, *) {
            if (_pipController != nil) && self._pictureInPicture && !_pipController.isPictureInPictureActive() {
                dispatch_async(dispatch_get_main_queue(), {
                    _pipController.startPictureInPicture()
                })
            } else if (_pipController != nil) && !self._pictureInPicture && _pipController.isPictureInPictureActive() {

                dispatch_async(dispatch_get_main_queue(), {
                    _pipController.stopPictureInPicture()
                })
            } else {
                // Fallback on earlier versions
            } }
    }

#if TARGET_OS_IOS
    func setRestoreUserInterfaceForPIPStopCompletionHandler(restore:Bool) {
        if _restoreUserInterfaceForPIPStopCompletionHandler != nil {
            _restoreUserInterfaceForPIPStopCompletionHandler(restore)
            _restoreUserInterfaceForPIPStopCompletionHandler = nil
        }
    }

    func setupPipController() {
        if #available(iOS 9.0, *) {
            AVAudioSession.sharedInstance().setActive(true, error: nil)
            UIApplication.sharedApplication().beginReceivingRemoteControlEvents()


            if (_pipController == nil) && self._playerLayer && AVPictureInPictureController.isPictureInPictureSupported() {
                _pipController = AVPictureInPictureController(playerLayer:self._playerLayer)
                if #available(iOS 14.2, *) {
                    _pipController.canStartPictureInPictureAutomaticallyFromInline = true
                }
                _pipController.delegate = self
            }
        } else {
            // Fallback on earlier versions
        }
    }

    func enablePictureInPicture(frame:CGRect) {

        self.disablePictureInPicture()
        self.usePlayerLayer(frame)
    }


    func playerLayerSetup(frame:CGRect) {
        if (_player != nil) {
            // Create new controller passing reference to the AVPlayerLayer
            self._playerLayer = AVPlayerLayer.playerLayerWithPlayer(_player)
            let vc:UIViewController! = UIApplication.sharedApplication().keyWindow().rootViewController()
            self._playerLayer.frame = frame
            self._playerLayer.needsDisplayOnBoundsChange = true
            //  [self._playerLayer addObserver:self forKeyPath:readyForDisplayKeyPath options:NSKeyValueObservingOptionNew context:nil];
            vc.view.layer.addSublayer(self._playerLayer)
            vc.view.layer.needsDisplayOnBoundsChange = true
            if #available(iOS 9.0, *) {
                _pipController = nil
            }
            self.setupPipController()
        }
    }


    func usePlayerLayer(frame:CGRect) {
        if (_player != nil)
        {
            if (self._playerLayer == nil) {
                return
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, ((0.2 * NSEC_PER_SEC) as! int64_t)),
                           dispatch_get_main_queue(), {
                self.pictureInPicture = true
            })
        }
    }

    func disablePictureInPicture() {
        self.pictureInPicture = false
        NSLog("applicationWillEnterForeground disablePictureInPicture")
        if (self._playerLayer != nil) {
            self._playerLayer.removeFromSuperlayer()
            self._playerLayer = nil
            if _eventSink != nil {
                _eventSink(["event" : "pipStop"])
            }
        }
    }
#endif

    func pictureInPictureControllerDidStopPictureInPicture(pictureInPictureController:AVPictureInPictureController!) {
        self.disablePictureInPicture()
    }

    func pictureInPictureControllerDidStartPictureInPicture(pictureInPictureController:AVPictureInPictureController!) {
        if _eventSink != nil {
            _eventSink(["event" : "pipStart"])
        }
    }

    func pictureInPictureControllerWillStopPictureInPicture(pictureInPictureController:AVPictureInPictureController!) {

    }

    func pictureInPictureControllerWillStartPictureInPicture(pictureInPictureController:AVPictureInPictureController!) {
    }

    func pictureInPictureController(pictureInPictureController:AVPictureInPictureController!, failedToStartPictureInPictureWithError error:NSError!) {
    }

    func pictureInPictureController(pictureInPictureController:AVPictureInPictureController!, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:(Bool)->Void) {
        self.restoreUserInterfaceForPIPStopCompletionHandler = true
    }

    func setAudioTrack(name:String, index:Int) {
        let audioSelectionGroup:AVMediaSelectionGroup! = _player.currentItem().asset().mediaSelectionGroupForMediaCharacteristic(AVMediaCharacteristicAudible)
        let options:[AnyObject]! = audioSelectionGroup.options


        for var audioTrackIndex:Int=0 ; audioTrackIndex < options.count() ; audioTrackIndex++ {
            let option:AVMediaSelectionOption! = options.objectAtIndex(audioTrackIndex)
            let metaDatas:[AnyObject]! = AVMetadataItem.metadataItemsFromArray(option.commonMetadata, withKey:"title", keySpace:"comn")
            if metaDatas.count > 0 {
                let title:String! = (metaDatas.objectAtIndex(0) as! AVMetadataItem).stringValue
                if name.compare(title) == NSOrderedSame && audioTrackIndex == index  {
                    _player.currentItem().selectMediaOption(option, inMediaSelectionGroup: audioSelectionGroup)
                }
            }

         }

    }

    func setMixWithOthers(mixWithOthers:bool) {
      if mixWithOthers {
        AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback,
                                         withOptions:AVAudioSessionCategoryOptionMixWithOthers,
                                               error:nil)
      } else {
        AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback, error:nil)
      }
    }


#endif

   

    /// This method allows you to dispose without touching the event channel.  This
    /// is useful for the case where the Engine is in the process of deconstruction
    /// so the channel is going to die or is already dead.
    func disposeSansEventChannel() {
        @try{
            self.clear()
        }
        @catch(exception:NSException!) {
            NSLog(exception.debugDescription)
        }
    }

    func dispose() {
        self.pause()
        self.disposeSansEventChannel()
        _eventChannel.streamHandler = nil
        self.disablePictureInPicture()
        self.pictureInPicture = false
        _disposed = true
    }

    func setOnBackgroundCountingListener(pFunction:(Void)->Void) {
            self.lis=pFunction
    }
}
