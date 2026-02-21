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
                    name: "麥克風",
                    isGranted: viewModel.permissionManager.microphoneStatus == .authorized
                )
                .onTapGesture {
                    viewModel.permissionManager.resetPermissionRequestFlag()
                    viewModel.permissionManager.requestPermissionIfNeeded(.microphone) { _ in }
                }

                PermissionStatusRow(
                    name: "語音辨識",
                    isGranted: viewModel.permissionManager.speechRecognitionStatus == .authorized
                )
                .onTapGesture {
                    viewModel.permissionManager.resetPermissionRequestFlag()
                    viewModel.permissionManager.requestPermissionIfNeeded(.speechRecognition) { _ in }
                }

                PermissionStatusRow(
                    name: "輔助功能",
                    isGranted: viewModel.permissionManager.accessibilityStatus == .authorized
                )
                .onTapGesture {
                    viewModel.permissionManager.resetPermissionRequestFlag()
                    viewModel.permissionManager.requestPermissionIfNeeded(.accessibility) { _ in }
                }

                Button("請求權限") {
                    // 重置權限請求標記，這樣才會再次彈出系統對話框
                    viewModel.permissionManager.resetPermissionRequestFlag()
                    // 請求權限
                    viewModel.permissionManager.requestAllPermissionsIfNeeded { _ in }
                }
            } header: {
                Text("權限狀態")
            } footer: {
                Text("點擊任一項目可查看或設定權限")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 音訊輸入設備選擇
            Section {
                Picker("輸入設備", selection: Binding(
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
                    Label("重新整理設備", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.link)
            } header: {
                Text("音訊輸入")
            } footer: {
                Text("選擇要用於語音輸入的麥克風設備")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Toggle("轉錄完成後自動插入文字", isOn: $viewModel.autoInsertText)
                    .toggleStyle(.checkbox)

                Picker("錄音快捷鍵", selection: $selectedHotkey) {
                    ForEach(HotkeyOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedHotkey) { _, newValue in
                    viewModel.updateHotkey(newValue)
                }

                // T5-1：觸發模式選擇（即時生效）
                Picker("觸發模式", selection: $selectedTriggerMode) {
                    ForEach(RecordingTriggerMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedTriggerMode) { _, newValue in
                    viewModel.updateRecordingTriggerMode(newValue)
                }
            } header: {
                Text("一般設定")
            } footer: {
                if selectedTriggerMode == .pressAndHold {
                    Text("按住快捷鍵開始錄音，放開即送出轉寫結果。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("按一次開始錄音，再按一次停止並將結果送出。")
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

