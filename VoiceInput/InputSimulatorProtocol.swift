import Foundation

/// 文字模擬輸入協定，用於分離實體 CGEvent 與測試環境
protocol InputSimulatorProtocol: AnyObject {
    /// 檢查應用程式是否具有輔助功能 (Accessibility) 權限
    func checkAccessibilityPermission(showAlert: Bool) -> Bool
    
    /// 請求輔助功能權限
    func requestAccessibilityPermission(completion: @escaping (Bool) -> Void)
    
    /// 插入文字到當前焦點視窗
    func insertText(_ text: String)
}
