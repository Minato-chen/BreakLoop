import Foundation

public final class PresetStore: ObservableObject {
    public static let shared = PresetStore()
    
    private let userDefaultsKey = "BreakLoop.SavedPresets.v1"
    private let activePresetIdKey = "BreakLoop.ActivePresetId.v1"
    private let lastAppVersionKey = "BreakLoop.LastAppVersion"
    
    @Published public var presets: [Preset] = []
    @Published public var activePresetId: UUID
    
    public static var applicationSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("BreakLoop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    public init() {
        // 1. 双轨恢复机制：优先从 UserDefaults，若异常则从 Application Support 镜像中恢复
        let (loadedPresets, activeUUID) = Self.loadPersistedPresets(
            userDefaultsKey: userDefaultsKey,
            activePresetIdKey: activePresetIdKey
        )
        
        // 2. 字段/命名平滑迁移（如历史遗留的命名统一为 "专注"、"休息(自由)"）
        var sanitizedPresets = loadedPresets
        var didMigrate = false
        for (pIdx, p) in sanitizedPresets.enumerated() {
            for (bIdx, b) in p.blocks.enumerated() {
                if b.type == .work && (b.name == "工作" || b.name == "工作专注") {
                    sanitizedPresets[pIdx].blocks[bIdx].name = "专注"
                    didMigrate = true
                } else if b.type == .rest && b.timingMode == .stopwatch && (b.name == "自由休息" || b.name == "自由大休") {
                    sanitizedPresets[pIdx].blocks[bIdx].name = "休息(自由)"
                    didMigrate = true
                }
            }
        }
        self.presets = sanitizedPresets
        self.activePresetId = activeUUID
        
        if didMigrate {
            save()
        } else {
            // 确保 Application Support 镜像同步存在
            syncToMirrorFile()
        }
        
        // 3. 异步触发版本升级快照，绝不阻塞当前 init() 杜绝递归单例锁死
        DispatchQueue.main.async { [weak self] in
            self?.checkVersionUpgradeSnapshot()
        }
    }
    
    public var activePreset: Preset {
        get {
            presets.first(where: { $0.id == activePresetId }) ?? Preset.defaultPresets[0]
        }
        set {
            if let index = presets.firstIndex(where: { $0.id == newValue.id }) {
                presets[index] = newValue
            } else {
                presets.append(newValue)
            }
            activePresetId = newValue.id
            save()
        }
    }
    
