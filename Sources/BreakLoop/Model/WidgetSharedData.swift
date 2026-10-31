import Foundation

/// 主 App 与 macOS WidgetKit 小组件共享的数据模型
public struct WidgetSharedData: Codable {
    public let modeRaw: String           // "working", "resting", "standby"
    public let presetName: String
    public let targetEndDate: Date?      // 工作倒计时目标结束时间（WidgetKit 通过 Text(timerInterval:) 自主渲染）
    public let restStartDate: Date?      // 休息开始时间
    public let todayWorkMinutes: Int
    public let todayRestMinutes: Int
    public let completedCycles: Int
    public let lastUpdated: Date
    
    public init(
        modeRaw: String,
        presetName: String,
        targetEndDate: Date?,
        restStartDate: Date?,
        todayWorkMinutes: Int,
        todayRestMinutes: Int,
        completedCycles: Int,
        lastUpdated: Date = Date()
    ) {
        self.modeRaw = modeRaw
        self.presetName = presetName
        self.targetEndDate = targetEndDate
        self.restStartDate = restStartDate
        self.todayWorkMinutes = todayWorkMinutes
        self.todayRestMinutes = todayRestMinutes
        self.completedCycles = completedCycles
        self.lastUpdated = lastUpdated
    }
    
    public static var previewData: WidgetSharedData {
        WidgetSharedData(
            modeRaw: "working",
            presetName: "护眼 20-20-20",
            targetEndDate: Date().addingTimeInterval(15 * 60),
            restStartDate: nil,
            todayWorkMinutes: 85,
            todayRestMinutes: 15,
            completedCycles: 4
        )
    }
}

/// 共享存储桥接
public enum WidgetDataManager {
    // App Group 标识符（若未开启 App Group 则降级至共享的 UserDefaults 路径）
    private static let appGroupIdentifier = "group.com.breakloop.shared"
    private static let key = "BreakLoop.WidgetSharedData"
    
    private static var userDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
    
    public static func save(data: WidgetSharedData) {
        if let encoded = try? JSONEncoder().encode(data) {
            userDefaults.set(encoded, forKey: key)
        }
    }
    
    public static func load() -> WidgetSharedData {
        guard let data = userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(WidgetSharedData.self, from: data) else {
            return WidgetSharedData(
                modeRaw: "standby",
                presetName: "待机中",
                targetEndDate: nil,
                restStartDate: nil,
                todayWorkMinutes: 0,
                todayRestMinutes: 0,
                completedCycles: 0
            )
        }
        return decoded
    }
}
