import Foundation
import AVFoundation
import AppKit

/// 自定义音频模型
public struct CustomSound: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var fileName: String
    public var duration: TimeInterval
    public var createdAt: Date
    
    public init(id: UUID = UUID(), name: String, fileName: String, duration: TimeInterval, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.duration = duration
        self.createdAt = createdAt
    }
}

/// 声音选择项包装（统一管理系统音与自定义音）
public struct SoundOption: Identifiable, Hashable {
    public var id: String { identifier }
    public let identifier: String
    public let displayName: String
    public let isCustom: Bool
    
    public init(identifier: String, displayName: String, isCustom: Bool = false) {
        self.identifier = identifier
        self.displayName = displayName
        self.isCustom = isCustom
    }
}

/// 全局声音管理器（音频导入、沙盒管理、多轮循环播放、长音频截断渐弱）
public final class SoundManager: ObservableObject {
    public static let shared = SoundManager()
    
    // 内置系统提示音列表
    public static let builtinSounds: [SoundOption] = [
        SoundOption(identifier: "Glass", displayName: "Glass (清脆)"),
        SoundOption(identifier: "Ping", displayName: "Ping (利落)"),
        SoundOption(identifier: "Pop", displayName: "Pop (气泡)"),
        SoundOption(identifier: "Tink", displayName: "Tink (微响)"),
        SoundOption(identifier: "Basso", displayName: "Basso (深沉)"),
        SoundOption(identifier: "Morse", displayName: "Morse (电码)"),
        SoundOption(identifier: "Purr", displayName: "Purr (猫噜)"),
        SoundOption(identifier: "Sosumi", displayName: "Sosumi (打击)"),
        SoundOption(identifier: "Submarine", displayName: "Submarine (潜艇)")
    ]
    
    // UserDefaults 键
    private let customSoundsKey = "BreakLoop.SoundManager.CustomSounds"
    private let defaultWorkSoundKey = "BreakLoop.SoundManager.DefaultWorkSound"
    private let defaultRestSoundKey = "BreakLoop.SoundManager.DefaultRestSound"
    private let defaultRepeatCountKey = "BreakLoop.SoundManager.RepeatCount"
    private let maxDurationKey = "BreakLoop.SoundManager.MaxDuration"
    private let volumeKey = "BreakLoop.SoundManager.Volume"
    
    @Published public private(set) var customSounds: [CustomSound] = []
    
    @Published public var defaultWorkSound: String {
        didSet { UserDefaults.standard.set(defaultWorkSound, forKey: defaultWorkSoundKey) }
    }
    @Published public var defaultRestSound: String {
        didSet { UserDefaults.standard.set(defaultRestSound, forKey: defaultRestSoundKey) }
    }
    @Published public var defaultRepeatCount: Int {
        didSet { UserDefaults.standard.set(defaultRepeatCount, forKey: defaultRepeatCountKey) }
    }
    @Published public var maxDurationSeconds: Double {
        didSet { UserDefaults.standard.set(maxDurationSeconds, forKey: maxDurationKey) }
    }
    @Published public var volume: Float {
        didSet { UserDefaults.standard.set(volume, forKey: volumeKey) }
    }
    
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var currentlyPlayingName: String? = nil
    
    private var audioPlayer: AVAudioPlayer?
    private var fadeTimer: Timer?
    private var repeatTimer: Timer?
    private var currentPlayCount: Int = 0
    private var targetRepeatCount: Int = 3
    
    public let soundsDirectory: URL
    
    private init() {
        // 初始化沙盒存储目录 ~/Library/Application Support/BreakLoop/Sounds
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("BreakLoop/Sounds", isDirectory: true)
        self.soundsDirectory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let defaults = UserDefaults.standard
        self.defaultWorkSound = defaults.string(forKey: defaultWorkSoundKey) ?? "Glass"
        self.defaultRestSound = defaults.string(forKey: defaultRestSoundKey) ?? "Ping"
        
        let savedRepeat = defaults.integer(forKey: defaultRepeatCountKey)
        self.defaultRepeatCount = savedRepeat > 0 ? savedRepeat : 3 // 默认 3 次
        
        let savedMaxDur = defaults.double(forKey: maxDurationKey)
        self.maxDurationSeconds = savedMaxDur > 0 ? savedMaxDur : 12.0 // 默认截断 12 秒 (10~15秒区间)
        
        let savedVolume = defaults.float(forKey: volumeKey)
        self.volume = savedVolume > 0 ? savedVolume : 0.85
        
        loadCustomSounds()
    }
    
    // MARK: - 自定义音频管理
    
    private func loadCustomSounds() {
        guard let data = UserDefaults.standard.data(forKey: customSoundsKey),
              let list = try? JSONDecoder().decode([CustomSound].self, from: data) else {
            self.customSounds = []
            return
        }
        self.customSounds = list.filter { item in
            FileManager.default.fileExists(atPath: fileURL(for: item).path)
        }
    }
    
    private func saveCustomSounds() {
        if let data = try? JSONEncoder().encode(customSounds) {
            UserDefaults.standard.set(data, forKey: customSoundsKey)
        }
    }
    
    public func fileURL(for sound: CustomSound) -> URL {
        soundsDirectory.appendingPathComponent(sound.fileName)
    }
    
    /// 导入外部音频文件并安全持久化
    @discardableResult
    public func importSound(from sourceURL: URL) -> CustomSound? {
        let ext = sourceURL.pathExtension.lowercased()
        guard ["mp3", "wav", "m4a", "aiff", "caf"].contains(ext) else {
            return nil
        }
        
        let id = UUID()
        let cleanName = sourceURL.deletingPathExtension().lastPathComponent
        let targetFileName = "\(id.uuidString).\(ext)"
        let targetURL = soundsDirectory.appendingPathComponent(targetFileName)
        
        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: targetURL)
            
