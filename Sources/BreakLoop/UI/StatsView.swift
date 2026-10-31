import SwiftUI
import Charts
import UniformTypeIdentifiers

/// 统计与回顾视图（集成 GitHub 风格工休热力矩阵与总体指标）
public struct StatsView: View {
    @ObservedObject var engine: TimerEngine
    @State private var daysActivity: [DayActivity] = []
    @State private var selectedRangeDays: Int = 7
    @State private var allSessionsInRange: [Session] = []
    
    public init(engine: TimerEngine) {
        self.engine = engine
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // 顶部范围切换与导出
            HStack {
                Picker("展示周期", selection: $selectedRangeDays) {
                    Text("最近 7 天").tag(7)
                    Text("最近 14 天").tag(14)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                
                Spacer()
                
                Button(action: exportCSV) {
                    Label("导出完整 CSV", systemImage: "arrow.down.doc")
                }
            }
            .padding(.horizontal)
            .padding(.top, 14)
            
            // 四宫格统计卡片
            overviewCards
                .padding(.horizontal)
            
            Divider()
            
            // 核心：GitHub 风格 24 小时工休热力矩阵
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("每日 24 小时工休分布矩阵")
                        .font(.headline)
                    Spacer()
                    Text("横轴 00:00 ~ 23:00")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                GitHubHeatmapMatrixView(days: daysActivity)
                    .padding(.horizontal)
            }
            
            Spacer(minLength: 4)
        }
        .frame(width: 680, height: 500)
        .onAppear {
            loadHeatmapData()
        }
        .onChange(of: selectedRangeDays) { _ in
            loadHeatmapData()
        }
    }
    
    // MARK: - 概览卡片
    private var overviewCards: some View {
        let totalWork = allSessionsInRange.filter { $0.kind == .work }.reduce(0) { $0 + $1.duration }
        let totalRest = allSessionsInRange.filter { $0.kind == .rest }.reduce(0) { $0 + $1.duration }
        let restCount = allSessionsInRange.filter { $0.kind == .rest }.count
        let ratio = totalRest > 0 ? String(format: "%.1f : 1", totalWork / totalRest) : "—"
        
        return HStack(spacing: 12) {
            statCard(title: "累计工作", value: TimeFormatter.formatNatural(seconds: Int(totalWork)), icon: "brain.head.profile", color: .orange)
            statCard(title: "累计休息", value: TimeFormatter.formatNatural(seconds: Int(totalRest)), icon: "cup.and.saucer.fill", color: .green)
            statCard(title: "休息轮次", value: "\(restCount) 次", icon: "arrow.triangle.2.circlepath", color: .teal)
            statCard(title: "工休比例", value: ratio, icon: "scalemass", color: .accentColor)
        }
    }
    
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundColor(.primary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    // MARK: - 构建并计算 24 小时热力矩阵数据
    private func loadHeatmapData() {
        let calendar = Calendar.current
        let now = engine.nowProvider()
        let startOfToday = calendar.startOfDay(for: now)
        
        guard let startDate = calendar.date(byAdding: .day, value: -(selectedRangeDays - 1), to: startOfToday) else { return }
        let endDate = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        
        let sessions = engine.sessionStore.sessions(in: startDate...endDate)
        self.allSessionsInRange = sessions
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM-dd"
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEE"
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        
        var calculatedDays: [DayActivity] = []
        
        // 从 startDate 遍历到今天
        for dayOffset in 0..<selectedRangeDays {
            guard let currentDay = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }
            let dayStart = calendar.startOfDay(for: currentDay)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            
            // 初始化当天的 24 个小时格子
            var hoursList = (0..<24).map { HourActivity(hour: $0, workSeconds: 0, restSeconds: 0, sessionCount: 0) }
            
            // 遍历并精确分配该天内每个小时的持续时长
            for s in sessions {
                // 判断 session 与当天是否有交集
                let overlapStart = max(s.start, dayStart)
                let overlapEnd = min(s.end, dayEnd)
                guard overlapStart < overlapEnd else { continue }
                
                // 将 session 细分到对应的小时
                var cursor = overlapStart
                while cursor < overlapEnd {
                    let hourNumber = calendar.component(.hour, from: cursor)
                    // 获取当前小时结束边界
                    let nextHour = calendar.date(byAdding: .hour, value: 1, to: calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: cursor))!)!
                    let chunkEnd = min(overlapEnd, nextHour)
                    let duration = chunkEnd.timeIntervalSince(cursor)
                    
                    if hourNumber >= 0 && hourNumber < 24 {
                        if s.kind == .work {
                            hoursList[hourNumber].workSeconds += duration
                        } else {
                            hoursList[hourNumber].restSeconds += duration
                        }
                        hoursList[hourNumber].sessionCount += 1
                    }
                    cursor = chunkEnd
                }
            }
            
            let dayObj = DayActivity(
                date: dayStart,
                dateString: dateFormatter.string(from: dayStart),
                weekdayName: weekdayFormatter.string(from: dayStart),
                hours: hoursList
            )
            calculatedDays.append(dayObj)
        }
        
        self.daysActivity = calculatedDays
    }
    
    // MARK: - 导出 CSV
    private func exportCSV() {
        let calendar = Calendar.current
        let now = engine.nowProvider()
        let startOfYear = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        let csvString = engine.sessionStore.exportCSV(for: startOfYear...now)
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "BreakLoop-Export.csv"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? csvString.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
