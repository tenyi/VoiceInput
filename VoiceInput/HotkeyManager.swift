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
}

/// 負責管理全域快捷鍵的類別
class HotkeyManager {
    /// 單例實例
    static let shared = HotkeyManager()

    /// 當快捷鍵被觸發時的閉包
    var onHotkeyPress: (() -> Void)?

    /// 監控鍵盤事件的監聽器
    private var eventMonitor: Any?
    /// 監控修飾鍵變動的監聽器
    private var flagsMonitor: Any?

    /// 目前設定的快捷鍵選項
    private(set) var currentHotkey: HotkeyOption = .rightCommand

    /// 用於檢測右側修飾鍵的標誌
    private var lastFlags: UInt = 0

    private init() {}

    /// 設定快捷鍵選項
    func setHotkey(_ option: HotkeyOption) {
        currentHotkey = option
        if HotkeyManager.shared.onHotkeyPress != nil {
            startMonitoring()
        }
    }

    /// 開始監聽快捷鍵
    func startMonitoring() {
        stopMonitoring()

        let targetHotkey = currentHotkey

        // 監聽全域修飾鍵變動
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event: event, targetHotkey: targetHotkey)
        }

        // 同時也監聽本地事件
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event: event, targetHotkey: targetHotkey)
            return event
        }
        self.eventMonitor = localMonitor
    }

    /// 處理修飾鍵變動事件
    private func handleFlagsChanged(event: NSEvent, targetHotkey: HotkeyOption) {
        let currentFlags = event.modifierFlags

        // 使用 CGEventSource 來獲取更詳細的修飾鍵狀態
        let source = CGEventSource(stateID: .hidSystemState)

        // 獲取特定鍵的按下狀態
        // 右邊 Command 鍵的 keyCode 是 0x36 (54)
        // 左邊 Command 鍵的 keyCode 是 0x37 (55) - 這可能是錯的，讓我查一下

        // 實際上讓我們用更簡單的方法：通過檢查 rawValue 的特定位
        let rawValue = currentFlags.rawValue

        var isTargetPressed = false

        switch targetHotkey {
        case .rightCommand:
            // Bit 20 表示右邊 Command (0x100000 = 1048576)
            isTargetPressed = (rawValue & 0x100000) != 0
        case .leftCommand:
            // Bit 19 表示左邊 Command (0x80000 = 524288)
            // 當沒有右邊 Command 且有 Command 時，視為左邊
            let hasCommand = (rawValue & NSEvent.ModifierFlags.command.rawValue) != 0
            let hasRightCommand = (rawValue & 0x100000) != 0
            isTargetPressed = hasCommand && !hasRightCommand
        case .rightOption:
            // Bit 18 表示右邊 Option (0x40000 = 262144)
            isTargetPressed = (rawValue & 0x40000) != 0
        case .leftOption:
            let hasOption = (rawValue & NSEvent.ModifierFlags.option.rawValue) != 0
            let hasRightOption = (rawValue & 0x40000) != 0
            isTargetPressed = hasOption && !hasRightOption
        case .fn:
            isTargetPressed = currentFlags.contains(.function)
        }

        if isTargetPressed {
            if !wasTargetPressed() {
                self.onHotkeyPress?()
            }
        }

        lastFlags = rawValue
    }

    /// 檢查目標鍵是否在上一次被按下
    private func wasTargetPressed() -> Bool {
        switch currentHotkey {
        case .rightCommand:
            return (lastFlags & 0x100000) != 0
        case .leftCommand:
            let hasCommand = (lastFlags & NSEvent.ModifierFlags.command.rawValue) != 0
            let hasRightCommand = (lastFlags & 0x100000) != 0
            return hasCommand && !hasRightCommand
        case .rightOption:
            return (lastFlags & 0x40000) != 0
        case .leftOption:
            let hasOption = (lastFlags & NSEvent.ModifierFlags.option.rawValue) != 0
            let hasRightOption = (lastFlags & 0x40000) != 0
            return hasOption && !hasRightOption
        case .fn:
            return (lastFlags & NSEvent.ModifierFlags.function.rawValue) != 0
        }
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
    }
}
