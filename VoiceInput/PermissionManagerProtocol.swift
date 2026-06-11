import Foundation

/// 權限管理協定,用於分離實體系統權限請求與測試環境
/// 注意:本 protocol 不繼承 `ObservableObject`——是否對 SwiftUI 暴露
/// `@Published` 屬性由實作類別自行決定(例如 `PermissionManager` 仍 conform
/// `ObservableObject` 以維持既有 SwiftUI 介面行為)。
protocol PermissionManagerProtocol: AnyObject {
    // MARK: - 狀態屬性(供 View 觀察,實作通常為 @Published)

    /// 麥克風權限目前狀態
    var microphoneStatus: PermissionStatus { get set }
    /// 語音辨識權限目前狀態
    var speechRecognitionStatus: PermissionStatus { get set }
    /// 輔助功能權限目前狀態
    var accessibilityStatus: PermissionStatus { get set }
    /// 是否已嘗試請求過輔助功能權限
    var hasPromptedForAccessibility: Bool { get set }
    /// 是否正在顯示自訂權限提示視窗
    var showingPermissionAlert: Bool { get set }
    /// 目前需要請求的權限類型
    var pendingPermissionType: PermissionType? { get set }

    // MARK: - 權限檢查

    /// 檢查所有權限狀態並更新對應屬性
    func checkAllPermissions()

    /// 取得麥克風權限狀態
    func checkMicrophoneStatus() -> PermissionStatus

    /// 取得語音辨識權限狀態
    func checkSpeechRecognitionStatus() -> PermissionStatus

    /// 取得輔助功能權限狀態
    func checkAccessibilityStatus() -> PermissionStatus

    /// 是否應主動請求權限(本次 session 尚未請求過)
    var shouldRequestPermissions: Bool { get }

    /// 所有必要權限是否皆已授權
    var allPermissionsGranted: Bool { get }

    // MARK: - 權限請求

    /// 重置 session 內的請求旗標,允許再次彈出系統對話框
    func resetPermissionRequestFlag()

    /// 請求單一權限(會彈出系統對話框)
    func requestPermission(_ type: PermissionType, completion: @escaping (Bool) -> Void)

    /// 請求單一權限;若已授權直接回傳,若未決定則彈出對話框,若已拒絕可選擇顯示自訂提示或打開系統偏好
    func requestPermissionIfNeeded(
        _ type: PermissionType,
        showCustomAlertIfDenied: Bool,
        completion: @escaping (Bool) -> Void
    )

    /// 批次請求所有尚未授權的權限(會依序彈出系統對話框)
    func requestAllPermissionsIfNeeded(completion: @escaping (Bool) -> Void)

    // MARK: - UI 輔助

    /// 開啟系統「隱私權與安全性」中對應權限的設定頁
    func openSystemPreferences(for type: PermissionType)

    /// 顯示自訂權限不足提示視窗
    func showPermissionAlert(for type: PermissionType)

    /// 取得第一個被拒絕的權限類型(若全部已授權則回傳 nil)
    func getFirstDeniedPermission() -> PermissionType?
}
