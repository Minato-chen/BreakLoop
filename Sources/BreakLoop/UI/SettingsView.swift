import SwiftUI

/// 预设方案专有管理视图（左侧方案切换，右侧极简模块化流水线画布，零卡顿）
public struct PresetManagerView: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var presetStore = PresetStore.shared
    @State private var selectedPresetId: UUID
    
    public init(engine: TimerEngine) {
        self.engine = engine
        _selectedPresetId = State(initialValue: engine.preset.id)
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // 左侧：预设方案选择列表（固定宽度，彻底避免 HSplitView 拖拉抖动）
            VStack(spacing: 0) {
                // 顶部：方案计数与新增
                HStack {
                    Text("方案列表 (\(presetStore.presets.count))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: createNewPreset) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("新增")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                List(selection: $selectedPresetId) {
                    ForEach(presetStore.presets) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .fontWeight(preset.id == selectedPresetId ? .semibold : .regular)
                                Text("\(preset.blocks.count) 步循环")
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
                .onChange(of: selectedPresetId) { newId in
                    if let selected = presetStore.presets.first(where: { $0.id == newId }) {
                        presetStore.activePresetId = selected.id
                        engine.preset = selected
                    }
                }
                
                Divider()
                
                // 底部操作栏（删除 + 上下移动，点选即应用，无冗余应用键）
                HStack(spacing: 6) {
                    Button(action: deleteSelectedPreset) {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(presetStore.presets.count <= 1)
                    
                    Button(action: { presetStore.moveUp(id: selectedPresetId) }) {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: { presetStore.moveDown(id: selectedPresetId) }) {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Spacer()
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
            }
            .frame(width: 190)
            
            Divider()
            
            // 右侧：模块化流程画布
            if let selectedBinding = bindingForSelectedPreset() {
                PipelineFlowCanvasView(preset: selectedBinding, engine: engine)
                    .onChange(of: selectedBinding.wrappedValue) { _ in
                        presetStore.save()
                    }
            } else {
                VStack {
                    Text("请选择方案")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func bindingForSelectedPreset() -> Binding<Preset>? {
        guard let index = presetStore.presets.firstIndex(where: { $0.id == selectedPresetId }) else {
            return nil
        }
        return $presetStore.presets[index]
    }
    
    private func createNewPreset() {
        let newPreset = Preset(
            name: "新专注循环",
            blocks: [
                FlowBlock.makeWork(name: "工作专注", minutes: 25),
                FlowBlock.makeCountdownRest(name: "短休", minutes: 5)
            ]
        )
        presetStore.addPreset(newPreset)
        selectedPresetId = newPreset.id
    }
    
    private func deleteSelectedPreset() {
        guard presetStore.presets.count > 1 else { return }
        let currentId = selectedPresetId
        if let currentIndex = presetStore.presets.firstIndex(where: { $0.id == currentId }) {
            let nextIndex = currentIndex > 0 ? currentIndex - 1 : 1
            selectedPresetId = presetStore.presets[nextIndex].id
            presetStore.deletePreset(id: currentId)
        }
    }
}

/// 全局设置主窗口
public struct SettingsView: View {
    @ObservedObject var engine: TimerEngine
    
    public init(engine: TimerEngine) {
        self.engine = engine
    }
    
    public var body: some View {
        TabView {
            PresetManagerView(engine: engine)
                .tabItem {
                    Label("方案", systemImage: "arrow.triangle.2.circlepath")
                }
            
            GeneralPreferencesView(engine: engine)
                .tabItem {
                    Label("偏好", systemImage: "gearshape")
                }
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}

/// 通用偏好设置
public struct GeneralPreferencesView: View {
    @ObservedObject var engine: TimerEngine
    @AppStorage("BreakLoop.LaunchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("BreakLoop.MenuBarShowTime") private var menuBarShowTime: Bool = false
    
    public init(engine: TimerEngine) {
        self.engine = engine
    }
    
    public var body: some View {
        Form {
            Section {
                Toggle("开机自启", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { val in
                        LaunchAtLogin.setEnabled(val)
                    }
                
                Toggle("菜单栏显示倒计时进度", isOn: $menuBarShowTime)
            } header: {
                Text("常规").font(.headline)
            }
            
            Section {
                Picker("提醒形式", selection: $engine.preset.alertStyle) {
                    Text("弹窗与声音").tag(AlertStyle.both)
                    Text("仅弹窗").tag(AlertStyle.popup)
                    Text("仅声音").tag(AlertStyle.sound)
                    Text("静音").tag(AlertStyle.none)
                }
            } header: {
                Text("提醒").font(.headline)
            }
            
            Section {
                Text("快捷键快速操作：")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("• ⌥ + Space: 快速切换工作 / 休息")
                    .font(.caption2)
                Text("• ⌥ + ⎋ (Escape): 随时挂起跳出并进入待机")
                    .font(.caption2)
            } header: {
                Text("快捷键").font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 关于视图
public struct AboutView: View {
    public init() {}
    
    public var body: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image(systemName: "circle.circle.fill")
                .font(.system(size: 54))
                .foregroundColor(.accentColor)
            
            Text("BreakLoop")
                .font(.system(size: 20, weight: .bold))
            
            Text("极简模块化专注循环引擎")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("v2.0 (Low Memory & CPU Optimized)")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
