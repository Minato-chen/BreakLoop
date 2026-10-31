import Foundation
import Combine

/// 计时器运行状态（严格极简三态）
public enum TimerMode: String, Codable, Equatable {
    case standby    // 待机中（软件不计算任何时长）
    case working    // 工作中（倒计时）
    case resting    // 休息中（自由正计时或固定倒计时）
}

/// 提醒触发事件
public struct AlertTriggerEvent: Equatable {
    public let message: String
    public let style: AlertStyle
    public let soundName: String
    public let cycleCount: Int
    public let isLongRest: Bool
}

/// 计时器引擎（低功耗、低内存、极简模块流水线）
public final class TimerEngine: ObservableObject {
    @Published public private(set) var mode: TimerMode = .standby
    @Published public private(set) var currentSeconds: Int = 0       // 当前秒数
    @Published public private(set) var targetSeconds: Int = 0        // 目标秒数
    @Published public private(set) var completedCycles: Int = 0      // 已完成大循环轮次
    @Published public private(set) var currentBlockIndex: Int = 0    // 当前流水线步数 (0-based)
    @Published public private(set) var isLongRest: Bool = false      // 长休息标记
    
    // 专门供给菜单栏的高效低频分钟显示（仅在分钟变化时触发 UI 重绘，彻底消除 CPU 占用）
    @Published public private(set) var menuBarText: String = ""
    
    @Published public var preset: Preset {
        didSet {
            if currentBlockIndex >= preset.blocks.count {
                currentBlockIndex = 0
            }
            if mode == .standby {
                resetToCurrentBlock()
            }
            updateMenuBarText()
            syncToWidget()
        }
    }
    
    public var currentBlock: FlowBlock? {
        guard !preset.blocks.isEmpty else { return nil }
        let idx = min(max(0, currentBlockIndex), preset.blocks.count - 1)
        return preset.blocks[idx]
    }
    
    // 下一个模块预测（让用户一眼掌握下一步）
    public var nextBlock: FlowBlock? {
        guard !preset.blocks.isEmpty else { return nil }
        let nextIdx = (currentBlockIndex + 1) % preset.blocks.count
        return preset.blocks[nextIdx]
    }
    
    @Published public private(set) var todayWorkSeconds: TimeInterval = 0
    @Published public private(set) var todayRestSeconds: TimeInterval = 0
    
    private var sessionStartDate: Date?
    private var targetEndDate: Date?
    private var hasTriggeredSoftTarget: Bool = false
    private var lastRecordedMinute: Int = -1
    
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
        
        let initialBlock = initialPreset.blocks.first
        let initialDuration = (initialBlock?.durationMinutes ?? 20) * 60
        self.targetSeconds = initialDuration
        self.currentSeconds = initialDuration
        
