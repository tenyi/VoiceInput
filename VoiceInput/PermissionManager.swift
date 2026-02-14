//
//  PermissionManager.swift
//  VoiceInput
//
//  統一管理所有系統權限的類別
//  包含麥克風、語音辨識、輔助功能權限的檢查與請求
//

import Foundation
import AVFoundation
import Speech
import ApplicationServices
import Cocoa
import SwiftUI
import Combine

/// 權限類型列舉
enum PermissionType: String, CaseIterable {
    case microphone = "microphone"
    case speechRecognition = "speechRecognition"
    case accessibility = "accessibility"

    /// 顯示名稱
    var displayName: String {
        switch self {
        case .microphone: return "麥克風"
        case .speechRecognition: return "語音辨識"
        case .accessibility: return "輔助功能"
        }
    }

    /// 系統偏好設定的 URL
    var systemPreferencesURL: URL? {
        switch self {
        case .microphone:
            // 麥克風隱私權設定
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speechRecognition:
            // 語音辨識隱私權設定
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .accessibility:
            // 輔助功能設定
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }

    /// 權限不足時的提示訊息
    var deniedMessage: String {
        switch self {
        case .microphone:
            return "VoiceInput 需要使用麥克風來錄製您的語音。\n\n請在「系統偏好設定」>「隱私權與安全性」>「麥克風」中允許 VoiceInput。"
        case .speechRecognition:
            return "VoiceInput 需要使用語音辨識來將語音轉換為文字。\n\n請在「系統偏好設定」>「隱私權與安全性」>「語音辨識」中允許 VoiceInput。"
        case .accessibility:
            return "VoiceInput 需要輔助功能權限來模擬鍵盤輸入，將文字輸入到其他應用程式中。\n\n請在「系統偏好設定」>「隱私權與安全性」>「輔助功能」中允許 VoiceInput。"
        }
    }
}

/// 權限狀態
enum PermissionStatus {
    case authorized   // 已授權
    case denied       // 被拒絕
    case notDetermined // 尚未決定
    case restricted   // 受限制
}

/// 統一管理權限的類別
class PermissionManager: ObservableObject {
    /// 單例實例
    static let shared = PermissionManager()

    /// 各權限的目前狀態
    @Published var microphoneStatus: PermissionStatus = .notDetermined
    @Published var speechRecognitionStatus: PermissionStatus = .notDetermined
    @Published var accessibilityStatus: PermissionStatus = .notDetermined

    /// 是否正在顯示權限提示視窗
    @Published var showingPermissionAlert = false
    /// 目前需要請求的權限類型
    @Published var pendingPermissionType: PermissionType?

    /// 標記是否已經請求過權限（防止重複彈出）
    private var hasRequestedPermissionsThisSession = false

    private init() {}

    /// 檢查所有權限狀態
    func checkAllPermissions() {
        microphoneStatus = checkMicrophoneStatus()
        speechRecognitionStatus = checkSpeechRecognitionStatus()
        accessibilityStatus = checkAccessibilityStatus()
    }

    /// 重置權限請求標記（當使用者主動要求檢查時呼叫）
    func resetPermissionRequestFlag() {
        hasRequestedPermissionsThisSession = false
    }

    /// 是否應該請求權限
    /// 只有在尚未請求過的情況下才返回 true
    var shouldRequestPermissions: Bool {
        return !hasRequestedPermissionsThisSession
    }

    /// 檢查麥克風權限狀態
    func checkMicrophoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    /// 檢查語音辨識權限狀態
    func checkSpeechRecognitionStatus() -> PermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    /// 檢查輔助功能權限狀態
    func checkAccessibilityStatus() -> PermissionStatus {
        let trusted = AXIsProcessTrusted()
        return trusted ? .authorized : .denied
    }

    /// 請求單一權限（會彈出系統對話框）
    func requestPermission(_ type: PermissionType, completion: @escaping (Bool) -> Void) {
        switch type {
        case .microphone:
            requestMicrophonePermission(completion: completion)
        case .speechRecognition:
            requestSpeechRecognitionPermission(completion: completion)
        case .accessibility:
            requestAccessibilityPermission(completion: completion)
        }
    }

