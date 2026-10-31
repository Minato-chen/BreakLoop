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
                        let isRunning = (engine.mode != .standby && engine.preset.id == preset.id)
                        let isDefault = (presetStore.activePresetId == preset.id)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .fontWeight(preset.id == selectedPresetId ? .semibold : .regular)
                                Text("\(preset.blocks.count) 步循环")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if isRunning {
                                HStack(spacing: 3) {
                                    Circle().fill(Color.green).frame(width: 5, height: 5)
                                    Text("运行中")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .clipShape(Capsule())
                            } else if isDefault {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("默认")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                            }
                        }
                        .tag(preset.id)
                    }
                }
                
                Divider()
                
                // 底部操作栏（删除 + 上下移动，运行中或默认方案保护不可删除）
                let isSelectedRunning = (engine.mode != .standby && engine.preset.id == selectedPresetId)
                let isSelectedActiveDefault = (presetStore.activePresetId == selectedPresetId)
                let canDelete = presetStore.presets.count > 1 && !isSelectedRunning && !isSelectedActiveDefault
                
                HStack(spacing: 6) {
                    Button(action: deleteSelectedPreset) {
                        Image(systemName: "trash")
                            .foregroundColor(canDelete ? .red.opacity(0.8) : .secondary.opacity(0.35))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canDelete)
                    .help(isSelectedRunning ? "当前方案正在运行中，不可删除" : (isSelectedActiveDefault ? "当前方案已设为默认方案，不可删除" : "删除选中的方案"))
                    
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
                FlowBlock.makeWork(name: "专注", minutes: 25),
                FlowBlock.makeCountdownRest(name: "短休", minutes: 5)
            ]
        )
        presetStore.addPreset(newPreset)
        selectedPresetId = newPreset.id
    }
    
    private func deleteSelectedPreset() {
        guard presetStore.presets.count > 1 else { return }
        let currentId = selectedPresetId
        let isRunning = (engine.mode != .standby && engine.preset.id == currentId)
        let isDefault = (presetStore.activePresetId == currentId)
        guard !isRunning && !isDefault else { return }
        
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

/// 通用偏好设置（极简精简，已将声音提醒与快捷键拆分为独立大类）
public struct GeneralPreferencesView: View {
    @ObservedObject var engine: TimerEngine
    @AppStorage("BreakLoop.LaunchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("BreakLoop.MenuBarShowTime") private var menuBarShowTime: Bool = false
    @AppStorage("BreakLoop.AutoStandbyOnScreenSaver") private var autoStandbyOnScreenSaver: Bool = true
    @AppStorage("BreakLoop.AutoStandbyOnIdle") private var autoStandbyOnIdle: Bool = true
    @AppStorage("BreakLoop.IdleTimeoutMinutes") private var idleTimeoutMinutes: Int = 10
    @AppStorage("BreakLoop.PauseTimeoutMinutes") private var pauseTimeoutMinutes: Int = 5
    
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
                Toggle("屏幕保护与锁屏时自动待机", isOn: $autoStandbyOnScreenSaver)
                
                Toggle("鼠标键盘长时间无操作时自动待机", isOn: $autoStandbyOnIdle)
                if autoStandbyOnIdle {
                    Picker("无操作判定超时", selection: $idleTimeoutMinutes) {
                        Text("5 分钟").tag(5)
                        Text("10 分钟 (推荐)").tag(10)
                        Text("15 分钟").tag(15)
                        Text("20 分钟").tag(20)
                    }
                }
                
                Picker("临时暂停超时自动转入待机", selection: $pauseTimeoutMinutes) {
                    Text("3 分钟").tag(3)
                    Text("5 分钟 (推荐)").tag(5)
                    Text("10 分钟").tag(10)
                    Text("15 分钟").tag(15)
                    Text("从不超时").tag(0)
                }
            } header: {
                Text("屏保与闲置保护").font(.headline)
            } footer: {
                Text("进入屏保或长时间无操作时自动转入待机，并自动回溯扣除离开时间；暂停超时自动收起待机，防后台虚耗。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 关于视图（包含 GitHub 仓库、检查更新与自动更新）
public struct AboutView: View {
    @ObservedObject var updater = UpdateChecker.shared
    @AppStorage("BreakLoop.AutoCheckUpdate") private var autoCheckUpdate: Bool = true
    
    public init() {}
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 20) {
                // 顶部应用标志（苹果风双弧流转环）
                VStack(spacing: 8) {
                    BrandLogoView(size: 60, showGlow: true)
                    
                    Text("BreakLoop")
                        .font(.system(size: 22, weight: .bold))
                    
                    Text("极简模块化专注循环引擎")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        Text("版本 \(updater.currentVersion)")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                        
                        Text("低能耗极致优化")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 16)
                
                Divider()
                    .frame(maxWidth: 520)
                
                // GitHub 仓库卡片
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.accentColor)
                        Text("开源项目与社区")
                            .font(.system(size: 13, weight: .bold))
                        Spacer()
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GitHub 仓库")
                                .font(.system(size: 13, weight: .medium))
                            Text("https://github.com/Minato-chen/BreakLoop")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: {
                            NSWorkspace.shared.open(updater.repoURL)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square")
                                Text("访问 GitHub")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(14)
                .frame(maxWidth: 520)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                
                // 检查更新 & 自动更新卡片
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.accentColor)
                        Text("软件更新")
                            .font(.system(size: 13, weight: .bold))
                        Spacer()
                    }
                    
                    // 自动检查更新开关
                    Toggle(isOn: $autoCheckUpdate) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自动检查更新")
                                .font(.system(size: 13, weight: .medium))
                            Text("应用启动时自动静默检查 GitHub Releases 最新版本")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    
                    Divider()
                    
                    // 手动检查更新操作行
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("当前版本检查")
                                .font(.system(size: 13, weight: .medium))
                            
                            switch updater.status {
                            case .idle:
                                if let date = updater.lastCheckTime {
                                    Text("上次检查：\(dateFormatted(date))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("尚未进行版本检查")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            case .checking:
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("正在连接 GitHub 检查最新发布...")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            case .upToDate(let version):
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("当前已是最新版本 (v\(version))")
                                        .foregroundColor(.green)
                                }
                                .font(.caption2)
                            case .newVersionAvailable(let version, _, _):
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(.orange)
                                    Text("发现新版本 \(version)")
                                        .foregroundColor(.orange)
                                        .fontWeight(.semibold)
                                }
                                .font(.caption2)
                            case .failed(let msg):
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                    Text(msg)
                                        .foregroundColor(.red)
                                }
                                .font(.caption2)
                            }
                        }
                        
                        Spacer()
                        
                        if case .newVersionAvailable(_, _, let downloadURL) = updater.status {
                            Button(action: {
                                NSWorkspace.shared.open(downloadURL)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("前往下载")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else {
                            Button(action: {
                                updater.checkForUpdates(isUserInitiated: true)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("检查更新")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(updater.status == .checking)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: 520)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                
                // 底部版权信息
                VStack(spacing: 4) {
                    Text("BreakLoop 遵循 MIT 开源协议发布")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Designed with care for ergonomics and deep focus.")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
    }
    
    private func dateFormatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
