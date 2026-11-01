import Foundation
import Combine
import CoreGraphics

/// 计时器运行状态（严格极简三态）
public enum TimerMode: String, Codable, Equatable {
    case standby    // 待机中（软件不计算任何时长）
    case working    // 工作中（倒计时）
    case resting    // 休息中（自由正计时或固定倒计时）
}

/// 提醒触发事件
public struct AlertTriggerEvent: Equatable {
    public enum ActionType: String, Codable, Equatable {
        case workCompleted   // 专注结束，提示去休息
        case restCompleted   // 倒计时休息结束，提示准备专注
    }
    
    public let actionType: ActionType
    public let title: String
    public let message: String
    public let style: AlertStyle
    public let soundName: String
    public let cycleCount: Int
    public let isLongRest: Bool
    public let snoozeMinutes: Int
    public let blockIndex: Int
    public let autoAdvanced: Bool
    
    public init(
        actionType: ActionType = .workCompleted,
        title: String = "该喝杯咖啡，休息一下了",
        message: String,
        style: AlertStyle = .both,
        soundName: String = "Glass",
        cycleCount: Int = 1,
        isLongRest: Bool = false,
        snoozeMinutes: Int = 5,
        blockIndex: Int = 0,
        autoAdvanced: Bool = false
    ) {
        self.actionType = actionType
        self.title = title
        self.message = message
        self.style = style
        self.soundName = soundName
        self.cycleCount = cycleCount
        self.isLongRest = isLongRest
        self.snoozeMinutes = snoozeMinutes
        self.blockIndex = blockIndex
        self.autoAdvanced = autoAdvanced
    }
}

/// 计时器引擎（低功耗、低内存、极简模块流水线）
public final class TimerEngine: ObservableObject {
    @Published public private(set) var mode: TimerMode = .standby
    @Published public private(set) var currentSeconds: Int = 0       // 当前秒数
    @Published public private(set) var targetSeconds: Int = 0        // 目标秒数
    @Published public private(set) var completedCycles: Int = 0      // 已完成大循环轮次
    @Published public private(set) var currentBlockIndex: Int = 0    // 当前流水线步数 (0-based)
    @Published public private(set) var isLongRest: Bool = false      // 长休息标记
    @Published public private(set) var isPaused: Bool = false        // 暂停状态标记
    
    public private(set) var pauseStartTime: Date?
    public private(set) var remainingSecondsOnPause: Int?
    public private(set) var lastStandbyReason: EndReason?
    public private(set) var savedRemainingSeconds: Int?
    
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
    private var hasTriggeredCompletionAlert: Bool = false
    private var hasTriggeredCutoffAlert: Bool = false
    private var alertTriggeredDate: Date?
    private var lastRecordedMinute: Int = -1
    private var lastChimedMinute: Int = -1
    
