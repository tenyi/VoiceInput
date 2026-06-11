import Foundation
import Testing
@testable import VoiceInput

/// PermissionManager 單元測試
/// 重點覆蓋 B2.2 麥克風 / B2.3 語音辨識 / B2.4 輔助功能 / B2.5 聚合邏輯
@Suite("PermissionManager")
struct PermissionManagerTests {

    // MARK: - B2.2 麥克風權限檢查

    /// checkMicrophoneStatus:系統回傳 authorized
    @Test("checkMicrophoneStatus 系統回傳 authorized")
    @MainActor
    func checkMicStatus_authorized() {
        let manager = PermissionManager()
        manager.checkMicStatusOverride = { .authorized }

        #expect(manager.checkMicrophoneStatus() == .authorized)
    }

    /// checkMicrophoneStatus:系統回傳 denied
    @Test("checkMicrophoneStatus 系統回傳 denied")
    @MainActor
    func checkMicStatus_denied() {
        let manager = PermissionManager()
        manager.checkMicStatusOverride = { .denied }

        #expect(manager.checkMicrophoneStatus() == .denied)
    }

    /// checkMicrophoneStatus:系統回傳 notDetermined
    @Test("checkMicrophoneStatus 系統回傳 notDetermined")
    @MainActor
    func checkMicStatus_notDetermined() {
        let manager = PermissionManager()
        manager.checkMicStatusOverride = { .notDetermined }

        #expect(manager.checkMicrophoneStatus() == .notDetermined)
    }

    // MARK: - B2.3 語音辨識權限檢查

    /// checkSpeechRecognitionStatus:系統回傳 authorized
    @Test("checkSpeechRecognitionStatus 系統回傳 authorized")
    @MainActor
    func checkSpeechStatus_authorized() {
        let manager = PermissionManager()
        manager.checkSpeechStatusOverride = { .authorized }

        #expect(manager.checkSpeechRecognitionStatus() == .authorized)
    }

    /// checkSpeechRecognitionStatus:系統回傳 denied
    @Test("checkSpeechRecognitionStatus 系統回傳 denied")
    @MainActor
    func checkSpeechStatus_denied() {
        let manager = PermissionManager()
        manager.checkSpeechStatusOverride = { .denied }

        #expect(manager.checkSpeechRecognitionStatus() == .denied)
    }

    /// checkSpeechRecognitionStatus:系統回傳 notDetermined
    @Test("checkSpeechRecognitionStatus 系統回傳 notDetermined")
    @MainActor
    func checkSpeechStatus_notDetermined() {
        let manager = PermissionManager()
        manager.checkSpeechStatusOverride = { .notDetermined }

        #expect(manager.checkSpeechRecognitionStatus() == .notDetermined)
    }

    // MARK: - B2.4 輔助功能權限檢查

    /// checkAccessibilityStatus:AXIsProcessTrusted 回傳 true → authorized
    @Test("checkAccessibilityStatus 已授權回傳 authorized")
    @MainActor
    func checkAccessibilityStatus_authorized() {
        let manager = PermissionManager()
        manager.checkAccessibilityOverride = { true }

        #expect(manager.checkAccessibilityStatus() == .authorized)
    }

    /// checkAccessibilityStatus:AXIsProcessTrusted 回傳 false 且已提示過 → denied
    @Test("checkAccessibilityStatus 未授權且已提示回傳 denied")
    @MainActor
    func checkAccessibilityStatus_denied() {
        let manager = PermissionManager()
        manager.hasPromptedForAccessibility = true
        manager.checkAccessibilityOverride = { false }

        #expect(manager.checkAccessibilityStatus() == .denied)
    }

    // MARK: - B2.5 checkAllPermissions 聚合測試

    /// 全部授權:checkAllPermissions 更新三個狀態,allPermissionsGranted == true
    @Test("checkAllPermissions 全部授權時 allPermissionsGranted 為 true")
    @MainActor
    func checkAllPermissions_allAuthorized() {
        let manager = PermissionManager()
        manager.checkMicStatusOverride = { .authorized }
        manager.checkSpeechStatusOverride = { .authorized }
        manager.checkAccessibilityOverride = { true }

        manager.checkAllPermissions()

        #expect(manager.microphoneStatus == .authorized)
        #expect(manager.speechRecognitionStatus == .authorized)
        #expect(manager.accessibilityStatus == .authorized)
        #expect(manager.allPermissionsGranted)
        #expect(manager.getFirstDeniedPermission() == nil)
    }

    /// 麥克風被拒絕:allPermissionsGranted == false,getFirstDeniedPermission 回傳 .microphone
    @Test("checkAllPermissions 麥克風被拒時 allPermissionsGranted 為 false")
    @MainActor
    func checkAllPermissions_micDenied() {
        let manager = PermissionManager()
        manager.checkMicStatusOverride = { .denied }
        manager.checkSpeechStatusOverride = { .authorized }
        manager.checkAccessibilityOverride = { true }

        manager.checkAllPermissions()

        #expect(manager.microphoneStatus == .denied)
        #expect(!manager.allPermissionsGranted)
        #expect(manager.getFirstDeniedPermission() == .microphone)
    }
}
