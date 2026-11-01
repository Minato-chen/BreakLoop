import Foundation

/// 模块类型：专注 或 休息
public enum FlowBlockType: String, Codable, CaseIterable {
    case work = "work"
    case rest = "rest"
    
    public var displayName: String {
        switch self {
        case .work: return "专注"
        case .rest: return "休息"
        }
    }
}

/// 模块计时方式
public enum BlockTimingMode: String, Codable, CaseIterable {
    case countdown = "countdown" // 固定倒计时
    case stopwatch = "stopwatch" // 自己决定（正计时，自由休息）
    
    public var displayName: String {
        switch self {
        case .countdown: return "固定倒计时"
        case .stopwatch: return "自己决定 (正计时)"
        }
    }
}

/// 提醒方式
public enum AlertStyle: String, Codable, CaseIterable {
    case both    // 弹窗与声音
    case sound   // 仅声音
    case popup   // 仅弹窗
    case none    // 不提醒（完全静默）
    
    public var displayName: String {
        switch self {
        case .both: return "弹窗与声音"
        case .sound: return "仅声音"
        case .popup: return "仅弹窗"
        case .none: return "不提醒（完全静默）"
        }
    }
}

/// 打断恢复策略（支持针对专注与休息自定义不同恢复行为）
public enum InterruptRecovery: String, Codable, CaseIterable {
    case resetCurrent = "resetCurrent"   // 从本步满额重新开始
    case resume = "resume"               // 断点续传（继续剩余时间）
    case advanceNext = "advanceNext"     // 推进至下一步（开始新阶段）
    case resetCycle = "resetCycle"       // 重置整轮（回第 1 步）
    
    public var displayName: String {
        switch self {
        case .resetCurrent: return "重置本步"
        case .resume: return "断点续传"
        case .advanceNext: return "推进至下一步"
        case .resetCycle: return "重置整轮"
        }
    }
    
    public func displayName(for type: FlowBlockType) -> String {
        return displayName
    }
}

/// 休息计时方式（保留兼容）
public enum RestTimingMode: String, Codable, CaseIterable {
    case stopwatch  // 正计时
    case countdown  // 倒计时
}

/// 工作流模式（保留兼容）
public enum FlowMode: String, Codable, CaseIterable {
    case continuousLoop    // 健康循环
    case pomodoro          // 番茄钟
    case intervalTimer     // 固定间隔
    case custom            // 自定义模块循环
}

/// 休息轮换规则（保留兼容）
public struct RotationRule: Codable, Identifiable, Equatable {
    public var id: UUID
    public var everyNthCycle: Int
    public var message: String
    
    public init(id: UUID = UUID(), everyNthCycle: Int, message: String) {
        self.id = id
        self.everyNthCycle = everyNthCycle
        self.message = message
    }
}

/// 自由休息到达截止阈值时的处理行为
public enum CutoffAction: String, Codable, CaseIterable {
    case alertAndStandby = "alert"      // 弹窗提醒（无人响应自动待机）
    case silentAndStandby = "silent"    // 仅彻底静默（零弹窗，超时自动待机）
    
    public var displayName: String {
        switch self {
        case .alertAndStandby: return "弹窗提醒（无人响应自动待机）"
        case .silentAndStandby: return "仅彻底静默（零弹窗，超时自动待机）"
        }
    }
}

/// 快捷指令风格的独立工作/休息模块
public struct FlowBlock: Codable, Identifiable, Equatable {
    public var id: UUID
    public var type: FlowBlockType
    public var name: String
    public var durationMinutes: Int        // 倒计时时长（分），或正计时的预计/参考分钟
    public var countdownSeconds: Int? = nil // 精确倒计时秒数（若设置如20s，则以此为准）
    public var timingMode: BlockTimingMode // 倒计时 / 正计时
    public var targetSeconds: Int? = nil   // 兼容历史字段
    public var soundName: String = "Glass" // 结束提示音
    public var message: String = ""        // 提示文案，如 "看远方 20 秒", "闭目养神"
    public var autoAdvance: Bool = true    // 结束后是否自动推进到下一块
    public var snoozeMinutes: Int = 5      // 稍后提醒延时时长（默认 5 分钟）
    
