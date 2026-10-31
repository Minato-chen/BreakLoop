import SwiftUI

/// 专注控制仪表台视图（二元状态大按钮 + 纯分钟显示 + 今日概览）
public struct DashboardView: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var presetStore = PresetStore.shared
    
    public init(engine: TimerEngine) {
        self.engine = engine
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            // 顶部预设选择与全局待机按钮
            HStack {
                Menu {
                    ForEach(presetStore.presets) { p in
                        Button(action: {
                            presetStore.activePresetId = p.id
                            engine.preset = p
                        }) {
                            HStack {
                                Text(p.name)
                                if engine.preset.id == p.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.2.square")
                        Text(engine.preset.name)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .menuStyle(.borderlessButton)
                
                Spacer()
                
                if engine.mode != .standby {
                    Button(action: { engine.enterStandby(reason: .manual) }) {
                        Label("进入待机", systemImage: "moon.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            
            Spacer()
            
            // 核心大盘（分钟级倒计时与状态）
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(statusColor.opacity(0.12), lineWidth: 16)
                        .frame(width: 200, height: 200)
                    
                    VStack(spacing: 6) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(statusColor)
                        
                        Text(displayMinutes)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text(statusTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 核心大按钮：去休息 或 去工作
                switch engine.mode {
                case .working:
                    Button(action: { engine.startRest() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "cup.and.saucer.fill")
                            Text("去休息")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 180, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .clipShape(Capsule())
                    
                case .resting:
                    Button(action: { engine.startNextWorkCycle() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "brain.head.profile")
                            Text("开始工作")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 180, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .clipShape(Capsule())
                    
                case .standby:
                    Button(action: { engine.startWork() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("开始专注 (\(engine.preset.workMinutes)m)")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 190, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .clipShape(Capsule())
                }
            }
            
            Spacer()
            
            // 底部今日指标小卡片
            HStack(spacing: 14) {
                metricCard(
                    title: "今日专注",
                    value: TimeFormatter.formatNatural(seconds: Int(engine.todayWorkSeconds)),
                    icon: "brain.head.profile",
                    color: .orange
                )
                metricCard(
                    title: "今日休息",
                    value: TimeFormatter.formatNatural(seconds: Int(engine.todayRestSeconds)),
                    icon: "cup.and.saucer.fill",
                    color: .green
                )
                metricCard(
                    title: "完成轮次",
                    value: "\(engine.completedCycles) 轮",
                    icon: "repeat",
                    color: .accentColor
                )
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }
    
    // MARK: - 辅助组件
    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private var displayMinutes: String {
        switch engine.mode {
        case .working:
            return TimeFormatter.formatMinutesOnly(seconds: engine.currentSeconds)
        case .resting:
            return "\(max(1, engine.currentSeconds / 60))m"
        case .standby:
            return "\(engine.preset.workMinutes)m"
        }
    }
    
    private var statusTitle: String {
        switch engine.mode {
        case .working: return "沉浸工作中"
        case .resting: return "身心放松中"
        case .standby: return "就绪待机"
        }
    }
    
    private var statusColor: Color {
        switch engine.mode {
        case .working: return .orange
        case .resting: return .green
        case .standby: return .secondary
        }
    }
    
    private var statusIcon: String {
        switch engine.mode {
        case .working: return "brain.head.profile"
        case .resting: return "cup.and.saucer.fill"
        case .standby: return "leaf.fill"
        }
    }
}
