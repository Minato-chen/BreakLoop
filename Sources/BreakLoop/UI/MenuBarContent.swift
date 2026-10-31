import SwiftUI

/// 极简直观的菜单栏下拉交互（以当前进度与核心动作为首，无冗余文字）
public struct MenuBarContent: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var presetStore = PresetStore.shared
    
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
            
            // 2. 核心快捷动作（规范文本，杜绝“去工作 (工作)”同义重复）
            switch engine.mode {
            case .working:
                Button(action: { engine.advanceToNextBlock() }) {
                    Label(actionButtonTitle, systemImage: "cup.and.saucer.fill")
                }
                
            case .resting:
                Button(action: { engine.advanceToNextBlock() }) {
                    Label(actionButtonTitle, systemImage: "laptopcomputer")
                }
                
            case .standby:
                Button(action: { engine.startCurrentBlock() }) {
                    Label(actionButtonTitle, systemImage: "play.fill")
                }
            }
            
            // 运行中的流转控制
            if engine.mode != .standby {
                Button(action: { engine.advanceToNextBlock() }) {
                    Label("跳过本步", systemImage: "forward.fill")
                }
                
                Button(action: { engine.enterStandby(reason: .manual) }) {
                    Label("进入待机", systemImage: "moon.fill")
                }
            }
            
            Divider()
            
            // 3. 方案切换
            Menu("方案: \(engine.preset.name)") {
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
            
            // 4. 打开主面板
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
        case .working:
            if let name = engine.nextBlock?.name, name != "休息" && name != "休息放松" && !name.isEmpty {
                return "进入休息 · \(name)"
            }
            return "进入休息"
        case .resting:
            if let name = engine.nextBlock?.name, name != "工作" && name != "工作专注" && !name.isEmpty {
                return "开始专注 · \(name)"
            }
            return "开始专注"
        case .standby:
            if let name = engine.currentBlock?.name, name != "工作" && name != "工作专注" && !name.isEmpty {
                return "开始 · \(name)"
            }
            return "开始专注"
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
                return "[\(step)/\(total)] \(blockName) · 已休 \(max(1, engine.currentSeconds / 60))m"
            }
        case .standby:
            return "待机中 · 下一步: [1/\(total)] \(engine.preset.blocks.first?.name ?? "")"
        }
    }
}
