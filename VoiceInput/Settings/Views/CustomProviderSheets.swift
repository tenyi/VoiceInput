import SwiftUI

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

