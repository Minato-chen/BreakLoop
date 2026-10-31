import Foundation
import Combine

/// 计时器运行状态（严格极简三态）
public enum TimerMode: String, Codable, Equatable {
    case standby    // 待机中（软件不计算任何时长）
    case working    // 工作中（倒计时）
    case resting    // 休息中（自由正计时）
}

/// 提醒触发事件
public struct AlertTriggerEvent: Equatable {
    public let message: String
    public let style: AlertStyle
    public let soundName: String
    public let cycleCount: Int
    public let isLongRest: Bool
}

/// 计时器引擎（核心二元工作/休息逻辑 + 全局待机出口）
public final class TimerEngine: ObservableObject {
    @Published public private(set) var mode: TimerMode = .standby
    @Published public private(set) var currentSeconds: Int = 0   // 当前显示的秒数
    @Published public private(set) var targetSeconds: Int = 0    // 目标秒数
    @Published public private(set) var completedCycles: Int = 0  // 已完成轮次
    
    @Published public var preset: Preset {
        didSet {
            if mode == .standby {
                targetSeconds = preset.workMinutes * 60
                currentSeconds = targetSeconds
            }
        }
    }
    
    // 今日累计时间（秒）
    @Published public private(set) var todayWorkSeconds: TimeInterval = 0
    @Published public private(set) var todayRestSeconds: TimeInterval = 0
    
    private var sessionStartDate: Date?
    private var targetEndDate: Date?
    
    public let sessionStore: SessionStore
    public var nowProvider: () -> Date
    public var onAlertTriggered: ((AlertTriggerEvent) -> Void)?
    
    private var tickTimer: Timer?
    private var heartbeatCounter: Int = 0
    
    public init(
        preset: Preset? = nil,
        sessionStore: SessionStore = SessionStore(),
        nowProvider: @escaping () -> Date = { Date() }
    ) {
        let initialPreset = preset ?? Preset.defaultPresets[0]
        self.preset = initialPreset
        self.sessionStore = sessionStore
        self.nowProvider = nowProvider
        
        self.targetSeconds = initialPreset.workMinutes * 60
        self.currentSeconds = self.targetSeconds
        
        sessionStore.recoverUnfinishedSessionIfNeeded()
        refreshTodayStats()
    }
    
    deinit {
        stopTimers()
    }
    
    // MARK: - 核心二元状态流转
    
    /// 开始工作（全新一轮工作）
    public func startWork() {
        let now = nowProvider()
        if mode != .standby {
            closeCurrentSession(endedAt: now, reason: .completed)
        }
        
        mode = .working
        sessionStartDate = now
        targetSeconds = preset.workMinutes * 60
        currentSeconds = targetSeconds
        targetEndDate = now.addingTimeInterval(TimeInterval(targetSeconds))
        
        startTimer()
        recordHeartbeat()
        syncToWidget()
    }
    
    /// 进入休息（无论是工作归零自动进入、还是用户点击休息、或是提前结束工作）
    public func startRest() {
        let now = nowProvider()
        if mode == .working {
            closeCurrentSession(endedAt: now, reason: .completed)
        }
        
        mode = .resting
        sessionStartDate = now
        currentSeconds = 0
        targetSeconds = (preset.restTargetSeconds != nil) ? preset.restTargetSeconds! : (preset.restMinutes * 60)
        targetEndDate = nil
        
        startTimer()
        recordHeartbeat()
        syncToWidget()
    }
    
    /// 结束休息并开始下一轮工作
    public func startNextWorkCycle() {
        completedCycles += 1
        startWork()
    }
    
    /// 稍后提醒 5 分钟
    public func snooze(minutes: Int = 5) {
        let now = nowProvider()
        mode = .working
        targetSeconds = minutes * 60
        currentSeconds = targetSeconds
        targetEndDate = now.addingTimeInterval(TimeInterval(targetSeconds))
        startTimer()
        syncToWidget()
    }
    
