import Foundation
import CoreGraphics
import AppKit

/// 空闲与系统电源/锁屏状态监听器
public final class IdleMonitor {
    public weak var engine: TimerEngine?
    
    private var pollTimer: Timer?
    private var isMonitoring = false
    
    // 空闲判定轮询周期（秒）
    public var pollInterval: TimeInterval = 15.0
    private var sleepStartDate: Date?
    
    public init(engine: TimerEngine? = nil) {
        self.engine = engine
    }
    
    deinit {
        stop()
    }
    
    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // 1. 启动定时轮询空闲时间
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkIdle()
        }
        
        // 2. 监听系统休眠、开盖唤醒与合盖通知
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(handleDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(handleScreensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        
        // 3. 监听锁屏与屏保通知（DistributedNotificationCenter）
        let distCenter = DistributedNotificationCenter.default()
        distCenter.addObserver(
            self,
            selector: #selector(handleScreenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        distCenter.addObserver(
            self,
            selector: #selector(handleScreenSaverStarted),
            name: NSNotification.Name("com.apple.screensaver.didstart"),
            object: nil
        )
    }
    
    public func stop() {
        isMonitoring = false
        pollTimer?.invalidate()
        pollTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    // MARK: - 空闲检测逻辑
    public func checkIdle() {
        guard let engine = engine, engine.mode != .standby else { return }
        
        let autoStandbyOnIdle = UserDefaults.standard.object(forKey: "BreakLoop.AutoStandbyOnIdle") as? Bool ?? true
        guard autoStandbyOnIdle else { return }
        
        // 键鼠最后事件空闲时间（秒）
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        
        // 休息阶段：离开工位属于健康行为，豁免 10 分钟常规键鼠检测；仅当超过休息上限时才判定超时
        if engine.mode == .resting {
            let restLimitMinutes = max(engine.currentBlock?.chimeEndMinutes ?? engine.preset.restMaxMinutes, engine.preset.restMaxMinutes)
            let restLimitSeconds = Double(restLimitMinutes * 60)
            if idleSeconds >= restLimitSeconds {
                let lastActivityDate = engine.nowProvider().addingTimeInterval(-idleSeconds)
                engine.enterStandby(reason: .idle, at: lastActivityDate)
            }
            return
        }
        
        let configuredMins = UserDefaults.standard.object(forKey: "BreakLoop.IdleTimeoutMinutes") as? Int
        let idleMinutes = configuredMins ?? engine.preset.idleMinutes
        let idleLimitSeconds = Double(idleMinutes * 60)
        
        if idleSeconds >= idleLimitSeconds {
            // 回溯至最后一次键鼠活动的时间
            let lastActivityDate = engine.nowProvider().addingTimeInterval(-idleSeconds)
            engine.enterStandby(reason: .idle, at: lastActivityDate)
        }
    }
    
    // MARK: - 系统事件回调
    @objc private func handleWillSleep() {
        guard let engine = engine, engine.mode != .standby else { return }
        if engine.mode == .resting {
            // 休息阶段：记录盒盖时间戳，唤醒时再按盒盖时长结算
            sleepStartDate = engine.nowProvider()
        } else {
            // 专注阶段：盒盖直接进待机
            engine.enterStandby(reason: .sleep)
        }
    }
    
    @objc private func handleDidWake() {
        guard let engine = engine, engine.mode == .resting, let sleepStart = sleepStartDate else {
            sleepStartDate = nil
            return
        }
        let now = engine.nowProvider()
        let sleepDuration = now.timeIntervalSince(sleepStart)
        sleepStartDate = nil
        
        let maxRestMins = max(engine.currentBlock?.chimeEndMinutes ?? engine.preset.restMaxMinutes, engine.preset.restMaxMinutes)
        let maxRestSeconds = Double(maxRestMins * 60)
        
        if sleepDuration > maxRestSeconds {
            // 盒盖时长远超休息阈值（如睡了几小时或已离开），以休息上限封顶结束并进入待机
            let cappedEndDate = sleepStart.addingTimeInterval(maxRestSeconds)
            engine.enterStandby(reason: .restTimeout, at: cappedEndDate)
        } else if let block = engine.currentBlock, block.timingMode == .countdown {
            // 倒计时短休：如果在盒盖离开期间倒计时已经走完，唤醒时直接静默切入待机（免去开盖弹窗打扰），就绪下一步专注
            let remaining = engine.currentSeconds
            if sleepDuration >= Double(remaining) {
                let actualEnd = sleepStart.addingTimeInterval(Double(remaining))
                engine.enterStandby(reason: .completed, at: actualEnd)
            }
        }
    }
    
    @objc private func handleScreensDidSleep() {
        guard let engine = engine, engine.mode != .standby else { return }
        // 休息阶段允许黑屏闭目养神，不打断休息
        if engine.mode == .resting { return }
        let autoStandbyOnScreenSaver = UserDefaults.standard.object(forKey: "BreakLoop.AutoStandbyOnScreenSaver") as? Bool ?? true
        if autoStandbyOnScreenSaver {
            engine.enterStandby(reason: .locked)
        }
    }
    
    @objc private func handleScreenLocked() {
        guard let engine = engine, engine.mode != .standby else { return }
        // 休息阶段锁屏不打断休息计时
        if engine.mode == .resting { return }
        let autoStandbyOnScreenSaver = UserDefaults.standard.object(forKey: "BreakLoop.AutoStandbyOnScreenSaver") as? Bool ?? true
        if autoStandbyOnScreenSaver {
            engine.enterStandby(reason: .locked)
        }
    }
    
    @objc private func handleScreenSaverStarted() {
        guard let engine = engine, engine.mode != .standby else { return }
        if engine.mode == .resting { return }
        let autoStandbyOnScreenSaver = UserDefaults.standard.object(forKey: "BreakLoop.AutoStandbyOnScreenSaver") as? Bool ?? true
        if autoStandbyOnScreenSaver {
            engine.enterStandby(reason: .locked)
        }
    }
}