    // 正计时专属：阶段递增轻报时配置（默认关闭，不暂停，零弹窗）
    public var enableIncrementalChimes: Bool = false // 开启阶段递增报时
    public var chimeStartMinutes: Int = 20           // 起始报时阈值（如 20 分钟，响 2 下）
    public var chimeEndMinutes: Int = 40             // 截止报时阈值（如 40 分钟为最后一次，之后彻底静默）
    public var chimeCutoffAction: CutoffAction = .alertAndStandby // 到达截止阈值时的行为（默认弹窗提醒，超时待机）
    
    /// 获取当前模块实际的完整倒计时总秒数
    public var totalCountdownSeconds: Int {
        if let sec = countdownSeconds, sec > 0 {
            return sec
        }
        return max(1, durationMinutes) * 60
    }
    
    public init(
        id: UUID = UUID(),
        type: FlowBlockType,
        name: String,
        durationMinutes: Int = 20,
        countdownSeconds: Int? = nil,
        timingMode: BlockTimingMode = .countdown,
        targetSeconds: Int? = nil,
        soundName: String = "Glass",
        message: String = "",
        autoAdvance: Bool = true,
        snoozeMinutes: Int = 5,
        enableIncrementalChimes: Bool = false,
        chimeStartMinutes: Int = 20,
        chimeEndMinutes: Int = 40,
        chimeCutoffAction: CutoffAction = .alertAndStandby
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.durationMinutes = durationMinutes
        self.countdownSeconds = countdownSeconds
        // 工作模块始终强制为倒计时；仅休息模块可自由选择倒计时或正计时
        self.timingMode = (type == .work) ? .countdown : timingMode
        self.targetSeconds = targetSeconds
        self.soundName = soundName
        self.message = message
        self.autoAdvance = autoAdvance
        self.snoozeMinutes = snoozeMinutes
        self.enableIncrementalChimes = enableIncrementalChimes
        self.chimeStartMinutes = chimeStartMinutes
        self.chimeEndMinutes = chimeEndMinutes
        self.chimeCutoffAction = chimeCutoffAction
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, name, durationMinutes, countdownSeconds, timingMode, targetSeconds
        case soundName, message, autoAdvance, snoozeMinutes
        case enableIncrementalChimes, chimeStartMinutes, chimeEndMinutes, chimeCutoffAction
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.type = try container.decode(FlowBlockType.self, forKey: .type)
        self.name = try container.decode(String.self, forKey: .name)
        self.durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        self.countdownSeconds = try container.decodeIfPresent(Int.self, forKey: .countdownSeconds)
        let rawTimingMode = try container.decode(BlockTimingMode.self, forKey: .timingMode)
        self.timingMode = (self.type == .work) ? .countdown : rawTimingMode
        self.targetSeconds = try container.decodeIfPresent(Int.self, forKey: .targetSeconds)
        self.soundName = try container.decodeIfPresent(String.self, forKey: .soundName) ?? "Glass"
        self.message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        self.autoAdvance = try container.decodeIfPresent(Bool.self, forKey: .autoAdvance) ?? true
        self.snoozeMinutes = try container.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 5
        self.enableIncrementalChimes = try container.decodeIfPresent(Bool.self, forKey: .enableIncrementalChimes) ?? false
        self.chimeStartMinutes = try container.decodeIfPresent(Int.self, forKey: .chimeStartMinutes) ?? 20
        self.chimeEndMinutes = try container.decodeIfPresent(Int.self, forKey: .chimeEndMinutes) ?? 40
        self.chimeCutoffAction = try container.decodeIfPresent(CutoffAction.self, forKey: .chimeCutoffAction) ?? .alertAndStandby
    }
    
