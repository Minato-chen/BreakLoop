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
                // 顶部：方案列表标题（固定高度 46，与右侧标题栏基线完全对齐）
                HStack {
                    Text("方案列表 (\(presetStore.presets.count))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary.opacity(0.85))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
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
                        .contextMenu {
                            Button(action: {
                                ConfigBackupManager.shared.exportSinglePresetWithSavePanel(preset)
                            }) {
                                Label("导出此方案...", systemImage: "square.and.arrow.up")
                            }
                            Button(action: {
                                duplicatePreset(preset)
                            }) {
                                Label("复制方案", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
                
                Divider()
                
                // 底部操作栏（+、上移、下移、删除，运行中或默认方案保护不可删除）
                let isSelectedRunning = (engine.mode != .standby && engine.preset.id == selectedPresetId)
                let isSelectedActiveDefault = (presetStore.activePresetId == selectedPresetId)
                let canDelete = presetStore.presets.count > 1 && !isSelectedRunning && !isSelectedActiveDefault
                
                HStack(spacing: 6) {
                    Button(action: createNewPreset) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("新增预设方案")
                    
                    Button(action: { presetStore.moveUp(id: selectedPresetId) }) {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("上移选中方案")
                    
                    Button(action: { presetStore.moveDown(id: selectedPresetId) }) {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("下移选中方案")
                    
                    Button(action: deleteSelectedPreset) {
                        Image(systemName: "trash")
                            .foregroundColor(canDelete ? .red.opacity(0.8) : .secondary.opacity(0.35))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canDelete)
                    .help(isSelectedRunning ? "当前方案正在运行中，不可删除" : (isSelectedActiveDefault ? "当前方案已设为默认方案，不可删除" : "删除选中的方案"))
                    
                    Spacer()
                    
                    Menu {
                        Button(action: {
                            ConfigBackupManager.shared.importWithOpenPanel { result in
                                if case .success(let importRes) = result {
                                    if let targetId = importRes.targetPresetId {
                                        selectedPresetId = targetId
                                    } else if let first = presetStore.presets.first {
                                        selectedPresetId = first.id
                                    }
                                }
                            }
                        }) {
                            Label("导入方案或备份...", systemImage: "square.and.arrow.down")
                        }
                        
                        if let selected = presetStore.presets.first(where: { $0.id == selectedPresetId }) {
                            Button(action: {
                                ConfigBackupManager.shared.exportSinglePresetWithSavePanel(selected)
                            }) {
                                Label("导出当前方案...", systemImage: "square.and.arrow.up")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help("方案导入与导出")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
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
    
    private func duplicatePreset(_ preset: Preset) {
        var copy = preset
        copy.id = UUID()
        copy.name = "\(preset.name) (副本)"
        presetStore.addPreset(copy)
        selectedPresetId = copy.id
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
    @AppStorage("BreakLoop.MenuBarShowTime") private var menuBarShowTime: Bool = true
    @AppStorage("BreakLoop.MenuBarShowStep") private var menuBarShowStep: Bool = false
    @AppStorage("BreakLoop.MenuBarShowSymbol") private var menuBarShowSymbol: Bool = true
    @AppStorage("BreakLoop.MenuBarSymbolStyle") private var menuBarSymbolStyle: String = "chevron"
    @AppStorage("BreakLoop.MenuBarShowStandbyText") private var menuBarShowStandbyText: Bool = false
    
    @AppStorage("BreakLoop.AutoStandbyOnScreenSaver") private var autoStandbyOnScreenSaver: Bool = true
    @AppStorage("BreakLoop.AutoStandbyOnIdle") private var autoStandbyOnIdle: Bool = true
    @AppStorage("BreakLoop.IdleTimeoutMinutes") private var idleTimeoutMinutes: Int = 10
    @AppStorage("BreakLoop.PauseTimeoutMinutes") private var pauseTimeoutMinutes: Int = 5
    
    private static let intFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 1
        f.maximum = 999
        return f
    }()
    
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
            } header: {
                Text("常规").font(.headline)
            }
            
            Section {
                Toggle("菜单栏显示时间与状态", isOn: $menuBarShowTime)
                    .onChange(of: menuBarShowTime) { _ in engine.updateMenuBarText() }
                
                if menuBarShowTime {
                    Toggle("显示循环步数 (如 1/2)", isOn: $menuBarShowStep)
                        .onChange(of: menuBarShowStep) { _ in engine.updateMenuBarText() }
                    
                    Toggle("显示计时方向符号", isOn: $menuBarShowSymbol)
                        .onChange(of: menuBarShowSymbol) { _ in engine.updateMenuBarText() }
                    
                    Toggle("待机时显示「待机」文字", isOn: $menuBarShowStandbyText)
                        .onChange(of: menuBarShowStandbyText) { _ in engine.updateMenuBarText() }
                    
                    if menuBarShowSymbol {
                        Picker("符号样式", selection: $menuBarSymbolStyle) {
                            Text("< 倒计时 / > 正计时 (推荐)").tag("chevron")
                            Text("< 倒计时 / + 正计时").tag("plus")
                        }
                        .onChange(of: menuBarSymbolStyle) { _ in engine.updateMenuBarText() }
                    }
                    
                    // 实时模拟预览条
                    HStack(spacing: 8) {
                        Text("外观预览:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        menuBarPreviewPill
                    }
                    .padding(.top, 4)
                }
            } header: {
                Text("菜单栏").font(.headline)
            } footer: {
                Text("默认采用紧凑设计（隐藏步数，保留方向符号），在菜单栏占用极小横向空间，且清晰区分正倒计时。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Section {
                Toggle("屏幕保护与锁屏时自动待机", isOn: $autoStandbyOnScreenSaver)
                
                Toggle("鼠标键盘长时间无操作时自动待机", isOn: $autoStandbyOnIdle)
                if autoStandbyOnIdle {
                    HStack {
                        Text("无操作判定超时")
                        Spacer()
                        TextField("", value: $idleTimeoutMinutes, formatter: Self.intFormatter)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 48)
                        Stepper("", value: $idleTimeoutMinutes, in: 1...180)
                            .labelsHidden()
                        Text("分钟")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Text("临时暂停超时自动转入待机")
                    Spacer()
                    TextField("", value: $pauseTimeoutMinutes, formatter: Self.intFormatter)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 48)
                    Stepper("", value: $pauseTimeoutMinutes, in: 1...120)
                        .labelsHidden()
                    Text("分钟")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("屏保与闲置保护").font(.headline)
            } footer: {
                Text("进入屏保或长时间无操作时自动转入待机，并自动回溯扣除离开时间；暂停超时自动收起待机，防后台虚耗。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("导出全部配置备份")
                            .font(.system(size: 13, weight: .medium))
                        Text("将当前所有方案与全局偏好导出为独立 JSON 文件")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("导出备份...") {
                        ConfigBackupManager.shared.exportFullBackupWithSavePanel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("恢复或导入配置")
                            .font(.system(size: 13, weight: .medium))
                        Text("从备份或方案文件还原，支持合并方案或完全覆盖")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("导入备份...") {
                        ConfigBackupManager.shared.importWithOpenPanel { result in
                            switch result {
                            case .success(let res):
                                let alert = NSAlert()
                                alert.messageText = "导入成功"
                                alert.informativeText = res.message
                                alert.runModal()
                            case .failure(let err):
                                let alert = NSAlert()
                                alert.messageText = "导入失败"
                                alert.informativeText = err.localizedDescription
                                alert.alertStyle = .warning
                                alert.runModal()
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } header: {
                Text("备份与数据管理").font(.headline)
            } footer: {
                Text("每次更新版本前系统会自动在本地创建安全快照；您也可以随时导出备份用于换机或多设备同步。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var menuBarPreviewPill: some View {
        let stepText = menuBarShowStep ? "1/2 " : ""
        let symCountdown = menuBarShowSymbol ? "<" : ""
        let symCountup = menuBarShowSymbol ? (menuBarSymbolStyle == "plus" ? "+" : ">") : ""
        
        return HStack(spacing: 8) {
            // 待机状态预览（展示纯图标 vs 图标+文字）
            HStack(spacing: 3) {
                Image(systemName: "circle.dashed")
                    .foregroundColor(.secondary)
                if menuBarShowStandbyText {
                    Text("待机")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            
            // 专注状态预览
            HStack(spacing: 3) {
                Image(systemName: "record.circle")
                    .foregroundColor(.blue)
                Text("\(stepText)\(symCountdown)20m")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            
            // 休息状态预览
            HStack(spacing: 3) {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundColor(.green)
                Text("\(stepText)\(symCountup)5m")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
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
