import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let engine = TimerEngine(preset: PresetStore.shared.activePreset)
    lazy var idleMonitor = IdleMonitor(engine: engine)
    
    private var mainWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 标准 App 策略：有 Dock 图标，支持主窗口
        NSApp.setActivationPolicy(.regular)
        
        // 1. 绑定到点提醒
        engine.onAlertTriggered = { [weak self] event in
            guard let self = self else { return }
            AlertManager.shared.trigger(
                event: event,
                onStartRest: { [weak self] in
                    self?.engine.startRest()
                },
                onSnooze: { [weak self] in
                    self?.engine.snooze(minutes: 5)
                },
                onDismiss: {}
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
                } else if self.engine.mode == .standby {
                    self.engine.startWork()
                }
            case .startRest:
                self.engine.startRest()
            case .enterStandby:
                self.engine.enterStandby(reason: .manual)
            }
        }
        HotKeyManager.shared.registerDefaultHotKeys()
        
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
                contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "BreakLoop"
            window.titlebarAppearsTransparent = true
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
}

@main
struct BreakLoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("BreakLoop.MenuBarShowTime") private var menuBarShowTime: Bool = false
    
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
            HStack(spacing: 4) {
                Image(systemName: menuBarIcon)
                if menuBarShowTime {
                    Text(appDelegate.engine.menuBarText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
            }
        }
    }
    
    private var menuBarIcon: String {
        switch appDelegate.engine.mode {
        case .working:
            return "book.closed.fill"   // 统一为书本
        case .resting:
            return "cup.and.saucer.fill" // 统一为咖啡
        case .standby:
            return "leaf.fill"           // 待机绿叶
        }
    }
}

