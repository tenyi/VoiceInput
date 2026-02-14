import Foundation
import ApplicationServices
import Cocoa

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
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // 模擬 Cmd+V 組合鍵
        let source = CGEventSource(stateID: .hidSystemState)
        
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true) // Command 鍵按下
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V 鍵按下
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)   // V 鍵放開
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) // Command 鍵放開
        
        // 設定 Command 修飾鍵旗標
        cmdDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        
        // 發送事件
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }
}
