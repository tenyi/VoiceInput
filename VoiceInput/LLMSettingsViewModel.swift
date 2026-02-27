import Foundation
import SwiftUI
import Combine
import os

// MARK: - LLM Provider 類型
/// LLM 服務提供者類型
enum LLMProvider: String, CaseIterable, Codable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case ollama = "Ollama"
    case custom = "Custom"

    /// 預設 URL
    var defaultURL: String {
        switch self {
        case .openAI, .anthropic:
            return ""
        case .ollama:
            return "http://localhost:11434/v1/chat/completions"
        case .custom:
            return ""
        }
    }

    /// 預設模型
    var defaultModel: String {
        switch self {
        case .openAI:
            return "gpt-4o-mini"
        case .anthropic:
            return "claude-3-haiku-20240307"
        case .ollama:
            return "llama3"
        case .custom:
            return ""
        }
    }
}

/// 自訂 LLM 提供者結構
struct CustomLLMProvider: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var url: String
    var model: String
    var prompt: String

    /// 顯示名稱
    var displayName: String { name }

    /// API URL (url 的別名)
    var apiURL: String { url }
}

/// 內建 Provider 設定結構
struct BuiltInProviderSettings: Codable {
    var url: String
    var model: String
}

/// 管理 LLM 相關設定與提供者
class LLMSettingsViewModel: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "LLMSettingsViewModel")
    
    /// 用於延遲寫入 Keychain，避免每打一個字就寫一次
    private let saveAPIKeySubject = PassthroughSubject<(String, LLMProvider, String?), Never>()
    private var cancellables = Set<AnyCancellable>()
    
    @Published var keychainErrorMessage: String?
    
    // MARK: - AppStorage 設定
    
    @AppStorage("llmProvider") var llmProvider: String = LLMProvider.openAI.rawValue {
        didSet {
            // 切換 Provider 時，我們只處理非敏感資料的載入。
            // 敏感資料 (API Key) 的拉取我們現在只靠 View 的需求或底層實際請求來決定
            let provider = currentLLMProvider
            loadBuiltInProviderSettings(for: provider)
            loadAPIKey(for: provider, customId: selectedCustomProviderId)
        }
    }
    
    @AppStorage("llmEnabled") var llmEnabled: Bool = false

    @AppStorage("llmURL") var llmURL: String = "" {
        didSet { saveCurrentBuiltInProviderSettings() }
    }

    @Published var llmAPIKey: String = "" {
        didSet {
            guard !isInternalUpdating else { return }
            saveAPIKeySubject.send((llmAPIKey, currentLLMProvider, selectedCustomProviderId))
        }
    }
    
    @AppStorage("llmModel") var llmModel: String = "" {
        didSet { saveCurrentBuiltInProviderSettings() }
    }
    
    @AppStorage("llmPrompt") var llmPrompt: String = ""
    
    @AppStorage("selectedCustomProviderId") var selectedCustomProviderId: String? {
        didSet {
            let provider = currentLLMProvider
            loadBuiltInProviderSettings(for: provider)
            loadAPIKey(for: provider, customId: selectedCustomProviderId)
        }
    }
    
    @AppStorage("customProvidersData") private var customProvidersData: Data = Data()
    @Published var customProviders: [CustomLLMProvider] = []
    
    @AppStorage("builtInProviderSettingsData") private var builtInProviderSettingsData: Data = Data()
    private var builtInProviderSettings: [String: BuiltInProviderSettings] = [:]

    static let defaultLLMPrompt = "你是專業的校稿員，只做以下兩件事：1. 修正錯字。 2. 根據語氣加入適當的標點符號。 請直接輸出修正後的文字，不要包含任何其他說明或解釋。"
    
    private let keychain: KeychainProtocol
    private let userDefaults: UserDefaults
    private var isInternalUpdating = false

    init(keychain: KeychainProtocol = KeychainHelper.shared, userDefaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.userDefaults = userDefaults
        
        setupAPIKeySaving()
        loadCustomProviders()
        loadBuiltInProviderSettingsData()
        
        // 為了避免 AppStorage 尚未掛載完成導致的競態條件，手動讀取 UserDefaults.standard 取得真正的值
        let realProviderString = userDefaults.string(forKey: "llmProvider") ?? LLMProvider.openAI.rawValue
        let realCustomId = userDefaults.string(forKey: "selectedCustomProviderId")
        
        let initialProvider = LLMProvider(rawValue: realProviderString) ?? .openAI
        let effectiveProvider = (realCustomId != nil && realProviderString == "Custom") ? .custom : initialProvider
        
        // 根據剛才手動抓到的真實值來進行配置（這時候 selectedCustomProviderId 哪怕還沒 didSet，我們也已經掌握到其確實的值）
        loadBuiltInProviderSettings(for: effectiveProvider)
        loadAPIKey(for: effectiveProvider, customId: realCustomId)
        
        // 遷移防錯
        loadLegacyLLMAPIKeyIfNeeded()
    }
    
    private func setupAPIKeySaving() {
        saveAPIKeySubject
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] (key, provider, customId) in
                self?.saveAPIKey(key: key, provider: provider, customId: customId)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Provider 計算屬性
    
    var currentLLMProvider: LLMProvider {
        if selectedCustomProviderId != nil && llmProvider == "Custom" {
            return .custom
        }
        return LLMProvider(rawValue: llmProvider) ?? .openAI
    }
    
    var selectedCustomProvider: CustomLLMProvider? {
        guard let idString = selectedCustomProviderId,
              let uuid = UUID(uuidString: idString) else {
            return nil
        }
        return customProviders.first { $0.id == uuid }
    }
    
    // MARK: - 自訂 Provider 管理
    
    private func loadCustomProviders() {
        guard !customProvidersData.isEmpty else {
            customProviders = []
            return
        }
        do {
            let decoder = JSONDecoder()
            customProviders = try decoder.decode([CustomLLMProvider].self, from: customProvidersData)
        } catch {
            logger.error("無法載入自訂 Provider 列表: \(error.localizedDescription)")
            customProviders = []
        }
    }
    
    private func saveCustomProviders() {
        do {
            let encoder = JSONEncoder()
            customProvidersData = try encoder.encode(customProviders)
        } catch {
            logger.error("無法儲存自訂 Provider 列表: \(error.localizedDescription)")
        }
    }
    
    func addCustomProvider(_ provider: CustomLLMProvider) {
        customProviders.append(provider)
        saveCustomProviders()
    }
    
    func updateCustomProvider(_ provider: CustomLLMProvider) {
        if let index = customProviders.firstIndex(where: { $0.id == provider.id }) {
            customProviders[index] = provider
            saveCustomProviders()
            
            if selectedCustomProviderId == provider.id.uuidString {
                objectWillChange.send()
            }
        }
    }
    
    func removeCustomProvider(at offsets: IndexSet) {
        let removedProviders = offsets.map { customProviders[$0] }
        customProviders.remove(atOffsets: offsets)
        saveCustomProviders()

        for provider in removedProviders {
            deleteProviderFromKeychain(provider)
        }
    }

    /// 通過 provider 刪除自訂 Provider
    func removeCustomProvider(_ provider: CustomLLMProvider) {
        if let index = customProviders.firstIndex(where: { $0.id == provider.id }) {
            removeCustomProvider(at: IndexSet(integer: index))
        }
    }

    private func deleteProviderFromKeychain(_ provider: CustomLLMProvider) {
        do {
            try keychain.delete(
                service: "com.tenyi.voiceinput",
                account: "llmAPIKey.\(provider.id.uuidString)"
            )
        } catch {
            logger.error("無法刪除 API Key: \(error.localizedDescription)")
        }
        if selectedCustomProviderId == provider.id.uuidString {
            selectedCustomProviderId = nil
            llmProvider = LLMProvider.openAI.rawValue
        }
    }

    // MARK: - 內建 Provider 管理
    
    private func loadBuiltInProviderSettingsData() {
        guard !builtInProviderSettingsData.isEmpty else { return }
        do {
            builtInProviderSettings = try JSONDecoder().decode([String: BuiltInProviderSettings].self, from: builtInProviderSettingsData)
        } catch {
            builtInProviderSettings = [:]
            logger.error("無法載入內建 Provider 設定: \(error.localizedDescription)")
        }
    }
    
    private func saveBuiltInProviderSettings() {
        do {
            builtInProviderSettingsData = try JSONEncoder().encode(builtInProviderSettings)
        } catch {
            logger.error("無法儲存內建 Provider 設定: \(error.localizedDescription)")
        }
    }
    
    private func saveCurrentBuiltInProviderSettings() {
        let provider = currentLLMProvider
        guard provider != .custom else { return }
        
        let settings = BuiltInProviderSettings(url: llmURL, model: llmModel)
        builtInProviderSettings[provider.rawValue] = settings
        saveBuiltInProviderSettings()
    }
    
    func loadBuiltInProviderSettings(for provider: LLMProvider) {
        guard provider != .custom else { return }
        
        if let settings = builtInProviderSettings[provider.rawValue] {
            llmURL = settings.url
            llmModel = settings.model
        } else {
            llmURL = provider.defaultURL
            llmModel = provider.defaultModel
        }
    }
    
    // MARK: - API Key (Keychain) 管理

    private func providerAPIKeyAccount(for provider: LLMProvider, customId: String?) -> String {
        if provider == .custom, let id = customId {
            return "llmAPIKey.\(id)"
        }
        return "llmAPIKey.\(provider.rawValue)"
    }

    private func loadLegacyLLMAPIKeyIfNeeded() {
        do {
            if let savedKey = try keychain.read(service: "com.tenyi.voiceinput", account: "llmAPIKey"), !savedKey.isEmpty {
                isInternalUpdating = true
                llmAPIKey = savedKey
                isInternalUpdating = false
                return
            }
        } catch {
            logger.error("讀取舊版 API Key 失敗: \(error.localizedDescription)")
        }
    }

    private func saveAPIKey(key: String, provider: LLMProvider, customId: String?) {
        let account = providerAPIKeyAccount(for: provider, customId: customId)
        do {
            try keychain.save(
                key,
                service: "com.tenyi.voiceinput",
                account: account
            )
            DispatchQueue.main.async {
                self.keychainErrorMessage = nil
            }
        } catch {
            DispatchQueue.main.async {
                self.keychainErrorMessage = error.localizedDescription
            }
            logger.error("儲存 API Key 失敗: \(error.localizedDescription)")
        }
    }

    func loadAPIKey(for provider: LLMProvider, customId: String? = nil) {
        let account = providerAPIKeyAccount(for: provider, customId: customId)

        isInternalUpdating = true
        defer { isInternalUpdating = false }

        do {
            if let savedKey = try keychain.read(service: "com.tenyi.voiceinput", account: account) {
                llmAPIKey = savedKey
                DispatchQueue.main.async { self.keychainErrorMessage = nil }
            } else if let legacyKey = try keychain.read(service: "com.tenyi.voiceinput", account: "llmAPIKey"), provider == .openAI {
                llmAPIKey = legacyKey
                saveAPIKey(key: legacyKey, provider: provider, customId: customId)
                DispatchQueue.main.async { self.keychainErrorMessage = nil }
            } else {
                llmAPIKey = ""
                DispatchQueue.main.async { self.keychainErrorMessage = nil }
            }
        } catch {
            llmAPIKey = ""
            DispatchQueue.main.async { self.keychainErrorMessage = error.localizedDescription }
            logger.error("讀取 API Key 失敗: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Configuration 解析
    
    /// 解析最終要送給 LLM 請求的組態
    /// 為了絕對的準確性：實際發送請求時不看 ViewModel 當下可能處於過渡期的 llmAPIKey
    /// 而是直接同步重拉一次 Keychain，確保每次呼叫 LLM 必定使用符合當前 Provider/customId 的正確金鑰。
    func resolveEffectiveConfiguration() -> EffectiveLLMConfiguration {
        let providerString = userDefaults.string(forKey: "llmProvider") ?? LLMProvider.openAI.rawValue
        let customId = userDefaults.string(forKey: "selectedCustomProviderId")
        let requestProvider = (customId != nil && providerString == "Custom") ? .custom : (LLMProvider(rawValue: providerString) ?? .openAI)
        let exactAccountName = providerAPIKeyAccount(for: requestProvider, customId: customId)
        
        // 忽略讀取失敗，回退為空字串，因為設定時已經反映給 UI 了
        let exactAPIKey = (try? keychain.read(service: "com.tenyi.voiceinput", account: exactAccountName)) ?? ""

        return LLMSettingsViewModel.resolveEffectiveLLMConfiguration(
            prompt: llmPrompt,
            provider: requestProvider,
            apiKey: exactAPIKey,
            url: llmURL,
            model: llmModel,
            selectedCustomProvider: selectedCustomProvider
        )
    }
    
    static func resolveEffectiveLLMConfiguration(
        prompt: String,
        provider: LLMProvider,
        apiKey: String,
        url: String,
        model: String,
        selectedCustomProvider: CustomLLMProvider?
    ) -> EffectiveLLMConfiguration {
        let resolvedPrompt = prompt.isEmpty ? LLMSettingsViewModel.defaultLLMPrompt : prompt
        var resolvedProvider = provider
        let resolvedAPIKey = apiKey  // API key 不需要修改，使用 let
        var resolvedURL = url
        var resolvedModel = model

        if let custom = selectedCustomProvider {
            resolvedProvider = .custom
            resolvedURL = custom.url
            resolvedModel = custom.model
        }
        
        return EffectiveLLMConfiguration(
            prompt: resolvedPrompt,
            provider: resolvedProvider,
            apiKey: resolvedAPIKey,
            url: resolvedURL,
            model: resolvedModel
        )
    }
}

/// 用於包裝最終解析結果的結構
struct EffectiveLLMConfiguration {
    let prompt: String
    let provider: LLMProvider
    let apiKey: String
    let url: String
    let model: String
}