    /// 快捷创建专注模块
    public static func makeWork(name: String = "专注", minutes: Int = 20, message: String? = nil, sound: String? = nil) -> FlowBlock {
        FlowBlock(
            type: .work,
            name: name,
            durationMinutes: minutes,
            countdownSeconds: nil,
            timingMode: .countdown,
            targetSeconds: nil,
            soundName: sound ?? SoundManager.shared.defaultWorkSound,
            message: message ?? SoundManager.shared.defaultWorkMessage,
            autoAdvance: true
        )
    }
    
    /// 快捷创建固定倒计时休息模块（支持分钟或精确秒数）
    public static func makeCountdownRest(
        name: String = "休息",
        minutes: Int = 5,
        seconds: Int? = nil,
        message: String? = nil,
        sound: String? = nil
    ) -> FlowBlock {
        FlowBlock(
            type: .rest,
            name: name,
            durationMinutes: seconds != nil ? max(1, seconds! / 60) : minutes,
            countdownSeconds: seconds,
            timingMode: .countdown,
            targetSeconds: nil,
            soundName: sound ?? SoundManager.shared.defaultRestSound,
            message: message ?? SoundManager.shared.defaultRestMessage,
            autoAdvance: false
        )
    }
    
    /// 快捷创建自由正计时休息模块（纯粹自由走时，无中途弹窗）
    public static func makeStopwatchRest(
        name: String = "自由休息",
        targetSeconds: Int? = nil,
        message: String? = nil,
        sound: String? = nil,
        enableChimes: Bool = false,
        chimeStart: Int = 20,
        chimeEnd: Int = 40,
        cutoffAction: CutoffAction = .alertAndStandby
    ) -> FlowBlock {
        FlowBlock(
            type: .rest,
            name: name,
            durationMinutes: 5,
            countdownSeconds: nil,
            timingMode: .stopwatch,
            targetSeconds: targetSeconds,
            soundName: sound ?? SoundManager.shared.defaultRestSound,
            message: message ?? SoundManager.shared.defaultRestMessage,
            autoAdvance: false,
            enableIncrementalChimes: enableChimes,
            chimeStartMinutes: chimeStart,
            chimeEndMinutes: chimeEnd,
            chimeCutoffAction: cutoffAction
        )
    }
}

