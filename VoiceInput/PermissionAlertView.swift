//
//  PermissionAlertView.swift
//  VoiceInput
//
//  權限提示視窗元件
//  顯示權限不足時的提示訊息與操作按鈕
//

import SwiftUI

/// 權限提示視窗
struct PermissionAlertView: View {
    /// 權限類型
    let permissionType: PermissionType
    /// 關閉視窗的回調
    let onDismiss: () -> Void

    /// 權限管理員
    @ObservedObject private var permissionManager = PermissionManager.shared

    var body: some View {
        VStack(spacing: 20) {
            // 圖示
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            // 標題
            Text("VoiceInput 需要權限")
                .font(.headline)
                .foregroundColor(.primary)

            // 說明訊息
            Text(permissionType.deniedMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // 按鈕區域
            HStack(spacing: 16) {
                // 取消按鈕
                Button("取消") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                // 打開系統偏好設定按鈕
                Button("打開系統偏好設定") {
                    permissionManager.openSystemPreferences(for: permissionType)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 400, height: 280)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

/// 權限狀態檢查並顯示提示的檢視
struct PermissionCheckView<Content: View>: View {
    /// 當權限不足時要顯示的內容
    let content: Content
    /// 是否在權限不足時顯示提示（預設為 true）
    var showAlert: Bool = true

    @ObservedObject private var permissionManager = PermissionManager.shared

    var body: some View {
        Group {
            if permissionManager.allPermissionsGranted {
                content
            } else if showAlert {
                // 顯示第一個被拒絕的權限提示
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)

                    Text("權限不足")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("VoiceInput 需要以下權限才能正常運作：")
                        .font(.body)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        if permissionManager.microphoneStatus != .authorized {
                            PermissionStatusRow(
                                name: "麥克風",
                                isGranted: false
                            )
                        }
                        if permissionManager.speechRecognitionStatus != .authorized {
                            PermissionStatusRow(
                                name: "語音辨識",
                                isGranted: false
                            )
                        }
                        if permissionManager.accessibilityStatus != .authorized {
                            PermissionStatusRow(
                                name: "輔助功能",
                                isGranted: false
                            )
                        }
                    }

                    Button("打開系統偏好設定") {
                        // 嘗試打開輔助功能設定（最關鍵的權限）
                        if let url = PermissionType.accessibility.systemPreferencesURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
    }
}

/// 權限狀態列
struct PermissionStatusRow: View {
    let name: String
    let isGranted: Bool

    var body: some View {
        HStack {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isGranted ? .green : .red)
            Text(name)
                .foregroundColor(isGranted ? .primary : .secondary)
            Spacer()
        }
    }
}

#Preview("Permission Alert") {
    PermissionAlertView(
        permissionType: .accessibility,
        onDismiss: {}
    )
}

#Preview("Permission Check") {
    PermissionCheckView(
        content: Text("主要內容")
    )
}
