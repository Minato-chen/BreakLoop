import SwiftUI
import Charts
import UniformTypeIdentifiers

/// 统计时间跨度维度（参考苹果日历：日 / 周 / 月 / 年）
public enum StatsTimeScope: String, CaseIterable, Identifiable {
    case day = "日"
    case week = "周"
    case month = "月"
    case year = "年"
    
    public var id: String { rawValue }
}

/// 苹果日历风格工休统计与回顾视图（支持日/周/月/年多维度、随心日历选期、本日/本周/本月/本年极速跳转）
public struct StatsView: View {
    public let engine: TimerEngine
    
    @State private var currentScope: StatsTimeScope = .week
    @State private var dateAnchor: Date = Date()
    @State private var allSessionsInRange: [Session] = []
    @State private var daysActivity: [DayActivity] = []
    @State private var monthCells: [MonthCell] = []
    @State private var yearMonthsData: [YearMonthData] = []
    @State private var showDatePickerPopover: Bool = false
    
    public init(engine: TimerEngine) {
        self.engine = engine
    }
    
    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2 // 周一为一周开始
        return cal
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            // 1. 顶部专业工具栏：维度切换 + 历史日历随心选 + 快速跳转当期 + 导出
            topToolbar
                .padding(.horizontal, 20)
                .padding(.top, 14)
            
            // 2. 四宫格指标卡片
            overviewCards
                .padding(.horizontal, 20)
            
            Divider()
            
            // 3. 核心视图区（按 日/周/月/年 分支呈现）
            Group {
                switch currentScope {
                case .day:
                    dayTimelineView
                case .week:
                    weekGridView
                case .month:
                    monthCalendarGridView
                case .year:
                    yearContributionView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            reloadData()
        }
        .onChange(of: currentScope) { _ in
            reloadData()
        }
        .onChange(of: dateAnchor) { _ in
            reloadData()
        }
    }
    
