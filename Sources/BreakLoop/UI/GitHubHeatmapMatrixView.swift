import SwiftUI

/// 某小时内的统计数据汇总
public struct HourActivity: Identifiable {
    public var id: Int { hour }
    public let hour: Int              // 0 ~ 23
    public var workSeconds: TimeInterval
    public var restSeconds: TimeInterval
    public var sessionCount: Int
    
    public var workMinutes: Int {
        Int(round(workSeconds / 60.0))
    }
    
    public var restMinutes: Int {
        Int(round(restSeconds / 60.0))
    }
}

/// 某天的 24 小时活跃情况
public struct DayActivity: Identifiable {
    public var id: String { dateString }
    public let date: Date
    public let dateString: String
    public let weekdayName: String
    public var hours: [HourActivity] // 24 个小时
}

/// GitHub 风格的工休 24 小时热力矩阵视图
public struct GitHubHeatmapMatrixView: View {
    let days: [DayActivity]
    @State private var hoveredCell: (day: DayActivity, hour: HourActivity)?
    
    private let hourLabels = [0, 3, 6, 9, 12, 15, 18, 21]
    
    public init(days: [DayActivity]) {
        self.days = days
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶部小时横轴标尺
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 44, alignment: .leading)
                
                HStack(spacing: 4) {
                    ForEach(0..<24, id: \.self) { h in
                        if hourLabels.contains(h) {
                            Text(String(format: "%02d", h))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Spacer()
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.trailing, 8)
            
            // 每一天的 24 格热力行
            VStack(spacing: 5) {
                ForEach(days) { day in
                    HStack(spacing: 6) {
                        // 左侧星期/日期标号
                        Text(day.weekdayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 44, alignment: .leading)
                        
                        // 24 个小时格子
                        HStack(spacing: 4) {
                            ForEach(day.hours) { hour in
                                heatmapCell(day: day, hour: hour)
                            }
                        }
                    }
                }
            }
            
            // 底部 Hover 详情与图例
            HStack(alignment: .center) {
                if let hover = hoveredCell {
                    HStack(spacing: 8) {
                        Text("\(hover.day.weekdayName) \(hover.day.dateString) \(String(format: "%02d:00", hover.hour.hour))")
                            .fontWeight(.semibold)
                        Text("💻 专注: \(hover.hour.workMinutes)m")
                            .foregroundColor(Color(red: 0.05, green: 0.52, blue: 1.0))
                        if hover.hour.restMinutes > 0 {
                            Text("☕️ 休息: \(hover.hour.restMinutes)m")
                                .foregroundColor(Color(red: 0.18, green: 0.82, blue: 0.38))
                        }
                        if hover.hour.restMinutes > 0 && hover.hour.workMinutes > 0 {
                            let ratio = Double(hover.hour.workMinutes) / Double(hover.hour.restMinutes)
                            Text("📊 比率: \(String(format: "%.1f", ratio)):1")
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                } else {
                    Text("鼠标悬停在表盘圆环上查看具体小时专注与休息明细")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 双弧流转圆环图例 (专注弧 + 休息弧 + 满环60m)
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: 0.05, green: 0.52, blue: 1.0))
                            .frame(width: 7, height: 7)
                        Text("专注弧")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: 0.18, green: 0.82, blue: 0.38))
                            .frame(width: 7, height: 7)
                        Text("休息弧")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Circle()
                            .stroke(Color.primary.opacity(0.22), lineWidth: 1.5)
                            .frame(width: 7, height: 7)
                        Text("满环 60m")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.top, 6)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
    
    // MARK: - 设计 A：双弧流转表盘圆环 (60分钟满圈表盘)
    private func heatmapCell(day: DayActivity, hour: HourActivity) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.5)
                .fill(level0Color.opacity(0.35))
            
            DualArcRingView(
                workMinutes: Double(hour.workMinutes),
                restMinutes: Double(hour.restMinutes),
                maxMinutes: 60.0,
                size: 14.5,
                lineWidth: 2.2,
                showTrack: true
            )
        }
        .frame(height: 18)
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered {
                hoveredCell = (day, hour)
            } else if hoveredCell?.day.id == day.id && hoveredCell?.hour.id == hour.id {
                hoveredCell = nil
            }
        }
    }
    
    // MARK: - GitHub 原生 Primer 绿色阶 (100% 独立实色，暗黑模式通透纯正)
    private var level0Color: Color {
        Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.09, green: 0.11, blue: 0.13, alpha: 1.0) // #161b22
                : NSColor(red: 0.92, green: 0.93, blue: 0.94, alpha: 1.0) // #ebedf0
        }))
    }
    
    private var restBadgeColor: Color {
        Color(red: 0.35, green: 0.65, blue: 1.0) // #58A6FF GitHub Accent Blue
    }
    
    private func gitHubGreen(minutes: Int) -> Color {
        if minutes >= 45 {
            // Level 4 (45m+): 顶格荧光翠绿 #39d353
            return Color(red: 0.224, green: 0.827, blue: 0.325)
        } else if minutes >= 30 {
            // Level 3 (30~44m): 鲜活草绿 #26a641
            return Color(red: 0.149, green: 0.651, blue: 0.255)
        } else if minutes >= 15 {
            // Level 2 (15~29m): 经典中绿 #006d32
            return Color(red: 0.000, green: 0.427, blue: 0.196)
        } else if minutes > 0 {
            // Level 1 (1~14m): 沉稳深墨绿 #0e4429
            return Color(red: 0.055, green: 0.267, blue: 0.161)
        } else {
            return level0Color
        }
    }
}
