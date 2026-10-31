import SwiftUI

public enum NavigationSection: String, CaseIterable, Identifiable {
    case dashboard = "专注仪表台"
    case heatmap = "工休热力图"
    case presets = "预设方案管理"
    case settings = "偏好与关于"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .dashboard: return "timer"
        case .heatmap: return "chart.bar.xaxis"
        case .presets: return "slider.horizontal.3"
        case .settings: return "gearshape"
        }
    }
}

/// 标准 macOS 风格一体化主窗口界面
public struct MainAppView: View {
    @ObservedObject var engine: TimerEngine
    @State private var selectedSection: NavigationSection = .dashboard
    
    public init(engine: TimerEngine) {
        self.engine = engine
    }
    
    public var body: some View {
        NavigationSplitView {
            // 左侧侧边栏
            List(NavigationSection.allCases, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    Label(section.rawValue, systemImage: section.iconName)
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            // 右侧内容详情
            Group {
                switch selectedSection {
                case .dashboard:
                    DashboardView(engine: engine)
                case .heatmap:
                    StatsView(engine: engine)
                case .presets:
                    presetsManagerView
                case .settings:
                    preferencesAndAboutView
                }
            }
            .frame(minWidth: 540, minHeight: 460)
        }
        .frame(minWidth: 720, minHeight: 480)
    }
    
    // MARK: - 预设方案管理页
    private var presetsManagerView: some View {
        SettingsView(engine: engine, defaultTab: .presets)
    }
    
    // MARK: - 偏好与关于页
    private var preferencesAndAboutView: some View {
        SettingsView(engine: engine, defaultTab: .general)
    }
}
