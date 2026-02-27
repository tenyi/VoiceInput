import SwiftUI
import os

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

        Task {
            do {
                let correctedText = try await LLMService.shared.correctText(
                    text: testInputText,
                    prompt: config.prompt,
                    provider: config.provider,
                    apiKey: config.apiKey,
                    url: config.url,
                    model: config.model
                )
                await MainActor.run {
                    self.testOutput = correctedText
                    self.testSucceeded = true
                    self.isTesting = false
                }
            } catch {
                await MainActor.run {
                    self.testError = error.localizedDescription
                    self.isTesting = false
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
                Toggle(String(localized: "llm.enable.toggle"), isOn: $llmSettings.llmEnabled)
                    .toggleStyle(.checkbox)
            } header: {
                Text(String(localized: "llm.section.enable"))
            } footer: {
                Text(String(localized: "llm.enable.footer"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Provider 選擇
            Section {
                Picker(String(localized: "llm.provider.picker"), selection: Binding(
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
                    Section(String(localized: "llm.provider.builtin")) {
                        ForEach(LLMProvider.allCases, id: \.self) { provider in
                            Text(provider.rawValue).tag(provider.rawValue)
                        }
                    }
                    // 自訂 Provider
                    if !llmSettings.customProviders.isEmpty {
                        Section(String(localized: "llm.provider.custom")) {
                            ForEach(llmSettings.customProviders) { provider in
                                Text(provider.displayName).tag(provider.id.uuidString)
                            }
                        }
                    }
                }
                .pickerStyle(.menu)

                // 管理自訂 Provider 按鈕
                Button(action: { showingProviderManager = true }) {
                    Label(String(localized: "llm.provider.manage"), systemImage: "folder.circle")
                }
                .buttonStyle(.link)
            } header: {
                Text(String(localized: "llm.section.provider"))
            } footer: {
                Text(String(localized: "llm.provider.footer"))
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
                        TextField(String(localized: "llm.api.apiUrl"), text: Binding(
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

                        SecureField(String(localized: "llm.api.apiKey"), text: $llmSettings.llmAPIKey)
                        .textFieldStyle(.roundedBorder)

                        if let errorMessage = llmSettings.keychainErrorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        TextField(String(localized: "llm.api.modelName"), text: Binding(
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
                        Label(String(localized: "llm.provider.delete"), systemImage: "trash")
                    }
                    .buttonStyle(.link)
                } else {
                    // 內建 Provider 的設定
                    // 模型名稱 (所有 provider 都需要)
                    TextField(String(localized: "llm.api.modelName"), text: $llmSettings.llmModel)
                        .textFieldStyle(.roundedBorder)

                    // OpenAI / Anthropic 需要 API Key
                    if selectedProvider == .openAI || selectedProvider == .anthropic {
                        SecureField(String(localized: "llm.api.apiKey"), text: $llmSettings.llmAPIKey)
                            .textFieldStyle(.roundedBorder)
                        if let errorMessage = llmSettings.keychainErrorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    // Ollama 需要 URL
                    if selectedProvider == .ollama {
                        TextField(String(localized: "llm.api.apiUrl"), text: $llmSettings.llmURL)
                            .textFieldStyle(.roundedBorder)
                            .onAppear {
                                if llmSettings.llmURL.isEmpty {
                                    llmSettings.llmURL = "http://localhost:11434/v1/chat/completions"
                                }
                            }
                    }

                    // 自訂 API 需要 URL 和 API Key
                    if selectedProvider == .custom {
                        TextField(String(localized: "llm.api.apiUrl"), text: $llmSettings.llmURL)
                            .textFieldStyle(.roundedBorder)

                        SecureField(String(localized: "llm.api.apiKeyOptional"), text: $llmSettings.llmAPIKey)
                            .textFieldStyle(.roundedBorder)
                        if let errorMessage = llmSettings.keychainErrorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            } header: {
                Text(selectedCustomProvider != nil
                     ? String(localized: "llm.section.customProviderSettings")
                     : String(localized: "llm.section.apiSettings"))
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
                    Button(String(localized: "llm.prompt.resetDefault")) {
                        promptText = LLMSettingsViewModel.defaultLLMPrompt
                        llmSettings.llmPrompt = ""
                    }
                    .buttonStyle(.link)

                    Spacer()

                    if promptText != LLMSettingsViewModel.defaultLLMPrompt && !promptText.isEmpty {
                        Text(String(localized: "llm.prompt.customized"))
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text(String(localized: "llm.prompt.useDefault"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text(String(localized: "llm.section.prompt"))
            } footer: {
                Text(String(localized: "llm.prompt.footer"))
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
                                Text(String(localized: "llm.test.testing"))
                            } else {
                                Image(systemName: "play.fill")
                                Text(String(localized: "llm.test.button"))
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
                            Text(String(localized: "llm.test.input"))
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
                                Text(String(localized: "llm.test.output"))
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
                                Text(String(localized: "llm.test.error"))
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
                Text(String(localized: "llm.section.test"))
            } footer: {
                Text(String(localized: "llm.test.footer"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
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
        .onAppear {
            if let customId = llmSettings.selectedCustomProviderId,
               llmSettings.llmProvider == LLMProvider.custom.rawValue,
               let customProvider = llmSettings.customProviders.first(where: { $0.id.uuidString == customId }) {
                applySelectedCustomProvider(customProvider)
            } else {
                let currentProvider = LLMProvider(rawValue: llmSettings.llmProvider) ?? .openAI
                applyBuiltInProvider(currentProvider)
            }
        }
    }
}

// MARK: - 歷史記錄設定視圖
