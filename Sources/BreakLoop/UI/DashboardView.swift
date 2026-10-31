import SwiftUI

/// 极简现代扁平仪表盘（极简阶段展示、低功耗、零说明文字赘述）
public struct DashboardView: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var presetStore = PresetStore.shared
    
    public init(engine: TimerEngine) {
        self.engine = engine
    }
    
    public var body: some View {
        ZStack {
            // 背景层：轻量渐变（无繁重高斯模糊）
            backgroundGlow
            
            VStack(spacing: 0) {
                // 顶部：当前方案名 + 待机出口
                topBar
                    .padding(.horizontal, 32)
                    .padding(.top, 20)
                
                Spacer()
                
                // 中央核心计时与控制
                VStack(spacing: 18) {
                    // 状态图标
                    ZStack {
                        Circle()
                            .fill(themeColor.opacity(0.12))
                            .frame(width: 110, height: 110)
                        
                        if engine.mode == .standby {
                            BrandLogoView(size: 46, showGlow: true)
                        } else {
                            Image(systemName: mainSymbol)
                                .font(.system(size: 42, weight: .medium))
                                .foregroundColor(themeColor)
                        }
                    }
                    
                    // 分钟倒计时与当前阶段简标
                    VStack(spacing: 4) {
                        Text(displayMinutes)
                            .font(.system(size: 60, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text(stateTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(themeColor)
                    }
                    
                    // 核心阶段指示轨（横向直观节点：已过/当前/未来）
                    horizontalStageTrack
                        .padding(.top, 6)
                    
                    // 核心操作按钮组（去休息/去工作 + 跳过）
                    actionControlGroup
                        .padding(.top, 10)
                }
                
                Spacer()
                
                // 底部轻量指标
                HStack(spacing: 14) {
                    summaryPill(
                        title: "今日专注",
                        value: TimeFormatter.formatNatural(seconds: Int(engine.todayWorkSeconds)),
                        icon: "laptopcomputer",
                        color: .blue
                    )
                    summaryPill(
                        title: "今日休息",
                        value: TimeFormatter.formatNatural(seconds: Int(engine.todayRestSeconds)),
                        icon: "cup.and.saucer.fill",
                        color: .green
                    )
                    summaryPill(
                        title: "循环轮次",
                        value: "\(engine.completedCycles) 轮",
                        icon: "arrow.triangle.2.circlepath",
                        color: .purple
                    )
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
    }
    
    // MARK: - 顶部工具栏（方案直接切换 + 待机出口）
    private var topBar: some View {
        HStack {
            Menu {
                ForEach(presetStore.presets) { preset in
                    Button(action: {
                        presetStore.activePresetId = preset.id
                        engine.preset = preset
                    }) {
                        HStack {
                            Text("\(preset.name) (\(preset.blocks.count)步)")
                            if engine.preset.id == preset.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.stack.3d.down.right.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text(engine.preset.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .help("点击直接切换预设方案")
            
            Spacer()
            
            if engine.mode != .standby {
                Button(action: { engine.enterStandby(reason: .manual) }) {
                    HStack(spacing: 5) {
                        Image(systemName: "moon.fill")
                        Text("进入待机")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - 横向直观节点轨（支持直接点击任意阶段秒速切换）
    private var horizontalStageTrack: some View {
        HStack(spacing: 6) {
            ForEach(Array(engine.preset.blocks.enumerated()), id: \.element.id) { index, block in
                let isCurrent = (engine.mode != .standby && engine.currentBlockIndex == index)
                let isDone = (engine.mode != .standby && engine.currentBlockIndex > index)
                let blockColor: Color = block.type == .work ? .blue : (block.timingMode == .stopwatch ? .purple : .green)
                
                Button(action: {
                    engine.jumpToBlock(index: index)
                }) {
                    HStack(spacing: 4) {
                        if isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        Text(block.name)
                            .font(.system(size: 11, weight: isCurrent ? .bold : .medium))
                            .foregroundColor(isCurrent ? blockColor : (isDone ? .secondary : .secondary.opacity(0.7)))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        isCurrent ? blockColor.opacity(0.14) : (isDone ? Color.primary.opacity(0.04) : Color.clear)
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(isCurrent ? blockColor : Color.primary.opacity(0.12), lineWidth: isCurrent ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
                .help("点击直达此步骤：\(block.name)")
                
                if index < engine.preset.blocks.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.35))
                }
            }
        }
    }
    
    // MARK: - 核心操作按钮组（支持开始专注、直接休息与跳过）
    private var actionControlGroup: some View {
        HStack(spacing: 12) {
            Group {
                switch engine.mode {
                case .working:
                    Button(action: { engine.advanceToNextBlock() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "cup.and.saucer.fill")
                            Text("进入休息")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 150, height: 42)
                        .background(Color.green)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    
                case .resting:
                    Button(action: { engine.advanceToNextBlock() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "laptopcomputer")
                            Text("开始专注")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 150, height: 42)
                        .background(Color.blue)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    
                case .standby:
                    HStack(spacing: 12) {
                        Button(action: { engine.startCurrentBlock() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                Text("开始专注")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 140, height: 42)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { engine.startRest() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "cup.and.saucer.fill")
                                Text("直接休息")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("立即开启休息流程")
                        
                        if engine.currentBlockIndex > 0 {
                            Button(action: { engine.resetCycleToBeginning() }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, height: 42)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("重置整轮大循环（回到第 1 步）")
                        }
                    }
                }
            }
            
            // 暂停/继续控制
            if engine.mode != .standby {
                Button(action: { engine.togglePause() }) {
                    Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(engine.isPaused ? .orange : .primary)
                        .frame(width: 40, height: 42)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(engine.isPaused ? "继续计时" : "临时暂停（超时自动转待机并回溯）")
            }
            
            // 跳过本步
            if engine.mode != .standby {
                Button(action: { engine.advanceToNextBlock() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 40, height: 42)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("跳过本步")
            }
        }
    }
    
    // MARK: - 底部指标
    private func summaryPill(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    // MARK: - 轻量背景
    private var backgroundGlow: some View {
        LinearGradient(
            colors: [themeColor.opacity(0.08), Color.clear],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }
    
    // MARK: - 动态计算属性
    private var displayMinutes: String {
        switch engine.mode {
        case .working:
            return TimeFormatter.formatMinutesOnly(seconds: engine.currentSeconds)
        case .resting:
            if let block = engine.currentBlock, block.timingMode == .countdown {
                return TimeFormatter.formatMinutesOnly(seconds: engine.currentSeconds)
            } else {
                return "+\(max(1, engine.currentSeconds / 60))m"
            }
        case .standby:
            return "\(engine.currentBlock?.durationMinutes ?? 20)m"
        }
    }
    
    private var stateTitle: String {
        let blockName = engine.currentBlock?.name ?? "专注"
        let total = max(1, engine.preset.blocks.count)
        let step = engine.currentBlockIndex + 1
        
        if engine.isPaused {
            return "[\(step)/\(total)] \(blockName) · 暂停中"
        }
        
        switch engine.mode {
        case .working:
            return "[\(step)/\(total)] \(blockName)"
        case .resting:
            return "[\(step)/\(total)] \(blockName)"
        case .standby:
            return "待命中 · 下一步: \(blockName)"
        }
    }
    
    private var mainSymbol: String {
        if engine.isPaused { return "pause.circle.fill" }
        guard let block = engine.currentBlock else { return "leaf.fill" }
        switch engine.mode {
        case .working: return "laptopcomputer"
        case .resting:
            return (block.timingMode == .stopwatch) ? "figure.walk" : "cup.and.saucer.fill"
        case .standby: return "leaf.fill"
        }
    }
    
    private var themeColor: Color {
        if engine.isPaused { return .orange }
        guard let block = engine.currentBlock else { return .accentColor }
        switch engine.mode {
        case .working: return .blue
        case .resting:
            return (block.timingMode == .stopwatch) ? .purple : .green
        case .standby: return .accentColor
        }
    }
}
