import Foundation
import ApplicationServices
import Cocoa
import Carbon.HIToolbox

/// 負責模擬鍵盤輸入與處理輔助功能權限
class InputSimulator {
    /// 單例 (Singleton) 實例
    static let shared = InputSimulator()

    /// 權限管理員
    private let permissionManager = PermissionManager.shared

    private init() {}

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
    private func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general

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
        
        // 模擬 Cmd+V 組合鍵
        let source = CGEventSource(stateID: .hidSystemState)
        
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true) // Command 鍵按下
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true) // V 鍵按下
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)   // V 鍵放開
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false) // Command 鍵放開
        
        // 設定 Command 修飾鍵旗標
        cmdDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        
        // 發送事件
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        // 延遲一段時間後恢復剪貼簿內容，確保貼上操作已完成
        // 增加延遲時間到 1 秒，確保貼上操作有足夠時間完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // 檢查剪貼簿內容是否仍是我們設置的文字
            // 如果不是，表示貼上成功或使用者又複製了新內容
            let currentContent = pasteboard.string(forType: .string)

            if currentContent == text {
                // 剪貼簿仍是我們的文字，表示貼上可能失敗
                // 或者目標應用程式沒有響應，恢復原始內容
                pasteboard.clearContents()
                if !oldItemSnapshots.isEmpty {
                    let restoredItems: [NSPasteboardItem] = oldItemSnapshots.map { snapshot in
                        let restoredItem = NSPasteboardItem()
                        for (type, data) in snapshot {
                            restoredItem.setData(data, forType: type)
                        }
                        return restoredItem
                    }
                    pasteboard.writeObjects(restoredItems)
                }
            }
            // 如果內容已經改變（不是 text），表示：
            // 1. 貼上成功，目標應用程式取走了文字
            // 2. 使用者又複製了新內容
            // 這兩種情況都不需要恢復原始內容
        }
    }
}
