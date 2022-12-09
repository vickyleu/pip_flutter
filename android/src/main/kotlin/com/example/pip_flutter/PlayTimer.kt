package com.example.pip_flutter

import java.util.*

class PlayTimer {
    // 定时器对象
    var timer: Timer? = null

    // 定时器时间间隔
    var timeInterval: Long = 0

    // 上一次打点时间戳
    var lastTimestamp: Long = 0

    // 开始计时
    fun start(interval: Long) {
        // 设置定时器时间间隔
        timeInterval = interval
        // 开始执行定时器
        timer = Timer()
        timer?.schedule(object : TimerTask() {
            override fun run() {
                tick()
            }
        }, timeInterval, timeInterval)
    }

    // 暂停计时
    fun pause() {
        // 停止定时器
        timer?.cancel()
        timer = null
    }

    // 打点
    fun mark(): Boolean {
        // 获取当前时间戳
        val timestamp = System.currentTimeMillis()

        // 判断上一次打点时间戳与当前时间戳的间隔是否超过 30 秒
        if (timestamp - lastTimestamp < 30 * 1000) {
            // 间隔未超过 30 秒，打点失败
            return false
        } else {
            // 间隔超过 30 秒，更新上一次打点时间戳为当前时间戳，打点成功
            lastTimestamp = timestamp
            return true
        }
    }

    // 定时器执行的方法
    fun tick() {
        // 在该方法中执行定时器需要执行的具体操作
    }
}