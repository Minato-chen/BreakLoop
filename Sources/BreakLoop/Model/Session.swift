import Foundation

/// 记录类型：工作 或 休息
public enum SessionKind: String, Codable, CaseIterable {
    case work
    case rest
}

/// 结束原因
public enum EndReason: String, Codable, CaseIterable {
    case completed     // 计时正常完成
    case skipped       // 用户主动跳过（如工作提前跳过休息）
    case manual        // 用户手动待机或结束
    case idle          // 键鼠空闲超时
    case locked        // 锁屏/屏保
    case sleep         // 系统休眠
    case restTimeout   // 休息超时超上限
    case crashed       // 崩溃或未正常退出补记
}

/// 单次计时段记录
public struct Session: Codable, Identifiable, Equatable {
    public let id: UUID
    public var kind: SessionKind
    public var start: Date
    public var end: Date
    public var presetName: String
    public var endReason: EndReason
    
    public init(
        id: UUID = UUID(),
        kind: SessionKind,
        start: Date,
        end: Date,
        presetName: String,
        endReason: EndReason
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.presetName = presetName
        self.endReason = endReason
    }
    
    /// 经过时长（秒）
    public var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}
