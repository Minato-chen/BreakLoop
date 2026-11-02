import Foundation
import AppKit
import UniformTypeIdentifiers

/// 偏好设置数据快照（可序列化存储于备份包中）
public struct PreferencesSnapshot: Codable, Equatable {
    public var launchAtLogin: Bool?
    public var menuBarShowTime: Bool?
    public var menuBarShowStep: Bool?
    public var menuBarShowSymbol: Bool?
    public var menuBarSymbolStyle: String?
    public var menuBarShowStandbyText: Bool?
    public var autoStandbyOnScreenSaver: Bool?
    public var autoStandbyOnIdle: Bool?
    public var idleTimeoutMinutes: Int?
    public var pauseTimeoutMinutes: Int?
    public var autoCheckUpdate: Bool?
    public var enableGlobalHotKeys: Bool?
    public var soundVolume: Double?
    public var soundIsMuted: Bool?
    public var soundRepeatCount: Int?
    public var soundMaxDurationSeconds: Double?
    
    public init(
        launchAtLogin: Bool? = nil,
        menuBarShowTime: Bool? = nil,
        menuBarShowStep: Bool? = nil,
        menuBarShowSymbol: Bool? = nil,
        menuBarSymbolStyle: String? = nil,
        menuBarShowStandbyText: Bool? = nil,
        autoStandbyOnScreenSaver: Bool? = nil,
        autoStandbyOnIdle: Bool? = nil,
        idleTimeoutMinutes: Int? = nil,
        pauseTimeoutMinutes: Int? = nil,
        autoCheckUpdate: Bool? = nil,
        enableGlobalHotKeys: Bool? = nil,
        soundVolume: Double? = nil,
        soundIsMuted: Bool? = nil,
        soundRepeatCount: Int? = nil,
        soundMaxDurationSeconds: Double? = nil
    ) {
        self.launchAtLogin = launchAtLogin
        self.menuBarShowTime = menuBarShowTime
        self.menuBarShowStep = menuBarShowStep
        self.menuBarShowSymbol = menuBarShowSymbol
        self.menuBarSymbolStyle = menuBarSymbolStyle
        self.menuBarShowStandbyText = menuBarShowStandbyText
        self.autoStandbyOnScreenSaver = autoStandbyOnScreenSaver
        self.autoStandbyOnIdle = autoStandbyOnIdle
        self.idleTimeoutMinutes = idleTimeoutMinutes
        self.pauseTimeoutMinutes = pauseTimeoutMinutes
        self.autoCheckUpdate = autoCheckUpdate
        self.enableGlobalHotKeys = enableGlobalHotKeys
        self.soundVolume = soundVolume
        self.soundIsMuted = soundIsMuted
        self.soundRepeatCount = soundRepeatCount
        self.soundMaxDurationSeconds = soundMaxDurationSeconds
    }
}

/// 完整配置备份包
public struct BackupPackage: Codable {
    public var appVersion: String
    public var exportDate: Date
    public var activePresetId: UUID?
    public var presets: [Preset]
    public var preferences: PreferencesSnapshot?
    
    public init(
        appVersion: String,
        exportDate: Date = Date(),
        activePresetId: UUID?,
        presets: [Preset],
        preferences: PreferencesSnapshot?
    ) {
        self.appVersion = appVersion
        self.exportDate = exportDate
        self.activePresetId = activePresetId
        self.presets = presets
        self.preferences = preferences
    }
}

/// 单个方案分享包
public struct SinglePresetPackage: Codable {
    public var appVersion: String
    public var exportDate: Date
    public var preset: Preset
    
    public init(appVersion: String, exportDate: Date = Date(), preset: Preset) {
        self.appVersion = appVersion
        self.exportDate = exportDate
        self.preset = preset
    }
}

public extension Notification.Name {
    static let breakLoopConfigRestored = Notification.Name("BreakLoopConfigRestored")
}

/// 导入结果对象（携带提示消息与目标方案 ID）
public struct ImportResult: Equatable {
    public var message: String
    public var targetPresetId: UUID?
    
    public init(message: String, targetPresetId: UUID? = nil) {
        self.message = message
        self.targetPresetId = targetPresetId
    }
}

/// 配置备份与导入导出核心管理器
@MainActor
public final class ConfigBackupManager {
    public static let shared = ConfigBackupManager()
    
