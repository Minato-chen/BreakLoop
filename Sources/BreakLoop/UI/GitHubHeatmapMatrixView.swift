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
                        Text("\(hover.day.dateString) \(String(format: "%02d:00", hover.hour.hour))")
                            .fontWeight(.semibold)
                        Text("💼 工作: \(hover.hour.workMinutes)m")
                            .foregroundColor(.orange)
                        Text("🍵 休息: \(hover.hour.restMinutes)m")
                            .foregroundColor(.green)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                } else {
                    Text("鼠标悬停在小时方块上查看具体专注与休息明细")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 图例 Legend
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.orange.opacity(0.85))
                            .frame(width: 10, height: 10)
                        Text("工作")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green.opacity(0.85))
                            .frame(width: 10, height: 10)
                        Text("休息")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    Text("深浅 = 时长")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.top, 6)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
    
    // MARK: - 单个双拼小时方块
    private func heatmapCell(day: DayActivity, hour: HourActivity) -> some View {
        let hasActivity = hour.workMinutes > 0 || hour.restMinutes > 0
        
        return GeometryReader { geo in
            ZStack {
                // 底板（无活动时的浅灰底）
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.06))
                
                if hasActivity {
                    HStack(spacing: 0) {
                        // 左半边：工作时长（黄色系/暖金）
                        if hour.workMinutes > 0 {
                            Rectangle()
                                .fill(workColor(minutes: hour.workMinutes))
                                .frame(width: hour.restMinutes > 0 ? geo.size.width / 2 : geo.size.width)
                        }
                        
                        // 右半边：休息时长（绿色系/薄荷绿）
                        if hour.restMinutes > 0 {
                            Rectangle()
                                .fill(restColor(minutes: hour.restMinutes))
                                .frame(width: hour.workMinutes > 0 ? geo.size.width / 2 : geo.size.width)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }
        .frame(height: 18)
        .onHover { isHovered in
            if isHovered {
                hoveredCell = (day, hour)
            } else if hoveredCell?.day.id == day.id && hoveredCell?.hour.id == hour.id {
                hoveredCell = nil
            }
        }
    }
    
    // MARK: - 颜色深度计算 (类似 GitHub 4 级色深)
    private func workColor(minutes: Int) -> Color {
        if minutes >= 45 {
            return Color.orange // 满格专注
        } else if minutes >= 25 {
            return Color.orange.opacity(0.75)
        } else if minutes >= 10 {
            return Color.orange.opacity(0.5)
        } else {
            return Color.orange.opacity(0.28)
        }
    }
    
    private func restColor(minutes: Int) -> Color {
        if minutes >= 20 {
            return Color.green // 深度休息
        } else if minutes >= 10 {
            return Color.green.opacity(0.75)
        } else if minutes >= 4 {
            return Color.green.opacity(0.5)
        } else {
            return Color.green.opacity(0.28)
        }
    }
}
