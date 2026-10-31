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
        onStartRest: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        // 1. 播放声音
        if event.style == .sound || event.style == .both {
            playSound(named: event.soundName)
        }
        
        // 2. 弹窗提示
        if event.style == .popup || event.style == .both {
            showPanel(
                message: event.message,
                onStartRest: { [weak self] in
                    self?.dismiss()
                    onStartRest()
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
        message: String,
        onStartRest: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        dismiss()
        
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let width: CGFloat = 360
        let height: CGFloat = 160
        let x = screenRect.midX - (width / 2)
        let y = screenRect.maxY - height - 80 // 居中靠上
        
        let panel = AlertPanel(contentRect: NSRect(x: x, y: y, width: width, height: height))
        
        let alertView = AlertView(
            message: message,
            onStartRest: onStartRest,
            onSnooze: onSnooze,
            onDismiss: onDismiss
        )
        
        let hostingView = NSHostingView(rootView: alertView)
        panel.contentView = hostingView
        
        alertWindowController = NSWindowController(window: panel)
        panel.orderFrontRegardless()
    }
}

import SwiftUI

/// 原生精致磨砂毛玻璃风格的提醒浮窗视图
public struct AlertView: View {
    let message: String
    let onStartRest: () -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void
    
    public var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "eyes")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("该休息一下了")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.7))
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: 12) {
                Button(action: onSnooze) {
                    Text("稍后 5 分钟")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Button(action: onStartRest) {
                    Text("开始休息")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
