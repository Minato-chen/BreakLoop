import Carbon
import AppKit

/// 全局热键类型定义
public enum HotKeyAction: UInt32 {
    case toggleStartWorkOrNext = 1 // 开始工作 / 下一轮
    case startRest = 2             // 立即休息
    case enterStandby = 3          // 进入待机
}

/// 基于 Carbon RegisterEventHotKey 的轻量纯原生全局快捷键管理器（零三方依赖）
public final class HotKeyManager {
    public static let shared = HotKeyManager()
    
    public var onAction: ((HotKeyAction) -> Void)?
    private var hotKeyRefs: [EventHotKeyRef] = []
    
    private init() {}
    
    public func registerDefaultHotKeys() {
        unregisterAll()
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr, let action = HotKeyAction(rawValue: hotKeyID.id) {
                    DispatchQueue.main.async {
                        HotKeyManager.shared.onAction?(action)
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
        
        // 注册默认组合快捷键：
        // 1. Option + Shift + S: 开始工作/下一轮
        registerHotKey(id: .toggleStartWorkOrNext, keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey | shiftKey))
        // 2. Option + Shift + R: 立即休息
        registerHotKey(id: .startRest, keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey | shiftKey))
        // 3. Option + Shift + Escape: 进入待机
        registerHotKey(id: .enterStandby, keyCode: UInt32(kVK_Escape), modifiers: UInt32(optionKey | shiftKey))
    }
    
    private func registerHotKey(id: HotKeyAction, keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x42524C50), id: id.rawValue) // 'BRLP'
        var hotKeyRef: EventHotKeyRef?
        let err = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if err == noErr, let ref = hotKeyRef {
            hotKeyRefs.append(ref)
        }
    }
    
    public func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }
}
