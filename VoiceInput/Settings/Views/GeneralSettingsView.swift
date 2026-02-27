import SwiftUI


struct GeneralSettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel

    /// 目前選擇的快捷鍵
    @State private var selectedHotkey: HotkeyOption = HotkeyOption.rightCommand
    /// T5-1：目前選擇的觸發模式
    @State private var selectedTriggerMode: RecordingTriggerMode = .pressAndHold

    var body: some View {
        Form {
            // 權限狀態區塊
            Section {
                PermissionStatusRow(
                    name: String(localized: "general.permission.microphone"),
                    isGranted: viewModel.permissionManager.microphoneStatus == .authorized
                )
                .onTapGesture {
                    viewModel.permissionManager.resetPermissionRequestFlag()
                    viewModel.permissionManager.requestPermissionIfNeeded(.microphone) { _ in }
                }

                PermissionStatusRow(
                    name: String(localized: "general.permission.speechRecognition"),
                    isGranted: viewModel.permissionManager.speechRecognitionStatus == .authorized
                )
                .onTapGesture {
                    viewModel.permissionManager.resetPermissionRequestFlag()
                    viewModel.permissionManager.requestPermissionIfNeeded(.speechRecognition) { _ in }
                }

                PermissionStatusRow(
                    name: String(localized: "general.permission.accessibility"),
                    isGranted: viewModel.permissionManager.accessibilityStatus == .authorized
                )
                .onTapGesture {
                    viewModel.permissionManager.resetPermissionRequestFlag()
                    viewModel.permissionManager.requestPermissionIfNeeded(.accessibility) { _ in }
                }

                Button(String(localized: "general.permission.requestAll")) {
                    // 重置權限請求標記，這樣才會再次彈出系統對話框
                    viewModel.permissionManager.resetPermissionRequestFlag()
                    // 請求權限
                    viewModel.permissionManager.requestAllPermissionsIfNeeded { _ in }
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
                Picker(String(localized: "general.audioInput.picker"), selection: Binding(
                    get: { viewModel.selectedInputDeviceID },
                    set: { viewModel.selectedInputDeviceID = $0 }
                )) {
                    ForEach(viewModel.availableInputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .pickerStyle(.menu)
                .onAppear {
                    viewModel.refreshAudioDevices()
                }

                Button(action: {
                    viewModel.refreshAudioDevices()
                }) {
                    Label(String(localized: "general.audioInput.refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.link)
            } header: {
                Text(String(localized: "general.section.audioInput"))
            } footer: {
                Text(String(localized: "general.audioInput.footer"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Toggle(String(localized: "general.autoInsert"), isOn: $viewModel.autoInsertText)
                    .toggleStyle(.checkbox)

                Picker(String(localized: "general.hotkey.picker"), selection: $selectedHotkey) {
                    ForEach(HotkeyOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedHotkey) { _, newValue in
                    viewModel.updateHotkey(newValue)
                }

                // T5-1：觸發模式選擇（即時生效）
                Picker(String(localized: "general.triggerMode.picker"), selection: $selectedTriggerMode) {
                    ForEach(RecordingTriggerMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedTriggerMode) { _, newValue in
                    viewModel.updateRecordingTriggerMode(newValue)
                }
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
        .padding()
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