    /// 统一待机出口（停止所有计算，进入软件不计时状态）
    public func enterStandby(reason: EndReason = .manual, at time: Date? = nil) {
        guard mode != .standby else { return }
        let endAt = time ?? nowProvider()
        
        closeCurrentSession(endedAt: endAt, reason: reason)
        stopTimers()
        sessionStore.clearHeartbeat()
        
        mode = .standby
        sessionStartDate = nil
        targetEndDate = nil
        
        targetSeconds = preset.workMinutes * 60
        currentSeconds = targetSeconds
        
        refreshTodayStats()
        syncToWidget()
    }
    
    // MARK: - Tick 推进
    public func tick() {
        guard mode != .standby else { return }
        let now = nowProvider()
        
        heartbeatCounter += 1
        if heartbeatCounter >= 15 {
            heartbeatCounter = 0
            recordHeartbeat()
        }
        
        switch mode {
        case .working:
            guard let targetEnd = targetEndDate else { return }
            let remaining = targetEnd.timeIntervalSince(now)
            if remaining <= 0 {
                currentSeconds = 0
                triggerAlert()
                // 倒计时结束直接进入休息
                startRest()
            } else {
                currentSeconds = max(0, Int(ceil(remaining)))
            }
            
        case .resting:
            guard let start = sessionStartDate else { return }
            let elapsed = now.timeIntervalSince(start)
            let maxAllowedSeconds = Double(preset.restMaxMinutes * 60)
            if elapsed >= maxAllowedSeconds {
                enterStandby(reason: .restTimeout, at: now)
                return
            }
            currentSeconds = Int(elapsed)
            
        case .standby:
            break
        }
    }
    
    private func triggerAlert() {
        let cycleNumber = completedCycles + 1
        var msg = preset.message
        for rule in preset.rotation {
            if rule.everyNthCycle > 0 && cycleNumber % rule.everyNthCycle == 0 {
                msg = rule.message
                break
            }
        }
        
        let event = AlertTriggerEvent(
            message: msg,
            style: preset.alertStyle,
            soundName: preset.soundName,
            cycleCount: cycleNumber,
            isLongRest: false
        )
        onAlertTriggered?(event)
    }
    
    private func closeCurrentSession(endedAt: Date, reason: EndReason) {
        guard let start = sessionStartDate else { return }
        let actualEnd = max(start, endedAt)
        let kind: SessionKind = (mode == .working) ? .work : .rest
        
        let session = Session(
            kind: kind,
            start: start,
            end: actualEnd,
            presetName: preset.name,
            endReason: reason
        )
        sessionStore.append(session)
        refreshTodayStats()
    }
    
    private func recordHeartbeat() {
        guard let start = sessionStartDate, mode != .standby else { return }
        let kind: SessionKind = (mode == .working) ? .work : .rest
        let ongoingSession = Session(
            kind: kind,
            start: start,
            end: nowProvider(),
            presetName: preset.name,
            endReason: .manual
        )
        sessionStore.recordHeartbeat(session: ongoingSession, at: nowProvider())
    }
    
    public func refreshTodayStats() {
        let calendar = Calendar.current
        let now = nowProvider()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now
        
        let list = sessionStore.sessions(in: startOfDay...endOfDay)
        var workSec: TimeInterval = 0
        var restSec: TimeInterval = 0
        
        for s in list {
            if s.kind == .work {
                workSec += s.duration
            } else {
                restSec += s.duration
            }
        }
        
        todayWorkSeconds = workSec
        todayRestSeconds = restSec
        syncToWidget()
    }
    
    public func syncToWidget() {
        let shared = WidgetSharedData(
            modeRaw: mode.rawValue,
            presetName: preset.name,
            targetEndDate: targetEndDate,
            restStartDate: sessionStartDate,
            todayWorkMinutes: Int(todayWorkSeconds / 60),
            todayRestMinutes: Int(todayRestSeconds / 60),
            completedCycles: completedCycles
        )
        WidgetDataManager.save(data: shared)
    }
    
    private func startTimer() {
        stopTimers()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }
    
    private func stopTimers() {
        tickTimer?.invalidate()
        tickTimer = nil
    }
}