        sessionStore.recoverUnfinishedSessionIfNeeded()
        refreshTodayStats()
        updateMenuBarText()
    }
    
    deinit {
        stopTimers()
    }
    
    // MARK: - 状态流转
    
    public func startCurrentBlock() {
        guard let block = currentBlock else { return }
        let now = nowProvider()
        
        if mode != .standby {
            closeCurrentSession(endedAt: now, reason: .completed)
        }
        
        sessionStartDate = now
        hasTriggeredSoftTarget = false
        lastRecordedMinute = -1
        
        switch block.type {
        case .work:
            mode = .working
            isLongRest = false
            targetSeconds = max(1, block.durationMinutes) * 60
            currentSeconds = targetSeconds
            targetEndDate = now.addingTimeInterval(TimeInterval(targetSeconds))
            
        case .rest:
            mode = .resting
            isLongRest = (block.durationMinutes >= 15)
            if block.timingMode == .countdown {
                targetSeconds = max(1, block.durationMinutes) * 60
                currentSeconds = targetSeconds
                targetEndDate = now.addingTimeInterval(TimeInterval(targetSeconds))
            } else {
                targetSeconds = block.targetSeconds ?? (block.durationMinutes * 60)
                currentSeconds = 0
                targetEndDate = nil
            }
        }
        
        startTimer()
        recordInitialSession()
        updateMenuBarText()
        syncToWidget()
    }
    
    public func advanceToNextBlock() {
        guard !preset.blocks.isEmpty else {
            enterStandby()
            return
        }
        
        let nextIndex = currentBlockIndex + 1
        if nextIndex >= preset.blocks.count {
            completedCycles += 1
            currentBlockIndex = 0
        } else {
            currentBlockIndex = nextIndex
        }
        
        startCurrentBlock()
    }
    
    public func jumpToBlock(index: Int) {
        guard index >= 0 && index < preset.blocks.count else { return }
        currentBlockIndex = index
        startCurrentBlock()
    }
    
    public func enterStandby(reason: EndReason = .manual, at time: Date? = nil) {
        guard mode != .standby else { return }
        let endAt = time ?? nowProvider()
        
        closeCurrentSession(endedAt: endAt, reason: reason)
        stopTimers()
        sessionStore.clearHeartbeat()
        
        mode = .standby
        sessionStartDate = nil
        targetEndDate = nil
        isLongRest = false
        lastRecordedMinute = -1
        
        resetToCurrentBlock()
        refreshTodayStats()
        updateMenuBarText()
        syncToWidget()
    }
    
    public func startWork() {
        if let block = currentBlock, block.type == .work {
            startCurrentBlock()
        } else if let workIdx = preset.blocks.firstIndex(where: { $0.type == .work }) {
            currentBlockIndex = workIdx
            startCurrentBlock()
        } else {
            startCurrentBlock()
        }
    }
    
    public func startRest() {
        if let nextRestIdx = preset.blocks.indices.first(where: { $0 > currentBlockIndex && preset.blocks[$0].type == .rest }) {
            currentBlockIndex = nextRestIdx
            startCurrentBlock()
        } else if let firstRestIdx = preset.blocks.firstIndex(where: { $0.type == .rest }) {
            currentBlockIndex = firstRestIdx
            startCurrentBlock()
        } else {
            advanceToNextBlock()
        }
    }
    
    public func startNextWorkCycle() {
        advanceToNextBlock()
    }
    
    public func snooze(minutes: Int = 5) {
        let now = nowProvider()
        mode = .working
        targetSeconds = minutes * 60
        currentSeconds = targetSeconds
        targetEndDate = now.addingTimeInterval(TimeInterval(targetSeconds))
        startTimer()
        updateMenuBarText()
        syncToWidget()
    }
    
    private func resetToCurrentBlock() {
        if let block = currentBlock {
            let dur = (block.durationMinutes > 0 ? block.durationMinutes : 20) * 60
            targetSeconds = dur
            currentSeconds = dur
        } else {
            targetSeconds = 20 * 60
            currentSeconds = targetSeconds
        }
    }
    
    // MARK: - 极简低频菜单栏文本计算
    private func updateMenuBarText() {
        let total = max(1, preset.blocks.count)
        let step = currentBlockIndex + 1
        
        switch mode {
        case .standby:
            menuBarText = "\(total)步"
        case .working:
            let mins = max(1, Int(ceil(Double(max(0, currentSeconds)) / 60.0)))
            menuBarText = "\(step)/\(total) \(mins)m"
        case .resting:
            if let block = currentBlock, block.timingMode == .countdown {
                let mins = max(1, Int(ceil(Double(max(0, currentSeconds)) / 60.0)))
                menuBarText = "\(step)/\(total) \(mins)m"
            } else {
                let mins = max(1, currentSeconds / 60)
                menuBarText = "\(step)/\(total) \(mins)m"
            }
        }
    }
    
    // MARK: - Tick 推进 (高性能轻量化)
    public func tick() {
        guard mode != .standby, let block = currentBlock else { return }
        let now = nowProvider()
        
        // 心跳维护：每 30 秒仅轻量更新时间戳，绝不做昂贵 JSON 编码
        heartbeatCounter += 1
        if heartbeatCounter >= 30 {
            heartbeatCounter = 0
            sessionStore.updateHeartbeatTimestamp(at: now)
        }
        
        switch block.type {
        case .work:
            guard let targetEnd = targetEndDate else { return }
            let remaining = targetEnd.timeIntervalSince(now)
            if remaining <= 0 {
                currentSeconds = 0
                triggerAlert(for: block)
                advanceToNextBlock()
            } else {
                currentSeconds = max(0, Int(ceil(remaining)))
            }
            
        case .rest:
            if block.timingMode == .countdown {
                guard let targetEnd = targetEndDate else { return }
                let remaining = targetEnd.timeIntervalSince(now)
                if remaining <= 0 {
                    currentSeconds = 0
                    triggerAlert(for: block)
                    if block.autoAdvance {
                        advanceToNextBlock()
                    } else {
                        let maxAllowedSeconds = Double(preset.restMaxMinutes * 60)
                        if let start = sessionStartDate, now.timeIntervalSince(start) >= maxAllowedSeconds {
                            enterStandby(reason: .restTimeout, at: now)
                        }
                    }
                } else {
                    currentSeconds = max(0, Int(ceil(remaining)))
                }
            } else {
                guard let start = sessionStartDate else { return }
                let elapsed = now.timeIntervalSince(start)
                
                if let target = block.targetSeconds, target > 0, Int(elapsed) >= target, !hasTriggeredSoftTarget {
                    hasTriggeredSoftTarget = true
                    triggerAlert(for: block)
                }
                
                let maxAllowedSeconds = Double(preset.restMaxMinutes * 60)
                if elapsed >= maxAllowedSeconds {
                    enterStandby(reason: .restTimeout, at: now)
                    return
                }
                
                currentSeconds = Int(elapsed)
            }
        }
        
        // 分钟变更判定：仅在整分钟变化时才更新菜单栏字符串并写小组件（杜绝每秒 I/O 与 Diff）
        let currentMin = currentSeconds / 60
        if currentMin != lastRecordedMinute {
            lastRecordedMinute = currentMin
            updateMenuBarText()
            syncToWidget()
        }
    }
    
    private func triggerAlert(for block: FlowBlock) {
        let cycleNumber = completedCycles + 1
        var msg = block.message.isEmpty ? (block.type == .work ? "专注时间到" : "休息时间到") : block.message
        for rule in preset.rotation {
            if rule.everyNthCycle > 0 && cycleNumber % rule.everyNthCycle == 0 {
                msg = rule.message
                break
            }
        }
        let event = AlertTriggerEvent(
            message: msg,
            style: preset.alertStyle,
            soundName: block.soundName,
            cycleCount: cycleNumber,
            isLongRest: isLongRest
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
            presetName: "\(preset.name) · \(currentBlock?.name ?? "")",
            endReason: reason
        )
        sessionStore.append(session)
        refreshTodayStats()
    }
    
    private func recordInitialSession() {
        guard let start = sessionStartDate, mode != .standby else { return }
        let kind: SessionKind = (mode == .working) ? .work : .rest
        let ongoingSession = Session(
            kind: kind,
            start: start,
            end: nowProvider(),
            presetName: "\(preset.name) · \(currentBlock?.name ?? "")",
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
