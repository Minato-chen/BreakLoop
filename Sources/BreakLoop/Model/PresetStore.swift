import Foundation

public final class PresetStore: ObservableObject {
    public static let shared = PresetStore()
    
    private let userDefaultsKey = "BreakLoop.SavedPresets.v1"
    private let activePresetIdKey = "BreakLoop.ActivePresetId.v1"
    
    @Published public var presets: [Preset] = []
    @Published public var activePresetId: UUID
    
    public init() {
        let loadedPresets: [Preset]
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([Preset].self, from: data),
           !decoded.isEmpty {
            loadedPresets = decoded
        } else {
            loadedPresets = Preset.defaultPresets
        }
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
        if didMigrate {
            if let data = try? JSONEncoder().encode(sanitizedPresets) {
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
            }
        }
        
        if let savedActiveStr = UserDefaults.standard.string(forKey: activePresetIdKey),
           let savedUUID = UUID(uuidString: savedActiveStr),
           loadedPresets.contains(where: { $0.id == savedUUID }) {
            self.activePresetId = savedUUID
        } else {
            self.activePresetId = loadedPresets.first?.id ?? Preset.defaultPresets[0].id
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
    }
    
    public func addPreset(_ preset: Preset) {
        presets.append(preset)
        // 不自动替换 activePresetId，保持当前默认方案不变
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
}
