import SwiftUI

public enum NavigationSection: String, CaseIterable, Identifiable {
    case dashboard = "专注仪表台"
    case heatmap = "工休热力图"
    case presets = "方案管理"
    case sounds = "声音中心"
    case preferences = "偏好设置"
    case about = "关于"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .dashboard: return "book.closed.fill"
        case .heatmap: return "chart.bar.xaxis"
        case .presets: return "arrow.triangle.2.circlepath"
        case .sounds: return "speaker.wave.3.fill"
        case .preferences: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

/// 丝滑平整侧边栏（零弹跳、零卡顿、无嵌套 SplitView 错位）
public struct MainAppView: View {
    public let engine: TimerEngine
    @State private var selectedSection: NavigationSection = .dashboard
    
    public init(engine: TimerEngine) {
        self.engine = engine
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // 1. 扁平定制原生侧边栏（彻底杜绝 NavigationSplitView 固有弹跳）
            VStack(alignment: .leading, spacing: 4) {
                // 顶部极简品牌标识
                HStack(spacing: 8) {
                    Image(systemName: "circle.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 16))
                    Text("BreakLoop")
                        .font(.system(size: 14, weight: .bold))
                }
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 12)
                
                // 导航选项列表
                ForEach(NavigationSection.allCases) { section in
                    let isSelected = selectedSection == section
                    Button(action: { selectedSection = section }) {
                        HStack(spacing: 10) {
                            Image(systemName: section.iconName)
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 18)
                                .foregroundColor(isSelected ? .accentColor : .secondary)
                            
                            Text(section.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(isSelected ? .primary : .secondary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }
                
                Spacer()
                
                // 底部轻量状态胶囊（提取为独立子视图，隔离 1 秒重绘，保护主窗口不产生无谓 View 重建）
                SidebarStatusFooter(engine: engine)
            }
            .frame(width: 180)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            
            Divider()
            
            // 2. 右侧核心内容区（零延迟瞬时渲染）
            Group {
                switch selectedSection {
                case .dashboard:
                    DashboardView(engine: engine)
                case .heatmap:
                    StatsView(engine: engine)
                case .presets:
                    PresetManagerView(engine: engine)
                case .sounds:
                    SoundManagerView()
                case .preferences:
                    GeneralPreferencesView(engine: engine)
                case .about:
                    AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 840, minHeight: 540)
    }
}

/// 底部状态胶囊（独立观测，仅在步数或模式变更时刷新自身）
private struct SidebarStatusFooter: View {
    @ObservedObject var engine: TimerEngine
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(engine.mode == .standby ? Color.secondary : (engine.mode == .working ? Color.blue : Color.green))
                .frame(width: 6, height: 6)
            Text("\(engine.preset.name) · \(engine.currentBlockIndex + 1)/\(engine.preset.blocks.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
    }
}
