import SwiftUI

/// 菜单栏下拉内容（纯粹极简：二元工作/休息切换 + 待机出口）
public struct MenuBarContent: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var presetStore = PresetStore.shared
    
    var onOpenStats: () -> Void
    var onOpenSettings: () -> Void
    var onQuit: () -> Void
    
    public init(
        engine: TimerEngine,
        onOpenStats: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.engine = engine
        self.onOpenStats = onOpenStats
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
    }
    
    public var body: some View {
        VStack {
            // MARK: - 核心二元状态操作
            switch engine.mode {
            case .working:
                // 工作状态下：唯一的主要动作就是“去休息”
                Button(action: { engine.startRest() }) {
                    Label("进入休息", systemImage: "cup.and.saucer.fill")
                }
                
            case .resting:
                // 休息状态下：唯一的主要动作就是“去工作”
                Button(action: { engine.startNextWorkCycle() }) {
                    Label("开始工作 (\(engine.preset.workMinutes) 分钟)", systemImage: "brain.head.profile")
                }
                
            case .standby:
                // 待机状态下：启动工作
                Button(action: { engine.startWork() }) {
                    Label("开始工作 (\(engine.preset.workMinutes) 分钟)", systemImage: "play.circle.fill")
                }
            }
            
            // 待机出口（仅在工作中或休息中时展示）
            if engine.mode != .standby {
                Button(action: { engine.enterStandby(reason: .manual) }) {
                    Label("进入待机 (停止计时)", systemImage: "moon.fill")
                }
            }
            
            Divider()
            
            // 预设快速切换
            Menu("切换预设") {
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
            }
            
            Divider()
            
            // 历史回顾与设置
            Button(action: onOpenStats) {
                Label("数据统计与回顾...", systemImage: "chart.bar.xaxis")
            }
            
            Button(action: onOpenSettings) {
                Label("偏好设置与预设库...", systemImage: "gearshape")
            }
            
            Divider()
            
            // 今日累计简单概述
            Text("今日专注 \(TimeFormatter.formatNatural(seconds: Int(engine.todayWorkSeconds))) · 休息 \(TimeFormatter.formatNatural(seconds: Int(engine.todayRestSeconds)))")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            Button("退出 BreakLoop", action: onQuit)
                .keyboardShortcut("q")
        }
    }
}
