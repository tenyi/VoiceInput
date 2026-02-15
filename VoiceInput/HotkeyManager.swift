import Cocoa
import Carbon
import os

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

    /// 修飾鍵的 scancode
    var scancode: UInt16 {
        switch self {
        case .leftCommand: return 0x37  // 55 - Left Command
        case .rightCommand: return 0x36 // 54 - Right Command
        case .leftOption: return 0x3B   // 59 - Left Option
        case .rightOption: return 0x3C  // 60 - Right Option
        case .fn: return 0x3F            // 63 - Fn
        }
    }
}

/// 負責管理全域快捷鍵的類別
class HotkeyManager {
    /// 單例實例
    static let shared = HotkeyManager()
    
    /// 日誌記錄
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "HotkeyManager")

    /// 當快捷鍵被按下時的閉包（開始錄音）
    var onHotkeyPressed: (() -> Void)?

    /// 當快捷鍵被放開時的閉包（停止錄音，開始轉寫）
    var onHotkeyReleased: (() -> Void)?

    /// 目前設定的快捷鍵選項
    private(set) var currentHotkey: HotkeyOption = .rightCommand

    /// 追蹤目標鍵是否正在被按下
    private var isTargetKeyDown = false

    /// Event tap
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    /// 設定快捷鍵選項
    func setHotkey(_ option: HotkeyOption) {
        currentHotkey = option
        if onHotkeyPressed != nil || onHotkeyReleased != nil {
            startMonitoring()
        }
    }

    /// 開始監聽快捷鍵（使用 CGEventTap，需要輔助功能權限）
    func startMonitoring() {
        stopMonitoring()

        //let targetHotkey = currentHotkey

        // 設置事件過濾 mask
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        // 回調函數
        // 回調函數（listenOnly 模式下回傳值會被忽略）
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            // 檢查 Event Tap 是否被系統停用（例如因為處理超時）
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon = refcon {
                    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                        manager.logger.warning("Event Tap 被系統停用，已自動恢復 (原因類型: \(type.rawValue))")
                    }
                }
                // 對於這類通知事件，直接回傳原事件
                return Unmanaged.passUnretained(event)
            }
            
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            manager.handleEvent(proxy: proxy, type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // 創建 event tap
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: refcon
        ) else {
            logger.error("無法創建 CGEventTap，請確認已授予輔助功能權限")
            return
        }

        eventTap = tap

        // 添加到 run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// 處理事件
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // 修飾鍵只會觸發 .flagsChanged 事件，不會觸發 .keyDown / .keyUp
        // 因此必須透過 event.flags 來判斷修飾鍵是按下還是放開

        // 檢查是否是目標鍵
        var isTargetKey: Bool

        if type == .flagsChanged {
            // flagsChanged 事件：透過 keyCode（scancode）判斷是哪個修飾鍵
            if currentHotkey == .fn {
                // Fn 鍵：透過 .maskSecondaryFn 的狀態變化來判斷
                // 只在 fn flag 狀態「真正改變」時才視為目標鍵事件
                // 避免其他修飾鍵的 flagsChanged 事件被誤判為 fn 鍵事件
                let fnIsDown = event.flags.contains(.maskSecondaryFn)
                isTargetKey = (fnIsDown != isTargetKeyDown)
            } else {
                // 其他修飾鍵：透過 keyCode 比對 scancode
                isTargetKey = keyCode == Int64(currentHotkey.scancode)
            }
        } else {
            // keyDown / keyUp 事件（一般按鍵，目前不使用）
            isTargetKey = keyCode == Int64(currentHotkey.scancode)
        }

        // 判斷修飾鍵是否處於「按下」狀態
        let isKeyDown: Bool
        if type == .flagsChanged {
            // 修飾鍵：透過 flags 判斷按下或放開
            switch currentHotkey {
            case .leftCommand, .rightCommand:
                isKeyDown = event.flags.contains(.maskCommand)
            case .leftOption, .rightOption:
                isKeyDown = event.flags.contains(.maskAlternate)
            case .fn:
                isKeyDown = event.flags.contains(.maskSecondaryFn)
            }
        } else {
            // 一般按鍵
            isKeyDown = (type == .keyDown)
        }

        if isTargetKey {
            if isKeyDown && !isTargetKeyDown {
                // 按下
                logger.info("快捷鍵按下: \(self.currentHotkey.rawValue)")
                isTargetKeyDown = true
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyPressed?()
                }
            } else if !isKeyDown && isTargetKeyDown {
                // 放開
                logger.info("快捷鍵放開: \(self.currentHotkey.rawValue)")
                isTargetKeyDown = false
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyReleased?()
                }
            }
        }
    }

    /// 停止監聽快捷鍵
    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isTargetKeyDown = false
    }
}
