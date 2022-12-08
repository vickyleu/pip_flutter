//
//  PipFlutterView.swift
//  Runner
//
//  Created by vicky Leu on 2022/12/5.
//

import UIKit
import AVKit
import AVFoundation

class PipFlutterView : UIView {
    var player:AVPlayer!{
        get{self.playerLayer.player}
        set{
            
            self.playerLayer.player = newValue
        }
    }
    var playerLayer:AVPlayerLayer
    {
        get{(self.layer as! AVPlayerLayer)}
    }

    // Override UIView method
    override class var layerClass: AnyClass{
        return AVPlayerLayer.self
    }

    
}
