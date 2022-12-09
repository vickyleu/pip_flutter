//
//  PlayTimer.swift
//  pip_flutter
//
//  Created by vicky Leu on 2022/12/9.
//

import Foundation


class PlayTimer {
    // 定时器对象
    var timer: Timer?

    // 定时器时间间隔
    var timeInterval: TimeInterval = 0

    // 上一次打点时间戳
    var lastTimestamp: TimeInterval = 0

    // 开始计时
    func start(interval: TimeInterval) {
        // 设置定时器时间间隔
        timeInterval = interval

        // 开始执行定时器
        timer = Timer.scheduledTimer(timeInterval: timeInterval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    }

    // 暂停计时
    func pause() {
        // 停止定时器
        timer?.invalidate()
        timer = nil
    }

    // 打点
    func mark() -> Bool {
        // 获取当前时间戳
        let timestamp = Date().timeIntervalSince1970

        // 判断上一次打点时间戳与当前时间戳的间隔是否超过 30 秒
        if timestamp - lastTimestamp < 30 {
            // 间隔未超过 30 秒，打点失败
            return false
        } else {
            // 间隔超过 30 秒，更新上一次打点时间戳为当前时间戳，打点成功
            lastTimestamp = timestamp
            return true
        }
    }

    // 定时器执行的方法
    @objc func tick() {
        // 在该方法中执行定时器需要执行的具体操作
    }
}
