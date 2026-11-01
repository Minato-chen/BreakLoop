import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let engine = TimerEngine(preset: PresetStore.shared.activePreset)
    lazy var idleMonitor = IdleMonitor(engine: engine)
    
    private var mainWindow: NSWindow?
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 单实例自检互斥保护：杜绝多进程后台并存与提示音错乱
        enforceSingleInstance()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 标准 App 策略：有 Dock 图标，支持主窗口
        NSApp.setActivationPolicy(.regular)
        
        // 0. 刷新应用图标 (确保 Dock 与运行态图标即刻生效苹果风双弧呼吸环)
        if let iconImage = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = iconImage
        }
        
        // 1. 绑定到点提醒
        engine.onAlertTriggered = { [weak self] event in
            guard let self = self else { return }
            AlertManager.shared.trigger(
                event: event,
                onPrimaryAction: { [weak self] in
                    guard let self = self else { return }
                    // 核心逻辑修复：
                    // 若当前模块未开启自动推进（此时计时器停在 00:00 等待人工确认），点击主按钮才推进到下一步；
                    // 若已开启自动推进（工作结束时已自动切换并正在进行休息计时），点击「离开工位」仅为关闭浮窗确认已知晓，
                    // 绝不能再次触发 advanceToNextBlock()，否则会导致刚开始的休息被瞬间跳过直接回到专注！
                    if !event.autoAdvanced {
                        self.engine.advanceToNextBlock()
                    }
                },
                onSnooze: { [weak self] in
                    self?.engine.snooze(
                        minutes: event.snoozeMinutes,
                        rewindingTo: event.blockIndex,
                        actionType: event.actionType
                    )
                },
                onDismiss: { [weak self] in
                    guard let self = self else { return }
                    // 若用户直接关闭弹窗（未点击延时与主行动），兜底平滑推进至下一步，绝不挂在 0 秒停滞
                    if !event.autoAdvanced {
                        self.engine.advanceToNextBlock()
                    }
                }
            )
        }
        
        // 2. 启动空闲/休眠监听
        idleMonitor.start()
        
        // 3. 注册全局快捷键
        HotKeyManager.shared.onAction = { [weak self] action in
            guard let self = self else { return }
            switch action {
            case .toggleStartWorkOrNext:
                if self.engine.mode == .resting {
                    self.engine.startNextWorkCycle()
                } else if self.engine.mode == .working {
                    self.engine.advanceToNextBlock()
                } else if self.engine.mode == .standby {
                    self.engine.startWork()
                }
            case .startRest:
                self.engine.startRest()
            case .enterStandby:
                self.engine.enterStandby(reason: .manual)
            }
        }
        if HotKeyManager.isEnabledInUserDefaults {
            HotKeyManager.shared.registerDefaultHotKeys()
        }
        
        // 4. 自动检查软件版本更新（若开启）
        if UserDefaults.standard.object(forKey: "BreakLoop.AutoCheckUpdate") == nil || UserDefaults.standard.bool(forKey: "BreakLoop.AutoCheckUpdate") {
            UpdateChecker.shared.checkForUpdates(isUserInitiated: false)
        }
        
        // 5. 启动默认打开主窗口
        showMainWindow()
    }
    
    // 点击 Dock 图标时重新唤起主窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }
    
    // MARK: - 主窗口管理（标准 macOS: 关闭窗口只隐藏，不退出应用）
    func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 880, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.minSize = NSSize(width: 860, height: 550)
            window.title = "BreakLoop"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.center()
            window.delegate = self
            window.contentView = NSHostingView(rootView: MainAppView(engine: engine))
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // 点击左上角红叉时仅隐藏窗口，不退出后台计时
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
    
    // MARK: - 单实例互斥与退出生命周期管理
    private func enforceSingleInstance() {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let bundleId = Bundle.main.bundleIdentifier ?? "com.breakloop.BreakLoop"
        
        let allApps = NSWorkspace.shared.runningApplications
        let otherInstances = allApps.filter { app in
            guard app.processIdentifier != currentPid else { return false }
            return app.bundleIdentifier == bundleId || app.localizedName == "BreakLoop"
        }
        
        guard !otherInstances.isEmpty else { return }
        
        let currentIsProduction = Bundle.main.bundlePath.hasPrefix("/Applications")
        for oldApp in otherInstances {
            let oldPath = oldApp.bundleURL?.path ?? ""
            // 若历史残留实例来自非 /Applications 目录（例如 Xcode 临时调试进程），直接清理终止
            if currentIsProduction && !oldPath.hasPrefix("/Applications") {
                oldApp.terminate()
            } else {
                // 若已有正常实例正在运行，唤起其主窗口，当前多余进程即刻退出，杜绝重复并发
                oldApp.activate(options: [.activateIgnoringOtherApps])
                exit(0)
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // 彻底退出清理：停止一切计时器、空闲监听、全局热键与声音，确保不留僵死后台
        idleMonitor.stop()
        HotKeyManager.shared.unregisterAll()
        SoundManager.shared.stop()
        AlertManager.shared.closePanel()
        engine.enterStandby(reason: .manual)
    }
}

@main
struct BreakLoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("BreakLoop.MenuBarShowTime") private var menuBarShowTime: Bool = true
    
    var body: some Scene {
        // 菜单栏保留轻量控制入口
        MenuBarExtra {
            MenuBarContent(
                engine: appDelegate.engine,
                onOpenDashboard: {
                    appDelegate.showMainWindow()
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
        } label: {
            MenuBarLabelView(engine: appDelegate.engine, showTime: menuBarShowTime)
        }
    }
}

/// 菜单栏图标与文字响应视图（直接绑定 @ObservedObject，确保模式或倒计时变化时 0 延迟即时重绘）
struct MenuBarLabelView: View {
    @ObservedObject var engine: TimerEngine
    let showTime: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: menuBarIcon)
            if showTime {
                Text(engine.menuBarText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
        }
    }
    
    private var menuBarIcon: String {
        if engine.isPaused {
            return "pause.circle.fill"   // 临时暂停：显式暂停标识
        }
        switch engine.mode {
        case .working:
            return "record.circle"       // 专注中：聚焦环
        case .resting:
            return "cup.and.saucer.fill" // 休息中：咖啡杯
        case .standby:
            return "circle.dashed"       // 待机中：流转环
        }
    }
}