    public enum ImportMode {
        case merge     // 追加合并方案
        case overwrite // 完整覆盖还原
    }
    
    private init() {}
    
    // MARK: - 偏好读取与回填
    public func capturePreferencesSnapshot() -> PreferencesSnapshot {
        let defaults = UserDefaults.standard
        return PreferencesSnapshot(
            launchAtLogin: defaults.object(forKey: "BreakLoop.LaunchAtLogin") as? Bool,
            menuBarShowTime: defaults.object(forKey: "BreakLoop.MenuBarShowTime") as? Bool ?? true,
            menuBarShowStep: defaults.object(forKey: "BreakLoop.MenuBarShowStep") as? Bool ?? false,
            menuBarShowSymbol: defaults.object(forKey: "BreakLoop.MenuBarShowSymbol") as? Bool ?? true,
            menuBarSymbolStyle: defaults.string(forKey: "BreakLoop.MenuBarSymbolStyle") ?? "chevron",
            menuBarShowStandbyText: defaults.object(forKey: "BreakLoop.MenuBarShowStandbyText") as? Bool ?? false,
            autoStandbyOnScreenSaver: defaults.object(forKey: "BreakLoop.AutoStandbyOnScreenSaver") as? Bool ?? true,
            autoStandbyOnIdle: defaults.object(forKey: "BreakLoop.AutoStandbyOnIdle") as? Bool ?? true,
            idleTimeoutMinutes: defaults.object(forKey: "BreakLoop.IdleTimeoutMinutes") as? Int ?? 10,
            pauseTimeoutMinutes: defaults.object(forKey: "BreakLoop.PauseTimeoutMinutes") as? Int ?? 5,
            autoCheckUpdate: defaults.object(forKey: "BreakLoop.AutoCheckUpdate") as? Bool ?? true,
            enableGlobalHotKeys: defaults.object(forKey: "BreakLoop.EnableGlobalHotKeys") as? Bool ?? true,
            soundVolume: defaults.object(forKey: "BreakLoop.SoundManager.Volume") as? Double,
            soundIsMuted: defaults.object(forKey: "BreakLoop.SoundManager.IsMuted") as? Bool,
            soundRepeatCount: defaults.object(forKey: "BreakLoop.SoundManager.RepeatCount") as? Int,
            soundMaxDurationSeconds: defaults.object(forKey: "BreakLoop.SoundManager.MaxDuration") as? Double
        )
    }
    
    public func applyPreferencesSnapshot(_ snap: PreferencesSnapshot) {
        let defaults = UserDefaults.standard
        let isRealApp = Bundle.main.bundlePath.hasSuffix(".app")
        
        if let v = snap.launchAtLogin {
            defaults.set(v, forKey: "BreakLoop.LaunchAtLogin")
            if isRealApp {
                LaunchAtLogin.setEnabled(v)
            }
        }
        if let v = snap.menuBarShowTime { defaults.set(v, forKey: "BreakLoop.MenuBarShowTime") }
        if let v = snap.menuBarShowStep { defaults.set(v, forKey: "BreakLoop.MenuBarShowStep") }
        if let v = snap.menuBarShowSymbol { defaults.set(v, forKey: "BreakLoop.MenuBarShowSymbol") }
        if let v = snap.menuBarSymbolStyle { defaults.set(v, forKey: "BreakLoop.MenuBarSymbolStyle") }
        if let v = snap.menuBarShowStandbyText { defaults.set(v, forKey: "BreakLoop.MenuBarShowStandbyText") }
        if let v = snap.autoStandbyOnScreenSaver { defaults.set(v, forKey: "BreakLoop.AutoStandbyOnScreenSaver") }
        if let v = snap.autoStandbyOnIdle { defaults.set(v, forKey: "BreakLoop.AutoStandbyOnIdle") }
        if let v = snap.idleTimeoutMinutes { defaults.set(v, forKey: "BreakLoop.IdleTimeoutMinutes") }
        if let v = snap.pauseTimeoutMinutes { defaults.set(v, forKey: "BreakLoop.PauseTimeoutMinutes") }
        if let v = snap.autoCheckUpdate { defaults.set(v, forKey: "BreakLoop.AutoCheckUpdate") }
        if let v = snap.enableGlobalHotKeys {
            defaults.set(v, forKey: "BreakLoop.EnableGlobalHotKeys")
            if isRealApp {
                HotKeyManager.isEnabledInUserDefaults = v
            }
        }
        if let v = snap.soundVolume { defaults.set(v, forKey: "BreakLoop.SoundManager.Volume") }
        if let v = snap.soundIsMuted { defaults.set(v, forKey: "BreakLoop.SoundManager.IsMuted") }
        if let v = snap.soundRepeatCount { defaults.set(v, forKey: "BreakLoop.SoundManager.RepeatCount") }
        if let v = snap.soundMaxDurationSeconds { defaults.set(v, forKey: "BreakLoop.SoundManager.MaxDuration") }
    }
    