    // MARK: - 顶部工具栏（苹果日历风格）
    private var topToolbar: some View {
        HStack(spacing: 12) {
            // 左侧：维度切换（日 / 周 / 月 / 年）
            Picker("", selection: $currentScope) {
                ForEach(StatsTimeScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            
            Spacer()
            
            // 中间：时间导航器（向前翻页、点击展开日历随意选、向后翻页、当期快速跳转）
            HStack(spacing: 8) {
                Button(action: stepPrevious) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                // 日历选期触发器（点击弹出日历随意选期）
                Button(action: { showDatePickerPopover.toggle() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                        Text(scopeTitle)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $showDatePickerPopover, arrowEdge: .bottom) {
                    calendarPickerPopoverContent
                }
                
                Button(action: stepNext) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                // 极速跳转对应当期（今日/本周/本月/本年）
                if isAlreadyAtCurrentPeriod {
                    Button(action: jumpToCurrentPeriod) {
                        Text(currentJumpButtonTitle)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button(action: jumpToCurrentPeriod) {
                        Text(currentJumpButtonTitle)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            
            Spacer()
            
            // 右侧：导出 CSV
            Button(action: exportCSV) {
                Label("导出 CSV", systemImage: "arrow.down.doc")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    
    // MARK: - 日历随心选弹窗（根据当前日/周/月/年提供最顺手的选择器）
    private var calendarPickerPopoverContent: some View {
        VStack(spacing: 12) {
            switch currentScope {
            case .day, .week:
                VStack(spacing: 8) {
                    HStack {
                        Text(currentScope == .day ? "选择任意日期" : "选择任意周的一天")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    DatePicker(
                        "",
                        selection: $dateAnchor,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(width: 280)
                }
                .padding(12)
                
            case .month:
                VStack(spacing: 10) {
                    HStack {
                        Text("选择任意月份")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        // 年份微调
                        let curYear = calendar.component(.year, from: dateAnchor)
                        HStack(spacing: 4) {
                            Button(action: {
                                dateAnchor = calendar.date(byAdding: .year, value: -1, to: dateAnchor) ?? dateAnchor
                            }) {
                                Image(systemName: "chevron.left").font(.caption2)
                            }
                            Text("\(curYear)年")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Button(action: {
                                dateAnchor = calendar.date(byAdding: .year, value: 1, to: dateAnchor) ?? dateAnchor
                            }) {
                                Image(systemName: "chevron.right").font(.caption2)
                            }
                        }
                    }
                    
                    // 12 个月份网格
                    let curMonth = calendar.component(.month, from: dateAnchor)
                    let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
                    LazyVGrid(columns: cols, spacing: 6) {
                        ForEach(1...12, id: \.self) { m in
                            Button(action: {
                                var comps = calendar.dateComponents([.year], from: dateAnchor)
                                comps.month = m
                                comps.day = 1
                                if let target = calendar.date(from: comps) {
                                    dateAnchor = target
                                    showDatePickerPopover = false
                                }
                            }) {
                                Text("\(m)月")
                                    .font(.system(size: 12, weight: m == curMonth ? .bold : .medium))
                                    .frame(maxWidth: .infinity, minHeight: 32)
                                    .background(m == curMonth ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                                    .foregroundColor(m == curMonth ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14)
                .frame(width: 240)
                
            case .year:
                VStack(spacing: 8) {
                    HStack {
                        Text("选择任意年份")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    let curYear = calendar.component(.year, from: dateAnchor)
                    let startYear = curYear - 4
                    let endYear = curYear + 1
                    
                    VStack(spacing: 4) {
                        ForEach(startYear...endYear, id: \.self) { y in
                            Button(action: {
                                var comps = calendar.dateComponents([.month, .day], from: dateAnchor)
                                comps.year = y
                                if let target = calendar.date(from: comps) {
                                    dateAnchor = target
                                    showDatePickerPopover = false
                                }
                            }) {
                                HStack {
                                    Text("\(y)年")
                                        .font(.system(size: 13, weight: y == curYear ? .bold : .regular))
                                    Spacer()
                                    if y == curYear {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(y == curYear ? Color.accentColor.opacity(0.1) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .frame(width: 180)
            }
        }
    }
    
    // MARK: - 当期跳转逻辑与标题
    private var currentJumpButtonTitle: String {
        switch currentScope {
        case .day: return "今天"
        case .week: return "本周"
        case .month: return "本月"
        case .year: return "本年"
        }
    }
    
    private var isAlreadyAtCurrentPeriod: Bool {
        let now = Date()
        switch currentScope {
        case .day:
            return calendar.isDate(dateAnchor, inSameDayAs: now)
        case .week:
            let weekNow = calendar.component(.weekOfYear, from: now)
            let yearNow = calendar.component(.yearForWeekOfYear, from: now)
            let weekAnchor = calendar.component(.weekOfYear, from: dateAnchor)
            let yearAnchor = calendar.component(.yearForWeekOfYear, from: dateAnchor)
            return weekNow == weekAnchor && yearNow == yearAnchor
        case .month:
            return calendar.isDate(dateAnchor, equalTo: now, toGranularity: .month)
        case .year:
            return calendar.isDate(dateAnchor, equalTo: now, toGranularity: .year)
        }
    }
    
    private func jumpToCurrentPeriod() {
        dateAnchor = Date()
    }
    
    // MARK: - 四宫格指标卡
    private var overviewCards: some View {
        let totalWork = allSessionsInRange.filter { $0.kind == .work }.reduce(0) { $0 + $1.duration }
        let totalRest = allSessionsInRange.filter { $0.kind == .rest }.reduce(0) { $0 + $1.duration }
        let restCount = allSessionsInRange.filter { $0.kind == .rest }.count
        let ratio = totalRest > 0 ? String(format: "%.1f : 1", totalWork / totalRest) : "—"
        
        return HStack(spacing: 12) {
            statCard(title: "累计专注", value: TimeFormatter.formatNatural(seconds: Int(totalWork)), icon: "laptopcomputer", color: .blue)
            statCard(title: "累计休息", value: TimeFormatter.formatNatural(seconds: Int(totalRest)), icon: "cup.and.saucer.fill", color: .green)
            statCard(title: "休息轮次", value: "\(restCount) 次", icon: "arrow.triangle.2.circlepath", color: .purple)
            statCard(title: "工休比例", value: ratio, icon: "scalemass.fill", color: .orange)
        }
    }
    
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
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
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    // MARK: - 1. 日视图（当天 24 小时流水甘特轴）
    private var dayTimelineView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("当日工休时序流水 (24小时)")
                    .font(.headline)
                Spacer()
                Text("共 \(allSessionsInRange.count) 条记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if allSessionsInRange.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("该日暂无专注或休息记录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(allSessionsInRange.sorted(by: { $0.start < $1.start })) { s in
                            let isWork = s.kind == .work
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isWork ? Color.blue : Color.green)
                                    .frame(width: 4, height: 32)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(isWork ? "💻 工作专注" : "☕️ 休息")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(s.presetName)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Text("\(timeStr(s.start)) ~ \(timeStr(s.end))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Text(TimeFormatter.formatNatural(seconds: Int(s.duration)))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(isWork ? .blue : .green)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 2. 周视图（当前选定周 7天×24小时矩阵）
    private var weekGridView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("本周 24 小时工休分布矩阵")
                    .font(.headline)
                Spacer()
                Text("横轴 00:00 ~ 23:00")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            GitHubHeatmapMatrixView(days: daysActivity)
            
            Spacer(minLength: 0)
        }
    }
    
    // MARK: - 3. 月视图（整月日历格子热力图，支持点击任意天穿透到日视图）
    private var monthCalendarGridView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("月度专注日历热力")
                    .font(.headline)
                Spacer()
                Text("点击任意日期方格可穿透查看当日详情")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // 7 列日历网格（周一至周日）
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]
            
            HStack {
                ForEach(weekdaySymbols, id: \.self) { sym in
                    Text(sym)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)
            
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(monthCells) { cell in
                    Button(action: {
                        if cell.isCurrentMonth {
                            dateAnchor = cell.date
                            currentScope = .day
                        }
                    }) {
                        VStack(spacing: 2) {
                            Text("\(cell.dayNumber)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(cell.isCurrentMonth ? .primary : .secondary.opacity(0.3))
                            
                            if cell.workMinutes > 0 {
                                Text("\(cell.workMinutes)m")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            } else {
                                Text("-")
                                    .font(.system(size: 9))
                                    .foregroundColor(.clear)
                            }
                        }
                        .frame(height: 48)
                        .frame(maxWidth: .infinity)
                        .background(
                            cell.isCurrentMonth
                            ? (cell.workMinutes > 0 ? Color.blue.opacity(min(1.0, 0.25 + Double(cell.workMinutes) / 240.0)) : Color(NSColor.controlBackgroundColor))
                            : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(cell.isToday ? Color.accentColor : Color.primary.opacity(0.06), lineWidth: cell.isToday ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer(minLength: 0)
        }
    }
    
    // MARK: - 4. 年视图（全年 12 个月专注全景）
    private var yearContributionView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("年度月份专注分布")
                    .font(.headline)
                Spacer()
                Text("纵览全年各月专注成果")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Chart(yearMonthsData) { item in
                BarMark(
                    x: .value("月份", item.monthLabel),
                    y: .value("专注时长 (小时)", item.workHours)
                )
                .foregroundStyle(Color.blue.gradient)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .padding(.vertical, 8)
            
            Spacer(minLength: 0)
        }
    }
    
    // MARK: - 翻页与标题计算
    private var scopeTitle: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        
        switch currentScope {
        case .day:
            df.dateFormat = "yyyy年MM月dd日 EEEE"
            return df.string(from: dateAnchor)
        case .week:
            let weekOfYear = calendar.component(.weekOfYear, from: dateAnchor)
            let year = calendar.component(.yearForWeekOfYear, from: dateAnchor)
            return "\(year)年 第\(weekOfYear)周"
        case .month:
            df.dateFormat = "yyyy年 MM月"
            return df.string(from: dateAnchor)
        case .year:
            df.dateFormat = "yyyy年"
            return df.string(from: dateAnchor)
        }
    }
    
    private func stepPrevious() {
        switch currentScope {
        case .day:
            dateAnchor = calendar.date(byAdding: .day, value: -1, to: dateAnchor) ?? dateAnchor
        case .week:
            dateAnchor = calendar.date(byAdding: .weekOfYear, value: -1, to: dateAnchor) ?? dateAnchor
        case .month:
            dateAnchor = calendar.date(byAdding: .month, value: -1, to: dateAnchor) ?? dateAnchor
        case .year:
            dateAnchor = calendar.date(byAdding: .year, value: -1, to: dateAnchor) ?? dateAnchor
        }
    }
    
    private func stepNext() {
        switch currentScope {
        case .day:
            dateAnchor = calendar.date(byAdding: .day, value: 1, to: dateAnchor) ?? dateAnchor
        case .week:
            dateAnchor = calendar.date(byAdding: .weekOfYear, value: 1, to: dateAnchor) ?? dateAnchor
        case .month:
            dateAnchor = calendar.date(byAdding: .month, value: 1, to: dateAnchor) ?? dateAnchor
        case .year:
            dateAnchor = calendar.date(byAdding: .year, value: 1, to: dateAnchor) ?? dateAnchor
        }
    }
    
    // MARK: - 数据聚合刷新（仅在切换维度或日期时触发，杜绝每秒重复计算与内存激增）
    private func reloadData() {
        let interval = currentInterval()
        let sessions = engine.sessionStore.sessions(in: interval.start...interval.end)
        self.allSessionsInRange = sessions
        
        switch currentScope {
        case .day:
            break
        case .week:
            buildWeekActivity(from: sessions, in: interval)
        case .month:
            self.monthCells = generateMonthCalendarCells(from: sessions, in: interval)
        case .year:
            self.yearMonthsData = generateYearlyMonthsData(from: sessions, in: interval)
        }
    }
    
    private func currentInterval() -> DateInterval {
        switch currentScope {
        case .day:
            let start = calendar.startOfDay(for: dateAnchor)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
            
        case .week:
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: dateAnchor)
            let start = calendar.date(from: comps) ?? calendar.startOfDay(for: dateAnchor)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            return DateInterval(start: start, end: end)
            
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: dateAnchor)
            let start = calendar.date(from: comps) ?? calendar.startOfDay(for: dateAnchor)
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
            
        case .year:
            let comps = calendar.dateComponents([.year], from: dateAnchor)
            let start = calendar.date(from: comps) ?? calendar.startOfDay(for: dateAnchor)
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        }
    }
    
    // 静态复用 DateFormatter，彻底消除反复创建 Foundation Formatter 造成的内存暴涨
    private static let dayStringFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
    
    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df
    }()
    
    private static let csvDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df
    }()
    
    private func buildWeekActivity(from sessions: [Session], in interval: DateInterval) {
        var days: [DayActivity] = []
        var cur = interval.start
        let weekdaySymbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        
        while cur < interval.end {
            let dayStart = cur
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let daySessions = sessions.filter { $0.start >= dayStart && $0.start < dayEnd }
            let dateStr = Self.dayStringFormatter.string(from: dayStart)
            
            let weekdayIdx = calendar.component(.weekday, from: dayStart) - 1
            let weekdayStr = (weekdayIdx >= 0 && weekdayIdx < 7) ? weekdaySymbols[weekdayIdx] : ""
            
            var hours: [HourActivity] = []
            for h in 0..<24 {
                let hStart = calendar.date(byAdding: .hour, value: h, to: dayStart)!
                let hEnd = calendar.date(byAdding: .hour, value: 1, to: hStart)!
                
                var wSec: TimeInterval = 0
                var rSec: TimeInterval = 0
                var count: Int = 0
                
                for s in daySessions {
                    let overlapStart = max(s.start, hStart)
                    let overlapEnd = min(s.end, hEnd)
                    if overlapEnd > overlapStart {
                        let dur = overlapEnd.timeIntervalSince(overlapStart)
                        if s.kind == .work { wSec += dur } else { rSec += dur }
                        count += 1
                    }
                }
                hours.append(HourActivity(hour: h, workSeconds: wSec, restSeconds: rSec, sessionCount: count))
            }
            
            days.append(DayActivity(date: dayStart, dateString: dateStr, weekdayName: weekdayStr, hours: hours))
            cur = dayEnd
        }
        self.daysActivity = days
    }
    
    // MARK: - 月度格子模型生成（稳定 ID，避免无谓视图重绘重建）
    private struct MonthCell: Identifiable {
        var id: String { "\(date.timeIntervalSince1970)" }
        var date: Date
        var dayNumber: Int
        var isCurrentMonth: Bool
        var isToday: Bool
        var workMinutes: Int
    }
    
    private func generateMonthCalendarCells(from sessions: [Session], in interval: DateInterval) -> [MonthCell] {
        let monthStart = interval.start
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let offset = (firstWeekday + 5) % 7
        
        guard let daysCount = calendar.range(of: .day, in: .month, for: monthStart)?.count else { return [] }
        
        var cells: [MonthCell] = []
        let today = Date()
        
        for i in 0..<offset {
            let prevDate = calendar.date(byAdding: .day, value: -(offset - i), to: monthStart) ?? monthStart
            cells.append(MonthCell(date: prevDate, dayNumber: calendar.component(.day, from: prevDate), isCurrentMonth: false, isToday: false, workMinutes: 0))
        }
        
        for day in 1...daysCount {
            let curDate = calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
            let dayStart = calendar.startOfDay(for: curDate)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            
            let daySessions = sessions.filter { $0.start >= dayStart && $0.start < dayEnd && $0.kind == .work }
            let totalMins = Int(daySessions.reduce(0) { $0 + $1.duration } / 60)
            let isTod = calendar.isDate(curDate, inSameDayAs: today)
            
            cells.append(MonthCell(date: curDate, dayNumber: day, isCurrentMonth: true, isToday: isTod, workMinutes: totalMins))
        }
        
        return cells
    }
    
    // MARK: - 年度图表数据
    private struct YearMonthData: Identifiable {
        var id: String { monthLabel }
        var monthLabel: String
        var workHours: Double
    }
    
    private func generateYearlyMonthsData(from sessions: [Session], in interval: DateInterval) -> [YearMonthData] {
        let yearStart = interval.start
        var result: [YearMonthData] = []
        
        for m in 0..<12 {
            let mStart = calendar.date(byAdding: .month, value: m, to: yearStart) ?? yearStart
            let mEnd = calendar.date(byAdding: .month, value: 1, to: mStart) ?? mStart
            
            let mSessions = sessions.filter { $0.start >= mStart && $0.start < mEnd && $0.kind == .work }
            let hours = mSessions.reduce(0) { $0 + $1.duration } / 3600.0
            
            let label = "\(m + 1)月"
            result.append(YearMonthData(monthLabel: label, workHours: hours))
        }
        
        return result
    }
    
    private func timeStr(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
    
    // MARK: - CSV 导出
    private func exportCSV() {
        let sessions = allSessionsInRange.sorted(by: { $0.start < $1.start })
        var csv = "类型,方案,开始时间,结束时间,时长(秒),结束原因\n"
        
        for s in sessions {
            let kindStr = (s.kind == .work) ? "工作" : "休息"
            let startStr = Self.csvDateFormatter.string(from: s.start)
            let endStr = Self.csvDateFormatter.string(from: s.end)
            let line = "\(kindStr),\"\(s.presetName)\",\(startStr),\(endStr),\(Int(s.duration)),\(s.endReason.rawValue)\n"
            csv.append(line)
        }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "BreakLoop-工休记录-\(scopeTitle).csv"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
