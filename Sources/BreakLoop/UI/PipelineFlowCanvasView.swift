import SwiftUI
import AppKit

/// 模块化循环流程画布（传统下拉选择式、输入+上下微调、零截断、居中闭环）
public struct PipelineFlowCanvasView: View {
    @Binding var preset: Preset
    @ObservedObject var engine: TimerEngine
    
    // 展开状态追踪
    @State private var expandedBlockIds: Set<UUID> = []
    @State private var hoveredConnectorId: String? = nil
    
    public init(preset: Binding<Preset>, engine: TimerEngine) {
        self._preset = preset
        self.engine = engine
    }
    
    private var isPresetRunning: Bool {
        engine.mode != .standby && engine.preset.id == preset.id
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 顶部方案标题栏
            headerSection
            
            Divider()
            
            // 流程图卡片序列与回路
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    if isPresetRunning {
                        lockBanner
                            .padding(.top, 14)
                    }
                    
                    // 起点微标
                    startBadge
                        .padding(.top, isPresetRunning ? 10 : 18)
                        .padding(.bottom, 6)
                    
                    // 居中垂直流程序列（宽度自适应，内边距充足，杜绝侧边栏截断）
                    VStack(spacing: 0) {
                        // 1. 顶部插入点（在第 1 个模块上方插入）
                        connectorView(
                            id: "top-before-0",
                            tooltip: "在第 1 步上方插入新模块",
                            insertAction: { newBlock in
                                insertBlock(newBlock, before: 0)
                            }
                        )
                        
                        ForEach(Array(preset.blocks.enumerated()), id: \.element.id) { index, block in
                            let isRunningThisBlock = isPresetRunning && engine.currentBlockIndex == index
                            let isExpanded = expandedBlockIds.contains(block.id)
                            
                            // 模块卡片（折叠 + 传统下拉与输入展开）
                            flowBlockCard(for: block, at: index, isRunning: isRunningThisBlock, isExpanded: isExpanded)
                                .id(block.id)
                            
                            // 中间连接线与纯粹插入（仅工作模块 / 休息模块）
                            if index < preset.blocks.count - 1 {
                                connectorView(
                                    id: "mid-after-\(index)",
                                    tooltip: "在第 \(index + 1) 步后插入新模块",
                                    insertAction: { newBlock in
                                        insertBlock(newBlock, after: index)
                                    }
                                )
                            }
                        }
                        
                        // 2. 末尾插入点（在最后一个模块下方、回到循环前插入）
                        connectorView(
                            id: "bottom-after-last",
                            tooltip: "在末尾追加新模块",
                            insertAction: { newBlock in
                                insertBlock(newBlock, after: preset.blocks.count - 1)
                            }
                        )
                        
                        // 结尾指向从头循环
                        loopBackDestinationNode
                        
                        // 打断恢复策略
                        interruptRecoverySection
                    }
                    .frame(maxWidth: 460)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color(NSColor.windowBackgroundColor).opacity(0.35))
        }
    }
    
    // MARK: - 顶部标题区
    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.down.right.fill")
                        .foregroundColor(.accentColor)
                    TextField("方案名称", text: $preset.name)
                        .font(.system(size: 15, weight: .bold))
                        .textFieldStyle(.plain)
                        .frame(maxWidth: 180)
                        .disabled(isPresetRunning)
                }
                
                Text("(\(preset.blocks.count) 步循环)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isPresetRunning {
                HStack(spacing: 8) {
                    Text("运行中 [\(engine.currentBlockIndex + 1)/\(preset.blocks.count)]")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                    
                    Button("待机") {
                        engine.enterStandby(reason: .manual)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 8) {
                    let isDefault = (PresetStore.shared.activePresetId == preset.id)
                    Button(action: {
                        PresetStore.shared.activePresetId = preset.id
                        if engine.mode == .standby {
                            engine.preset = preset
                        }
                    }) {
                        HStack(spacing: 4) {
                            if isDefault {
                                Image(systemName: "checkmark")
                            }
                            Text(isDefault ? "已设为下轮默认" : "应用为下轮默认")
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isDefault)
                    .help(isDefault ? "当前循环结束后将自动执行此方案" : "点击设为下轮默认方案（不打断当前计时）")
                    
                    Button(action: {
                        PresetStore.shared.activePresetId = preset.id
                        engine.preset = preset
                        engine.resetCycleToBeginning()
                        engine.startCurrentBlock()
                    }) {
                        Label("立即启用", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("立即结束当前进度，切换到此方案并从头开始")
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - 运行中锁定提示胶囊（置于循环起点上方）
    private var lockBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
            Text("当前方案正在运行中，模块卡片已锁定")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
    }
    
    // MARK: - 打断恢复策略配置
    private var interruptRecoverySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 13, weight: .semibold))
                Text("打断恢复策略")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary.opacity(0.85))
            }
            
            VStack(spacing: 8) {
                HStack {
                    Text("💻 专注被打断恢复:")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: $preset.workInterruptRecovery) {
                        ForEach(InterruptRecovery.allCases, id: \.self) { r in
                            Text(r.displayName(for: .work)).tag(r)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 175)
                }
                
                HStack {
                    Text("☕️ 休息被打断恢复:")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: $preset.restInterruptRecovery) {
                        ForEach(InterruptRecovery.allCases, id: \.self) { r in
                            Text(r.displayName(for: .rest)).tag(r)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 175)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .disabled(isPresetRunning)
        }
        .padding(.top, 16)
    }
    
    // MARK: - 循环起点微标（与从头循环采用一致的精致半透胶囊样式）
    private var startBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 11, weight: .bold))
            Text("循环起点")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundColor(.accentColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.accentColor.opacity(0.3), lineWidth: 1.2))
    }
    
    // MARK: - 模块卡片（折叠 + 传统下拉与输入上下微调）
    private func flowBlockCard(for block: FlowBlock, at index: Int, isRunning: Bool, isExpanded: Bool) -> some View {
        let isWork = block.type == .work
        let isStopwatch = block.timingMode == .stopwatch
        let themeColor: Color = isWork ? .blue : (isStopwatch ? .purple : .green)
        
        return VStack(alignment: .leading, spacing: 0) {
            // 1. 卡片摘要条（默认显示）
            HStack(spacing: 8) {
                // 序号圆形标
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(themeColor)
                    .frame(width: 20, height: 20)
                    .background(themeColor.opacity(0.14))
                    .clipShape(Circle())
                
                // 模块名与类型标签
                HStack(spacing: 6) {
                    TextField("模块名", text: binding(for: index).name)
                        .font(.system(size: 13, weight: .semibold))
                        .textFieldStyle(.plain)
                        .frame(minWidth: 70, maxWidth: 120)
                        .disabled(isPresetRunning)
                    
                    Text(isWork ? "专注" : (isStopwatch ? "休息(自由)" : "休息"))
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(themeColor.opacity(0.12))
                        .foregroundColor(themeColor)
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                // 极简时长/模式徽章
                if isStopwatch {
                    if block.enableIncrementalChimes {
                        Text("正计时 (\(block.chimeStartMinutes)~\(block.chimeEndMinutes)m报时)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.purple)
                    } else {
                        Text("自由正计时 (纯净)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.purple)
                    }
                } else {
                    if let sec = block.countdownSeconds, sec > 0 {
                        Text("\(sec) 秒")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(block.durationMinutes) 分钟")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                
                // 运行态指示
                if isRunning {
                    Text(TimeFormatter.format(seconds: engine.currentSeconds))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                } else if isPresetRunning {
                    Button("跳至此步") {
                        engine.jumpToBlock(index: index)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                
                // 操作菜单（在此上方 / 下方插入专注模块 / 休息模块）
                Menu {
                    Section("向上方插入") {
                        Button(action: {
                            insertBlock(FlowBlock.makeWork(), before: index)
                        }) {
                            Label("在此上方插入专注模块", systemImage: "laptopcomputer")
                        }
                        Button(action: {
                            insertBlock(FlowBlock.makeCountdownRest(name: "休息", minutes: 5), before: index)
                        }) {
                            Label("在此上方插入休息模块", systemImage: "cup.and.saucer.fill")
                        }
                    }
                    
                    Section("向下方插入") {
                        Button(action: {
                            insertBlock(FlowBlock.makeWork(), after: index)
                        }) {
                            Label("在此下方插入专注模块", systemImage: "laptopcomputer")
                        }
                        Button(action: {
                            insertBlock(FlowBlock.makeCountdownRest(name: "休息", minutes: 5), after: index)
                        }) {
                            Label("在此下方插入休息模块", systemImage: "cup.and.saucer.fill")
                        }
                    }
                    
                    Divider()
                    
                    Button(action: { duplicateBlock(at: index) }) {
                        Label("复制模块", systemImage: "doc.on.doc")
                    }
                    Button(action: {
                        guard index > 0 else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            preset.blocks.swapAt(index, index - 1)
                        }
                    }) {
                        Label("上移", systemImage: "arrow.up")
                    }
                    .disabled(index == 0)
                    
                    Button(action: {
                        guard index < preset.blocks.count - 1 else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            preset.blocks.swapAt(index, index + 1)
                        }
                    }) {
                        Label("下移", systemImage: "arrow.down")
                    }
                    .disabled(index >= preset.blocks.count - 1)
                    
                    Divider()
                    
                    Button(role: .destructive, action: { deleteBlock(at: index) }) {
                        if preset.blocks.count <= 1 {
                            Label("删除模块 (至少保留 1 个)", systemImage: "trash")
                        } else {
                            Label("删除模块", systemImage: "trash")
                        }
                    }
                    .disabled(preset.blocks.count <= 1)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundColor(isPresetRunning ? .secondary.opacity(0.3) : .secondary)
                        .frame(width: 18, height: 18)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .disabled(isPresetRunning)
                .help(isPresetRunning ? "当前方案正在运行中，不可增删或排序模块" : "更多操作")
                
                // 展开/折叠切换按钮
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isExpanded {
                            expandedBlockIds.remove(block.id)
                        } else {
                            expandedBlockIds.insert(block.id)
                        }
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            
            // 2. 详细配置面板（仅在展开时显示，类型固定，工作与休息职责分明）
            if isExpanded {
                Divider()
                    .padding(.horizontal, 8)
                
                Group {
                    if isWork {
                    // 💻 专注模块配置（固定倒计时，无歧义，专注高效）
                    VStack(alignment: .leading, spacing: 10) {
                        // (1) 专注时长与稍后提醒
                        HStack(spacing: 12) {
                            HStack(spacing: 6) {
                                Text("专注时长:")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                TextField("", value: binding(for: index).durationMinutes, formatter: Self.intFormatter)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 48)
                                
                                Stepper("", value: binding(for: index).durationMinutes, in: 1...480)
                                    .labelsHidden()
                                
                                Text("分钟")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Text("稍后提醒:")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                TextField("", value: binding(for: index).snoozeMinutes, formatter: Self.intFormatter)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 44)
                                
                                Stepper("", value: binding(for: index).snoozeMinutes, in: 1...60)
                                    .labelsHidden()
                                
                                Text("分钟")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // (2) 提示音设置
                        HStack(spacing: 6) {
                            Text("到点提示音:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Picker("", selection: binding(for: index).soundName) {
                                ForEach(SoundManager.shared.allAvailableSounds()) { option in
                                    Text(option.displayName).tag(option.identifier)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(minWidth: 165)
                            
                            Button(action: {
                                SoundManager.shared.preview(soundName: preset.blocks[index].soundName)
                            }) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("试听声音")
                            
                            Spacer()
                        }
                        
                        // (3) 提示文案（通栏宽框）
                        HStack(spacing: 6) {
                            Text("提示文案:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            TextField("如：专注结束，起身活动一下吧...", text: binding(for: index).message)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity)
                        }
                        
                        // (4) 结束后自动推进
                        Toggle("专注结束后自动推进到下一步", isOn: binding(for: index).autoAdvance)
                            .font(.system(size: 12))
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.02))
                } else {
                    // ☕️ 休息模块配置（仅在此提供 倒计时 / 正计时 形式选择）
                    VStack(alignment: .leading, spacing: 10) {
                        // (1) 休息形式
                        HStack(spacing: 6) {
                            Text("休息形式:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Picker("", selection: Binding(
                                get: { block.timingMode },
                                set: { newMode in
                                    binding(for: index).timingMode.wrappedValue = newMode
                                    if newMode == .countdown {
                                        binding(for: index).name.wrappedValue = "休息"
                                    } else {
                                        binding(for: index).name.wrappedValue = "休息(自由)"
                                        binding(for: index).autoAdvance.wrappedValue = false
                                    }
                                }
                            )) {
                                Text("倒计时 (固定时长)").tag(BlockTimingMode.countdown)
                                Text("自由休息 (正计时)").tag(BlockTimingMode.stopwatch)
                            }
                            .pickerStyle(.menu)
                            .frame(minWidth: 165)
                            
                            Spacer()
                        }
                        
                        if block.timingMode == .countdown {
                            // (2) 倒计时专属：休息时长 与 稍后提醒（同行对齐，节奏同专注模块）
                            HStack(spacing: 12) {
                                HStack(spacing: 6) {
                                    Text("休息时长:")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)
                                    
                                    TextField("", value: Binding(
                                        get: { block.durationMinutes },
                                        set: {
                                            binding(for: index).durationMinutes.wrappedValue = max(1, min(240, $0))
                                            binding(for: index).countdownSeconds.wrappedValue = nil
                                        }
                                    ), formatter: Self.intFormatter)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 48)
                                    
                                    Stepper("", value: Binding(
                                        get: { block.durationMinutes },
                                        set: {
                                            binding(for: index).durationMinutes.wrappedValue = $0
                                            binding(for: index).countdownSeconds.wrappedValue = nil
                                        }
                                    ), in: 1...240)
                                    .labelsHidden()
                                    
                                    Text("分钟")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 6) {
                                    Text("稍后提醒:")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)
                                    
                                    TextField("", value: binding(for: index).snoozeMinutes, formatter: Self.intFormatter)
                                        .textFieldStyle(.roundedBorder)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 44)
                                    
                                    Stepper("", value: binding(for: index).snoozeMinutes, in: 1...60)
                                        .labelsHidden()
                                    
                                    Text("分钟")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // (3) 到点提示音（独立通栏，绝不挤压截断）
                            HStack(spacing: 6) {
                                Text("到点提示音:")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Picker("", selection: binding(for: index).soundName) {
                                    ForEach(SoundManager.shared.allAvailableSounds()) { option in
                                        Text(option.displayName).tag(option.identifier)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(minWidth: 165)
                                
                                Button(action: {
                                    SoundManager.shared.preview(soundName: preset.blocks[index].soundName)
                                }) {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                                .help("试听声音")
                                
                                Spacer()
                            }
                            
                            // (4) 提示文案
                            HStack(spacing: 6) {
                                Text("提示文案:")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("如：看远方 20 秒、喝水深呼吸...", text: binding(for: index).message)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity)
                            }
                            
                            // (5) 自动推进
                            Toggle("休息结束后自动推进到下一步", isOn: binding(for: index).autoAdvance)
                                .font(.system(size: 12))
                        } else {
                            // (2) 正计时自由休息专属：阶段轻报时
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("开启阶段轻报时（纯声音）", isOn: binding(for: index).enableIncrementalChimes)
                                    .font(.system(size: 12))
                                
                                if block.enableIncrementalChimes {
                                    HStack(spacing: 14) {
                                        HStack(spacing: 6) {
                                            Text("起始阈值:")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.secondary)
                                            TextField("", value: Binding(
                                                get: { block.chimeStartMinutes },
                                                set: {
                                                    let val = max(1, min(240, $0))
                                                    binding(for: index).chimeStartMinutes.wrappedValue = val
                                                    if binding(for: index).chimeEndMinutes.wrappedValue < val {
                                                        binding(for: index).chimeEndMinutes.wrappedValue = val
                                                    }
                                                }
                                            ), formatter: Self.intFormatter)
                                                .textFieldStyle(.roundedBorder)
                                                .multilineTextAlignment(.trailing)
                                                .frame(width: 48)
                                            Stepper("", value: Binding(
                                                get: { block.chimeStartMinutes },
                                                set: {
                                                    binding(for: index).chimeStartMinutes.wrappedValue = $0
                                                    if binding(for: index).chimeEndMinutes.wrappedValue < $0 {
                                                        binding(for: index).chimeEndMinutes.wrappedValue = $0
                                                    }
                                                }
                                            ), in: 1...240)
                                                .labelsHidden()
                                            Text("分钟")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        HStack(spacing: 6) {
                                            Text("截止阈值:")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.secondary)
                                            TextField("", value: Binding(
                                                get: { max(block.chimeStartMinutes, block.chimeEndMinutes) },
                                                set: { binding(for: index).chimeEndMinutes.wrappedValue = max(block.chimeStartMinutes, min(480, $0)) }
                                            ), formatter: Self.intFormatter)
                                                .textFieldStyle(.roundedBorder)
                                                .multilineTextAlignment(.trailing)
                                                .frame(width: 48)
                                            Stepper("", value: Binding(
                                                get: { max(block.chimeStartMinutes, block.chimeEndMinutes) },
                                                set: { binding(for: index).chimeEndMinutes.wrappedValue = max(block.chimeStartMinutes, $0) }
                                            ), in: 2...480)
                                                .labelsHidden()
                                            Text("分钟")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                    }
                                    
                                    HStack(spacing: 6) {
                                        Text("到达截止阈值时:")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.secondary)
                                        Picker("", selection: binding(for: index).chimeCutoffAction) {
                                            ForEach(CutoffAction.allCases, id: \.self) { action in
                                                Text(action.displayName).tag(action)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                        .frame(minWidth: 175)
                                    }
                                    
                                    Text("💡 起始至截止区间内，每 10 分钟轻敲钟提示进度，到期执行截止动作。")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else {
                                    Text("当前为纯净自由休息模式，休息期间零弹窗零打扰，离开屏幕安心放松。")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            
                            // (3) 报时声音
                            HStack(spacing: 6) {
                                Text("报时声音:")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Picker("", selection: binding(for: index).soundName) {
                                    ForEach(SoundManager.shared.allAvailableSounds()) { option in
                                        Text(option.displayName).tag(option.identifier)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(minWidth: 165)
                                
                                Button(action: {
                                    SoundManager.shared.preview(soundName: preset.blocks[index].soundName)
                                }) {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                                .help("试听声音")
                                
                                Spacer()
                            }
                            
                            // (4) 截止弹窗文案
                            if block.enableIncrementalChimes {
                                HStack(spacing: 6) {
                                    Text("截止弹窗文案:")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)
                                    TextField("准备开始下一轮专注", text: binding(for: index).message)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12))
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.02))
                }
            }
            .disabled(isPresetRunning)
        }
    }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: isRunning ? themeColor.opacity(0.22) : Color.black.opacity(0.03), radius: isRunning ? 6 : 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isRunning ? themeColor : Color.primary.opacity(0.08), lineWidth: isRunning ? 1.5 : 1)
        )
    }
    
    // MARK: - 居中连线与侧偏插入（主轴贯穿无遮挡，向右微偏悬停显现）
    private func connectorView(id: String, tooltip: String, insertAction: @escaping (FlowBlock) -> Void) -> some View {
        let isHovered = (hoveredConnectorId == id)
        
        return ZStack {
            // 纯粹干净的垂直连接线（保持笔直贯穿，无重叠阻断）
            Rectangle()
                .fill(isHovered && !isPresetRunning ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.12))
                .frame(width: 1.5, height: 26)
            
            if !isPresetRunning {
                // 悬停时显现的右侧微型分支引导线
                Rectangle()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: 12, height: 1.2)
                    .offset(x: 6)
                    .opacity(isHovered ? 1.0 : 0.0)
                
                // 方案 1：向右偏离中心线的侧挂式插入按钮（限定圆形，悬停才高亮显现）
                Menu {
                    Button(action: {
                        insertAction(FlowBlock.makeWork())
                    }) {
                        Label("插入专注模块", systemImage: "laptopcomputer")
                    }
                    
                    Button(action: {
                        insertAction(FlowBlock.makeCountdownRest(name: "休息", minutes: 5))
                    }) {
                        Label("插入休息模块", systemImage: "cup.and.saucer.fill")
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(NSColor.controlBackgroundColor))
                            .frame(width: 20, height: 20)
                            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                    .overlay(
                        Circle().stroke(Color.accentColor.opacity(0.6), lineWidth: 1.2)
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20, height: 20)
                .contentShape(Circle())
                .offset(x: 22)
                .opacity(isHovered ? 1.0 : 0.0)
                .help(tooltip)
            }
        }
        .frame(width: 80, height: 26)
        .contentShape(Rectangle())
        .onHover { h in
            guard !isPresetRunning else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredConnectorId = h ? id : nil
            }
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - 居中闭环“从头循环”节点
    private var loopBackDestinationNode: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.4))
                .frame(width: 2, height: 14)
            
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.accentColor.opacity(0.6))
                .padding(.bottom, 4)
            
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .bold))
                Text("从头循环")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.accentColor.opacity(0.3), lineWidth: 1.2))
        }
        .padding(.top, 2)
    }
    
    // MARK: - 辅助计算
    private static let intFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 1
        f.maximum = 999
        return f
    }()
    
    private func targetText(for block: FlowBlock) -> String {
        guard let s = block.targetSeconds, s > 0 else { return "无限制" }
        if s < 60 { return "\(s)秒" }
        return "\(s / 60)分钟"
    }
    
    private func binding(for index: Int) -> Binding<FlowBlock> {
        Binding(
            get: { preset.blocks[index] },
            set: { preset.blocks[index] = $0 }
        )
    }
    
    private func insertBlock(_ block: FlowBlock, before index: Int) {
        let safeIndex = max(0, min(index, preset.blocks.count))
        withAnimation(.easeInOut(duration: 0.2)) {
            preset.blocks.insert(block, at: safeIndex)
        }
        if engine.preset.id == preset.id {
            engine.preset = preset
        }
    }
    
    private func insertBlock(_ block: FlowBlock, after index: Int) {
        let targetIndex = index + 1
        withAnimation(.easeInOut(duration: 0.2)) {
            if targetIndex >= preset.blocks.count {
                preset.blocks.append(block)
            } else {
                preset.blocks.insert(block, at: targetIndex)
            }
        }
        if engine.preset.id == preset.id {
            engine.preset = preset
        }
    }
    
    private func duplicateBlock(at index: Int) {
        guard index >= 0 && index < preset.blocks.count else { return }
        var copy = preset.blocks[index]
        copy.id = UUID()
        copy.name = "\(copy.name) (副本)"
        insertBlock(copy, after: index)
    }
    
    private func deleteBlock(at index: Int) {
        guard preset.blocks.count > 1 else { return }
        guard index >= 0 && index < preset.blocks.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            _ = preset.blocks.remove(at: index)
        }
        if engine.preset.id == preset.id {
            engine.preset = preset
        }
    }
}