    public func save() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
        UserDefaults.standard.set(activePresetId.uuidString, forKey: activePresetIdKey)
        syncToMirrorFile()
    }
    
    public func addPreset(_ preset: Preset) {
        presets.append(preset)
        save()
    }
    
    public func deletePreset(id: UUID) {
        guard presets.count > 1 else { return } // 至少保留一个预设
        presets.removeAll(where: { $0.id == id })
        if activePresetId == id {
            activePresetId = presets.first!.id
        }
        save()
    }
    
    public func movePresets(fromOffsets source: IndexSet, toOffset destination: Int) {
        presets.move(fromOffsets: source, toOffset: destination)
        save()
    }
    
    public func moveUp(id: UUID) {
        guard let index = presets.firstIndex(where: { $0.id == id }), index > 0 else { return }
        presets.swapAt(index, index - 1)
        save()
    }
    
    public func moveDown(id: UUID) {
        guard let index = presets.firstIndex(where: { $0.id == id }), index < presets.count - 1 else { return }
        presets.swapAt(index, index + 1)
        save()
    }
    
    // MARK: - 安全加载与分级容错 (Safe Loading & Fault Tolerance)
    
    private static func loadPersistedPresets(userDefaultsKey: String, activePresetIdKey: String) -> ([Preset], UUID) {
        let mirrorURL = applicationSupportDirectory.appendingPathComponent("presets.json")
        
        // 尝试从 UserDefaults 主存读取
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            if let result = decodePresetsLossy(from: data), !result.isEmpty {
                let activeId = resolveActivePresetId(activePresetIdKey: activePresetIdKey, presets: result)
                return (result, activeId)
            } else {
                // UserDefaults 存在数据但无法解析 -> 隔离归档脏数据，绝不直接抹除
                quarantineCorruptedData(data, reason: "userdefaults_corrupted")
            }
        }
        
        // 若 UserDefaults 为空或破损，从 Application Support 镜像文件加载
        if FileManager.default.fileExists(atPath: mirrorURL.path),
           let mirrorData = try? Data(contentsOf: mirrorURL) {
            if let result = decodePresetsLossy(from: mirrorData), !result.isEmpty {
                let activeId = resolveActivePresetId(activePresetIdKey: activePresetIdKey, presets: result)
                // 回填修复至 UserDefaults
                if let encoded = try? JSONEncoder().encode(result) {
                    UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
                }
                return (result, activeId)
            } else {
                quarantineCorruptedData(mirrorData, reason: "mirror_corrupted")
            }
        }
        
        // 最终优雅兜底：出厂默认预设方案
        let defaultList = Preset.defaultPresets
        return (defaultList, defaultList[0].id)
    }
    
    private static func resolveActivePresetId(activePresetIdKey: String, presets: [Preset]) -> UUID {
        if let savedActiveStr = UserDefaults.standard.string(forKey: activePresetIdKey),
           let savedUUID = UUID(uuidString: savedActiveStr),
           presets.contains(where: { $0.id == savedUUID }) {
            return savedUUID
        }
        return presets.first?.id ?? Preset.defaultPresets[0].id
    }
    
    /// 逐项容错解码（Safe Lossy Decoding）：如果单个方案格式不兼容，不连累其余健全方案
    public static func decodePresetsLossy(from data: Data) -> [Preset]? {
        let decoder = JSONDecoder()
        
        // 1. 全量优先标准解码
        if let fullDecoded = try? decoder.decode([Preset].self, from: data), !fullDecoded.isEmpty {
            return fullDecoded
        }
        
        // 2. 逐项流式解码
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        
        var recovered: [Preset] = []
        for itemDict in jsonArray {
            if let itemData = try? JSONSerialization.data(withJSONObject: itemDict),
               let preset = try? decoder.decode(Preset.self, from: itemData) {
                recovered.append(preset)
            }
        }
        
        return recovered.isEmpty ? nil : recovered
    }
    
    /// 双写镜像至 Application Support/BreakLoop/presets.json
    private func syncToMirrorFile() {
        let mirrorURL = Self.applicationSupportDirectory.appendingPathComponent("presets.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(presets) {
            try? data.write(to: mirrorURL, options: .atomic)
        }
    }
    
    /// 脏数据隔离归档至 ~/Library/Application Support/BreakLoop/Corrupted/
    private static func quarantineCorruptedData(_ data: Data, reason: String) {
        let dir = applicationSupportDirectory.appendingPathComponent("Corrupted")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileURL = dir.appendingPathComponent("corrupted_\(reason)_\(timestamp).json")
        try? data.write(to: fileURL, options: .atomic)
    }
    
    // MARK: - 版本升级自动静默快照 (Upgrade Auto Snapshot)
    
    @MainActor
    private func checkVersionUpgradeSnapshot() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.2"
        let lastVersion = UserDefaults.standard.string(forKey: lastAppVersionKey)
        
        if lastVersion == nil {
            // 首次运行或首次引入版本记录
            UserDefaults.standard.set(currentVersion, forKey: lastAppVersionKey)
            createSnapshot(versionLabel: "v\(currentVersion)_initial")
        } else if lastVersion != currentVersion {
            // 版本升级！自动快照旧版本方案与配置
            createSnapshot(versionLabel: "v\(lastVersion ?? "legacy")_before_upgrade")
            UserDefaults.standard.set(currentVersion, forKey: lastAppVersionKey)
        }
    }
    
    @MainActor
    private func createSnapshot(versionLabel: String) {
        let dir = Self.applicationSupportDirectory.appendingPathComponent("Backups")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileURL = dir.appendingPathComponent("snapshot_\(versionLabel)_\(timestamp).json")
        
        if let packageData = ConfigBackupManager.shared.generateBackupPackageData(presets: self.presets, activePresetId: self.activePresetId) {
            try? packageData.write(to: fileURL, options: .atomic)
            cleanOldSnapshots(in: dir, keepCount: 10)
        }
    }
    
    private func cleanOldSnapshots(in dir: URL, keepCount: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else { return }
        
        let sorted = files.sorted { u1, u2 in
            let d1 = (try? u1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            let d2 = (try? u2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            return d1 > d2
        }
        
        if sorted.count > keepCount {
            for oldFile in sorted.dropFirst(keepCount) {
                try? FileManager.default.removeItem(at: oldFile)
            }
        }
    }
}
