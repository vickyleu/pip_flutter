import Foundation
import MediaPlayer
import AVKit
import AVFoundation
import GLKit


public  class SwiftPipFlutterPlugin: NSObject, FlutterPlugin, FlutterPlatformViewFactory {

    private var players = Dictionary<Int, PipFlutter>.init(minimumCapacity: 1)

    private var bgTask: UIBackgroundTaskIdentifier?
    private var isInPipMode: Bool = false
    private var aspect: AspectToken?

    private  static var _sharedInstance: SwiftPipFlutterPlugin?

    private lazy var channel: FlutterMethodChannel = {
        FlutterMethodChannel.init(name: "pipflutter_player_channel", binaryMessenger: registrar.messenger())
    }()

    private var _dataSourceDict = Dictionary<Int, Dictionary<String, AnyObject>>()
    private var _timeObserverIdDict = Dictionary<String, AnyObject>()
    private var _artworkImageDict = Dictionary<String, MPMediaItemArtwork>()

    private var texturesCount: Int = -1

    private var _notificationPlayer: PipFlutter?
    private var _remoteCommandsInitialized: Bool = false

    private var _cacheManager: PipCacheManager = PipCacheManager()

    class func shareInstance() -> SwiftPipFlutterPlugin {
        return _sharedInstance!
    }

    private var messenger: FlutterBinaryMessenger
    private var registrar: FlutterPluginRegistrar

    init(_ registrar: FlutterPluginRegistrar) {
        self.messenger = registrar.messenger()
        self.registrar = registrar
        super.init()
        self.registrar.addMethodCallDelegate(self, channel: self.channel)
        self.registrar.addApplicationDelegate(self)
        self.registrar.register(self, withId: "com.pipflutter/pipflutter_player")
        Self._sharedInstance = self
        self._cacheManager.setup()

    }

    // MARK: - FlutterPlugin protocol

    public static func register(with registrar: FlutterPluginRegistrar) {
       _ = SwiftPipFlutterPlugin(registrar)
    }

    // MARK: - FlutterPlatformViewFactory protocol

    public func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        let textureId = (args as! Dictionary<String, AnyObject>)["textureId"] as! NSNumber
        let player = players[textureId.intValue]
        return player!
    }

    
    
    private  func aaa() {
        if self.aspect != nil {
            return
        }
        do {
            // 拿到需要插入执行的 block
            let wrappedBlock: @convention(block) (AspectInfo) -> Void = { (info:AspectInfo) in
                if !self.isInPipMode{
                    var flutterController : FlutterViewController? = nil
                    let rootVc = UIApplication.shared.keyWindow?.rootViewController
                    if let navigationVc = rootVc as? UINavigationController {
                        if let vc = navigationVc.children.first as? FlutterViewController{
                            flutterController = vc
                        }
                    }
                    if flutterController == nil{
                        guard let controller:FlutterViewController  = rootVc as? FlutterViewController else {return}
                        flutterController = controller
                    }
                    guard let controller:FlutterViewController = flutterController as? FlutterViewController else {return}

                    if self.players.count != 1{
                        return
                    }
                    if !controller.isKind(of: FlutterViewController.self){
                        return
                    }
                    let players = self.players.map{$0.1}
                    guard let player:PipFlutter  = players.last else {return}
                    if player.isPlaying && !player.isPiping {
                        self.channel.invokeMethod("preparePipFrame", arguments: nil)
                        self.isInPipMode = true
                    }
                }
            }
            let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
            
            self.aspect = try FlutterViewController.aspect_hook(#selector(FlutterViewController.viewWillLayoutSubviews),with: .positionAfter, usingBlock: wrappedObject)
        } catch let error {
            print("\(error.localizedDescription)")
        }
    }

    private  func bbb() {
        self.aspect?.remove()
    }


    public  func applicationWillEnterForeground(_ application: UIApplication) {
        if self.bgTask != nil {
            application.endBackgroundTask(self.bgTask!)
        }
        if self.players.count != 1 {
            return
        }
        let players = self.players.map {
            $0.1
        }
        let player = players.last

        if player != nil && player!.isPlaying && player!.isPiping {
            self.channel.invokeMethod("exitPip", arguments: nil)
        }
        self.bgTask = .invalid
        self.isInPipMode = false
        print("applicationWillEnterForeground exitPip")
//

    }

    public  func applicationDidEnterBackground(_ application: UIApplication) {
        if self.players.count != 1 {
            return
        }
        let players = self.players.map {
            $0.1
        }
        let player = players.last
        if player != nil && player!.isPlaying && !player!.isPiping {
            print("preparePip to")
            self.channel.invokeMethod("prepareToPip", arguments: nil)
            self.backgroundHandler(player!, application)
        }
    }

    func notifyDart(_ player: PipFlutter) {

        let position: Int = Int(player.position())
        let duration: Int = Int(player.duration())

        self.channel.invokeMethod("pipNotify", arguments: ["position": position, "duration": duration])
    }

    func backgroundHandler(_ player: PipFlutter, _ app: UIApplication) {
        NSLog("### -->backgroundinghandler")
        self.bgTask = app.beginBackgroundTask {
            NSLog("====任务完成了。。。。。。。。。。。。。。。===>")
            // [app endBackgroundTask:bgTask];
        }
        // Start the long-running task
        DispatchQueue.global(qos: .default).async {
            while true && self.bgTask != .invalid {
                self.notifyDart(player)
                Thread.sleep(forTimeInterval: 1)
            }
            self.notifyDart(player)
        }
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        self.players.map {
                    $0.1
                }
                .forEach { v in
                    v.disposeSansEventChannel()
                }
        self.players.removeAll()
    }


    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }


    // MARK: - SwiftPipFlutterPlugin class

    func newTextureId() -> Int {
        texturesCount += 1
        return texturesCount
    }

    func onPlayerSetup(_ player: PipFlutter, result: FlutterResult) {
        let textureId = self.newTextureId()
        let eventChannel = FlutterEventChannel.init(name: "pipflutter_player_channel/videoEvents\(textureId)", binaryMessenger: messenger)
        player.setMixWithOthers(false)
        eventChannel.setStreamHandler(player)
        player.eventChannel = eventChannel

        player.setOnBackgroundCountingListener {
            self.bgTask = .invalid
        }

        self.players[textureId] = player

        result(["textureId": textureId])
    }

