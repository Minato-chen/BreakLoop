import SwiftUI

/// 增强型预设管理与偏好设置视图（支持全面增删改、深度自定义与通用选项）
public struct SettingsView: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var presetStore = PresetStore.shared
    
    @AppStorage("BreakLoop.LaunchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("BreakLoop.ShowDesktopWidget") private var showDesktopWidget: Bool = true
    @AppStorage("BreakLoop.MenuBarShowTime") private var menuBarShowTime: Bool = false
    
    @State private var selectedPresetId: UUID
    @State private var selectedTab: SettingsTab
    
    public enum SettingsTab: Hashable {
        case general
        case presets
        case hotkeys
        case about
    }
    
    public init(engine: TimerEngine, defaultTab: SettingsTab = .general) {
        self.engine = engine
        _selectedPresetId = State(initialValue: engine.preset.id)
        _selectedTab = State(initialValue: defaultTab)
    }
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tag(SettingsTab.general)
                .tabItem {
                    Label("通用设置", systemImage: "gearshape")
                }
            
            presetsManagerTab
                .tag(SettingsTab.presets)
                .tabItem {
                    Label("预设方案管理", systemImage: "slider.horizontal.3")
                }
            
            hotkeysTab
                .tag(SettingsTab.hotkeys)
                .tabItem {
                    Label("全局快捷键", systemImage: "keyboard")
                }
            
            aboutTab
                .tag(SettingsTab.about)
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 通用设置
    private var generalTab: some View {
        Form {
            Section {
                Toggle("开机自动启动 BreakLoop", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        LaunchAtLogin.setEnabled(newValue)
                    }
                
                Toggle("菜单栏图标旁显示分钟倒计时（关闭后仅显示静止小图标）", isOn: $menuBarShowTime)
            } header: {
                Text("启动与显示偏好").font(.headline)
            }
            
            Section {
                Stepper(value: $engine.preset.idleMinutes, in: 1...60) {
                    HStack {
                        Text("键鼠离开自动待机阈值:")
                        Spacer()
                        Text("\(engine.preset.idleMinutes) 分钟")
                            .foregroundColor(.secondary)
                    }
                }
                
                Stepper(value: $engine.preset.restMaxMinutes, in: 5...120) {
                    HStack {
                        Text("休息超上限自动待机兜底:")
                        Spacer()
                        Text("\(engine.preset.restMaxMinutes) 分钟")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("空闲与防沉迷保护").font(.headline)
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - 预设库全面管理 (增删改)
    private var presetsManagerTab: some View {
        HSplitView {
            // 左侧预设列表
            VStack(spacing: 0) {
                // 顶部操作栏（显著的添加按钮）
                HStack {
                    Text("预设方案 (\(presetStore.presets.count))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: createNewPreset) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("新增预设")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                List(selection: $selectedPresetId) {
                    ForEach(presetStore.presets) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .fontWeight(preset.id == selectedPresetId ? .semibold : .regular)
                                Text("\(preset.workMinutes)m 工作 · \(preset.mode.rawValue)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if engine.preset.id == preset.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                                    .font(.caption)
                            }
                        }
                        .tag(preset.id)
                    }
                }
                
                Divider()
                
                // 底部操作栏（删除 + 上移 + 下移 + 应用）
                HStack(spacing: 6) {
                    Button(action: deleteSelectedPreset) {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(presetStore.presets.count <= 1)
                    .help("删除预设")
                    
                    Button(action: { presetStore.moveUp(id: selectedPresetId) }) {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("上移排序")
                    
                    Button(action: { presetStore.moveDown(id: selectedPresetId) }) {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("下移排序")
                    
                    Spacer()
                    
                    Button("应用此预设") {
                        if let selected = presetStore.presets.first(where: { $0.id == selectedPresetId }) {
                            presetStore.activePresetId = selected.id
                            engine.preset = selected
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(engine.preset.id == selectedPresetId)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
            }
            .frame(minWidth: 200, maxWidth: 240)
            
            // 右侧预设详情编辑
            if let selectedBinding = bindingForSelectedPreset() {
                Form {
                    Section {
                        TextField("预设名称", text: selectedBinding.name)
                        
                        Picker("工作流模式", selection: selectedBinding.mode) {
                            Text("自由循环 (Continuous)").tag(FlowMode.continuousLoop)
                            Text("番茄钟 (Pomodoro)").tag(FlowMode.pomodoro)
                            Text("固定间隔 (Interval)").tag(FlowMode.intervalTimer)
                            Text("自定义模式").tag(FlowMode.custom)
                        }
                    } header: {
                        Text("基础信息").font(.headline)
                    }
                    
                    Section {
                        Stepper(value: selectedBinding.workMinutes, in: 1...120) {
                            HStack {
                                Text("工作时长:")
                                Spacer()
                                Text("\(selectedBinding.wrappedValue.workMinutes) 分钟")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Toggle("工作结束后自动进入休息", isOn: selectedBinding.autoStartRest)
                        
                        Picker("休息计时形式", selection: selectedBinding.restTimingMode) {
                            Text("自由正计时 (放松无压力)").tag(RestTimingMode.stopwatch)
                            Text("严格倒计时 (番茄钟式)").tag(RestTimingMode.countdown)
                        }
                        
                        if selectedBinding.wrappedValue.restTimingMode == .stopwatch {
                            Stepper(value: Binding(
                                get: { selectedBinding.wrappedValue.restTargetSeconds ?? 20 },
                                set: { selectedBinding.wrappedValue.restTargetSeconds = $0 }
                            ), in: 10...300, step: 10) {
                                HStack {
                                    Text("建议休息目标:")
                                    Spacer()
                                    Text("\(selectedBinding.wrappedValue.restTargetSeconds ?? 20) 秒")
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Stepper(value: selectedBinding.restMinutes, in: 1...60) {
                                HStack {
                                    Text("短休息时长:")
                                    Spacer()
                                    Text("\(selectedBinding.wrappedValue.restMinutes) 分钟")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("工作与休息节奏").font(.headline)
                    }
                    
                    Section {
                        TextField("提醒文本提示", text: selectedBinding.message)
                        
                        Picker("提醒方式", selection: selectedBinding.alertStyle) {
                            Text("浮窗与声音").tag(AlertStyle.both)
                            Text("仅浮窗").tag(AlertStyle.popup)
                            Text("仅声音").tag(AlertStyle.sound)
                            Text("静音").tag(AlertStyle.none)
                        }
                        
                        Picker("系统音效", selection: selectedBinding.soundName) {
                            Text("Glass (轻灵玻璃)").tag("Glass")
                            Text("Ping (清脆金属)").tag("Ping")
                            Text("Tink (微响敲击)").tag("Tink")
                            Text("Pop (灵动泡泡)").tag("Pop")
                            Text("Submarine (低沉潜艇)").tag("Submarine")
                        }
                    } header: {
                        Text("到点提醒效果").font(.headline)
                    }
                }
                .formStyle(.grouped)
                .onChange(of: selectedBinding.wrappedValue) { updated in
                    presetStore.save()
                    if engine.preset.id == updated.id {
                        engine.preset = updated
                    }
                }
            } else {
                Text("请在左侧选择一个预设进行编辑")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - 快捷键
    private var hotkeysTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("免权限原生全局快捷键")
                .font(.headline)
            
            VStack(spacing: 12) {
                hotkeyRow(title: "开始专注工作 / 下一轮", shortcut: "⌥ ⇧ S")
                hotkeyRow(title: "立即开始放松休息", shortcut: "⌥ ⇧ R")
                hotkeyRow(title: "进入待机 (结束并归档当前轮)", shortcut: "⌥ ⇧ Esc")
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            
            Spacer()
            
            Text("提示：全局快捷键无需在系统设置授予任何辅助功能隐私权限，在任意全屏游戏、会议或代码编辑器中均可随心响应。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    // MARK: - 关于
    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()
            
            // 图标与名称
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
            }
            
            VStack(spacing: 4) {
                Text("BreakLoop")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("版本 1.0 (Build 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("原生 macOS 超轻量“工作 / 休息”循环节拍工具\n按设定节奏提醒放松护眼，精确回溯记录，杜绝久视伤害。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Divider()
                .frame(width: 320)
            
            VStack(spacing: 6) {
                Text("特性：零外部重度依赖 · 无网络权限 · 键鼠空闲自动回溯 · 免权限全局快捷键")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private func hotkeyRow(title: String, shortcut: String) -> some View {
        HStack {
            Text(title).font(.body)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(NSColor.unemphasizedSelectedContentBackgroundColor))
                .cornerRadius(6)
        }
    }
    
    // MARK: - 辅助方法
    private func bindingForSelectedPreset() -> Binding<Preset>? {
        guard let index = presetStore.presets.firstIndex(where: { $0.id == selectedPresetId }) else {
            return nil
        }
        return $presetStore.presets[index]
    }
    
    private func createNewPreset() {
        let newPreset = Preset(
            name: "新自定义预设",
            mode: .continuousLoop,
            workMinutes: 30,
            autoStartRest: true,
            restTimingMode: .stopwatch,
            restTargetSeconds: 30,
            restMinutes: 3,
            message: "专注完成，深呼吸喝口水"
        )
        presetStore.addPreset(newPreset)
        selectedPresetId = newPreset.id
    }
    
    private func deleteSelectedPreset() {
        presetStore.deletePreset(id: selectedPresetId)
        if let first = presetStore.presets.first {
            selectedPresetId = first.id
        }
    }
}
