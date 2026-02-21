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
class HotkeyManager: HotkeyManagerProtocol {
    enum HotkeyTransition: Equatable {
        case none
        case pressed
        case released
    }
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

        // 檢查輔助功能權限
        let isTrusted = AXIsProcessTrusted()
        logger.info("輔助功能權限狀態: \(isTrusted)")

        if !isTrusted {
            logger.warning("輔助功能權限未授予，無法創建 Event Tap")
        }

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
            // 嘗試取得更詳細的錯誤資訊
            let isTrusted = AXIsProcessTrusted()
            logger.error("無法創建 CGEventTap，請確認已授予輔助功能權限。AXIsProcessTrusted = \(isTrusted)")
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

        if type == .flagsChanged {
            let transition = processFlagsChangedEvent(keyCode: keyCode, flags: event.flags)
            switch transition {
            case .pressed:
                dispatchHotkeyEvent(isDown: true)
            case .released:
                dispatchHotkeyEvent(isDown: false)
            case .none:
                break
            }
        } else {
            // keyDown / keyUp 事件（一般按鍵，目前保留擴充彈性）
            guard keyCode == Int64(currentHotkey.scancode) else { return }
            let isNowDown = (type == .keyDown)
            if isNowDown != isTargetKeyDown {
                isTargetKeyDown = isNowDown
                dispatchHotkeyEvent(isDown: isNowDown)
            }
        }
    }

    /// T2-1：keycode 驅動的 flagsChanged 狀態機，回傳可重播的狀態轉換結果。
    @discardableResult
    func processFlagsChangedEvent(keyCode: Int64, flags: CGEventFlags) -> HotkeyTransition {
        guard keyCode == Int64(currentHotkey.scancode) else { return .none }

        let isNowDown: Bool
        let rawFlags = flags.rawValue

        switch currentHotkey {
        case .fn:
            isNowDown = flags.contains(.maskSecondaryFn)
        case .leftCommand:
            // NX_DEVICELCMDKEYMASK = 0x000008
            isNowDown = (rawFlags & 0x000008) != 0
        case .rightCommand:
            // NX_DEVICERCMDKEYMASK = 0x000010
            isNowDown = (rawFlags & 0x000010) != 0
        case .leftOption:
            // NX_DEVICELALTKEYMASK = 0x000020
            isNowDown = (rawFlags & 0x000020) != 0
        case .rightOption:
            // NX_DEVICERALTKEYMASK = 0x000040
            isNowDown = (rawFlags & 0x000040) != 0
        }

        guard isNowDown != isTargetKeyDown else { return .none }
        isTargetKeyDown = isNowDown
        return isNowDown ? .pressed : .released
    }

    /// 測試輔助：重置按鍵內部狀態
    func resetStateForTesting() {
        isTargetKeyDown = false
    }

    /// 派送快捷鍵按下/放開事件到主執行緒
    private func dispatchHotkeyEvent(isDown: Bool) {
        if isDown {
            logger.info("快捷鍵按下: \(self.currentHotkey.rawValue)")
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyPressed?()
            }
        } else {
            logger.info("快捷鍵放開: \(self.currentHotkey.rawValue)")
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyReleased?()
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
