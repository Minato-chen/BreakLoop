import Foundation

/// 时间显示与格式化工具（支持分钟级与简洁格式）
public enum TimeFormatter {
    /// 仅分钟级别显示（例如 25m、1m、4m，绝无 < 等符号干扰）
    public static func formatMinutesOnly(seconds: Int) -> String {
        if seconds <= 0 {
            return "0m"
        }
        if seconds < 60 {
            return "1m"
        }
        let mins = Int(ceil(Double(seconds) / 60.0))
        return "\(mins)m"
    }
    
    /// 标准分:秒（如 25:00），当需要精细查看时备用
    public static func format(seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
    
    /// 简短自然描述（如 45 分钟、1 小时 20 分）
    public static func formatNatural(seconds: Int) -> String {
        let m = seconds / 60
        if m >= 60 {
            let h = m / 60
            let remM = m % 60
            return remM > 0 ? "\(h)小时\(remM)分" : "\(h)小时"
        } else {
            return "\(max(1, m))分钟"
        }
    }
    
    /// 兼容旧版格式（如 15m 30s 或 20s）
    public static func formatShort(seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 {
            return "\(m)m \(s)s"
        } else {
            return "\(s)s"
        }
    }
}