    // MARK: - 备份生成
    public func generateBackupPackageData(presets: [Preset]? = nil, activePresetId: UUID? = nil) -> Data? {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.2"
        let resolvedPresets = presets ?? PresetStore.shared.presets
        let resolvedActiveId = activePresetId ?? (presets != nil ? resolvedPresets.first?.id : PresetStore.shared.activePresetId)
        let package = BackupPackage(
            appVersion: currentVersion,
            exportDate: Date(),
            activePresetId: resolvedActiveId,
            presets: resolvedPresets,
            preferences: capturePreferencesSnapshot()
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(package)
    }
    
    public func generateSinglePresetData(preset: Preset) -> Data? {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.2"
        let package = SinglePresetPackage(
            appVersion: currentVersion,
            exportDate: Date(),
            preset: preset
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(package)
    }
    
    // MARK: - 文件名安全清洗
    public static func sanitizeFileName(_ name: String, fallback: String = "Preset") -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?*\"<>|")
            .union(.controlCharacters)
            .union(.newlines)
        let sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "-")
        let trimmed = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-_. ").union(.whitespacesAndNewlines))
        if trimmed.isEmpty {
            return fallback
        }
        return trimmed
    }
    
    // MARK: - 备份与方案恢复导入
    public func importBackup(data: Data, mode: ImportMode) -> Result<ImportResult, Error> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // 尝试解码标准 BackupPackage
        if let package = try? decoder.decode(BackupPackage.self, from: data) {
            return applyBackupPackage(package, mode: mode)
        }
        
        // 兼容支持：若用户直接导入了一个裸的 [Preset] JSON 数组
        if let presets = PresetStore.decodePresetsLossy(from: data), !presets.isEmpty {
            let package = BackupPackage(
                appVersion: "legacy",
                exportDate: Date(),
                activePresetId: presets.first?.id,
                presets: presets,
                preferences: nil
            )
            return applyBackupPackage(package, mode: mode)
        }
        
        // 兼容支持：若用户导入的是单个方案 SinglePresetPackage 或单个 Preset
        if let single = try? decoder.decode(SinglePresetPackage.self, from: data) {
            let newId = importSinglePreset(single.preset)
            return .success(ImportResult(message: "已成功导入方案「\(single.preset.name)」", targetPresetId: newId))
        }
        if let singlePreset = try? decoder.decode(Preset.self, from: data) {
            let newId = importSinglePreset(singlePreset)
            return .success(ImportResult(message: "已成功导入方案「\(singlePreset.name)」", targetPresetId: newId))
        }
        
        return .failure(NSError(domain: "BreakLoop", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法识别所选文件格式，请确认其是否为有效的 BreakLoop 备份或方案 JSON 文件。"]))
    }
    
    private func applyBackupPackage(_ package: BackupPackage, mode: ImportMode) -> Result<ImportResult, Error> {
        guard !package.presets.isEmpty else {
            return .failure(NSError(domain: "BreakLoop", code: -2, userInfo: [NSLocalizedDescriptionKey: "备份文件中未包含任何专注方案。"]))
        }
        
        switch mode {
        case .merge:
            var importedCount = 0
            var firstImportedId: UUID? = nil
            for var p in package.presets {
                // 赋予全新 UUID 避免与现有方案 ID 冲突
                p.id = UUID()
                if firstImportedId == nil {
                    firstImportedId = p.id
                }
                // 重名方案标记
                if PresetStore.shared.presets.contains(where: { $0.name == p.name }) {
                    p.name = "\(p.name) (导入)"
                }
                PresetStore.shared.presets.append(p)
                importedCount += 1
            }
            PresetStore.shared.save()
            return .success(ImportResult(
                message: "已合并导入 \(importedCount) 个方案，当前设置已保留。",
                targetPresetId: firstImportedId
            ))
            
        case .overwrite:
            PresetStore.shared.presets = package.presets
            let targetId: UUID
            if let activeId = package.activePresetId, package.presets.contains(where: { $0.id == activeId }) {
                targetId = activeId
            } else {
                targetId = package.presets.first!.id
            }
            PresetStore.shared.activePresetId = targetId
            PresetStore.shared.save()
            
            if let prefs = package.preferences {
                applyPreferencesSnapshot(prefs)
            }
            
            // 立即广播配置已还原通知，触发引擎与菜单栏秒级同步
            NotificationCenter.default.post(name: .breakLoopConfigRestored, object: nil)
            
            return .success(ImportResult(
                message: "已完整还原 \(package.presets.count) 个方案及偏好设置。",
                targetPresetId: targetId
            ))
        }
    }
    
    @discardableResult
    public func importSinglePreset(_ preset: Preset) -> UUID {
        var newPreset = preset
        newPreset.id = UUID()
        if PresetStore.shared.presets.contains(where: { $0.name == newPreset.name }) {
            newPreset.name = "\(newPreset.name) (导入)"
        }
        PresetStore.shared.addPreset(newPreset)
        return newPreset.id
    }
    
    // MARK: - 原生 macOS 对话框交互
    public func exportFullBackupWithSavePanel() {
        guard let data = generateBackupPackageData() else { return }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        let timestamp = formatter.string(from: Date())
        let defaultFileName = "BreakLoop_Backup_\(timestamp).json"
        
        let savePanel = NSSavePanel()
        savePanel.title = "导出 BreakLoop 配置备份"
        savePanel.nameFieldStringValue = defaultFileName
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.allowedContentTypes = [.json]
        
        if savePanel.runModal() == .OK, let targetURL = savePanel.url {
            do {
                try data.write(to: targetURL, options: .atomic)
            } catch {
                let alert = NSAlert()
                alert.messageText = "导出失败"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
    
    public func exportSinglePresetWithSavePanel(_ preset: Preset) {
        guard let data = generateSinglePresetData(preset: preset) else { return }
        
        let safeName = Self.sanitizeFileName(preset.name, fallback: "Preset")
        let defaultFileName = "\(safeName).breakloop.json"
        
        let savePanel = NSSavePanel()
        savePanel.title = "导出方案「\(preset.name)」"
        savePanel.nameFieldStringValue = defaultFileName
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.allowedContentTypes = [.json]
        
        if savePanel.runModal() == .OK, let targetURL = savePanel.url {
            try? data.write(to: targetURL, options: .atomic)
        }
    }
    
    public func importWithOpenPanel(completion: @escaping (Result<ImportResult, Error>) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.title = "选择 BreakLoop 备份或方案文件"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.json]
        
        guard openPanel.runModal() == .OK, let selectedURL = openPanel.url else { return }
        guard let data = try? Data(contentsOf: selectedURL) else {
            completion(.failure(NSError(domain: "BreakLoop", code: -3, userInfo: [NSLocalizedDescriptionKey: "无法读取所选文件。"])))
            return
        }
        
        // 弹出模式选择弹窗：合并 还是 覆盖
        let alert = NSAlert()
        alert.messageText = "请选择恢复方式"
        alert.informativeText = "您可以选择将备份方案「追加合并」至现有列表中，或彻底「完整覆盖」当前所有方案与偏好设置。"
        alert.addButton(withTitle: "追加合并方案（推荐）")
        alert.addButton(withTitle: "完整覆盖还原")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 合并
            let res = importBackup(data: data, mode: .merge)
            completion(res)
        } else if response == .alertSecondButtonReturn {
            // 覆盖
            let confirmAlert = NSAlert()
            confirmAlert.messageText = "确认完整覆盖？"
            confirmAlert.informativeText = "当前所有方案与设置将被备份文件全面替代，此操作无法撤销。"
            confirmAlert.alertStyle = .critical
            confirmAlert.addButton(withTitle: "确认覆盖")
            confirmAlert.addButton(withTitle: "取消")
            
            if confirmAlert.runModal() == .alertFirstButtonReturn {
                let res = importBackup(data: data, mode: .overwrite)
                completion(res)
            }
        }
    }
}
