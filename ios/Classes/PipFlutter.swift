//
//  PipFlutter.swift
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







public class PipFlutter : NSObject, FlutterPlatformView, FlutterStreamHandler, AVPictureInPictureControllerDelegate {
    
    private var pipController:AVPictureInPictureController?
    private var restoreUserInterfaceForPIPStopCompletionHandler:((Bool)->Void)?
    
    
    private(set) var player = AVPlayer()
    private(set) var loaderDelegate:PipFlutterEzDrmAssetsLoaderDelegate?
    var eventChannel:FlutterEventChannel?
    var preferredTransform:CGAffineTransform?
    private(set) var disposed:Bool=false
    private(set) var eventSink:FlutterEventSink?
    
    private(set) var isPlaying=false
    var isPiping: Bool{
        get{
            self.mPictureInPicture
        }
    }
    
    var frame:CGRect = .zero
    
    var isLooping=false
    private(set)var isInitialized=false
    private(set) var key:String?
    private(set) var failedCount:Int=0
    var playerLayer:AVPlayerLayer?
    var mPictureInPicture=false
    private(set) var playerToGoPipFlag=true
    var observersAdded=false
    
    var stalledCount:Int = 0
    var isStalledCheckStarted=false
    var playerRate:Float = 1
    
    var overriddenDuration=0
    var lastAvPlayerTimeControlStatus:AVPlayer.TimeControlStatus?
    
    
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
        let playerView = PipFlutterView(frame:self.frame)
        playerView.player = self.player
        return playerView
    }
    
    func addObservers(item:AVPlayerItem!) {
        if !self.observersAdded {
            player.addObserver(self, forKeyPath:"rate", options:.new, context:nil)
            player.addObserver(self, forKeyPath: "timeControlStatus", options:.new,  context: nil)//监听 timeControlStatus（为了监听画中画模式的暂停播放）
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
            player.removeObserver(self, forKeyPath:"timeControlStatus", context:nil)
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
    
    @objc func itemDidPlayToEndTime(_ notification:NSNotification) {
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
    
    func getVideoCompositionWithTransform(transform:CGAffineTransform, withAsset asset:AVAsset, withVideoTrack videoTrack:AVAssetTrack) -> AVMutableVideoComposition {
        
        let instruction:AVMutableVideoCompositionInstruction! = AVMutableVideoCompositionInstruction.init()
        
        instruction.timeRange = CMTimeRange.init(start: .zero, duration: asset.duration)
        
        let layerInstruction:AVMutableVideoCompositionLayerInstruction! = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(self.preferredTransform!, at:.zero)
        
        let videoComposition:AVMutableVideoComposition! = AVMutableVideoComposition()
        instruction.layerInstructions = [ layerInstruction ]
        videoComposition.instructions = [ instruction ]
        
        // If in portrait mode, switch the width and height of the video
        var width:CGFloat = videoTrack.naturalSize.width
        var height:CGFloat = videoTrack.naturalSize.height
        let rotationDegrees:Int = Int(round(radiansToDegrees(radians: Float(atan2(self.preferredTransform!.b, self.preferredTransform!.a)))))
        if rotationDegrees == 90 || rotationDegrees == 270 {
            width = videoTrack.naturalSize.height
            height = videoTrack.naturalSize.width
        }
        videoComposition.renderSize = CGSizeMake(width, height)
        
        let nominalFrameRate:Float = videoTrack.nominalFrameRate
        var fps:Int = 30
        if nominalFrameRate > 0 {
            fps = Int(ceil(nominalFrameRate))
        }
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: Int32(fps))
        
        return videoComposition
    }
    
    func fixTransform(videoTrack:AVAssetTrack!) -> CGAffineTransform {
        var transform:CGAffineTransform = videoTrack.preferredTransform
        // TODO(@recastrodiaz): why do we need to do this? Why is the preferredTransform incorrect?
        // At least 2 user videos show a black screen when in portrait mode if we directly use the
        // videoTrack.preferredTransform Setting tx to the height of the video instead of 0, properly
        // displays the video https://github.com/flutter/flutter/issues/17606#issuecomment-413473181
        let rotationDegrees:Int = Int(round(radiansToDegrees(radians: Float(atan2(transform.b, transform.a)))))
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
        let path = Bundle.main.path(forResource: asset, ofType: nil)
        
        return self.setDataSourceURL( url: URL.init(fileURLWithPath: path!) , withKey:key, withCertificateUrl:certificateUrl, withLicenseUrl:licenseUrl, withHeaders: [:], withCache: false, cacheKey:cacheKey, cacheManager:cacheManager, overriddenDuration:overriddenDuration, videoExtension: nil)
    }
    
    func setDataSourceURL(url:URL, withKey key:String, withCertificateUrl certificateUrl:String?, withLicenseUrl licenseUrl:String?, withHeaders headers:Dictionary<String,AnyObject>?, withCache useCache:Bool, cacheKey:String?, cacheManager:PipCacheManager, overriddenDuration:Int, videoExtension:String?) {
        self.overriddenDuration = 0
        
        var headers = headers
        var cacheKey = cacheKey
        var videoExtension = videoExtension
        
        if  headers == nil {
            headers = [:]
        }
        var item:AVPlayerItem!
        if useCache {
            item = cacheManager.getCachingPlayerItemForNormalPlayback(url, cacheKey:cacheKey, videoExtension: videoExtension, headers:headers!)
        } else {
            let urlSpecial = url.specialSchemeURL
            
            let asset:AVURLAsset! = AVURLAsset(url: urlSpecial, options:["AVURLAssetHTTPHeaderFieldsKey" : headers as Any])
            if certificateUrl != nil && certificateUrl!.lengthOfBytes(using: .utf8) > 0 {
                self.loaderDelegate =   PipFlutterEzDrmAssetsLoaderDelegate.init(URL.init(string: certificateUrl!)!, URL.init(string: licenseUrl!)!)
                //            dispatch_queue_attr_t qos = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, -1);
                let streamQueue = DispatchQueue.init(label: "streamQueue")
                asset.resourceLoader.setDelegate(self.loaderDelegate, queue: streamQueue)
                print("url====>setDelegate>>>\(urlSpecial)")
            }else{
//                 self.loaderDelegate =   PipFlutterEzDrmAssetsLoaderDelegate.init()
            }
            item = AVPlayerItem(asset: asset)
        }
        
        if  #available(iOS 10.0, *), overriddenDuration > 0 {
            self.overriddenDuration = overriddenDuration
        }
        return self.setDataSourcePlayerItem(item: item, withKey:key)
    }
    
    func setDataSourcePlayerItem(item:AVPlayerItem!, withKey key:String!) {
        self.key = key
        self.stalledCount = 0
        self.isStalledCheckStarted = false
        self.playerRate = 1
        self.player.replaceCurrentItem(with: item)
        
        let asset = item.asset
        let assetCompletionHandler:()->Void = {
            if asset.statusOfValue(forKey: "tracks", error: nil) == .loaded {
                let tracks = asset.tracks(withMediaType: AVMediaType.video)
                if tracks.count > 0 {
                    let videoTrack = tracks[0]
                    let trackCompletionHandler:()->Void = {
                        if self.disposed {return}
                        if videoTrack.statusOfValue(forKey: "preferredTransform", error: nil) == .loaded{
                            // Rotate the video by using a videoComposition and the preferredTransform
                            self.preferredTransform = self.fixTransform(videoTrack: videoTrack)
                            // Note:
                            // https://developer.apple.com/documentation/avfoundation/avplayeritem/1388818-videocomposition
                            // Video composition can only be used with file-based media and is not supported for
                            // use with media served using HTTP Live Streaming.
                            let videoComposition = self.getVideoCompositionWithTransform(transform: self.preferredTransform!,
                                                                                         withAsset:asset,
                                                                                         withVideoTrack:videoTrack)
                            item.videoComposition = videoComposition
                        }
                    }
                    videoTrack.loadValuesAsynchronously(forKeys: ["preferredTransform"],completionHandler: trackCompletionHandler)
                    
                }
            }
        }
        
        asset.loadValuesAsynchronously(forKeys: ["tracks"],completionHandler: assetCompletionHandler)
        
        self.addObservers(item: item)
    }
    
    func handleStalled() {
        if self.isStalledCheckStarted {
            return
        }
        self.isStalledCheckStarted = true
        self.startStalledCheck()
    }
    
    @objc func startStalledCheck() {
        guard let currentItem = self.player.currentItem else {return}
        
        print("startStalledCheck \(self.availableDuration() - CMTimeGetSeconds(currentItem.currentTime()))  availableDuration()\(self.availableDuration())  currentItemTime() \(CMTimeGetSeconds(currentItem.currentTime()) )")
        if currentItem.isPlaybackLikelyToKeepUp ||
            self.availableDuration() - CMTimeGetSeconds(currentItem.currentTime()) > 10.0 {
            self.play()
            if self.eventSink != nil {
                var values = [[Int64]]()
                currentItem.loadedTimeRanges.forEach { rangeValue in
                    let range = rangeValue.timeRangeValue
                    let start = PipFlutterTimeUtils.timeToMillis(range.start)
                    var end = start + PipFlutterTimeUtils.timeToMillis(range.duration)
                    if CMTIME_IS_VALID(self.player.currentItem!.forwardPlaybackEndTime){
                        let endTime = PipFlutterTimeUtils.timeToMillis(self.player.currentItem!.forwardPlaybackEndTime)
                        if end > endTime {
                            end = endTime
                        }
                    }
                    values.append([start,end])
                }
                self.eventSink!(["event" : "bufferingUpdate", "values" : values, "key" : self.key as Any])
            }
        } else {
            self.stalledCount+=1
            if self.stalledCount > 60 {
                self.eventSink?(FlutterError(code: "VideoError",
                                             message:"Failed to load video: playback stalled",
                                             details:nil))
                return
            }
            
            if(self.stalledCount<3){
                if let currentTime = self.player.currentItem?.currentTime() {
                    let second = CMTimeGetSeconds(currentTime)
                    
                    self.seekTo(location: Int(second*1000)+10 )
                }
            }
            
            self.perform(#selector(self.startStalledCheck), with:nil, afterDelay:1)
            
        }
    }
    
    func availableDuration() -> TimeInterval {
        guard let loadedTimeRanges = self.player.currentItem?.loadedTimeRanges else {return 0}
        if loadedTimeRanges.count > 0 {
            let timeRange = loadedTimeRanges[0].timeRangeValue
            let startSeconds:Float64 = CMTimeGetSeconds(timeRange.start)
            let durationSeconds:Float64 = CMTimeGetSeconds(timeRange.duration)
            let result:TimeInterval = startSeconds + durationSeconds
            return result
        } else {
            return 0
        }
        
    }
    
    
    public override  func  observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        if keyPath == "timeControlStatus", let newStatusValue = change?[.newKey] as? Int, let newStatus = AVPlayer.TimeControlStatus(rawValue: newStatusValue) {
            
            print("timeControlStatus  newStatusValue:\(newStatusValue)  newStatus:\(newStatus) self.player.rate:\(self.player.rate)  isPictureInPictureActive=\(self.pipController?.isPictureInPictureActive == true)  self.player.timeControlStatus:\(self.player.timeControlStatus) lastAvPlayerTimeControlStatus:\(self.lastAvPlayerTimeControlStatus?.rawValue)")
            
            if newStatus == .paused && self.player.rate == 0 && self.pipController?.isPictureInPictureActive == true {
                
                if self.lastAvPlayerTimeControlStatus != self.player.timeControlStatus{
                    // 缓冲不足，且画中画模式激活，手动继续播放
                    player.play()
                    self.lastAvPlayerTimeControlStatus = self.player.timeControlStatus
                }else{
                    if(self.playerToGoPipFlag){
                        player.play()
                        self.playerToGoPipFlag=false
                    }
                }
            }
            return
        }else if (keyPath == "rate") {
            if #available(iOS 10.0, *) {
                if self.pipController?.isPictureInPictureActive == true {
                    //                    self.lastAvPlayerTimeControlStatus != nil &&
                    if self.lastAvPlayerTimeControlStatus == self.player.timeControlStatus {
                        //                        if self.player.timeControlStatus == .paused {
                        //                            self.isPlaying=false
                        //                            self.eventSink?(["event" : "pause"])
                        //                            return
                        //                        }
                        //                        if self.player.timeControlStatus == .playing {
                        //                            self.isPlaying = true
                        //                            self.eventSink?(["event" : "play"])
                        //                        }
                        return
                    }
                    
                    if self.player.timeControlStatus == .paused {
                        self.lastAvPlayerTimeControlStatus = self.player.timeControlStatus
                        self.isPlaying=false
                        self.eventSink?(["event" : "pause"])
                        
                        return
                        
                    }
                    if self.player.timeControlStatus == .playing {
                        self.lastAvPlayerTimeControlStatus = self.player.timeControlStatus
                        self.isPlaying = true
                        self.eventSink?(["event" : "play"])
                        
                    }
                }
            }
            let currentItem = self.player.currentItem
            
            let currentTime = currentItem?.currentTime() ?? .zero
            let duration = currentItem?.duration ?? .zero
            
            
            
            if self.player.rate == 0 && //if player rate dropped to 0
                ///TODO  这里需要修改
                currentTime > .zero &&
                currentTime < duration &&
                //CMTIME_COMPARE_INLINE(_player.currentItem.currentTime, >, kCMTimeZero) && //if video was started
                //CMTIME_COMPARE_INLINE(_player.currentItem.currentTime, <, _player.currentItem.duration) && //but not yet finished
                self.isPlaying { //instance variable to handle overall state (changed to YES when user triggers playback)
                self.handleStalled()
            }
        }
        
        let context = context
        if context != nil{
            if(context! == timeRangeContext && object is AVPlayerItem){
                if self.eventSink != nil {
                    var values = [[Int64]]()
                    (object as! AVPlayerItem).loadedTimeRanges.forEach { rangeValue in
                        let range = rangeValue.timeRangeValue
                        let start = PipFlutterTimeUtils.timeToMillis(range.start)
                        var end = start + PipFlutterTimeUtils.timeToMillis(range.duration)
                        if CMTIME_IS_VALID(self.player.currentItem!.forwardPlaybackEndTime){
                            let endTime = PipFlutterTimeUtils.timeToMillis(self.player.currentItem!.forwardPlaybackEndTime)
                            if end > endTime {
                                end = endTime
                            }
                        }
                        values.append([start,end])
                    }
                    self.eventSink!(["event" : "bufferingUpdate", "values" : values, "key" : self.key as Any])
                }
            } else if context! == presentationSizeContext {
                self.onReadyToPlay()
            }
            
            else if context! == statusContext {
                let item = object as! AVPlayerItem
                switch item.status {
                case .failed:
                    print("Failed to load video:")
                    print(item.error.debugDescription)
                    self.eventSink?(FlutterError(code: "VideoError", message: "Failed to load video:\(item.error?.localizedDescription)", details: nil))
                    break
                case .unknown:
                    break
                case .readyToPlay:
                    self.onReadyToPlay()
                    break
                @unknown default:
                    break
                }
            } else if context! == playbackLikelyToKeepUpContext {
                if self.player.currentItem?.isPlaybackLikelyToKeepUp == true {
                    self.updatePlayingState()
                    self.eventSink?(["event" : "bufferingEnd", "key" : self.key])
                }
            } else if context! == playbackBufferEmptyContext {
                self.eventSink?(["event" : "bufferingStart", "key" : self.key])
            } else if context! == playbackBufferFullContext {
                self.eventSink?(["event" : "bufferingEnd", "key" : self.key])
            }
        }
        
    }
    
    func updatePlayingState() {
        if !self.isInitialized || (self.key == nil) {
            return
        }
        if !self.observersAdded {
            self.addObservers(item: self.player.currentItem)
        }
        
        if self.isPlaying {
            if #available(iOS 10.0, *) {
                self.player.playImmediately(atRate: 1.0)
                self.player.rate = self.playerRate
            } else {
                self.player.play()
                self.player.rate = self.playerRate
            }
        } else {
            self.player.pause()
        }
    }
    
    func onReadyToPlay() {
        if (self.eventSink != nil) && !self.isInitialized &&  self.key != nil {
            if (self.player.currentItem == nil) {
                return
            }
            if self.player.status != .readyToPlay {
                return
            }
            
            let size = self.player.currentItem?.presentationSize
            let width = size?.width ?? 0
            let height = size?.height ?? 0
            
            
            let asset = self.player.currentItem?.asset
            let onlyAudio = (asset?.tracks(withMediaType: .video).count ?? 0) == 0
            
            // The player has not yet initialized.
            if !onlyAudio && height == CGSizeZero.height && width == CGSizeZero.width {
                return
            }
            let isLive:Bool = CMTIME_IS_INDEFINITE(self.player.currentItem!.duration)
            // The player may be initialized but still needs to determine the duration.
            if isLive == false && self.duration() == 0 {
                return
            }
            
            //Fix from https://github.com/flutter/flutter/issues/66413
            let track = self.player.currentItem!.tracks.first!
            let naturalSize = track.assetTrack!.naturalSize
            let prefTrans = track.assetTrack!.preferredTransform
            let realSize:CGSize = CGSizeApplyAffineTransform(naturalSize, prefTrans)
            
            let duration = PipFlutterTimeUtils.timeToMillis( self.player.currentItem!.asset.duration)
            if self.overriddenDuration > 0 && duration > self.overriddenDuration {
                self.player.currentItem!.forwardPlaybackEndTime = CMTimeMake(value: Int64(self.overriddenDuration/1000), timescale: 1)
            }
            
            self.isInitialized = true
            self.updatePlayingState()
            self.eventSink?([
                "event" : "initialized",
                "duration" : self.duration(),
                "width" : abs(realSize.width) == 0 ?abs(realSize.width): width,
                "height" : abs(realSize.height) == 0 ? abs(realSize.height): height,
                "key" : self.key!
            ])
        }
    }
    
    func play() {
        self.stalledCount = 0
        self.isStalledCheckStarted = false
        self.isPlaying = true
        self.updatePlayingState()
    }
    
    func pause() {
        self.isPlaying = false
        self.updatePlayingState()
    }
    
    func position() -> Int64 {
        return PipFlutterTimeUtils.timeToMillis(self.player.currentTime() )
    }
    
    func absolutePosition() -> Int64 {
        
        if self.player.currentItem!.currentDate() != nil {
            return PipFlutterTimeUtils.timeToMillis(CMTime(value: CMTimeValue(self.player.currentItem!.currentDate()!.timeIntervalSince1970), timescale: 1) )
        }else{
            return 0
        }
        
    }
    
    func duration() -> Int64 {
        var time:CMTime
        if #available(iOS 13, *) {
            time =  self.player.currentItem?.duration ?? .zero
        } else {
            time =  self.player.currentItem?.asset.duration ?? .zero
        }
        if !CMTIME_IS_INVALID(self.player.currentItem?.forwardPlaybackEndTime ?? .zero) {
            time = self.player.currentItem!.forwardPlaybackEndTime
        }
        
        return PipFlutterTimeUtils.timeToMillis(time)
    }
    
    func seekTo(location:Int) {
        ///When player is playing, pause video, seek to new position and start again. This will prevent issues with seekbar jumps.
        let wasPlaying = self.isPlaying
        if wasPlaying {
            self.player.pause()
        }
        
        self.player.seek(to: CMTimeMake(value: Int64(location), timescale: 1000),
                         toleranceBefore:CMTime.zero,
                         toleranceAfter:CMTime.zero,
                         completionHandler:{ (finished:Bool) in
            if wasPlaying {
                self.player.rate = self.playerRate
            }
        })
    }
    
    // `setIsLooping:` has moved as a setter.
    
    func setVolume(_ volume:Double) {
        self.player.volume = Float((volume < 0.0)   ?  0.0   :  (volume > 1.0) ? 1.0 : volume)
    }
    
    func setSpeed(_ speed:Double, result:FlutterResult) {
        if speed == 1.0 || speed == 0.0 {
            self.playerRate = 1
            result(nil)
        } else if speed < 0 || speed > 2.0 {
            result(FlutterError(code: "unsupported_speed",
                                message:"Speed must be >= 0.0 and <= 2.0",
                                details:nil))
        } else if (speed > 1.0 && self.player.currentItem!.canPlayFastForward) ||
                    (speed < 1.0 && self.player.currentItem!.canPlaySlowForward) {
            self.playerRate = Float(speed)
            result(nil)
        } else {
            if speed > 1.0 {
                result(FlutterError(code: "unsupported_fast_forward",
                                    message:"This video cannot be played fast forward",
                                    details:nil))
            } else {
                result(FlutterError(code: "unsupported_slow_forward",
                                    message:"This video cannot be played slow forward",
                                    details:nil))
            }
        }
        
        if self.isPlaying {
            self.player.rate = self.playerRate
        }
    }
    
    
    func setTrackParameters(_ width:Int,_ height:Int,_ bitrate:Int) {
        self.player.currentItem?.preferredPeakBitRate = Double(bitrate)
        if #available(iOS 11.0, *) {
            if width == 0 && height == 0 {
                self.player.currentItem?.preferredMaximumResolution = .zero
            } else {
                self.player.currentItem?.preferredMaximumResolution = CGSize(width: width, height: height)
            }
        }
    }
    
    
    
    func setPictureInPicture(pictureInPicture:Bool) {
        self.mPictureInPicture = pictureInPicture
        print("setPictureInPicture pictureInPicture : \(pictureInPicture) pipController:\(self.pipController) mPictureInPicture:\(self.mPictureInPicture) isPictureInPictureActive:\(self.pipController!.isPictureInPictureActive)")
        if #available(iOS 9.0, *) {
            if (self.pipController != nil) && self.mPictureInPicture && !self.pipController!.isPictureInPictureActive {
                
                DispatchQueue.main.async {
                    self.pipController!.startPictureInPicture()
                }
            } else if (self.pipController != nil) && !self.mPictureInPicture && self.pipController!.isPictureInPictureActive {
                DispatchQueue.main.async {
                    self.pipController!.stopPictureInPicture()
                    self.playerToGoPipFlag=true
                }
            } else {
                // Fallback on earlier versions
            } }
    }
    
    func setRestoreUserInterfaceForPIPStopCompletionHandler(restore:Bool) {
        restoreUserInterfaceForPIPStopCompletionHandler?(restore)
        restoreUserInterfaceForPIPStopCompletionHandler = nil
    }
    
    func setupPipController() {
        if #available(iOS 9.0, *) {
            do{
                try  AVAudioSession.sharedInstance().setActive(true)
            }catch{
            }
            UIApplication.shared.beginReceivingRemoteControlEvents()
            if (self.pipController == nil) && self.playerLayer != nil && AVPictureInPictureController.isPictureInPictureSupported() {
                self.pipController = AVPictureInPictureController(playerLayer:self.playerLayer!)
                if #available(iOS 14.2, *) {
                    self.pipController!.canStartPictureInPictureAutomaticallyFromInline = true
                }
                self.pipController!.delegate = self
            }
        } else {
            // Fallback on earlier versions
        }
    }
    
    func enablePictureInPicture(frame:CGRect) {
        self.usePlayerLayer(frame: frame)
    }
    
    
    func playerLayerSetup(frame:CGRect) {
        print("setPictureInPicture pictureInPicture : playerLayerSetup\(frame)")
        //        self.setPictureInPicture(pictureInPicture: false)
        self.mPictureInPicture = false
        self.playerToGoPipFlag=true
        if (self.playerLayer != nil) {
            self.playerLayer!.removeFromSuperlayer()
            self.playerLayer = nil
        }
        // Create new controller passing reference to the AVPlayerLayer
        self.playerLayer = AVPlayerLayer(player: self.player)
        let vc = UIApplication.shared.keyWindow!.rootViewController!
        self.playerLayer!.frame = frame
        self.playerLayer!.needsDisplayOnBoundsChange = true
        //  [self._playerLayer addObserver:self forKeyPath:readyForDisplayKeyPath options:NSKeyValueObservingOptionNew context:nil];
        vc.view.layer.addSublayer(self.playerLayer!)
        self.playerLayer!.isHidden=true
        vc.view.layer.needsDisplayOnBoundsChange = true
        if #available(iOS 9.0, *) {
            self.pipController = nil
        }
        self.setupPipController()
    }
    
    
    func usePlayerLayer(frame:CGRect) {
        print("setPictureInPicture pictureInPicture : usePlayerLayer\(frame) \(self.playerLayer)")
        if (self.playerLayer == nil) {
            return
        }
        self.playerLayer!.isHidden=false
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200), execute:
                                        {
            self.setPictureInPicture(pictureInPicture: true)
        })
    }
    
    func disablePictureInPictureNoAction() {
        self.playerLayer?.isHidden=true
        self.eventSink?(["event" : "pipStop"])
    }
    func disablePictureInPicture() {
        
        //        self.playerLayer?.removeFromSuperlayer()
        //        self.playerLayer = nil
        //        self.setPictureInPicture(pictureInPicture: false)
        self.mPictureInPicture = false
        self.playerToGoPipFlag=true
        if (self.pipController != nil) {
            DispatchQueue.main.async {
                self.pipController!.stopPictureInPicture()
                self.playerLayer?.removeFromSuperlayer()
                self.playerLayer = nil
            }
        }
        
    }
    
    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("pictureInPictureControllerDidStopPictureInPicture")
        //        self.disablePictureInPicture()
    }
    
    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        self.eventSink?(["event" : "pipStart"])
        print("pictureInPictureControllerDidStartPictureInPicture")
    }
    
    
    public func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("pictureInPictureControllerWillStopPictureInPicture")
    }
    
    
    public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("pictureInPictureControllerWillStartPictureInPicture")
    }
    
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        //画中画播放器启动失败
        print("failedToStartPictureInPictureWithError:: \(error)")
    }
    
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        
        self.setRestoreUserInterfaceForPIPStopCompletionHandler(restore: true)
        
        //画中画播放停止的事件
        print("restoreUserInterfaceForPictureInPictureStopWithCompletionHandler")
    }
    
    func setAudioTrack(_ name:String, index:Int) {
        let audioSelectionGroup = self.player.currentItem!.asset.mediaSelectionGroup(forMediaCharacteristic: AVMediaCharacteristic.audible)!
        let options = audioSelectionGroup.options
        
        for audioTrackIndex in (0..<options.count) {
            let option = options[audioTrackIndex]
            let metaDatas = AVMetadataItem.metadataItems(from: option.commonMetadata , withKey: "title", keySpace: AVMetadataKeySpace.common)
            
            if metaDatas.count > 0 {
                let title = metaDatas[0].stringValue
                if name == title && audioTrackIndex==index{
                    self.player.currentItem!.select(option, in: audioSelectionGroup)
                }
                
            }
        }
    }
    
    func setMixWithOthers(_ mixWithOthers:Bool) {
        do{
            if mixWithOthers {
                try AVAudioSession.sharedInstance().setCategory(.playback,options: .mixWithOthers)
            } else {
                try AVAudioSession.sharedInstance().setCategory(.playback)
            }
        }catch{
        }
    }
    
    
    /// This method allows you to dispose without touching the event channel.  This
    /// is useful for the case where the Engine is in the process of deconstruction
    /// so the channel is going to die or is already dead.
    func disposeSansEventChannel() {
        do{
            try? self.clear()
        }catch let error{
            print("\(error.localizedDescription)")
        }
    }
    
    func dispose() {
        self.pause()
        self.disposeSansEventChannel()
        self.eventChannel?.setStreamHandler(nil)
        
        self.disablePictureInPicture()
        self.mPictureInPicture = false
        self.playerToGoPipFlag=true
        self.disposed = true
    }
    
    func setOnBackgroundCountingListener(_ pFunction:( ()->Void)?) {
        self.lis=pFunction
    }
}