//

    func setupRemoteNotification(_ player: PipFlutter) {
        _notificationPlayer = player
        self.stopOtherUpdateListener(player)
        let dataSource = _dataSourceDict[Int(self.getTextureId(player))!]!
        var showNotification: Bool = false
        let showNotificationObject = dataSource["showNotification"]
        if showNotificationObject != nil {
            showNotification = dataSource["showNotification"] as! Bool
        }
        let title = dataSource["title"] as! String
        let author = dataSource["author"] as! String
        let imageUrl = dataSource["imageUrl"] as? String

        if showNotification {
            self.setRemoteCommandsNotificationActive()
            self.setupRemoteCommands(player)
            self.setupRemoteCommandNotification(player, title, author, imageUrl)
            self.setupUpdateListener(player, title, author, imageUrl)
        }
    }


    func setRemoteCommandsNotificationActive() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
        }
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }


    func setRemoteCommandsNotificationNotActive() {
        if self.players.count == 0 {
            do {
                try AVAudioSession.sharedInstance().setActive(false)
            } catch  {
            }
        }
        UIApplication.shared.endReceivingRemoteControlEvents()
    }

    func setupRemoteCommands(_ player: PipFlutter) {
        if _remoteCommandsInitialized {
            return
        }
        let commandCenter: MPRemoteCommandCenter! = MPRemoteCommandCenter.shared()
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        if #available(iOS 9.1, *) {
            commandCenter.changePlaybackPositionCommand.isEnabled = true
        }
        commandCenter.togglePlayPauseCommand.addTarget { event in
            if self._notificationPlayer != nil {
                if self._notificationPlayer!.isPlaying {
                    self._notificationPlayer!.eventSink?(["event": "play"])
                } else {
                    self._notificationPlayer!.eventSink?(["event": "pause"])
                }
            }
            return .success
        }
        commandCenter.playCommand.addTarget { event in
            if self._notificationPlayer != nil {
                self._notificationPlayer!.eventSink?(["event": "play"])
            }
            return .success
        }
        commandCenter.pauseCommand.addTarget { event in
            if self._notificationPlayer != nil {
                self._notificationPlayer!.eventSink?(["event": "pause"])
            }
            return .success
        }


        if #available(iOS 9.1, *) {
            commandCenter.changePlaybackPositionCommand.addTarget { event in
                if self._notificationPlayer != nil {
                    let playbackEvent = event as! MPChangePlaybackPositionCommandEvent

                    let time: CMTime = CMTimeMake(value: Int64(playbackEvent.positionTime), timescale: 1)
                    let millis = PipFlutterTimeUtils.timeToMillis(time)
                    self._notificationPlayer!.seekTo(location:  Int((millis)))
                    self._notificationPlayer!.eventSink?(["event": "seek", "position": millis])
                }
                return .success
            }

        }
        _remoteCommandsInitialized = true
    }


    func setupRemoteCommandNotification(_ player: PipFlutter, _ title: String, _ author: String, _ imageUrl: String?) {
        let positionInSeconds: Float = Float(player.position() / 1000)
        let durationInSeconds: Float = Float(player.duration() / 1000)


        var nowPlayingInfoDict: [String: AnyObject] = [
            MPMediaItemPropertyArtist: author as AnyObject,
            MPMediaItemPropertyTitle: title as AnyObject,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: NSNumber(value: positionInSeconds),
            MPMediaItemPropertyPlaybackDuration: NSNumber(value: durationInSeconds),
            MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: 1)
        ]


        if imageUrl != nil {
            let key: String! = self.getTextureId(player)
            let artworkImage = _artworkImageDict[key]

            if key != nil {
                if (artworkImage != nil) {
                    nowPlayingInfoDict[MPMediaItemPropertyArtwork] = artworkImage
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfoDict
                } else {
                    DispatchQueue.global(qos: .background).async {[weak self] in
                        do {
                            var tempArtworkImage: UIImage?
                            if !imageUrl!.contains("http") {
                                tempArtworkImage = UIImage.init(contentsOfFile: imageUrl!)
                            } else {
                                tempArtworkImage = UIImage.init(data: try Data.init(contentsOf: URL.init(string: imageUrl!)!))
                            }
                            if tempArtworkImage != nil {
                                let image = tempArtworkImage!
                                let boundsSize = CGSize(width: image.size.width, height: image.size.height)
                                let artworkImage = MPMediaItemArtwork(image: image)
//                                let artworkImage = MPMediaItemArtwork.init(boundsSize: boundsSize) { size in
//                                    return image
//                                }
                                self?._artworkImageDict[key] = artworkImage
                                nowPlayingInfoDict[MPMediaItemPropertyArtwork] = artworkImage
                            }
                            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfoDict
                        } catch  {

                        }
                    }
                }
            }
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfoDict
        }
    }

