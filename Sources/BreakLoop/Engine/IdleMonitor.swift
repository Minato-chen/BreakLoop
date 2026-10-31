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
        
        // 2. 监听系统休眠与合盖通知
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
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
        engine?.enterStandby(reason: .sleep)
    }
    
    @objc private func handleScreensDidSleep() {
        let autoStandbyOnScreenSaver = UserDefaults.standard.object(forKey: "BreakLoop.AutoStandbyOnScreenSaver") as? Bool ?? true
        if autoStandbyOnScreenSaver {
            engine?.enterStandby(reason: .locked)
        }
    }
    
    @objc private func handleScreenLocked() {
        let autoStandbyOnScreenSaver = UserDefaults.standard.object(forKey: "BreakLoop.AutoStandbyOnScreenSaver") as? Bool ?? true
        if autoStandbyOnScreenSaver {
            engine?.enterStandby(reason: .locked)
        }
    }
    
    @objc private func handleScreenSaverStarted() {
        let autoStandbyOnScreenSaver = UserDefaults.standard.object(forKey: "BreakLoop.AutoStandbyOnScreenSaver") as? Bool ?? true
        if autoStandbyOnScreenSaver {
            engine?.enterStandby(reason: .locked)
        }
    }
}
