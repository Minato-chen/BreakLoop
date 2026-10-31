import WidgetKit
import SwiftUI

struct BreakLoopWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetSharedData
}

struct BreakLoopWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BreakLoopWidgetEntry {
        BreakLoopWidgetEntry(date: Date(), data: .previewData)
    }

    func getSnapshot(in context: Context, completion: @escaping (BreakLoopWidgetEntry) -> Void) {
        let entry = BreakLoopWidgetEntry(date: Date(), data: WidgetDataManager.load())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BreakLoopWidgetEntry>) -> Void) {
        let currentData = WidgetDataManager.load()
        let entry = BreakLoopWidgetEntry(date: Date(), data: currentData)
        
        // 5 分钟刷新一次或者在状态变更时触发
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

/// macOS 系统小组件视图（原生精致 Apple 风格，适配小号与中号）
struct BreakLoopWidgetEntryView: View {
    var entry: BreakLoopWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        default:
            smallWidget
        }
    }
    
    // MARK: - 小号小组件 (System Small: 放置在 macOS 桌面或通知中心)
    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.headline)
                Spacer()
                Text(statusText)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            
            Spacer()
            
            // 倒计时或状态展示
            if entry.data.modeRaw == "working", let targetEnd = entry.data.targetEndDate {
                Text(timerInterval: Date()...targetEnd, countsDown: true)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            } else if entry.data.modeRaw == "resting", let restStart = entry.data.restStartDate {
                Text(timerInterval: restStart...Date().addingTimeInterval(3600), countsDown: false)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.green)
            } else {
                Text("\(entry.data.todayWorkMinutes)m")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            
            Text(entry.data.presetName)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            Divider()
            
            HStack {
                Text("今日专注")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(entry.data.todayWorkMinutes) 分钟")
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .padding(14)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - 中号小组件 (System Medium)
    private var mediumWidget: some View {
        HStack(spacing: 16) {
            // 左侧状态
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                    Text(statusText)
                        .font(.headline)
                }
                
                Spacer()
                
                if entry.data.modeRaw == "working", let targetEnd = entry.data.targetEndDate {
                    Text(timerInterval: Date()...targetEnd, countsDown: true)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                } else if entry.data.modeRaw == "resting", let restStart = entry.data.restStartDate {
                    Text(timerInterval: restStart...Date().addingTimeInterval(3600), countsDown: false)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                } else {
                    Text("待机休息中")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
                
                Text(entry.data.presetName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // 右侧指标卡
            VStack(alignment: .leading, spacing: 8) {
                metricRow(title: "今日专注时长", value: "\(entry.data.todayWorkMinutes) 分钟", color: .orange)
                metricRow(title: "今日休息时长", value: "\(entry.data.todayRestMinutes) 分钟", color: .green)
                metricRow(title: "已完成循环", value: "\(entry.data.completedCycles) 轮", color: .accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func metricRow(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(color)
        }
    }
    
    private var statusText: String {
        switch entry.data.modeRaw {
        case "working": return "专注工作中"
        case "resting": return "放松休息中"
        default: return "待机就绪"
        }
    }
    
    private var statusColor: Color {
        switch entry.data.modeRaw {
        case "working": return .accentColor
        case "resting": return .green
        default: return .secondary
        }
    }
    
    private var statusIcon: String {
        switch entry.data.modeRaw {
        case "working": return "book.closed.fill"
        case "resting": return "cup.and.saucer.fill"
        default: return "leaf.fill"
        }
    }
}

@main
struct BreakLoopWidget: Widget {
    let kind: String = "BreakLoopWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BreakLoopWidgetProvider()) { entry in
            BreakLoopWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("BreakLoop 循环节奏")
        .description("在 macOS 桌面上随时查看当前专注阶段与今日累计时长。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