//

//
    func getTextureId(_ player: PipFlutter) -> String {
        let temp = self.players.allKeysForValue(val: player)
        if temp.count==0{
            return "\(-1)"
        }
        let key = temp.last!
        return "\(key)"
    }

//

    func setupUpdateListener(_ player: PipFlutter, _ title: String, _ author: String, _ imageUrl: String?) {
        let _timeObserverId = player.player.addPeriodicTimeObserver(forInterval: CMTimeMake(value: 1, timescale: 1), queue: nil) { time in
            self.setupRemoteCommandNotification(player, title, author, imageUrl)
        } as AnyObject
        let key = self.getTextureId(player)
        _timeObserverIdDict[key] = _timeObserverId
    }


    func disposeNotificationData(player: PipFlutter!) {
        if player == _notificationPlayer {
            _notificationPlayer = nil
            _remoteCommandsInitialized = false
        }
        let key: String! = self.getTextureId(player)
        var _timeObserverId = _timeObserverIdDict[key]
        _timeObserverIdDict.removeValue(forKey: key)
        _artworkImageDict.removeValue(forKey: key)

        if (_timeObserverId != nil) {
            player.player.removeTimeObserver(_timeObserverId! as Any)
            _timeObserverId = nil
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [:]
    }

//

    func stopOtherUpdateListener(_ player: PipFlutter) {
        let currentPlayerTextureId: String! = self.getTextureId(player)
        for (textureId, timeObserverId) in _timeObserverIdDict {
            if currentPlayerTextureId == textureId {
                continue
            }
            let playerToRemoveListener = self.players[Int(textureId)!]
            playerToRemoveListener?.player.removeTimeObserver(timeObserverId)
        }
        _timeObserverIdDict.removeAll()

    }
    
    

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            //Allow audio playback when the Ring/Silent switch is set to silent
            self.players.forEach { (key: Int, value: PipFlutter) in
                value.dispose()
            }
            self.players.removeAll()
            result(nil)
            break
        case "create":
            self.onPlayerSetup(PipFlutter.init(frame: .zero), result: result)
            break
        default:
            let argsMap = call.arguments as! Dictionary<String,AnyObject>
            let textureId = argsMap["textureId"] as! Int
            let player = self.players[textureId]!
            switch call.method{
            case "setDataSource":
                player.clear()
                // This call will clear cached frame because we will return transparent frame
                let dataSource = argsMap["dataSource"] as! Dictionary<String,AnyObject>
                _dataSourceDict[Int(self.getTextureId(player))!] = dataSource
                let assetArg = dataSource["asset"] as? String
                let uriArg = dataSource["uri"] as? String
                let key = dataSource["key"] as! String
                let certificateUrl = dataSource["certificateUrl"] as? String
                let licenseUrl = dataSource["licenseUrl"] as? String
                var headers = dataSource["headers"] as? Dictionary<String,AnyObject>
                let cacheKey = dataSource["cacheKey"] as? String
                let maxCacheSize = dataSource["maxCacheSize"] as? Int
                let videoExtension = dataSource["videoExtension"] as? String
                var overriddenDuration:Int = 0
                if !dataSource["overriddenDuration"].isNsnullOrNil() {
                    print("\(dataSource["overriddenDuration"])")
                    overriddenDuration = dataSource["overriddenDuration"] as! Int
                }

                var useCache:Bool = false
                let useCacheObject = dataSource["useCache"] as? Bool
                if useCacheObject != nil {
                    useCache = useCacheObject! as Bool
                    if useCache {
                        _cacheManager.setMaxCacheSize(NSNumber(value: maxCacheSize!))
                    }
                }
                if headers == nil {
                    headers = [:]
                }
                if (assetArg != nil) {
                    var assetPath:String
                    let package = dataSource["package"] as? String
                    if package != nil {
                        assetPath = registrar.lookupKey(forAsset: assetArg!, fromPackage: package!)
                    } else {
                        assetPath = registrar.lookupKey(forAsset: assetArg!)
                    }
                    player.setDataSourceAsset(asset: assetPath, withKey: key, withCertificateUrl: certificateUrl, withLicenseUrl: licenseUrl, cacheKey: cacheKey, cacheManager: _cacheManager, overriddenDuration: overriddenDuration)
                   
                } else if (uriArg != nil) {
                    
                    player.setDataSourceURL(url: URL.init(string: uriArg!)!, withKey: key, withCertificateUrl: certificateUrl, withLicenseUrl: licenseUrl, withHeaders: headers!, withCache: useCache, cacheKey: cacheKey, cacheManager: _cacheManager, overriddenDuration: overriddenDuration, videoExtension: videoExtension)
                } else {
                    result(FlutterMethodNotImplemented)
                    return
                }
                result(nil)
                break
            case "dispose":
                self.bbb()
                player.clear()
                self.disposeNotificationData(player: player)
                self.setRemoteCommandsNotificationNotActive()
                player.setOnBackgroundCountingListener(nil)
                self.players.removeValue(forKey: textureId)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(600), execute:
                {
                    if !player.disposed{
                        player.dispose()
                    }
                })
                if self.players.count == 0 {
                    do {
                        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    } catch {
                    }
                }
                result(nil)
                break
            case "setLooping":
                player.isLooping = argsMap["looping"] as! Bool
                result(nil)
                break
            case "setVolume":
                player.setVolume(argsMap["volume"] as! Double)
                result(nil)
                break
            case "play":
                self.setupRemoteNotification(player)
                player.play()
                self.aaa()
                result(nil)
                break
            case "position":
                result(player.position())
                break
            case "absolutePosition":
                result(player.absolutePosition())
                break
            case "seekTo":
                player.seekTo(location: argsMap["location"] as! Int)
                result(nil)
                break
            case "pause":
                player.pause()
                result(nil)
                break
            case "setSpeed":
                player.setSpeed(argsMap["speed"] as! Double, result:result)
                break
            case "setTrackParameters":
                let width = argsMap["width"] as! Int
                let height = argsMap["height"] as! Int
                let bitrate = argsMap["bitrate"] as! Int
                player.setTrackParameters(width, height, bitrate)
                result(nil)
                break
            case "enablePictureInPicture":
                let left = argsMap["left"] as! Double
                let top = argsMap["top"] as! Double
                let width = argsMap["width"] as! Double
                let height = argsMap["height"] as! Double
                player.enablePictureInPicture(frame: CGRect.init(x: left, y: top, width: width, height: height))
                result(nil)
                break
            case "enablePictureInPictureFrame":
                let left = argsMap["left"] as! Double
                let top = argsMap["top"] as! Double
                let width = argsMap["width"] as! Double
                let height = argsMap["height"] as! Double
                player.playerLayerSetup(frame: CGRect.init(x: left, y: top, width: width, height: height))
                result(nil)
                break
            case "isPictureInPictureSupported":
                if #available(iOS 9.0, *) {
                    if AVPictureInPictureController.isPictureInPictureSupported() {
                        result(true)
                        return
                    }
                }
                result(false)
                break
            case "disablePictureInPicture":
                player.disablePictureInPictureNoAction()
                result(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1500)) {
                    [weak player] in
                    player?.disablePictureInPicture()
                }
