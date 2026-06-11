import Foundation
import ApplicationServices
import Cocoa
import Carbon.HIToolbox

/// 負責模擬鍵盤輸入與處理輔助功能權限
class InputSimulator: InputSimulatorProtocol {
    /// 單例 (Singleton) 實例
    static let shared = InputSimulator()

    /// 剪貼簿還原延遲（秒），確保目標應用程式有足夠時間讀取 Cmd+V
    /// 此值允許 UI 事件循環處理完貼上動作
    private static let clipboardRestoreDelay: Double = 0.2

    /// 權限管理員
    private let permissionManager = PermissionManager.shared

    // MARK: - 測試用注入

    /// B3.2:剪貼簿抽象;測試可注入 MockPasteboard,生產環境使用 NSPasteboard.general
    var pasteboard: PasteboardProtocol = NSPasteboard.general

    /// B3.2:測試可注入 closure 取代 CGEvent 鍵盤模擬;生產環境留 nil
    var simulateKeyEventsOverride: (() -> Void)?

    /// A1.6:測試可注入 TestClock 跳過剪貼簿還原延遲;生產環境使用 SystemClock
    var clock: Clock = SystemClock()

    init() {}

    /// 檢查應用程式是否具有輔助功能 (Accessibility) 權限
    /// Checks if the app is trusted for accessibility.
    /// - Parameter showAlert: 是否在權限不足時顯示提示（預設為 true）
    /// - Returns: 若已授權則回傳 true
    func checkAccessibilityPermission(showAlert: Bool = true) -> Bool {
        let trusted = AXIsProcessTrusted()

        if !trusted && showAlert {
            // 權限不足，顯示提示
            permissionManager.showPermissionAlert(for: .accessibility)
        }

        return trusted
    }

    /// 請求輔助功能權限並顯示系統對話框
    /// - Parameter completion: 授權結果的回調
    func requestAccessibilityPermission(completion: @escaping (Bool) -> Void) {
        permissionManager.requestPermission(.accessibility, completion: completion)
    }
    
    /// 插入文字到當前焦點視窗
    /// Inserts text into the current focused window.
    /// - Parameter text: 要插入的文字
    func insertText(_ text: String) {
        // 方法 1: 使用剪貼簿與 Cmd+V (適用於較長文字)
        pasteText(text)
        
        // 方法 2: CGEvent 鍵盤模擬 (適用於單一字元，但較慢)
        // 目前對於長文本，貼上 (Paste) 效果較佳
    }
    
    /// 透過剪貼簿與模擬 Cmd+V 貼上文字
    /// B3.2:從 private 改為 internal,以便測試直接驗證剪貼簿邏輯
    func pasteText(_ text: String) {
        // 備份現有剪貼簿內容（保留所有型別，避免覆蓋圖片/檔案等資料）
        // 注意：NSPasteboardItem 不保證支援 copy()，改用型別+資料重建快照
        let oldItemSnapshots: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            var snapshot: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    snapshot[type] = data
                }
            }
            return snapshot
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let initialChangeCount = pasteboard.changeCount

        // 模擬 Cmd+V 組合鍵
        if let simulateKeyEvents = simulateKeyEventsOverride {
            // B3.2:測試注入,跳過真實 CGEvent
            simulateKeyEvents()
        } else {
            let source = CGEventSource(stateID: .hidSystemState)

            let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
            let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false)

            cmdDown?.flags = .maskCommand
            vDown?.flags = .maskCommand
            vUp?.flags = .maskCommand

            cmdDown?.post(tap: .cghidEventTap)
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
            cmdUp?.post(tap: .cghidEventTap)
        }

        // 延遲一小段時間後恢復剪貼簿內容，確保目標應用程式有足夠時間讀取 Cmd+V
        // A1.6:透過注入的 clock 取代 DispatchQueue.main.asyncAfter
        Task { @MainActor [weak self] in
            await self?.clock.sleep(for: .seconds(Self.clipboardRestoreDelay))
            self?.restoreClipboardIfNeeded(initialChangeCount: initialChangeCount, snapshots: oldItemSnapshots)
        }
    }

    /// B3.3:還原剪貼簿內容(若 changeCount 未被外部修改)
    /// 從 pasteText 的 asyncAfter 閉包提取,以便測試可直接同步呼叫
    func restoreClipboardIfNeeded(initialChangeCount: Int, snapshots: [[NSPasteboard.PasteboardType: Data]]) {
        if pasteboard.changeCount == initialChangeCount {
            pasteboard.clearContents()
            if !snapshots.isEmpty {
                let restoredItems: [NSPasteboardItem] = snapshots.map { snapshot in
                    let restoredItem = NSPasteboardItem()
                    for (type, data) in snapshot {
                        restoredItem.setData(data, forType: type)
                    }
                    return restoredItem
                }
                _ = pasteboard.writeObjects(restoredItems)
            }
        }
    }
}
