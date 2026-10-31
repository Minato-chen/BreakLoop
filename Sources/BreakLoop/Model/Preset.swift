import Foundation

/// 休息计时方式
public enum RestTimingMode: String, Codable, CaseIterable {
    case stopwatch  // 正计时（自由休息，达标轻提示，超上限进待机）
    case countdown  // 倒计时（严格休息，如番茄钟短休/长休）
}

/// 提醒方式
public enum AlertStyle: String, Codable, CaseIterable {
    case popup   // 仅浮窗
    case sound   // 仅声音
    case both    // 浮窗与声音
    case none    // 无提示（静音）
}

/// 工作流模式定义
public enum FlowMode: String, Codable, CaseIterable {
    case continuousLoop    // 核心模式：工作倒计时 -> 自由休息正计时
    case pomodoro          // 番茄钟：工作倒计时 -> 短/长休倒计时，按周期大休息
    case intervalTimer     // 固定间隔循环：工作倒计时 -> 固定休息倒计时
    case custom            // 自定义模式
}

/// 休息轮换提醒规则（如每 2 轮提示喝水，每 3 轮提示站立活动）
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

/// 行为预设
public struct Preset: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var mode: FlowMode
    
    // 工作配置
    public var workMinutes: Int
    public var autoStartRest: Bool
    
    // 休息配置
    public var restTimingMode: RestTimingMode
    public var restTargetSeconds: Int?        // 正计时时的达标目标（秒）
    public var restMinutes: Int               // 倒计时休息时长，或正计时目标分钟
    public var longRestMinutes: Int?          // 长休息（如番茄钟）
    public var longRestInterval: Int?         // 达到长休息的周期轮数（如 4 轮）
    public var autoStartNextWork: Bool        // 休息结束是否自动开始下一轮工作
    
    // 安全兜底与空闲
    public var restMaxMinutes: Int            // 休息超上限强制进待机
    public var idleMinutes: Int               // 键鼠空闲超时进待机
    
    // 提醒与提示
    public var alertStyle: AlertStyle
    public var soundName: String
    public var message: String
    public var rotation: [RotationRule]
    
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
        self.mode = mode
        self.workMinutes = workMinutes
        self.autoStartRest = autoStartRest
        self.restTimingMode = restTimingMode
        self.restTargetSeconds = restTargetSeconds
        self.restMinutes = restMinutes
        self.longRestMinutes = longRestMinutes
        self.longRestInterval = longRestInterval
        self.autoStartNextWork = autoStartNextWork
        self.restMaxMinutes = restMaxMinutes
        self.idleMinutes = idleMinutes
        self.alertStyle = alertStyle
        self.soundName = soundName
        self.message = message
        self.rotation = rotation
    }
    
    /// 系统内置预设
    public static var defaultPresets: [Preset] {
        [
            // 1. 20-20-20 护眼法则
            Preset(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                name: "护眼 20-20-20",
                mode: .continuousLoop,
                workMinutes: 20,
                autoStartRest: true,
                restTimingMode: .stopwatch,
                restTargetSeconds: 20,
                restMinutes: 1,
                restMaxMinutes: 30,
                idleMinutes: 10,
                alertStyle: .both,
                soundName: "Glass",
                message: "看远方 20 秒（20英尺外）"
            ),
            // 2. 经典番茄钟
            Preset(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                name: "经典番茄钟 25/5",
                mode: .pomodoro,
                workMinutes: 25,
                autoStartRest: true,
                restTimingMode: .countdown,
                restTargetSeconds: nil,
                restMinutes: 5,
                longRestMinutes: 15,
                longRestInterval: 4,
                autoStartNextWork: false,
                restMaxMinutes: 30,
                idleMinutes: 10,
                alertStyle: .both,
                soundName: "Ping",
                message: "番茄时间到，休息 5 分钟"
            ),
            // 3. 专注 45 分钟
            Preset(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                name: "专注 45 分钟",
                mode: .continuousLoop,
                workMinutes: 45,
                autoStartRest: true,
                restTimingMode: .stopwatch,
                restTargetSeconds: 300,
                restMinutes: 5,
                restMaxMinutes: 45,
                idleMinutes: 10,
                alertStyle: .both,
                soundName: "Tink",
                message: "专注完成，起身活动活动"
            ),
            // 4. 护眼 + 喝水 + 活动轮换
            Preset(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                name: "健康轮换（看远方/喝水/活动）",
                mode: .continuousLoop,
                workMinutes: 20,
                autoStartRest: true,
                restTimingMode: .stopwatch,
                restTargetSeconds: 30,
                restMinutes: 1,
                restMaxMinutes: 30,
                idleMinutes: 10,
                alertStyle: .both,
                soundName: "Pop",
                message: "看远方 20 秒",
                rotation: [
                    RotationRule(everyNthCycle: 2, message: "喝口水，深呼吸一下"),
                    RotationRule(everyNthCycle: 3, message: "站起来活动肩颈和腰部")
                ]
            )
        ]
    }
}