//                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + .milliseconds(1500), execute: {
////                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + .milliseconds(1500), execute: {
//                    [weak player] in
//                    player?.disablePictureInPicture()
////                    player?.mPictureInPicture = false
//                })
//                player.mPictureInPicture = false
                
               
                break
            case "setAudioTrack":
                let name = argsMap["name"] as! String
                let index = argsMap["index"] as! Int
                player.setAudioTrack(name, index: index)
                result(nil)
                break
            case "setMixWithOthers":
                player.setMixWithOthers(argsMap["mixWithOthers"] as! Bool)
                result(nil)
                break
            case "preCache":
                let dataSource = argsMap["dataSource"] as! Dictionary<String,AnyObject>
                let urlArg = dataSource["uri"] as? String
                let cacheKey = dataSource["cacheKey"] as? String
                var headers = dataSource["headers"]as? Dictionary<String,AnyObject>
                let maxCacheSize = dataSource["maxCacheSize"] as? Int
                var videoExtension = dataSource["videoExtension"] as? String

                if headers == nil {
                    headers = [:]
                }
                if videoExtension == nil {
                    videoExtension = nil
                }
                if urlArg != nil {
                    let url = URL.init(string: urlArg!)!
                    if self._cacheManager.isPreCacheSupported(url: url, videoExtension: videoExtension) {
                        self._cacheManager.setMaxCacheSize(NSNumber(value: maxCacheSize!))
                        self._cacheManager.preCacheURL(url, cacheKey: cacheKey, videoExtension: videoExtension, withHeaders: headers!) { success in

                        }
                    }else{
                        print("Pre cache is not supported for given data source.")
                    }
                }
                result(nil)
                break
            case "clearCache":
                self._cacheManager.clearCache()
                result(nil)
                break
            case "stopPreCache":
                let urlArg = argsMap["url"] as? String
                let cacheKey:String! = argsMap["cacheKey"] as? String
                let videoExtension = argsMap["videoExtension"] as? String
                if urlArg != nil {
                    let url = URL.init(string: urlArg!)!
                    if self._cacheManager.isPreCacheSupported(url: url, videoExtension: videoExtension) {
                        self._cacheManager.stopPreCache(url, cacheKey: cacheKey) { success in
                        }
                    }else{
                        print("Stop pre cache is not supported for given data source.")
                    }
                }
                result(nil)
                break
            default:
                result(FlutterMethodNotImplemented)
                break
            }
            break
        }
    }
}

extension Dictionary where Value: Equatable {
    func allKeysForValue(val: Value) -> [Key] {
        return self.filter {
                    $1 == val
                }
                .map {
                    $0.0
                }
    }
}

extension Optional where Wrapped: AnyObject {
    func isNsnullOrNil() -> Bool
       {
           if (self is NSNull) || (self == nil)
           {
               return true
           }
           else
           {
               return false
           }
       }
}

extension Optional where Wrapped: NSObject {
    func isNsnullOrNil() -> Bool
       {
           if (self is NSNull) || (self == nil)
           {
               return true
           }
           else
           {
               return false
           }
       }
}



