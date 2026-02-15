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
        .frame(width: 450, height: 320)
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
                Section {
                    HStack {
                        TextField("模型檔案路徑 (.bin)", text: $viewModel.whisperModelPath)
                        
                        Button("瀏覽...") {
                            viewModel.selectModelFile()
                        }
                    }
                } header: {
                    Text("Whisper 模型路徑")
                } footer: {
                    if viewModel.whisperModelPath.isEmpty {
                        Text("請選擇 Whisper 模型檔案 (.bin)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - LLM 修正設定視圖
struct LLMSettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel

    /// 目前的 provider (從字串轉換)
    @State private var selectedProvider: LLMProvider = .openAI
    /// Prompt 文字 (用於編輯，若有自訂則顯示自訂值，否則顯示預設值)
    @State private var promptText: String = ""

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
