import SwiftUI


struct GeneralSettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel

    /// 目前選擇的快捷鍵
    @State private var selectedHotkey: HotkeyOption = HotkeyOption.rightCommand
    /// T5-1：目前選擇的觸發模式
    @State private var selectedTriggerMode: RecordingTriggerMode = .pressAndHold

    /// 三項權限是否皆已授權（用於決定是否強調「請求權限」按鈕）
    private var allPermissionsGranted: Bool {
        let manager = viewModel.permissionManager
        return manager.microphoneStatus == .authorized
            && manager.speechRecognitionStatus == .authorized
            && manager.accessibilityStatus == .authorized
    }

    var body: some View {
        Form {
            // 頁首卡片
            SettingsPaneHeader(pane: .general)

            // 權限狀態區塊
            Section {
                PermissionRow(
                    title: String(localized: "general.permission.microphone"),
                    symbol: "mic.fill",
                    tint: .red,
                    isGranted: viewModel.permissionManager.microphoneStatus == .authorized
                ) {
                    viewModel.permissionManager.resetPermissionRequestFlag()
                    viewModel.permissionManager.requestPermissionIfNeeded(.microphone) { _ in }
                }

                PermissionRow(
                    title: String(localized: "general.permission.speechRecognition"),
                    symbol: "waveform",
                    tint: .pink,
                    isGranted: viewModel.permissionManager.speechRecognitionStatus == .authorized
                ) {
                    viewModel.permissionManager.resetPermissionRequestFlag()
                    viewModel.permissionManager.requestPermissionIfNeeded(.speechRecognition) { _ in }
                }

                PermissionRow(
                    title: String(localized: "general.permission.accessibility"),
                    symbol: "accessibility",
                    tint: .blue,
                    isGranted: viewModel.permissionManager.accessibilityStatus == .authorized
                ) {
                    viewModel.permissionManager.resetPermissionRequestFlag()
                    viewModel.permissionManager.requestPermissionIfNeeded(.accessibility) { _ in }
                }

                // 尚有權限未授權時才顯示「請求權限」按鈕，避免已完成設定時的視覺雜訊
                if !allPermissionsGranted {
                    HStack {
                        Spacer()
                        Button(String(localized: "general.permission.requestAll")) {
                            // 重置權限請求標記，這樣才會再次彈出系統對話框
                            viewModel.permissionManager.resetPermissionRequestFlag()
                            // 請求權限
                            viewModel.permissionManager.requestAllPermissionsIfNeeded { _ in }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } header: {
                Text(String(localized: "general.section.permissions"))
            } footer: {
                Text(String(localized: "general.permission.footer"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 音訊輸入設備選擇
            Section {
                Picker(selection: Binding(
                    get: { viewModel.selectedInputDeviceID },
                    set: { viewModel.selectedInputDeviceID = $0 }
                )) {
                    ForEach(viewModel.availableInputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                } label: {
                    SettingsRowLabel(
                        title: String(localized: "general.audioInput.picker"),
                        symbol: "mic.circle.fill",
                        tint: .orange
                    )
                }
                .pickerStyle(.menu)
                .onAppear {
                    viewModel.refreshAudioDevices()
                }

                HStack {
                    Spacer()
                    Button(action: {
                        viewModel.refreshAudioDevices()
                    }) {
                        Label(String(localized: "general.audioInput.refresh"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text(String(localized: "general.section.audioInput"))
            } footer: {
                Text(String(localized: "general.audioInput.footer"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 快捷鍵與輸入行為
            Section {
                Picker(selection: $selectedHotkey) {
                    ForEach(HotkeyOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                } label: {
                    SettingsRowLabel(
                        title: String(localized: "general.hotkey.picker"),
                        symbol: "command",
                        tint: .gray
                    )
                }
                .pickerStyle(.menu)
                .onChange(of: selectedHotkey) { _, newValue in
                    viewModel.updateHotkey(newValue)
                }

                // T5-1：觸發模式選擇（即時生效）
                Picker(selection: $selectedTriggerMode) {
                    ForEach(RecordingTriggerMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    SettingsRowLabel(
                        title: String(localized: "general.triggerMode.picker"),
                        symbol: "hand.tap.fill",
                        tint: .indigo
                    )
                }
                .pickerStyle(.menu)
                .onChange(of: selectedTriggerMode) { _, newValue in
                    viewModel.updateRecordingTriggerMode(newValue)
                }

                Toggle(isOn: $viewModel.autoInsertText) {
                    SettingsRowLabel(
                        title: String(localized: "general.autoInsert"),
                        symbol: "text.cursor",
                        tint: .green
                    )
                }
                .toggleStyle(.switch)
            } header: {
                Text(String(localized: "general.section.generalSettings"))
            } footer: {
                if selectedTriggerMode == .pressAndHold {
                    Text(String(localized: "general.triggerMode.pressAndHold.footer"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(String(localized: "general.triggerMode.toggle.footer"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $viewModel.permissionManager.showingPermissionAlert) {
            if let permissionType = viewModel.permissionManager.pendingPermissionType {
                PermissionAlertView(
                    permissionType: permissionType,
                    onDismiss: {
                        viewModel.permissionManager.showingPermissionAlert = false
                        viewModel.permissionManager.checkAllPermissions()
                    }
                )
            }
        }
        .onAppear {
            // 載入已儲存的快捷鍵設定
            if let saved = HotkeyOption(rawValue: viewModel.selectedHotkey) {
                selectedHotkey = saved
            }
            // 載入已儲存的觸發模式設定
            if let savedMode = RecordingTriggerMode(rawValue: viewModel.recordingTriggerMode) {
                selectedTriggerMode = savedMode
            }
        }
    }
}