    /// 請求權限（如果尚未決定則彈出系統對話框，如果已拒絕則顯示提示視窗）
    /// - Parameters:
    ///   - type: 權限類型
    ///   - showCustomAlertIfDenied: 當權限被拒絕時是否顯示自訂提示視窗
    ///   - completion: 回調
    func requestPermissionIfNeeded(
        _ type: PermissionType,
        showCustomAlertIfDenied: Bool = true,
        completion: @escaping (Bool) -> Void
    ) {
        // 先檢查目前狀態
        let currentStatus: PermissionStatus
        switch type {
        case .microphone:
            currentStatus = checkMicrophoneStatus()
        case .speechRecognition:
            currentStatus = checkSpeechRecognitionStatus()
        case .accessibility:
            currentStatus = checkAccessibilityStatus()
        }

        switch currentStatus {
        case .authorized:
            // 已授權，不需要請求
            completion(true)

        case .notDetermined:
            // 尚未決定，請求權限（會彈出系統對話框）
            requestPermission(type) { [weak self] granted in
                DispatchQueue.main.async {
                    // 請求後更新狀態
                    self?.checkAllPermissions()
                    completion(granted)
                }
            }

        case .denied, .restricted:
            // 已拒絕，顯示自訂提示視窗或直接打開系統偏好設定
            if showCustomAlertIfDenied {
                showPermissionAlert(for: type)
            } else {
                // 直接打開系統偏好設定
                openSystemPreferences(for: type)
            }
            completion(false)
        }
    }

    /// 請求所有尚未授權的權限（一次性請求所有 notDetermined 的權限）
    /// 會依序彈出系統對話框請求每個尚未決定的權限
    /// 注意：只有當尚未請求過權限時才會彈出對話框
    func requestAllPermissionsIfNeeded(completion: @escaping (Bool) -> Void) {
        // 先檢查當前狀態
        checkAllPermissions()

        // 已經請求過權限了，不要再重複請求
        guard !hasRequestedPermissionsThisSession else {
            completion(allPermissionsGranted)
            return
        }

        // 標記已經請求過
        hasRequestedPermissionsThisSession = true

        // 收集所有需要請求的權限（notDetermined 才需要請求）
        var permissionsToRequest: [PermissionType] = []

        if microphoneStatus == .notDetermined {
            permissionsToRequest.append(.microphone)
        }
        if speechRecognitionStatus == .notDetermined {
            permissionsToRequest.append(.speechRecognition)
        }
        if accessibilityStatus == .notDetermined {
            permissionsToRequest.append(.accessibility)
        }

        // 如果沒有需要請求的權限，檢查是否有被拒絕的
        if permissionsToRequest.isEmpty {
            // 權限已被拒絕，打開系統偏好設定讓使用者手動開啟
            if let deniedPermission = getFirstDeniedPermission() {
                openSystemPreferences(for: deniedPermission)
            }
            completion(allPermissionsGranted)
            return
        }

        // 使用串連方式依序請求每個權限
        requestPermissionsSequentially(permissionsToRequest, index: 0, completion: completion)
    }

    /// 依序請求權限（確保一個完成後再請求下一個）
    private func requestPermissionsSequentially(
        _ permissions: [PermissionType],
        index: Int,
        completion: @escaping (Bool) -> Void
    ) {
        guard index < permissions.count else {
            // 所有權限請求完成，檢查最終狀態
            checkAllPermissions()
            completion(allPermissionsGranted)
            return
        }

        let permission = permissions[index]

        // 檢查當前狀態是否仍然是 notDetermined
        let currentStatus: PermissionStatus
        switch permission {
        case .microphone:
            currentStatus = checkMicrophoneStatus()
        case .speechRecognition:
            currentStatus = checkSpeechRecognitionStatus()
        case .accessibility:
            currentStatus = checkAccessibilityStatus()
        }

        if currentStatus == .notDetermined {
            // 請求權限（會彈出系統對話框）
            requestPermission(permission) { [weak self] _ in
                // 這個權限請求完成，繼續下一個
                self?.requestPermissionsSequentially(permissions, index: index + 1, completion: completion)
            }
        } else {
            // 狀態已改變（例如用戶在對話框中拒絕了），跳過這個直接繼續
            requestPermissionsSequentially(permissions, index: index + 1, completion: completion)
        }
    }

