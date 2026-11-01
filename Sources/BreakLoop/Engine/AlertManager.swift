import AppKit
import AudioToolbox

/// 提醒浮窗窗口（符合 macOS 原生风格、非抢占式、全桌面空间可见）
public final class AlertPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
    }
}

/// 提醒与声音管理器
public final class AlertManager {
    public static let shared = AlertManager()
    
    private var alertWindowController: NSWindowController?
    
    public init() {}
    
    /// 触发提醒
    public func trigger(
        event: AlertTriggerEvent,
        onPrimaryAction: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        // 1. 播放声音（支持多轮重复、自定义声音以及长音平滑渐弱截断）
        if event.style == .sound || event.style == .both {
            SoundManager.shared.play(soundName: event.soundName)
        }
        
        // 2. 弹窗提示
        if event.style == .popup || event.style == .both {
            showPanel(
                event: event,
                onPrimaryAction: { [weak self] in
                    self?.dismiss()
                    onPrimaryAction()
                },
                onSnooze: { [weak self] in
                    self?.dismiss()
                    onSnooze()
                },
                onDismiss: { [weak self] in
                    self?.dismiss()
                    onDismiss()
                }
            )
        }
    }
    
    public func dismiss() {
        SoundManager.shared.stop()
        closePanel()
    }
    
    public func closePanel() {
        alertWindowController?.close()
        alertWindowController = nil
    }
    
    private func playSound(named soundName: String) {
        if let sound = NSSound(named: NSSound.Name(soundName)) {
            sound.play()
        } else {
            // 系统备用蜂鸣声
            NSSound.beep()
        }
    }
    
    private func showPanel(
        event: AlertTriggerEvent,
        onPrimaryAction: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        // 仅关闭前一个弹窗（若有），绝不停止刚刚触发播放的提示音
        closePanel()
        
        let alertView = AlertView(
            event: event,
            onPrimaryAction: onPrimaryAction,
            onSnooze: onSnooze,
            onDismiss: onDismiss
        )
        
        let hostingView = NSHostingView(rootView: alertView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 380, height: 120)
        let fittingSize = hostingView.fittingSize
        let width: CGFloat = 380
        let targetHeight = max(130, ceil(fittingSize.height))
        
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let x = screenRect.midX - (width / 2)
        let y = screenRect.maxY - targetHeight - 80 // 居中靠上
        
        let panel = AlertPanel(contentRect: NSRect(x: x, y: y, width: width, height: targetHeight))
        panel.contentView = hostingView
        
        alertWindowController = NSWindowController(window: panel)
        panel.orderFrontRegardless()
    }
}

import SwiftUI

/// 原生精致磨砂毛玻璃风格的提醒浮窗视图（自适应高度，长文案自动折行无截断）
public struct AlertView: View {
    let event: AlertTriggerEvent
    let onPrimaryAction: () -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void
    
    public var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: event.actionType == .workCompleted ? "cup.and.saucer.fill" : "laptopcomputer")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(event.actionType == .workCompleted ? .green : .blue)
                    .frame(width: 32, height: 32)
                
                // 咖啡/电脑图标旁边直接展示文案（自定义文案优先，默认文案兜底；支持多行自动折行）
                Text(event.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.6))
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: 12) {
                Button(action: onSnooze) {
                    Text("稍后 \(event.snoozeMinutes) 分钟")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Button(action: onPrimaryAction) {
                    Text(event.actionType == .workCompleted ? "离开工位" : "开始专注")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
