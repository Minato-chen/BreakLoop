import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 独立顶级大类：声音与提醒中心（全套声音管理、自定义音频导入、到点提醒形式、多轮重复与长音末尾平滑渐弱截断）
public struct SoundManagerView: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var soundManager = SoundManager.shared
    @State private var hasAppliedSoundsToAll: Bool = false
    @State private var hasAppliedMessagesToAll: Bool = false
    
    public init(engine: TimerEngine) {
        self.engine = engine
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                // 顶部标题
                headerSection
                
                Divider()
                
                // 1. 全局提醒形式（弹窗与声音 / 仅声音 / 仅弹窗 / 静音）
                alertStyleSection
                
                Divider()
                
                // 2. 全局提示策略（重复次数、截断保护、音量）
                strategySection
                
                Divider()
                
                // 3. 自定义音频管理库
                customSoundsSection
                
                Divider()
                
                // 4. 系统内置声音库
                builtinSoundsSection
            }
            .padding(24)
            .frame(maxWidth: 680)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
    }
    
    // MARK: - 顶部标题区
    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 26))
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 3) {
                Text("声音与提醒")
                    .font(.system(size: 18, weight: .bold))
                Text("配置工休提醒形式、设定提示音效、导入个人音频与长音平滑渐弱截断保护")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if soundManager.isPlaying {
                Button(action: { soundManager.stop() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                        Text("停止播放")
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
    
    // MARK: - 提醒形式卡片（融入声音与提醒中心）
    private var alertStyleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("提醒形式")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("到点提醒形式")
                        .font(.system(size: 13, weight: .medium))
                    Text("控制工休切换时的交互行为（支持弹窗与声音、仅声音、仅弹窗或完全静音）")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Picker("", selection: $engine.preset.alertStyle) {
                    Text("弹窗与声音").tag(AlertStyle.both)
                    Text("仅声音").tag(AlertStyle.sound)
                    Text("仅弹窗").tag(AlertStyle.popup)
                    Text("静音").tag(AlertStyle.none)
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                .onChange(of: engine.preset.alertStyle) { _ in
                    PresetStore.shared.activePreset = engine.preset
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
    
    // MARK: - 全局提示策略卡片
    private var strategySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("全局提醒策略")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                // 1. 重复次数（默认 3 次）
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("提示音连续重复播放")
                            .font(.system(size: 13, weight: .medium))
                        Text("避免单次提示音太微弱被遗漏，连续播放有节奏的多次提示")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Picker("", selection: $soundManager.defaultRepeatCount) {
                        Text("1 次 (轻柔)").tag(1)
                        Text("2 次").tag(2)
                        Text("3 次 (默认推荐)").tag(3)
                        Text("5 次 (强烈警示)").tag(5)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
                
                Divider()
                
                // 2. 长音频截断与末尾渐弱
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("长音频播放最长持续")
                            .font(.system(size: 13, weight: .medium))
                        Text("播放长音乐或闹铃时，自动于截断时间停止，并在末尾 2 秒平滑淡出渐弱")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Picker("", selection: $soundManager.maxDurationSeconds) {
                        Text("10 秒").tag(10.0)
                        Text("12 秒 (默认)").tag(12.0)
                        Text("15 秒").tag(15.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
                
                Divider()
                
                // 3. 独立提示音量
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("提示音量")
                            .font(.system(size: 13, weight: .medium))
                        Text("独立控制 BreakLoop 提醒发声响度 (\(Int(soundManager.volume * 100))%)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Slider(value: $soundManager.volume, in: 0.1...1.0)
                            .frame(width: 120)
                        
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // 4. 全局默认提示音
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("全局默认提示音")
                                .font(.system(size: 13, weight: .medium))
                            Text("新建专注或休息模块时的初始提示音")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: applyDefaultSoundsToAllBlocks) {
                            HStack(spacing: 4) {
                                if hasAppliedSoundsToAll {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.green)
                                    Text("已覆盖提示音")
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("应用声音到全部")
                                }
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("将当前选中的专注默认音与休息默认音，覆盖同步到所有方案现存的模块中")
                    }
                    
                    HStack(spacing: 20) {
                        HStack(spacing: 8) {
                            Text("专注默认音:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("", selection: $soundManager.defaultWorkSound) {
                                ForEach(soundManager.allAvailableSounds()) { option in
                                    Text(option.displayName).tag(option.identifier)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 135)
                            
                            Button(action: {
                                soundManager.preview(soundName: soundManager.defaultWorkSound, repeats: soundManager.defaultRepeatCount)
                            }) {
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("试听")
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Text("休息默认音:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("", selection: $soundManager.defaultRestSound) {
                                ForEach(soundManager.allAvailableSounds()) { option in
                                    Text(option.displayName).tag(option.identifier)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 135)
                            
                            Button(action: {
                                soundManager.preview(soundName: soundManager.defaultRestSound, repeats: soundManager.defaultRepeatCount)
                            }) {
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("试听")
                        }
                    }
                }
                
                Divider()
                
                // 5. 全局默认提醒文案
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("全局默认提醒文案")
                                .font(.system(size: 13, weight: .medium))
                            Text("新建专注或休息模块时的初始弹窗与通知文案")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: applyDefaultMessagesToAllBlocks) {
                            HStack(spacing: 4) {
                                if hasAppliedMessagesToAll {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.green)
                                    Text("已覆盖文案")
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "text.badge.checkmark")
                                    Text("应用文案到全部")
                                }
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("将当前设定的专注默认文案与休息默认文案，覆盖同步到所有方案现存的模块中")
                    }
                    
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            Text("专注默认文案:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 82, alignment: .trailing)
                            TextField("例如：专注结束，该休息一下了", text: $soundManager.defaultWorkMessage)
                                .textFieldStyle(.roundedBorder)
                            
                            if soundManager.defaultWorkMessage != "专注结束，该休息一下了" {
                                Button(action: { soundManager.defaultWorkMessage = "专注结束，该休息一下了" }) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("恢复为初始默认文案")
                            }
                        }
                        
                        HStack(spacing: 10) {
                            Text("休息默认文案:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 82, alignment: .trailing)
                            TextField("例如：休息结束，准备开始下一轮专注", text: $soundManager.defaultRestMessage)
                                .textFieldStyle(.roundedBorder)
                            
                            if soundManager.defaultRestMessage != "休息结束，准备开始下一轮专注" {
                                Button(action: { soundManager.defaultRestMessage = "休息结束，准备开始下一轮专注" }) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("恢复为初始默认文案")
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    private func applyDefaultSoundsToAllBlocks() {
        let workSound = soundManager.defaultWorkSound
        let restSound = soundManager.defaultRestSound
        
        for pIdx in PresetStore.shared.presets.indices {
            for bIdx in PresetStore.shared.presets[pIdx].blocks.indices {
                if PresetStore.shared.presets[pIdx].blocks[bIdx].type == .work {
                    PresetStore.shared.presets[pIdx].blocks[bIdx].soundName = workSound
                } else {
                    PresetStore.shared.presets[pIdx].blocks[bIdx].soundName = restSound
                }
            }
        }
        PresetStore.shared.save()
        if let current = PresetStore.shared.presets.first(where: { $0.id == engine.preset.id }) {
            engine.preset = current
        }
        withAnimation {
            hasAppliedSoundsToAll = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                hasAppliedSoundsToAll = false
            }
        }
    }
    
    private func applyDefaultMessagesToAllBlocks() {
        let workMsg = soundManager.defaultWorkMessage
        let restMsg = soundManager.defaultRestMessage
        
        for pIdx in PresetStore.shared.presets.indices {
            for bIdx in PresetStore.shared.presets[pIdx].blocks.indices {
                if PresetStore.shared.presets[pIdx].blocks[bIdx].type == .work {
                    PresetStore.shared.presets[pIdx].blocks[bIdx].message = workMsg
                } else {
                    PresetStore.shared.presets[pIdx].blocks[bIdx].message = restMsg
                }
            }
        }
        PresetStore.shared.save()
        if let current = PresetStore.shared.presets.first(where: { $0.id == engine.preset.id }) {
            engine.preset = current
        }
        withAnimation {
            hasAppliedMessagesToAll = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                hasAppliedMessagesToAll = false
            }
        }
    }
    
    // MARK: - 自定义音频管理
    private var customSoundsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("自定义音频库 (\(soundManager.customSounds.count))")
                        .font(.system(size: 14, weight: .bold))
                    Text("支持导入 MP3、WAV、M4A 等个人音效，文件将安全存储于本地沙盒")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: importAudioFile) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("导入本地音频")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            if soundManager.customSounds.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.35))
                        Text("尚未导入自定义音频")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("点击上方“导入本地音频”添加你喜欢的铃声或白噪音")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(soundManager.customSounds) { sound in
                        let isThisPlaying = soundManager.isPlaying && soundManager.currentlyPlayingName == sound.name
                        
                        HStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .font(.system(size: 14))
                                .foregroundColor(isThisPlaying ? .accentColor : .secondary)
                                .frame(width: 20)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sound.name)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(formatDuration(sound.duration))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // 试听 / 停止
                            Button(action: {
                                if isThisPlaying {
                                    soundManager.stop()
                                } else {
                                    soundManager.play(soundName: sound.name)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isThisPlaying ? "stop.fill" : "play.fill")
                                    Text(isThisPlaying ? "停止" : "试听")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            // 删除
                            Button(action: {
                                soundManager.deleteSound(id: sound.id)
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .help("删除此音频")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }
    
    // MARK: - 系统内置声音库
    private var builtinSoundsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("系统预设声音")
                .font(.system(size: 14, weight: .bold))
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(SoundManager.builtinSounds) { sound in
                    let isThisPlaying = soundManager.isPlaying && soundManager.currentlyPlayingName == sound.identifier
                    
                    Button(action: {
                        if isThisPlaying {
                            soundManager.stop()
                        } else {
                            soundManager.preview(soundName: sound.identifier, repeats: soundManager.defaultRepeatCount)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: isThisPlaying ? "stop.circle.fill" : "speaker.wave.2.circle.fill")
                                .foregroundColor(isThisPlaying ? .accentColor : .secondary)
                            Text(sound.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(isThisPlaying ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - 辅助操作
    private func importAudioFile() {
        let openPanel = NSOpenPanel()
        openPanel.title = "选择提示音文件"
        openPanel.prompt = "导入"
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.allowedContentTypes = [
            UTType.audio,
            UTType.mp3,
            UTType.wav,
            UTType(filenameExtension: "m4a") ?? .audio,
            UTType.aiff
        ]
        
        if openPanel.runModal() == .OK {
            for url in openPanel.urls {
                soundManager.importSound(from: url)
            }
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 {
            return "\(s) 秒"
        }
        return "\(s / 60)分\(s % 60)秒"
    }
}