            // 读取音频时长
            let player = try? AVAudioPlayer(contentsOf: targetURL)
            let finalDuration = player?.duration ?? 1.0
            
            let customSound = CustomSound(
                id: id,
                name: cleanName,
                fileName: targetFileName,
                duration: finalDuration
            )
            
            DispatchQueue.main.async {
                self.customSounds.append(customSound)
                self.saveCustomSounds()
            }
            return customSound
        } catch {
            return nil
        }
    }
    
    /// 删除自定义音频
    public func deleteSound(id: UUID) {
        guard let index = customSounds.firstIndex(where: { $0.id == id }) else { return }
        let sound = customSounds[index]
        let url = fileURL(for: sound)
        try? FileManager.default.removeItem(at: url)
        customSounds.remove(at: index)
        saveCustomSounds()
        
        if defaultWorkSound == sound.name {
            defaultWorkSound = "Glass"
        }
        if defaultRestSound == sound.name {
            defaultRestSound = "Ping"
        }
    }
    
    /// 获取全部可选项（内置 + 自定义）
    public func allAvailableSounds() -> [SoundOption] {
        var result = Self.builtinSounds
        for item in customSounds {
            result.append(SoundOption(identifier: item.name, displayName: "🎵 \(item.name)", isCustom: true))
        }
        return result
    }
    
    // MARK: - 音频播放核心控制（AVAudioPlayer，支持重复与长音末尾渐弱截断）
    
    /// 播放提示音
    /// - Parameters:
    ///   - soundName: 提示音名称（系统内置名或自定义音频名称）
    ///   - repeatCount: 重复次数（默认为全局 defaultRepeatCount，即 3 次）
    ///   - maxDuration: 最长持续时间（默认 12 秒，末尾 2 秒平滑渐弱）
    public func play(
        soundName: String,
        repeatCount: Int? = nil,
        maxDuration: TimeInterval? = nil
    ) {
        stop()
        
        let repeats = repeatCount ?? defaultRepeatCount
        let maxDur = maxDuration ?? maxDurationSeconds
        
        guard let url = resolveSoundURL(named: soundName) else {
            // 系统备用蜂鸣
            NSSound.beep()
            return
        }
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            self.audioPlayer = player
            
            self.isPlaying = true
            self.currentlyPlayingName = soundName
            self.currentPlayCount = 1
            self.targetRepeatCount = max(1, repeats)
            
            player.play()
            
            // 设定总截断保护定时器（例如 12 秒时截断，最后 2 秒执行平滑淡出）
            let fadeStartTime = max(1.0, maxDur - 2.0)
            scheduleFadeOut(after: fadeStartTime, totalDuration: maxDur)
            
            // 若为短音（小于 3 秒），且设置了多次重复，通过间隔定时器触发下一次
            if player.duration < 3.0 && self.targetRepeatCount > 1 {
                scheduleNextRepeat(interval: player.duration + 0.6)
            }
        } catch {
            NSSound.beep()
        }
    }
    
    /// 试听单次或全套
    public func preview(soundName: String, repeats: Int = 1) {
        play(soundName: soundName, repeatCount: repeats, maxDuration: 6.0)
    }
    
    /// 立即停止一切播放并清理定时器
    public func stop() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
        
        audioPlayer?.stop()
        audioPlayer = nil
        
        isPlaying = false
        currentlyPlayingName = nil
        currentPlayCount = 0
    }
    
    // MARK: - 内部播放辅助
    
    private func resolveSoundURL(named soundName: String) -> URL? {
        // 1. 检查是否为自定义音频
        if let custom = customSounds.first(where: { $0.name == soundName }) {
            let url = fileURL(for: custom)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        
        // 2. 检查系统内置声音目录 /System/Library/Sounds/<Name>.aiff
        let systemSoundPath = "/System/Library/Sounds/\(soundName).aiff"
        if FileManager.default.fileExists(atPath: systemSoundPath) {
            return URL(fileURLWithPath: systemSoundPath)
        }
        
        // 3. 兜底 NSSound 路径解析
        if NSSound(named: NSSound.Name(soundName)) != nil {
            return URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")
        }
        
        return URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")
    }
    
    private func scheduleNextRepeat(interval: TimeInterval) {
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self, self.isPlaying, let player = self.audioPlayer else { return }
            if self.currentPlayCount < self.targetRepeatCount {
                self.currentPlayCount += 1
                player.currentTime = 0
                player.play()
                
                if self.currentPlayCount < self.targetRepeatCount {
                    self.scheduleNextRepeat(interval: player.duration + 0.6)
                }
            }
        }
    }
    
    private func scheduleFadeOut(after delay: TimeInterval, totalDuration: TimeInterval) {
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.performFadeOut(duration: 2.0)
        }
    }
    
    private func performFadeOut(duration: TimeInterval) {
        guard let player = audioPlayer, isPlaying else { return }
        let steps = 20
        let stepInterval = duration / Double(steps)
        let initialVolume = player.volume
        var currentStep = 0
        
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] timer in
            guard let self = self, let p = self.audioPlayer, self.isPlaying else {
                timer.invalidate()
                return
            }
            currentStep += 1
            let ratio = 1.0 - (Double(currentStep) / Double(steps))
            p.volume = max(0, initialVolume * Float(ratio))
            
            if currentStep >= steps {
                timer.invalidate()
                self.stop()
            }
        }
    }
}