/// 模块化循环预设方案
public struct Preset: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    
    /// 核心：模块拼装循环链
    public var blocks: [FlowBlock]
    
    // 全局安全兜底与空闲
    public var restMaxMinutes: Int = 30            // 休息超上限强制进待机
    public var idleMinutes: Int = 10               // 键鼠空闲超时进待机
    public var alertStyle: AlertStyle = .both
    public var rotation: [RotationRule] = []
    
    // 阶段打断恢复策略（专注被打断 vs 休息被打断，彻底区分人性化策略）
    public var workInterruptRecovery: InterruptRecovery = .resetCurrent  // 专注被打断恢复（默认重置本步重新倒数）
    public var restInterruptRecovery: InterruptRecovery = .advanceNext   // 休息被打断恢复（默认推进至下一步开始专注！）
    
    // 兼容历史字段
    public var manualStandbyRecovery: InterruptRecovery {
        get { workInterruptRecovery }
        set { workInterruptRecovery = newValue }
    }
    public var passiveStandbyRecovery: InterruptRecovery {
        get { restInterruptRecovery }
        set { restInterruptRecovery = newValue }
    }
    
    // 兼容历史字段
    public var mode: FlowMode {
        get { .custom }
        set { }
    }
    
    public var workMinutes: Int {
        get { blocks.first(where: { $0.type == .work })?.durationMinutes ?? 20 }
        set {
            if let idx = blocks.firstIndex(where: { $0.type == .work }) {
                blocks[idx].durationMinutes = newValue
            }
        }
    }
    
    public var restTimingMode: RestTimingMode {
        get {
            let firstRest = blocks.first(where: { $0.type == .rest })
            return (firstRest?.timingMode == .countdown) ? .countdown : .stopwatch
        }
        set {
            if let idx = blocks.firstIndex(where: { $0.type == .rest }) {
                blocks[idx].timingMode = (newValue == .countdown) ? .countdown : .stopwatch
            }
        }
    }
    
    public var restMinutes: Int {
        get { blocks.first(where: { $0.type == .rest })?.durationMinutes ?? 5 }
        set {
            if let idx = blocks.firstIndex(where: { $0.type == .rest }) {
                blocks[idx].durationMinutes = newValue
            }
        }
    }
    
    public var restTargetSeconds: Int? {
        get { blocks.first(where: { $0.type == .rest })?.targetSeconds }
        set {
            if let idx = blocks.firstIndex(where: { $0.type == .rest }) {
                blocks[idx].targetSeconds = newValue
            }
        }
    }
    
    public var autoStartRest: Bool {
        get { blocks.first(where: { $0.type == .work })?.autoAdvance ?? true }
        set {
            if let idx = blocks.firstIndex(where: { $0.type == .work }) {
                blocks[idx].autoAdvance = newValue
            }
        }
    }
    
    public var autoStartNextWork: Bool {
        get { blocks.first(where: { $0.type == .rest })?.autoAdvance ?? false }
        set {
            if let idx = blocks.firstIndex(where: { $0.type == .rest }) {
                blocks[idx].autoAdvance = newValue
            }
        }
    }
    
    public var soundName: String {
        get { blocks.first?.soundName ?? "Glass" }
        set {
            for i in 0..<blocks.count {
                blocks[i].soundName = newValue
            }
        }
    }
    
    public var message: String {
        get { blocks.first?.message ?? "看远方 20 秒" }
        set {
            if !blocks.isEmpty {
                blocks[0].message = newValue
            }
        }
    }
    
    public var longRestMinutes: Int? {
        get { nil }
        set { }
    }
    public var longRestInterval: Int? {
        get { nil }
        set { }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        blocks: [FlowBlock],
        restMaxMinutes: Int = 30,
        idleMinutes: Int = 10,
        alertStyle: AlertStyle = .both,
        rotation: [RotationRule] = [],
        workInterruptRecovery: InterruptRecovery = .resetCurrent,
        restInterruptRecovery: InterruptRecovery = .advanceNext,
        manualStandbyRecovery: InterruptRecovery? = nil,
        passiveStandbyRecovery: InterruptRecovery? = nil
    ) {
        self.id = id
        self.name = name
        self.blocks = blocks
        self.restMaxMinutes = restMaxMinutes
        self.idleMinutes = idleMinutes
        self.alertStyle = alertStyle
        self.rotation = rotation
        self.workInterruptRecovery = manualStandbyRecovery ?? workInterruptRecovery
        self.restInterruptRecovery = passiveStandbyRecovery ?? restInterruptRecovery
    }
    
    // 兼容历史旧构造器
    public init(
        id: UUID = UUID(),
        name: String,
        mode: FlowMode = .continuousLoop,
        workMinutes: Int = 20,
        autoStartRest: Bool = true,
        restTimingMode: RestTimingMode = .stopwatch,
        restTargetSeconds: Int? = 20,
        restMinutes: Int = 5,
        longRestMinutes: Int? = nil,
        longRestInterval: Int? = nil,
        autoStartNextWork: Bool = false,
        restMaxMinutes: Int = 30,
        idleMinutes: Int = 10,
        alertStyle: AlertStyle = .both,
        soundName: String = "Glass",
        message: String = "看远方 20 秒",
        rotation: [RotationRule] = []
    ) {
        self.id = id
        self.name = name
        self.restMaxMinutes = restMaxMinutes
        self.idleMinutes = idleMinutes
        self.alertStyle = alertStyle
        self.rotation = rotation
        self.workInterruptRecovery = .resetCurrent
        self.restInterruptRecovery = .advanceNext
        
        // 自动转换成流水线模块
        if mode == .pomodoro {
            self.blocks = [
                FlowBlock.makeWork(name: "番茄 1", minutes: workMinutes, message: "第 1 轮专注完成，休息一下", sound: soundName),
                FlowBlock.makeCountdownRest(name: "短休 1", minutes: restMinutes, sound: soundName),
                FlowBlock.makeWork(name: "番茄 2", minutes: workMinutes, message: "第 2 轮专注完成，休息一下", sound: soundName),
                FlowBlock.makeCountdownRest(name: "短休 2", minutes: restMinutes, sound: soundName),
                FlowBlock.makeWork(name: "番茄 3", minutes: workMinutes, message: "第 3 轮专注完成，休息一下", sound: soundName),
                FlowBlock.makeCountdownRest(name: "短休 3", minutes: restMinutes, sound: soundName),
                FlowBlock.makeWork(name: "番茄 4", minutes: workMinutes, message: "第 4 轮专注完成，该长休了", sound: soundName),
                FlowBlock.makeCountdownRest(name: "长休", minutes: longRestMinutes ?? 15, sound: soundName)
            ]
        } else {
            let restBlock: FlowBlock
            if restTimingMode == .countdown {
                restBlock = FlowBlock.makeCountdownRest(name: "休息", minutes: restMinutes, message: message, sound: soundName)
            } else {
                restBlock = FlowBlock.makeStopwatchRest(name: "自由休息", targetSeconds: restTargetSeconds ?? 20, message: message, sound: soundName)
            }
            self.blocks = [
                FlowBlock.makeWork(name: "工作", minutes: workMinutes, message: message, sound: soundName),
                restBlock
            ]
        }
    }
    
    // MARK: - Codable 兼容解码
    enum CodingKeys: String, CodingKey {
        case id, name, blocks, restMaxMinutes, idleMinutes, alertStyle, rotation
        case workInterruptRecovery, restInterruptRecovery
        case manualStandbyRecovery, passiveStandbyRecovery
        // 旧字段
        case workMinutes, restTimingMode, restTargetSeconds, restMinutes, longRestMinutes, longRestInterval, soundName, message
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.restMaxMinutes = try container.decodeIfPresent(Int.self, forKey: .restMaxMinutes) ?? 30
        self.idleMinutes = try container.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? 10
        self.alertStyle = try container.decodeIfPresent(AlertStyle.self, forKey: .alertStyle) ?? .both
        self.rotation = try container.decodeIfPresent([RotationRule].self, forKey: .rotation) ?? []
        self.workInterruptRecovery = try container.decodeIfPresent(InterruptRecovery.self, forKey: .workInterruptRecovery)
            ?? container.decodeIfPresent(InterruptRecovery.self, forKey: .manualStandbyRecovery)
            ?? .resetCurrent
        self.restInterruptRecovery = try container.decodeIfPresent(InterruptRecovery.self, forKey: .restInterruptRecovery)
            ?? container.decodeIfPresent(InterruptRecovery.self, forKey: .passiveStandbyRecovery)
            ?? .advanceNext
        
        if let decodedBlocks = try container.decodeIfPresent([FlowBlock].self, forKey: .blocks), !decodedBlocks.isEmpty {
            self.blocks = decodedBlocks
        } else {
            // 兼容旧格式数据
            let wm = try container.decodeIfPresent(Int.self, forKey: .workMinutes) ?? 20
            let rtm = try container.decodeIfPresent(RestTimingMode.self, forKey: .restTimingMode) ?? .stopwatch
            let rm = try container.decodeIfPresent(Int.self, forKey: .restMinutes) ?? 5
            let rts = try container.decodeIfPresent(Int.self, forKey: .restTargetSeconds) ?? 20
            let sound = try container.decodeIfPresent(String.self, forKey: .soundName) ?? "Glass"
            let msg = try container.decodeIfPresent(String.self, forKey: .message) ?? "看远方 20 秒"
            
            let restBlock: FlowBlock
            if rtm == .countdown {
                restBlock = FlowBlock.makeCountdownRest(name: "休息", minutes: rm, message: msg, sound: sound)
            } else {
                restBlock = FlowBlock.makeStopwatchRest(name: "自由休息", targetSeconds: rts, message: msg, sound: sound)
            }
            self.blocks = [
                FlowBlock.makeWork(name: "工作", minutes: wm, message: msg, sound: sound),
                restBlock
            ]
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(blocks, forKey: .blocks)
        try container.encode(restMaxMinutes, forKey: .restMaxMinutes)
        try container.encode(idleMinutes, forKey: .idleMinutes)
        try container.encode(alertStyle, forKey: .alertStyle)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(workInterruptRecovery, forKey: .workInterruptRecovery)
        try container.encode(restInterruptRecovery, forKey: .restInterruptRecovery)
    }
    
    // MARK: - 三大标准预设模板
    public static var defaultPresets: [Preset] {
        [
            // 1. 健康循环（我的方案）
            Preset(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                name: "健康循环",
                blocks: [
                    FlowBlock.makeWork(name: "专注", minutes: 20, message: "20 分钟到了，起身远眺休息片刻", sound: "Glass"),
                    FlowBlock.makeStopwatchRest(name: "休息(自由)", targetSeconds: 20, message: "看远方 20 秒（20英尺外）", sound: "Glass")
                ],
                restMaxMinutes: 30,
                idleMinutes: 10,
                alertStyle: .both
            ),
            // 2. 经典番茄钟 (4轮大循环)
            Preset(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                name: "经典番茄钟",
                blocks: [
                    FlowBlock.makeWork(name: "第 1 轮专注", minutes: 25, message: "第 1 轮番茄完成，短休 5 分钟", sound: "Ping"),
                    FlowBlock.makeCountdownRest(name: "第 1 轮短休", minutes: 5, message: "短休结束，准备开启第 2 轮", sound: "Ping"),
                    FlowBlock.makeWork(name: "第 2 轮专注", minutes: 25, message: "第 2 轮番茄完成，短休 5 分钟", sound: "Ping"),
                    FlowBlock.makeCountdownRest(name: "第 2 轮短休", minutes: 5, message: "短休结束，准备开启第 3 轮", sound: "Ping"),
                    FlowBlock.makeWork(name: "第 3 轮专注", minutes: 25, message: "第 3 轮番茄完成，短休 5 分钟", sound: "Ping"),
                    FlowBlock.makeCountdownRest(name: "第 3 轮短休", minutes: 5, message: "短休结束，准备开启第 4 轮", sound: "Ping"),
                    FlowBlock.makeWork(name: "第 4 轮专注", minutes: 25, message: "4 轮专注全部达成！开始长休 15 分钟", sound: "Ping"),
                    FlowBlock.makeCountdownRest(name: "深度长休", minutes: 15, message: "长休结束，整组大循环重置", sound: "Ping")
                ],
                restMaxMinutes: 30,
                idleMinutes: 10,
                alertStyle: .both
            ),
            // 3. 混合专注流（实例：工作 -> 固定短休 -> 深度工作 -> 自由长休）
            Preset(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                name: "混合专注流",
                blocks: [
                    FlowBlock.makeWork(name: "热身专注", minutes: 20, message: "热身结束，闭目 5 分钟", sound: "Pop"),
                    FlowBlock.makeCountdownRest(name: "闭目养神", minutes: 5, message: "养神完毕，准备进入深度攻坚", sound: "Pop"),
                    FlowBlock.makeWork(name: "深度专注", minutes: 30, message: "攻坚完成，恭喜达成！自由放松", sound: "Glass"),
                    FlowBlock.makeStopwatchRest(name: "自由大休", targetSeconds: 300, message: "自由走动、喝水拉伸", sound: "Glass")
                ],
                restMaxMinutes: 45,
                idleMinutes: 15,
                alertStyle: .both
            )
        ]
    }
}
