import Foundation
import Combine
import SwiftUI
import os

/// 負責管理 LLM 文字修正服務的管理器
/// 管理 LLM 配置、Provider 切換與文字修正
class LLMManager: ObservableObject {
    /// 日誌記錄器
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "LLMManager")

    /// 是否啟用 LLM 修正
    @Published var llmEnabled: Bool = false

    /// LLM 服務提供者
    @Published var llmProvider: String = LLMProvider.openAI.rawValue

    /// 自訂 API URL
    @Published var llmURL: String = ""

    /// API Key (儲存在 Keychain)
    @Published var llmAPIKey: String = "" {
        didSet {
            // 儲存到 Keychain
            KeychainHelper.shared.save(llmAPIKey, service: "com.tenyi.voiceinput", account: "llmAPIKey")
        }
    }

    /// 模型名稱
    @Published var llmModel: String = ""

    /// 自訂提示詞
    @Published var llmPrompt: String = ""

    /// 預設提示詞
    static let defaultLLMPrompt = "你是一個專業的文案編輯助手。請修正以下文字中的錯誤（如果有），使其更加通順和準確，但不要改變原文的意思。直接回覆修正後的文字，不要加上任何解釋或備註："

    /// 自訂 Provider 列表（儲存用戶添加的 Provider）
    @AppStorage("customLLMProviders") private var customProvidersData: Data = Data()
    @Published var customProviders: [CustomLLMProvider] = []

    /// 目前選擇的自訂 Provider ID（若選擇內建 Provider 則為 nil）
    @AppStorage("selectedCustomProviderId") var selectedCustomProviderId: String?

    /// 取得目前的 LLM Provider
    var currentLLMProvider: LLMProvider {
        // 如果有選擇自訂 Provider，使用自訂 API 類型
        if selectedCustomProviderId != nil {
            return .custom
        }
        return LLMProvider(rawValue: llmProvider) ?? .openAI
    }

    /// 取得目前選擇的自訂 Provider（若無則返回 nil）
    var selectedCustomProvider: CustomLLMProvider? {
        guard let idString = selectedCustomProviderId,
              let uuid = UUID(uuidString: idString) else {
            return nil
        }
        return customProviders.first { $0.id == uuid }
    }

    /// 取得所有可用的 Provider 顯示名稱列表（包含內建和自訂）
    var allProviderDisplayNames: [String] {
        var names: [String] = []
        // 內建 Provider
        for provider in LLMProvider.allCases {
            names.append(provider.rawValue)
        }
        // 自訂 Provider
        for custom in customProviders {
            names.append(custom.displayName)
        }
        return names
    }

    init() {
        loadSettings()
    }

    // MARK: - 設定管理

    /// 載入設定
    func loadSettings() {
        // 載入 API Key from Keychain
        if let savedKey = KeychainHelper.shared.read(service: "com.tenyi.voiceinput", account: "llmAPIKey") {
            self.llmAPIKey = savedKey
        } else {
            // 向後相容：檢查舊的 UserDefaults 儲存位置
            let legacyKey = UserDefaults.standard.string(forKey: "llmAPIKey") ?? ""
            if !legacyKey.isEmpty {
                self.llmAPIKey = legacyKey
                // 遷移到 Keychain
                KeychainHelper.shared.save(legacyKey, service: "com.tenyi.voiceinput", account: "llmAPIKey")
                UserDefaults.standard.removeObject(forKey: "llmAPIKey")
            }
        }

        // 載入自訂 Provider 列表
        loadCustomProviders()
    }

    /// 儲存自訂 Provider 列表
    private func saveCustomProviders() {
        do {
            customProvidersData = try JSONEncoder().encode(customProviders)
        } catch {
            logger.error("無法保存自訂 Provider 列表: \(error.localizedDescription)")
        }
    }

    /// 載入自訂 Provider 列表
    private func loadCustomProviders() {
        do {
            customProviders = try JSONDecoder().decode([CustomLLMProvider].self, from: customProvidersData)
        } catch {
            customProviders = []
        }
    }

    /// 新增自訂 Provider
    func addCustomProvider(_ provider: CustomLLMProvider) {
        customProviders.append(provider)
        saveCustomProviders()
    }

    /// 刪除自訂 Provider
    func removeCustomProvider(_ provider: CustomLLMProvider) {
        customProviders.removeAll { $0.id == provider.id }
        // 如果刪除的是當前選擇的 Provider，重置選擇
        if selectedCustomProviderId == provider.id.uuidString {
            selectedCustomProviderId = nil
        }
        saveCustomProviders()
    }

    /// 更新自訂 Provider
    func updateCustomProvider(_ provider: CustomLLMProvider) {
        if let index = customProviders.firstIndex(where: { $0.id == provider.id }) {
            customProviders[index] = provider
            saveCustomProviders()
        }
    }

    // MARK: - LLM 修正

    /// 執行 LLM 文字修正
    /// - Parameters:
    ///   - text: 要修正的文字
    ///   - completion: 修正完成後的回調
    func correctText(text: String, completion: @escaping (Result<String, Error>) -> Void) {
        // 取得提示詞，若未自訂則使用預設值
        let prompt = llmPrompt.isEmpty ? LLMManager.defaultLLMPrompt : llmPrompt

        // 獲取當前 Provider 的配置
        var apiKey = llmAPIKey
        var url = llmURL
        var model = llmModel

        // 如果使用自訂 Provider，覆蓋配置
        if let customProvider = selectedCustomProvider {
            apiKey = customProvider.apiKey
            url = customProvider.apiURL
            model = customProvider.model
        }

        LLMService.shared.correctText(
            text: text,
            prompt: prompt,
            provider: currentLLMProvider,
            apiKey: apiKey,
            url: url,
            model: model,
            completion: completion
        )
    }

    /// 測試 LLM 連接
    /// - Parameters:
    ///   - text: 測試文字
    ///   - completion: 測試結果回調
    func testConnection(text: String, completion: @escaping (Result<String, Error>) -> Void) {
        correctText(text: text) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let correctedText):
                    completion(.success(correctedText))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
}