    public let sessionStore: SessionStore
    public var nowProvider: () -> Date
    public var idleSecondsProvider: () -> Double = {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
    public var onAlertTriggered: ((AlertTriggerEvent) -> Void)?
    
    private var tickTimer: Timer?
    private var heartbeatCounter: Int = 0
    private let userDefaults: UserDefaults
    
    public init(
        preset: Preset? = nil,
        sessionStore: SessionStore = SessionStore(),
        userDefaults: UserDefaults = .standard,
        nowProvider: @escaping () -> Date = { Date() },
        idleSecondsProvider: (() -> Double)? = nil
    ) {
        let initialPreset = preset ?? Preset.defaultPresets[0]
        self.preset = initialPreset
        self.sessionStore = sessionStore
        self.userDefaults = userDefaults
        self.nowProvider = nowProvider
        if let isp = idleSecondsProvider {
            self.idleSecondsProvider = isp
        }
        
        let initialBlock = initialPreset.blocks.first
        let initialDuration = (initialBlock?.durationMinutes ?? 20) * 60
        self.targetSeconds = initialDuration
        self.currentSeconds = initialDuration
        
        loadTodayCompletedCycles()
        sessionStore.recoverUnfinishedSessionIfNeeded()
        refreshTodayStats()
        updateMenuBarText()
    }
    
    deinit {
        stopTimers()
    }
    
    // MARK: - 暂停与继续控制
    public func togglePause() {
        if isPaused {
            resume()
        } else {
            pause()
        }
    }
    
    public func pause() {
        guard mode != .standby, !isPaused else { return }
        isPaused = true
        let now = nowProvider()
        pauseStartTime = now
        remainingSecondsOnPause = currentSeconds
        updateMenuBarText()
        syncToWidget()
    }
    
    public func resume() {
        guard isPaused else { return }
        let now = nowProvider()
        let pauseDuration = now.timeIntervalSince(pauseStartTime ?? now)
        if let start = sessionStartDate {
            sessionStartDate = start.addingTimeInterval(pauseDuration)
        }
        if let remaining = remainingSecondsOnPause {
            currentSeconds = remaining
            if mode == .working || (currentBlock?.timingMode == .countdown) {
                targetEndDate = now.addingTimeInterval(TimeInterval(remaining))
            }
        }
        isPaused = false
        pauseStartTime = nil
        remainingSecondsOnPause = nil
        updateMenuBarText()
        syncToWidget()
    }
    
    public func resetCycleToBeginning() {
        currentBlockIndex = 0
        savedRemainingSeconds = nil
        resetToCurrentBlock()
        updateMenuBarText()
        syncToWidget()
    }
    
    // MARK: - 状态流转
    
    public func startCurrentBlock() {
        guard let block = currentBlock else { return }
        let now = nowProvider()
        
        let wasInStandby = (mode == .standby)
        var shouldResumeSavedSeconds = false
        if wasInStandby {
            if let saved = savedRemainingSeconds, saved > 0 {
                shouldResumeSavedSeconds = true
            }
        }
        
        if mode != .standby {
            closeCurrentSession(endedAt: now, reason: .completed)
        }
        
        sessionStartDate = now
        hasTriggeredSoftTarget = false
        hasTriggeredCompletionAlert = false
        hasTriggeredCutoffAlert = false
        alertTriggeredDate = nil
        lastRecordedMinute = -1
        lastChimedMinute = -1
        isPaused = false
        pauseStartTime = nil
        remainingSecondsOnPause = nil
        
        switch block.type {
        case .work:
            mode = .working
            isLongRest = false
            targetSeconds = max(1, block.durationMinutes) * 60
            if shouldResumeSavedSeconds, let saved = savedRemainingSeconds {
                currentSeconds = saved
                targetEndDate = now.addingTimeInterval(TimeInterval(saved))
            } else {
                currentSeconds = targetSeconds
                targetEndDate = now.addingTimeInterval(TimeInterval(targetSeconds))
            }
            
        case .rest:
            mode = .resting
            isLongRest = (block.durationMinutes >= 15)
            if block.timingMode == .countdown {
                targetSeconds = block.totalCountdownSeconds
                if shouldResumeSavedSeconds, let saved = savedRemainingSeconds {
                    currentSeconds = saved
                    targetEndDate = now.addingTimeInterval(TimeInterval(saved))
                } else {
                    currentSeconds = targetSeconds
                    targetEndDate = now.addingTimeInterval(TimeInterval(targetSeconds))
                }
            } else {
                targetSeconds = 0
                currentSeconds = shouldResumeSavedSeconds ? (savedRemainingSeconds ?? 0) : 0
                targetEndDate = nil
            }
        }
        savedRemainingSeconds = nil
        
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
            incrementCompletedCycles()
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
        let previousMode = mode
        let interruptedBlock = currentBlock
        
        lastStandbyReason = reason
        savedRemainingSeconds = isPaused ? (remainingSecondsOnPause ?? currentSeconds) : currentSeconds
        isPaused = false
        pauseStartTime = nil
        remainingSecondsOnPause = nil
        alertTriggeredDate = nil
        hasTriggeredCompletionAlert = false
        hasTriggeredCutoffAlert = false
        AlertManager.shared.closePanel()
        
        closeCurrentSession(endedAt: endAt, reason: reason)
        stopTimers()
        sessionStore.clearHeartbeat()
        
        mode = .standby
        sessionStartDate = nil
        targetEndDate = nil
        isLongRest = false
        lastRecordedMinute = -1
        
        // 区分专注被打断 vs 休息被打断的不同恢复策略
        let recovery: InterruptRecovery
        if previousMode == .resting || interruptedBlock?.type == .rest {
            recovery = preset.restInterruptRecovery
        } else {
            recovery = preset.workInterruptRecovery
        }
        
        switch recovery {
        case .advanceNext:
            let nextIndex = currentBlockIndex + 1
            if nextIndex >= preset.blocks.count {
                incrementCompletedCycles()
                currentBlockIndex = 0
            } else {
                currentBlockIndex = nextIndex
            }
            savedRemainingSeconds = nil
        case .resetCycle:
            currentBlockIndex = 0
            savedRemainingSeconds = nil
        case .resetCurrent:
            savedRemainingSeconds = nil
        case .resume:
            break
        }
        
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
    
    public func snooze(minutes: Int = 5, rewindingTo blockIndex: Int? = nil) {
        if let idx = blockIndex, idx >= 0 && idx < preset.blocks.count {
            currentBlockIndex = idx
        }
        let now = nowProvider()
        // 若此前处于工作态且未结算（如未开启自动推进模式），先保存前一段专注会话
        if mode == .working, sessionStartDate != nil {
            closeCurrentSession(endedAt: now, reason: .completed)
        }
        sessionStartDate = now
        mode = .working
        targetSeconds = minutes * 60
        currentSeconds = targetSeconds
        targetEndDate = now.addingTimeInterval(TimeInterval(targetSeconds))
        hasTriggeredCompletionAlert = false
        hasTriggeredCutoffAlert = false
        alertTriggeredDate = nil
        startTimer()
        updateMenuBarText()
        syncToWidget()
    }
    
    private func resetToCurrentBlock() {
        if let block = currentBlock {
            if block.timingMode == .stopwatch {
                targetSeconds = 0
                currentSeconds = 0
            } else {
                let dur = block.totalCountdownSeconds
                targetSeconds = dur
                currentSeconds = dur
            }
        } else {
            targetSeconds = 20 * 60
            currentSeconds = targetSeconds
        }
    }
    
    // MARK: - 极简低频菜单栏文本计算
    public func updateMenuBarText() {
        let total = max(1, preset.blocks.count)
        let step = currentBlockIndex + 1
        
        // 偏好设置：默认隐藏步数、保留方向符号 (< 与 >)
        let showStep = userDefaults.object(forKey: "BreakLoop.MenuBarShowStep") as? Bool ?? false
        let showSymbol = userDefaults.object(forKey: "BreakLoop.MenuBarShowSymbol") as? Bool ?? true
        let symbolStyle = userDefaults.string(forKey: "BreakLoop.MenuBarSymbolStyle") ?? "chevron"
        
        let countdownSym = showSymbol ? "< " : ""
        let countupSym = showSymbol ? (symbolStyle == "plus" ? "+ " : "> ") : ""
        let stepPrefix = showStep ? "\(step)/\(total) " : ""
        
        if isPaused {
            menuBarText = showStep ? "\(step)/\(total) 暂停中" : "暂停中"
            return
        }
        
        switch mode {
        case .standby:
            menuBarText = showStep ? "\(total)步" : "待命"
        case .working:
            let mins = max(1, Int(ceil(Double(max(0, currentSeconds)) / 60.0)))
            menuBarText = "\(stepPrefix)\(countdownSym)\(mins)m"
        case .resting:
            if let block = currentBlock, block.timingMode == .countdown {
                if currentSeconds < 60 {
                    menuBarText = "\(stepPrefix)\(countdownSym)\(currentSeconds)s"
                } else {
                    let mins = max(1, Int(ceil(Double(max(0, currentSeconds)) / 60.0)))
                    menuBarText = "\(stepPrefix)\(countdownSym)\(mins)m"
                }
            } else {
                let mins = max(0, currentSeconds / 60)
                menuBarText = "\(stepPrefix)\(countupSym)\(mins)m"
            }
        }
    }
    
    // MARK: - Tick 推进 (高性能轻量化)
    public func tick() {
        guard mode != .standby, let block = currentBlock else { return }
        let now = nowProvider()
        
        // 暂停状态防遗忘检查（超时自动转入待机并回溯）
        if isPaused {
            let timeoutMins = userDefaults.object(forKey: "BreakLoop.PauseTimeoutMinutes") as? Int ?? 5
            if timeoutMins > 0, let pStart = pauseStartTime {
                let elapsed = now.timeIntervalSince(pStart)
                if elapsed >= Double(timeoutMins * 60) {
                    enterStandby(reason: .idle, at: pStart)
                }
            }
            return
        }
        
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
                if !hasTriggeredCompletionAlert {
                    hasTriggeredCompletionAlert = true
                    triggerAlert(for: block, actionType: .workCompleted)
                    alertTriggeredDate = now
                    if block.autoAdvance {
                        advanceToNextBlock()
                        return
                    }
                }
                
                // 未开启自动推进时：若弹窗弹出超过 3 分钟未操作
                if let alertDate = alertTriggeredDate, now.timeIntervalSince(alertDate) >= 180 {
                    alertTriggeredDate = nil
                    AlertManager.shared.closePanel()
                    // 仅当用户离开电脑（键鼠空闲 >= 60秒）时转入待机，并精准回溯结账时间至归零点；若正在电脑前打字赶工则不强行打断
                    if idleSecondsProvider() >= 60 {
                        enterStandby(reason: .idle, at: alertDate)
                        return
                    }
                }
            } else {
                currentSeconds = max(0, Int(ceil(remaining)))
            }
            
        case .rest:
            if block.timingMode == .countdown {
                guard let targetEnd = targetEndDate else { return }
                let remaining = targetEnd.timeIntervalSince(now)
                if remaining <= 0 {
                    currentSeconds = 0
                    if !hasTriggeredCompletionAlert {
                        hasTriggeredCompletionAlert = true
                        triggerAlert(for: block, actionType: .restCompleted)
                        alertTriggeredDate = now
                        if block.autoAdvance {
                            advanceToNextBlock()
                            return
                        }
                    }
                    
                    // 倒计时休息结束：若弹窗弹出超过 3 分钟无人点击，自动转入待机，时间精准回溯至归零点
                    if let alertDate = alertTriggeredDate, now.timeIntervalSince(alertDate) >= 180 {
                        alertTriggeredDate = nil
                        AlertManager.shared.closePanel()
                        enterStandby(reason: .restTimeout, at: alertDate)
                        return
                    }
                    
                    let maxAllowedSeconds = Double(preset.restMaxMinutes * 60)
                    if let start = sessionStartDate, now.timeIntervalSince(start) >= maxAllowedSeconds {
                        AlertManager.shared.closePanel()
                        enterStandby(reason: .restTimeout, at: now)
                        return
                    }
                } else {
                    currentSeconds = max(0, Int(ceil(remaining)))
                }
            } else {
                guard let start = sessionStartDate else { return }
                let elapsed = now.timeIntervalSince(start)
                let elapsedMinutes = Int(elapsed) / 60
                
                // 阶段递增轻报时：纯声音、绝不弹窗、计时不暂停
                if block.enableIncrementalChimes {
                    if elapsedMinutes >= block.chimeStartMinutes && elapsedMinutes <= block.chimeEndMinutes {
                        if elapsedMinutes != lastChimedMinute && (elapsedMinutes == block.chimeStartMinutes || elapsedMinutes % 10 == 0) {
                            lastChimedMinute = elapsedMinutes
                            let chimes = max(1, elapsedMinutes / 10)
                            SoundManager.shared.playChimes(soundName: block.soundName, count: chimes)
                        }
                    }
                    
                    // 到达截止阈值 (chimeEndMinutes)
                    if elapsedMinutes >= block.chimeEndMinutes {
                        if !hasTriggeredCutoffAlert {
                            hasTriggeredCutoffAlert = true
                            if block.chimeCutoffAction == .alertAndStandby {
                                triggerAlert(for: block, actionType: .restCompleted)
                                alertTriggeredDate = now
                            }
                        }
                    }
                }
                
                // 自由休息截止弹窗超时未操作（3 分钟无响应） -> 自动进入待机，时间精准回溯至截止点
                if let alertDate = alertTriggeredDate, now.timeIntervalSince(alertDate) >= 180 {
                    alertTriggeredDate = nil
                    AlertManager.shared.closePanel()
                    enterStandby(reason: .restTimeout, at: alertDate)
                    return
                }
                
                let maxAllowedSeconds = Double(preset.restMaxMinutes * 60)
                if elapsed >= maxAllowedSeconds {
                    AlertManager.shared.closePanel()
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
    
    private func triggerAlert(for block: FlowBlock, actionType: AlertTriggerEvent.ActionType) {
        let cycleNumber = completedCycles + 1
        let title = (actionType == .workCompleted) ? "该喝杯咖啡，休息一下了" : "休息结束，精力满满"
        var msg = block.message
        
        if actionType == .workCompleted {
            for rule in preset.rotation {
                if rule.everyNthCycle > 0 && cycleNumber % rule.everyNthCycle == 0 {
                    msg = rule.message
                    break
                }
            }
            if msg.isEmpty {
                msg = SoundManager.shared.defaultRestMessage.isEmpty ? "离开工位，走动喝水" : SoundManager.shared.defaultRestMessage
            }
        } else {
            if msg.isEmpty {
                msg = SoundManager.shared.defaultWorkMessage.isEmpty ? "准备开启新一轮专注" : SoundManager.shared.defaultWorkMessage
            }
        }
        
        let event = AlertTriggerEvent(
            actionType: actionType,
            title: title,
            message: msg,
            style: preset.alertStyle,
            soundName: block.soundName,
            cycleCount: cycleNumber,
            isLongRest: isLongRest,
            snoozeMinutes: block.snoozeMinutes,
            blockIndex: currentBlockIndex,
            autoAdvanced: block.autoAdvance
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
        loadTodayCompletedCycles()
    }
    
    // MARK: - 今日循环轮次持久化管理（跨预设累加，切换不归零）
    private var todayDateKey: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: nowProvider())
    }
    
    private var cyclesStorageKey: String {
        "BreakLoop.CompletedCycles.\(todayDateKey)"
    }
    
    public func loadTodayCompletedCycles() {
        completedCycles = userDefaults.integer(forKey: cyclesStorageKey)
    }
    
    public func incrementCompletedCycles() {
        completedCycles += 1
        userDefaults.set(completedCycles, forKey: cyclesStorageKey)
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
