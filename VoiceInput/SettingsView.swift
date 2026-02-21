//
//  SettingsView.swift
//  VoiceInput
//
//  Created by Tenyi on 2026/2/14.
//

import SwiftUI
import UniformTypeIdentifiers
import os

struct SettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel

    var body: some View {
        ScrollView {
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

                DictionarySettingsView()
                    .tabItem {
                        Label("字典", systemImage: "character.book.closed")
                    }

                HistorySettingsView()
                    .tabItem {
                        Label("歷史", systemImage: "clock.arrow.circlepath")
                    }
            }
            .frame(minWidth: 460, minHeight: 350)
            .padding()
        }
    }
}

// MARK: - Subviews

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
    @EnvironmentObject var modelManager: ModelManager

    var body: some View {
        Form {
            Section {
                Picker("辨識引擎", selection: Binding(
                    get: { viewModel.currentSpeechEngine },
                    set: { viewModel.selectedSpeechEngine = $0.rawValue }
                )) {
                    ForEach(SpeechRecognitionEngine.allCases) { engine in
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
                if modelManager.isImportingModel {
                    Section {
                        VStack(spacing: 12) {
                            // 進度條
                            ProgressView(value: modelManager.modelImportProgress) {
                                Text("正在匯入模型...")
                                    .font(.headline)
                            }
                            .progressViewStyle(.linear)

                            // 進度百分比
                            Text("\(Int(modelManager.modelImportProgress * 100))%")
                                .font(.title2)
                                .fontWeight(.medium)

                            // 速度和剩餘時間
                            HStack(spacing: 16) {
                                if !modelManager.modelImportSpeed.isEmpty {
                                    Label(modelManager.modelImportSpeed, systemImage: "speedometer")
                                }

                                if !modelManager.modelImportRemainingTime.isEmpty {
                                    Label(modelManager.modelImportRemainingTime, systemImage: "clock")
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
                if let error = modelManager.modelImportError {
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
                    if modelManager.importedModels.isEmpty {
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
                        ForEach(modelManager.importedModels, id: \.fileName) { model in
                            ModelRowView(
                                model: model,
                                isSelected: modelManager.whisperModelPath.contains(model.fileName),
                                modelsDirectory: modelManager.publicModelsDirectory,
                                onSelect: { modelManager.selectModel(model) },
                                onDelete: { modelManager.deleteModel(model) },
                                onShowInFinder: { modelManager.showModelInFinder(model) }
                            )
                        }
                    }

                    // 導入按鈕
                    Button(action: {
                        modelManager.importModel()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("匯入模型...")
                        }
                    }
                    .disabled(modelManager.isImportingModel)
                } header: {
                    HStack {
                        Text("已導入的模型")
                        Spacer()
                        if !modelManager.importedModels.isEmpty {
                            Text("\(modelManager.importedModels.count) 個")
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
    @EnvironmentObject var llmSettings: LLMSettingsViewModel

    /// 目前的 provider (從字串轉換)
    @State private var selectedProvider: LLMProvider = .openAI
    /// 目前選擇的自訂 Provider（若無則為 nil）
    @State private var selectedCustomProvider: CustomLLMProvider?
    /// 是否正在編輯自訂 Provider
    @State private var isEditingCustomProvider: Bool = false
    /// 顯示新增自訂 Provider 的表單
    @State private var showingAddCustomProvider: Bool = false
    /// 顯示 Provider 管理介面
    @State private var showingProviderManager: Bool = false
    /// 顯示新增自訂 Provider 表單（從管理介面觸發）
    @State private var showingAddFromManager: Bool = false
    /// Prompt 文字 (用於編輯，若有自訂則顯示自訂值，否則顯示預設值)
    @State private var promptText: String = ""

    // 測試相關狀態
    @State private var isTesting: Bool = false
    @State private var testOutput: String = ""
    @State private var testError: String = ""
    @State private var testSucceeded: Bool = false

    /// 測試文字
    private let testInputText = "垂直致中、致中對齊 鉛直至中水平緻中"

    /// 執行 LLM 測試
    private func performLLMTest() {
        isTesting = true
        testOutput = ""
        testError = ""
        testSucceeded = false

        let config = llmSettings.resolveEffectiveConfiguration()
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "LLMTest")

        LLMProcessingService.shared.process(
            text: testInputText,
            config: config,
            logger: logger
        ) { result in
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

    private func applySelectedCustomProvider(_ provider: CustomLLMProvider) {
        selectedCustomProvider = provider
        selectedProvider = .custom
        llmSettings.selectedCustomProviderId = provider.id.uuidString
        llmSettings.llmProvider = LLMProvider.custom.rawValue
        llmSettings.llmURL = provider.apiURL
        llmSettings.loadAPIKey(for: .custom, customId: provider.id.uuidString)
        llmSettings.llmModel = provider.model
        promptText = llmSettings.llmPrompt.isEmpty ? LLMSettingsViewModel.defaultLLMPrompt : llmSettings.llmPrompt
    }

    private func applyBuiltInProvider(_ provider: LLMProvider) {
        selectedProvider = provider
        selectedCustomProvider = nil
        llmSettings.selectedCustomProviderId = nil
        llmSettings.llmProvider = provider.rawValue
        llmSettings.loadAPIKey(for: provider)
        llmSettings.loadBuiltInProviderSettings(for: provider)
        promptText = llmSettings.llmPrompt.isEmpty ? LLMSettingsViewModel.defaultLLMPrompt : llmSettings.llmPrompt
    }

    var body: some View {
        Form {
            // 啟用開關
            Section {
                Toggle("啟用 LLM 自動修正", isOn: $llmSettings.llmEnabled)
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
                Picker("服務提供者", selection: Binding(
                    get: {
                        // 如果有選擇自訂 Provider，返回其 ID；否則返回內建 Provider 名稱
                        if let custom = selectedCustomProvider {
                            return custom.id.uuidString
                        }
                        return selectedProvider.rawValue
                    },
                    set: { (newValue: String) in
                        // 檢查是否是自訂 Provider（UUID 格式）
                        if let uuid = UUID(uuidString: newValue),
                           let customProvider = llmSettings.customProviders.first(where: { $0.id == uuid }) {
                            applySelectedCustomProvider(customProvider)
                        } else {
                            // 內建 Provider
                            applyBuiltInProvider(LLMProvider(rawValue: newValue) ?? .openAI)
                        }
                    }
                )) {
                    // 內建 Provider
                    Section("內建") {
                        ForEach(LLMProvider.allCases, id: \.self) { provider in
                            Text(provider.rawValue).tag(provider.rawValue)
                        }
                    }
                    // 自訂 Provider
                    if !llmSettings.customProviders.isEmpty {
                        Section("自訂") {
                            ForEach(llmSettings.customProviders) { provider in
                                Text(provider.displayName).tag(provider.id.uuidString)
                            }
                        }
                    }
                }
                .pickerStyle(.menu)

                // 管理自訂 Provider 按鈕
                Button(action: { showingProviderManager = true }) {
                    Label("管理自訂 Provider", systemImage: "folder.circle")
                }
                .buttonStyle(.link)
            } header: {
                Text("Provider")
            } footer: {
                Text("選擇 Provider 後可在此設定 API Key、模型等參數")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 根據不同 provider 顯示不同輸入欄位
            Section {
                // 自訂 Provider 的設定
                if let custom = selectedCustomProvider {
                    // 顯示並編輯自訂 Provider 的資訊
                    Group {
                        Text("Provider: \(custom.name)")
                            .font(.headline)
                        TextField("API URL", text: Binding(
                            get: { custom.url },
                            set: { newValue in
                                var updated = custom
                                updated.url = newValue
                                llmSettings.updateCustomProvider(updated)
                                selectedCustomProvider = updated
                                llmSettings.llmURL = newValue
                            }
                        ))
                        .textFieldStyle(.roundedBorder)

                        SecureField("API Key", text: $llmSettings.llmAPIKey)
                        .textFieldStyle(.roundedBorder)

                        TextField("模型名稱", text: Binding(
                            get: { custom.model },
                            set: { newValue in
                                var updated = custom
                                updated.model = newValue
                                llmSettings.updateCustomProvider(updated)
                                selectedCustomProvider = updated
                                llmSettings.llmModel = newValue
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    // 刪除按鈕
                    Button(role: .destructive, action: {
                        llmSettings.removeCustomProvider(custom)
                        applyBuiltInProvider(.openAI)
                    }) {
                        Label("刪除此 Provider", systemImage: "trash")
                    }
                    .buttonStyle(.link)
                } else {
                    // 內建 Provider 的設定
                    // 模型名稱 (所有 provider 都需要)
                    TextField("模型名稱", text: $llmSettings.llmModel)
                        .textFieldStyle(.roundedBorder)

                    // OpenAI / Anthropic 需要 API Key
                    if selectedProvider == .openAI || selectedProvider == .anthropic {
                        SecureField("API Key", text: $llmSettings.llmAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Ollama 需要 URL
                    if selectedProvider == .ollama {
                        TextField("API URL", text: $llmSettings.llmURL)
                            .textFieldStyle(.roundedBorder)
                            .onAppear {
                                if llmSettings.llmURL.isEmpty {
                                    llmSettings.llmURL = "http://localhost:11434/v1/chat/completions"
                                }
                            }
                    }

                    // 自訂 API 需要 URL 和 API Key
                    if selectedProvider == .custom {
                        TextField("API URL", text: $llmSettings.llmURL)
                            .textFieldStyle(.roundedBorder)

                        SecureField("API Key (可選)", text: $llmSettings.llmAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            } header: {
                Text(selectedCustomProvider != nil ? "自訂 Provider 設定" : "API 設定")
            }

            // Prompt 設定
            Section {
                // 使用@State 來處理編輯，若有自訂內容則顯示，否則顯示預設值
                TextEditor(text: $promptText)
                    .frame(height: 80)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: promptText) { _, newValue in
                        let valueToStore = newValue == LLMSettingsViewModel.defaultLLMPrompt ? "" : newValue
                        llmSettings.llmPrompt = valueToStore
                    }

                HStack {
                    Button("重置為預設") {
                        promptText = LLMSettingsViewModel.defaultLLMPrompt
                        llmSettings.llmPrompt = ""
                    }
                    .buttonStyle(.link)

                    Spacer()

                    if promptText != LLMSettingsViewModel.defaultLLMPrompt && !promptText.isEmpty {
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
                    .disabled(isTesting)

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
            if let customProvider = llmSettings.selectedCustomProvider {
                applySelectedCustomProvider(customProvider)
            } else {
                applyBuiltInProvider(llmSettings.currentLLMProvider)
            }
        }
        .sheet(isPresented: $showingAddCustomProvider) {
            AddCustomProviderSheet(llmSettings: llmSettings) { newProvider, newAPIKey in
                llmSettings.addCustomProvider(newProvider)
                llmSettings.selectedCustomProviderId = newProvider.id.uuidString
                llmSettings.llmAPIKey = newAPIKey
                // 自動選中新添加的 Provider
                applySelectedCustomProvider(newProvider)
            }
        }
        .sheet(isPresented: $showingProviderManager) {
            ManageCustomProvidersSheet(
                llmSettings: _llmSettings,
                onSelect: { provider in
                    applySelectedCustomProvider(provider)
                },
                onDelete: { provider in
                    // 如果刪除的是當前選中的 Provider，重置選擇
                    if selectedCustomProvider?.id == provider.id {
                        applyBuiltInProvider(.openAI)
                    }
                },
                onAdd: {
                    showingAddFromManager = true
                }
            )
        }
        .sheet(isPresented: $showingAddFromManager) {
            AddCustomProviderSheet(llmSettings: llmSettings) { newProvider, newAPIKey in
                llmSettings.addCustomProvider(newProvider)
                llmSettings.selectedCustomProviderId = newProvider.id.uuidString
                llmSettings.llmAPIKey = newAPIKey
                // 自動選中新添加的 Provider
                applySelectedCustomProvider(newProvider)
            }
        }
    }
}

// MARK: - 歷史記錄設定視圖
struct HistorySettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel
    @EnvironmentObject var historyManager: HistoryManager

    var body: some View {
        Form {
            Section {
                if historyManager.transcriptionHistory.isEmpty {
                    Text("目前沒有歷史輸入")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(historyManager.transcriptionHistory) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.createdAt.formatted(date: .omitted, time: .standard))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Button {
                                    historyManager.copyHistoryText(item.text)
                                } label: {
                                    Label("複製", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)

                                Button {
                                    historyManager.deleteHistoryItem(item)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("刪除此筆紀錄")
                            }

                            Text(item.text)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("最近 10 筆輸入")
            } footer: {
                Text("可快速複製或刪除歷史文字")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - 新增自訂 Provider  Sheet
/// 新增自訂 Provider 的表單
struct AddCustomProviderSheet: View {
    @Environment(\.dismiss) private var dismiss

    let llmSettings: LLMSettingsViewModel
    let onAdd: (CustomLLMProvider, String) -> Void

    @State private var name: String = ""
    @State private var apiURL: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var prompt: String = ""
    @State private var selectedTemplate: String = ""

    // 預設範本
    private let providerTemplates: [(name: String, url: String, model: String)] = [
        ("Qwen", "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", "qwen-turbo"),
        ("Kimi", "https://api.moonshot.com/v1/chat/completions", "moonshot-v1-8k-preview"),
        ("GLM", "https://api.z.ai/api/coding/paas/v4/chat/completions", "glm-4.7-flash"),
        ("DeepSeek", "https://api.deepseek.com/v1/chat/completions", "deepseek-chat"),
        ("OpenRouter", "https://openrouter.ai/api/v1/chat/completions", "openrouter/auto"),
        ("本地 Ollama", "http://localhost:11434/v1/chat/completions", "gemma3:4b")
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("Provider 資訊") {
                    TextField("顯示名稱", text: $name)
                        .textFieldStyle(.roundedBorder)

                    // 快速範本選擇
                    Picker("快速範本", selection: $selectedTemplate) {
                        Text("選擇範本...").tag("")
                        ForEach(providerTemplates, id: \.name) { template in
                            Text(template.name).tag(template.name)
                        }
                    }
                    .onChange(of: selectedTemplate) { _, newValue in
                        // 當選擇範本時自動填入
                        if !newValue.isEmpty, let template = providerTemplates.first(where: { $0.name == newValue }) {
                            name = template.name
                            apiURL = template.url
                            model = template.model
                            // 重置選擇，方便下次再次選擇
                            selectedTemplate = ""
                        }
                    }
                }

                Section("API 設定") {
                    TextField("API URL", text: $apiURL)
                        .textFieldStyle(.roundedBorder)

                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)

                    TextField("模型名稱", text: $model)
                        .textFieldStyle(.roundedBorder)
                }

                Section("提示詞（可選）") {
                    TextEditor(text: $prompt)
                        .frame(height: 60)
                        .font(.system(.body, design: .monospaced))
                }

                Section {
                    Button(action: addProvider) {
                        Text("新增 Provider")
                    }
                    .disabled(!isValid)
                }
            }
            .navigationTitle("新增自訂 Provider")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .frame(minWidth: 480, minHeight: 450)
        }
        .frame(minWidth: 480, minHeight: 450)
    }

    private var isValid: Bool {
        !name.isEmpty && !apiURL.isEmpty && !model.isEmpty
    }

    private func addProvider() {
        let provider = CustomLLMProvider(
            name: name,
            url: apiURL,
            model: model,
            prompt: prompt
        )
        onAdd(provider, apiKey)
        dismiss()
    }
}

// MARK: - 管理自訂 Provider Sheet
/// 管理已新增的自訂 Provider（檢視、刪除）
struct ManageCustomProvidersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var llmSettings: LLMSettingsViewModel

    let onSelect: (CustomLLMProvider) -> Void
    let onDelete: (CustomLLMProvider) -> Void
    let onAdd: () -> Void

    @State private var providerToDelete: CustomLLMProvider?

    var body: some View {
        NavigationView {
            List {
                if llmSettings.customProviders.isEmpty {
                    Text("尚未新增任何自訂 Provider")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(llmSettings.customProviders) { provider in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(provider.displayName)
                                    .font(.headline)
                                Text(provider.model)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // 刪除按鈕
                            Button(action: {
                                providerToDelete = provider
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(provider)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("管理自訂 Provider")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        dismiss()
                        onAdd()
                    }) {
                        Label("新增", systemImage: "plus")
                    }
                }
            }
            .alert("刪除 Provider", isPresented: Binding(
                get: { providerToDelete != nil },
                set: { if !$0 { providerToDelete = nil } }
            )) {
                Button("取消", role: .cancel) {
                    providerToDelete = nil
                }
                Button("刪除", role: .destructive) {
                    if let provider = providerToDelete {
                        onDelete(provider)
                        llmSettings.removeCustomProvider(provider)
                    }
                    providerToDelete = nil
                }
            } message: {
                if let provider = providerToDelete {
                    Text("確定要刪除「\(provider.displayName)」嗎？此操作無法復原。")
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

#Preview {
    SettingsView()
        .environmentObject(VoiceInputViewModel())
        .environmentObject(ModelManager())
        .environmentObject(HistoryManager())
}

