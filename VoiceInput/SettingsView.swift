//
//  SettingsView.swift
//  VoiceInput
//
//  Created by Tenyi on 2026/2/14.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("一般", systemImage: "gear")
                }

            TranscriptionSettingsView()
                .tabItem {
                    Label("轉錄", systemImage: "text.bubble")
                }

            ModelSettingsView()
                .tabItem {
                    Label("模型", systemImage: "cpu")
                }

            LLMSettingsView()
                .tabItem {
                    Label("LLM", systemImage: "brain")
                }
        }
        .frame(width: 480, height: 430)
        .padding()
    }
}

// MARK: - Subviews

struct GeneralSettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel

    /// 目前選擇的快捷鍵
    @State private var selectedHotkey: HotkeyOption = HotkeyOption.rightCommand

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
                    ForEach(viewModel.availableHotkeys, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedHotkey) { _, newValue in
                    viewModel.updateHotkey(newValue)
                }
            } header: {
                Text("一般設定")
            } footer: {
               Text("按下快捷鍵即可開始/停止錄音。")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
            // 載入已儲存的設定
            if let saved = HotkeyOption(rawValue: viewModel.selectedHotkey) {
                selectedHotkey = saved
            }
        }
    }
}

struct TranscriptionSettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel
    
    var body: some View {
        Form {
            Section {
                Picker("辨識語言", selection: $viewModel.selectedLanguage) {
                    ForEach(viewModel.availableLanguages.keys.sorted(), id: \.self) { key in
                        Text(viewModel.availableLanguages[key] ?? key).tag(key)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("語言設定")
            }
        }
        .padding()
    }
}

struct ModelSettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel

    var body: some View {
        Form {
            Section {
                Picker("辨識引擎", selection: Binding(
                    get: { viewModel.currentSpeechEngine },
                    set: { viewModel.selectedSpeechEngine = $0.rawValue }
                )) {
                    ForEach(VoiceInputViewModel.SpeechRecognitionEngine.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("語音辨識引擎")
            } footer: {
                if viewModel.currentSpeechEngine == .apple {
                    Text("使用 macOS 內建的 SFSpeechRecognizer，無需下載模型，但需連網。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("使用本機 Whisper 模型，需下載 .bin 模型檔案。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.currentSpeechEngine == .whisper {
                // 匯入進度顯示
                if viewModel.isImportingModel {
                    Section {
                        VStack(spacing: 12) {
                            // 進度條
                            ProgressView(value: viewModel.modelImportProgress) {
                                Text("正在匯入模型...")
                                    .font(.headline)
                            }
                            .progressViewStyle(.linear)

                            // 進度百分比
                            Text("\(Int(viewModel.modelImportProgress * 100))%")
                                .font(.title2)
                                .fontWeight(.medium)

                            // 速度和剩餘時間
                            HStack(spacing: 16) {
                                if !viewModel.modelImportSpeed.isEmpty {
                                    Label(viewModel.modelImportSpeed, systemImage: "speedometer")
                                }

                                if !viewModel.modelImportRemainingTime.isEmpty {
                                    Label(viewModel.modelImportRemainingTime, systemImage: "clock")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("匯入進度")
                    }
                }

                // 錯誤訊息顯示
                if let error = viewModel.modelImportError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.callout)
                    } header: {
                        Text("錯誤")
                    }
                }

                // 已導入的模型列表
                Section {
                    if viewModel.importedModels.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "cube.box")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("尚未導入任何模型")
                                .foregroundColor(.secondary)
                            Text("點擊下方按鈕匯入 Whisper 模型")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    } else {
                        ForEach(viewModel.importedModels, id: \.fileName) { model in
                            ModelRowView(
                                model: model,
                                isSelected: viewModel.whisperModelPath.contains(model.fileName),
                                modelsDirectory: viewModel.publicModelsDirectory,
                                onSelect: { viewModel.selectImportedModel(model) },
                                onDelete: { viewModel.deleteModel(model) },
                                onShowInFinder: { viewModel.showModelInFinder(model) }
                            )
                        }
                    }

                    // 導入按鈕
                    Button(action: {
                        viewModel.importModel()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("匯入模型...")
                        }
                    }
                    .disabled(viewModel.isImportingModel)
                } header: {
                    HStack {
                        Text("已導入的模型")
                        Spacer()
                        if !viewModel.importedModels.isEmpty {
                            Text("\(viewModel.importedModels.count) 個")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } footer: {
                    Text("點擊模型名稱選擇使用，點擊刪除圖示移除模型")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            }
        }
        .padding()
    }
}

/// 模型列表行視圖
struct ModelRowView: View {
    let model: ImportedModel
    let isSelected: Bool
    let modelsDirectory: URL
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onShowInFinder: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 模型圖示
            Image(systemName: "cpu.fill")
                .font(.title2)
                .foregroundColor(isSelected ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                // 模型名稱和類型標籤
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.body)
                        .fontWeight(.medium)

                    // 模型類型標籤
                    Text(model.inferredModelType)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }

                // 檔案大小和匯入日期
                HStack(spacing: 8) {
                    // 檔案大小
                    Label(model.fileSizeFormatted, systemImage: "externaldrive")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // 匯入日期
                    if let importDate = model.importDate as Date? {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(importDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 檔案存在狀態
                if !model.fileExists(in: modelsDirectory) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("檔案不存在")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // 選中狀態
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            }

            // 在 Finder 中顯示
            Button(action: onShowInFinder) {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("在 Finder 中顯示")

            // 刪除按鈕
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("刪除模型")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - LLM 修正設定視圖
struct LLMSettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel

    /// 目前的 provider (從字串轉換)
    @State private var selectedProvider: LLMProvider = .openAI
    /// Prompt 文字 (用於編輯，若有自訂則顯示自訂值，否則顯示預設值)
    @State private var promptText: String = ""

    // 測試相關狀態
    @State private var isTesting: Bool = false
    @State private var testOutput: String = ""
    @State private var testError: String = ""
    @State private var testSucceeded: Bool = false

    /// 測試文字
    private let testInputText = "垂直致中，致中對齊"

    /// 執行 LLM 測試
    private func performLLMTest() {
        isTesting = true
        testOutput = ""
        testError = ""
        testSucceeded = false

        viewModel.testLLM(text: testInputText) { result in
            DispatchQueue.main.async { [self] in
                isTesting = false
                switch result {
                case .success(let correctedText):
                    testOutput = correctedText
                    testSucceeded = true
                case .failure(let error):
                    testError = error.localizedDescription
                }
            }
        }
    }

    var body: some View {
        Form {
            // 啟用開關
            Section {
                Toggle("啟用 LLM 自動修正", isOn: $viewModel.llmEnabled)
                    .toggleStyle(.checkbox)
            } header: {
                Text("LLM 修正")
            } footer: {
                Text("轉錄完成後自動使用 LLM 修正文字內容")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Provider 選擇
            Section {
                Picker("服務提供者", selection: $selectedProvider) {
                    ForEach(viewModel.availableLLMProviders, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedProvider) { _, newValue in
                    viewModel.llmProvider = newValue.rawValue
                }
            } header: {
                Text("Provider")
            }

            // 根據不同 provider 顯示不同輸入欄位
            Section {
                // 模型名稱 (所有 provider 都需要)
                TextField("模型名稱", text: $viewModel.llmModel)
                    .textFieldStyle(.roundedBorder)

                // OpenAI / Anthropic 需要 API Key
                if selectedProvider == .openAI || selectedProvider == .anthropic {
                    SecureField("API Key", text: $viewModel.llmAPIKey)
                        .textFieldStyle(.roundedBorder)
                }

                // Ollama 需要 URL
                if selectedProvider == .ollama {
                    TextField("API URL", text: $viewModel.llmURL)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            if viewModel.llmURL.isEmpty {
                                viewModel.llmURL = "http://localhost:11434"
                            }
                        }
                }

                // 自訂 API 需要 URL 和 API Key
                if selectedProvider == .custom {
                    TextField("API URL", text: $viewModel.llmURL)
                        .textFieldStyle(.roundedBorder)

                    SecureField("API Key (可選)", text: $viewModel.llmAPIKey)
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("API 設定")
            }

            // Prompt 設定
            Section {
                // 使用@State 來處理編輯，若有自訂內容則顯示，否則顯示預設值
                TextEditor(text: $promptText)
                    .frame(height: 80)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: promptText) { _, newValue in
                        // 只有當值與預設不同時才儲存
                        if newValue != VoiceInputViewModel.defaultLLMPrompt {
                            viewModel.llmPrompt = newValue
                        } else {
                            viewModel.llmPrompt = ""
                        }
                    }

                HStack {
                    Button("重置為預設") {
                        promptText = VoiceInputViewModel.defaultLLMPrompt
                        viewModel.llmPrompt = ""
                    }
                    .buttonStyle(.link)

                    Spacer()

                    if promptText != VoiceInputViewModel.defaultLLMPrompt && !promptText.isEmpty {
                        Text("已自訂")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("使用預設")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("自訂 Prompt")
            } footer: {
                Text("編輯提示詞來改變 LLM 修正文字的方式")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 測試區塊
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    // 測試按鈕
                    Button(action: performLLMTest) {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("測試中...")
                            } else {
                                Image(systemName: "play.fill")
                                Text("測試 LLM 設定")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting || viewModel.llmModel.isEmpty)

                    // 測試結果顯示
                    if !testInputText.isEmpty || !testOutput.isEmpty || !testError.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            // 輸入文字
                            Text("輸入文字：")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(testInputText)
                                .font(.system(.body, design: .monospaced))
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)
                                .textSelection(.enabled)

                            // 輸出文字
                            if !testOutput.isEmpty {
                                Text("輸出文字：")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(testOutput)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(8)
                                    .background(testSucceeded ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                                    .cornerRadius(6)
                                    .textSelection(.enabled)
                            }

                            // 錯誤訊息
                            if !testError.isEmpty {
                                Text("錯誤：")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                Text(testError)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.red)
                                    .padding(8)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
            } header: {
                Text("測試 LLM")
            } footer: {
                Text("點擊測試按鈕驗證 LLM 設定是否正確")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .onAppear {
            // 載入已儲存的 provider
            selectedProvider = viewModel.currentLLMProvider
            // 載入 Prompt，若有自訂則使用自訂值，否則使用預設值顯示
            promptText = viewModel.llmPrompt.isEmpty ? VoiceInputViewModel.defaultLLMPrompt : viewModel.llmPrompt
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(VoiceInputViewModel())
}
