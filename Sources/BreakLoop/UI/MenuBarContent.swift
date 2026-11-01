import SwiftUI

/// 极简直观的菜单栏下拉交互（以当前进度与核心动作为首，无冗余文字）
public struct MenuBarContent: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var presetStore = PresetStore.shared
    @ObservedObject var soundManager = SoundManager.shared
    
    var onOpenDashboard: () -> Void
    var onQuit: () -> Void
    
    public init(
        engine: TimerEngine,
        onOpenDashboard: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.engine = engine
        self.onOpenDashboard = onOpenDashboard
        self.onQuit = onQuit
    }
    
    public var body: some View {
        VStack {
            // 1. 顶部：极简阶段进度条
            Text(stageSummaryText)
                .font(.headline)
            
            if let next = engine.nextBlock, engine.mode != .standby {
                Text("下一步: \(next.name) (\(next.durationMinutes)m)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // 2. 核心快捷动作（统一按计划流转，杜绝重复）
            switch engine.mode {
            case .working, .resting:
                Button(action: { engine.advanceToNextBlock() }) {
                    Label("推进至下一步", systemImage: "forward.end.fill")
                }
                
            case .standby:
                Button(action: { engine.startCurrentBlock() }) {
                    Label(actionButtonTitle, systemImage: "play.fill")
                }
            }
            
            // 运行中的流转控制
            if engine.mode != .standby {
                Button(action: { engine.togglePause() }) {
                    Label(engine.isPaused ? "继续计时" : "临时暂停", systemImage: engine.isPaused ? "play.fill" : "pause.fill")
                }
                
                Button(action: { engine.enterStandby(reason: .manual) }) {
                    Label("进入待机", systemImage: "moon.fill")
                }
            }
            
            Divider()
            
            // 3. 方案切换（运行中锁定，待机时可自由切换）
            Menu("方案: \(engine.preset.name)\(engine.mode != .standby ? " (运行中)" : "")") {
                ForEach(presetStore.presets) { p in
                    Button(action: {
                        presetStore.activePresetId = p.id
                        engine.preset = p
                    }) {
                        HStack {
                            Text("\(p.name) (\(p.blocks.count)步)")
                            if engine.preset.id == p.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            .disabled(engine.mode != .standby)
            
            // 4. 静音模式勾选（macOS 原生菜单勾选标记）
            Toggle("静音模式", isOn: $soundManager.isMuted)
                .keyboardShortcut("m")
            
            // 5. 打开主面板
            Button("打开仪表台") {
                onOpenDashboard()
            }
            .keyboardShortcut("o")
            
            Divider()
            
            // 5. 退出
            Button("退出 BreakLoop", action: onQuit)
                .keyboardShortcut("q")
        }
    }
    
    private var actionButtonTitle: String {
        switch engine.mode {
        case .working, .resting:
            return "推进至下一步"
        case .standby:
            let isNextWork = (engine.currentBlock?.type ?? .work) == .work
            return isNextWork ? "开始专注" : "开始休息"
        }
    }
    
    private var stageSummaryText: String {
        let blockName = engine.currentBlock?.name ?? "专注"
        let total = max(1, engine.preset.blocks.count)
        let step = engine.currentBlockIndex + 1
        
        switch engine.mode {
        case .working:
            return "[\(step)/\(total)] \(blockName) · 剩余 \(TimeFormatter.formatMinutesOnly(seconds: engine.currentSeconds))"
        case .resting:
            if let block = engine.currentBlock, block.timingMode == .countdown {
                return "[\(step)/\(total)] \(blockName) · 剩余 \(TimeFormatter.formatMinutesOnly(seconds: engine.currentSeconds))"
            } else {
                let mins = max(0, engine.currentSeconds / 60)
                return "[\(step)/\(total)] \(blockName) · 已休 \(mins)m"
            }
        case .standby:
            let nextBlock = engine.currentBlock ?? engine.preset.blocks.first
            return "待机中 · 下一步: [\(step)/\(total)] \(nextBlock?.name ?? "")"
        }
    }
}
