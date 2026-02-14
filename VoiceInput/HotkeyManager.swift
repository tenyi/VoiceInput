import Cocoa
import Carbon

/// 快捷鍵選項
enum HotkeyOption: String, CaseIterable {
    case rightCommand = "rightCommand"
    case leftCommand = "leftCommand"
    case fn = "fn"
    case rightOption = "rightOption"
    case leftOption = "leftOption"

    var displayName: String {
        switch self {
        case .rightCommand: return "右邊 Command (⌘)"
        case .leftCommand: return "左邊 Command (⌘)"
        case .fn: return "Fn 鍵"
        case .rightOption: return "右邊 Option (⌥)"
        case .leftOption: return "左邊 Option (⌥)"
        }
    }

    /// 修飾鍵的 scancode (使用 CGEvent 获取)
    var scancode: UInt16 {
        switch self {
        case .leftCommand: return 0x37  // 55 - Left Command
        case .rightCommand: return 0x36 // 54 - Right Command
        case .leftOption: return 0x3B   // 59 - Left Option
        case .rightOption: return 0x3C  // 60 - Right Option
        case .fn: return 0x3F            // 63 - Fn
        }
    }

    /// 對應的 CGEventFlag
    var eventFlag: CGEventFlags {
        switch self {
        case .leftCommand, .rightCommand: return .maskCommand
        case .leftOption, .rightOption: return .maskAlternate
        case .fn: return .maskShift  // Fn 沒有對應的 flag，需要特殊處理
        }
    }
}

/// 負責管理全域快捷鍵的類別
class HotkeyManager {
    /// 單例實例
    static let shared = HotkeyManager()

    /// 當快捷鍵被按下時的閉包（開始錄音）
    var onHotkeyPressed: (() -> Void)?

    /// 當快捷鍵被放開時的閉包（停止錄音，開始轉寫）
    var onHotkeyReleased: (() -> Void)?

    /// 監控鍵盤事件的監聽器
    private var eventMonitor: Any?
    private var flagsMonitor: Any?

    /// 目前設定的快捷鍵選項
    private(set) var currentHotkey: HotkeyOption = .rightCommand

    /// 追蹤目標鍵是否正在被按下
    private var isTargetKeyDown = false

    private init() {}

    /// 設定快捷鍵選項
    func setHotkey(_ option: HotkeyOption) {
        currentHotkey = option
        if onHotkeyPressed != nil || onHotkeyReleased != nil {
            startMonitoring()
        }
    }

    /// 開始監聽快捷鍵
    func startMonitoring() {
        stopMonitoring()

        let targetHotkey = currentHotkey

        // 使用 CGEventTap 監聽鍵盤事件，這可以獲取準確的 scancode
        // 設置事件 tap 回調
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        // 建立一個回調來處理事件
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            manager.handleEvent(proxy: proxy, type: type, event: event)
            return Unmanaged.passRetained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // 建立 event tap
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: refcon
        ) else {
            // 如果無法創建 event tap，回退到使用 NSEvent 監控
            setupFallbackMonitoring(targetHotkey: targetHotkey)
            return
        }

        // 啟用 event tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    /// 回退方案：使用 NSEvent 監控（當 CGEventTap 失敗時）
    private func setupFallbackMonitoring(targetHotkey: HotkeyOption) {
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event: event, targetHotkey: targetHotkey)
        }

        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event: event, targetHotkey: targetHotkey)
            return event
        }
        self.eventMonitor = localMonitor
    }

    /// 處理 CGEventTap 回調的事件
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // 檢查是否是目標鍵
        let isTargetKey: Bool

        if currentHotkey == .fn {
            // Fn 鍵需要通過 flagsChanged 來檢測
            // CGEventFlags 沒有 .function 成員，需要通過 rawValue 判斷
            let flags = event.flags
            let rawValue = flags.rawValue
            // Fn 鍵的 flag 是 0x10000000 (268435456)
            isTargetKey = (rawValue & 0x10000000) != 0
        } else {
            isTargetKey = keyCode == Int64(currentHotkey.scancode)
        }

        let isKeyDown = (type == .keyDown)

        if isTargetKey {
            if isKeyDown && !isTargetKeyDown {
                // 按下
                isTargetKeyDown = true
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyPressed?()
                }
            } else if !isKeyDown && isTargetKeyDown {
                // 放開
                isTargetKeyDown = false
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyReleased?()
                }
            }
        }
    }

    /// 處理 NSEvent 回退方案的事件
    private func handleFlagsChanged(event: NSEvent, targetHotkey: HotkeyOption) {
        let currentFlags = event.modifierFlags

        let isTargetPressed: Bool

        switch targetHotkey {
        case .rightCommand:
            // 使用 CGEvent 檢測右邊 Command
            isTargetPressed = checkKeyDown(keyCode: 0x36)
        case .leftCommand:
            isTargetPressed = checkKeyDown(keyCode: 0x37)
        case .rightOption:
            isTargetPressed = checkKeyDown(keyCode: 0x3C)
        case .leftOption:
            isTargetPressed = checkKeyDown(keyCode: 0x3B)
        case .fn:
            isTargetPressed = currentFlags.contains(.function)
        }

        if isTargetPressed && !isTargetKeyDown {
            isTargetKeyDown = true
            onHotkeyPressed?()
        } else if !isTargetPressed && isTargetKeyDown {
            isTargetKeyDown = false
            onHotkeyReleased?()
        }
    }

    /// 使用 CGEvent 檢查特定鍵是否被按下
    private func checkKeyDown(keyCode: UInt16) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        return CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) != nil
    }

    /// 停止監聽快捷鍵
    func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        isTargetKeyDown = false
    }
}