    /// 請求麥克風權限
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.microphoneStatus = granted ? .authorized : .denied
                completion(granted)
            }
        }
    }

    /// 請求語音辨識權限
    private func requestSpeechRecognitionPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                let granted = (status == .authorized)
                self?.speechRecognitionStatus = granted ? .authorized : .denied
                completion(granted)
            }
        }
    }

    /// 請求輔助功能權限
    /// 注意：輔助功能權限無法透過程式碼請求，必須使用者手動在系統偏好設定中開啟
    private func requestAccessibilityPermission(completion: @escaping (Bool) -> Void) {
        // 輔助功能權限無法直接請求，會彈出系統對話框
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)

        DispatchQueue.main.async { [weak self] in
            self?.accessibilityStatus = trusted ? .authorized : .denied
            completion(trusted)
        }
    }

    /// 請求所有必要權限
    func requestAllPermissions(completion: @escaping (Bool) -> Void) {
        // 先檢查所有權限
        requestPermission(.microphone) { [weak self] micGranted in
            self?.requestPermission(.speechRecognition) { speechGranted in
                self?.requestPermission(.accessibility) { accessibilityGranted in
                    let allGranted = micGranted && speechGranted && accessibilityGranted
                    DispatchQueue.main.async {
                        completion(allGranted)
                    }
                }
            }
        }
    }

    /// 檢查所有權限是否都已授權
    var allPermissionsGranted: Bool {
        return microphoneStatus == .authorized &&
               speechRecognitionStatus == .authorized &&
               accessibilityStatus == .authorized
    }

    /// 開啟系統偏好設定
    /// 使用 AppleScript 來打開對應的隱私權設定頁面，並選中我們的 App
    func openSystemPreferences(for type: PermissionType) {
        // 取得 App 的 Bundle Identifier
        let bundleId = Bundle.main.bundleIdentifier ?? "com.voiceinput.app"

        // 使用 AppleScript 打開對應的隱私權設定，並選中我們的 App
        let script: String

        switch type {
        case .microphone:
            script = """
            tell application "System Preferences"
                activate
                reveal anchor "Microphone" of pane id "com.apple.preference.security"
            end tell
            """
        case .speechRecognition:
            script = """
            tell application "System Preferences"
                activate
                reveal anchor "Dictation" of pane id "com.apple.preference.security"
            end tell
            """
        case .accessibility:
            script = """
            tell application "System Preferences"
                activate
                reveal anchor "Accessibility" of pane id "com.apple.preference.security"
            end tell
            delay 0.5
            tell application "System Events"
                tell process "System Preferences"
                    -- 嘗試在清單中選中我們的 App
                    try
                        set frontmost to true
                    end try
                end tell
            end tell
            """
        }

        // 執行 AppleScript
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                // 如果 AppleScript 失敗，退回到 URL 方式
                print("AppleScript error: \(error)")
                if let url = type.systemPreferencesURL {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    /// 顯示權限不足的提示
    func showPermissionAlert(for type: PermissionType) {
        pendingPermissionType = type
        showingPermissionAlert = true
    }

    /// 取得第一個需要請求的權限
    func getFirstDeniedPermission() -> PermissionType? {
        if microphoneStatus != .authorized {
            return .microphone
        }
        if speechRecognitionStatus != .authorized {
            return .speechRecognition
        }
        if accessibilityStatus != .authorized {
            return .accessibility
        }
        return nil
    }
}
