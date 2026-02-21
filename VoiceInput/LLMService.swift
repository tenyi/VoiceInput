//
//  LLMService.swift
//  VoiceInput
//
//  LLM 服務提供者，用於修正語音辨識結果中的錯誤
//

import Foundation

/// LLM 服務錯誤類型
enum LLMServiceError: LocalizedError {
    case invalidConfiguration      // 設定無效
    case invalidResponse           // 回應格式錯誤
    case networkError(Error)       // 網路錯誤
    case apiError(String)          // API 回傳錯誤
    case noContent                 // 無回應內容

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "LLM 設定無效，請檢查 API Key、URL 或模型名稱"
        case .invalidResponse:
            return "LLM 回應格式錯誤"
        case .networkError(let error):
            return "網路錯誤: \(error.localizedDescription)"
        case .apiError(let message):
            return "API 錯誤: \(message)"
        case .noContent:
            return "LLM 無回應內容"
        }
    }
}

/// LLM 服務類別，統一處理不同 provider 的 API 呼叫
class LLMService {
    /// 單例模式
    static var shared = LLMService()

    private let networkProvider: NetworkProviderProtocol

    init(networkProvider: NetworkProviderProtocol = URLSession.shared) {
        self.networkProvider = networkProvider
    }
    
    /// 正規化 URL,確保包含有效的 scheme
    /// - Parameter urlString: 原始 URL 字串
    /// - Returns: 正規化後的 URL 字串
    private func normalizeURL(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 如果已經有 scheme,直接返回
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        
        // 如果是 localhost 或 127.0.0.1,使用 http://
        if trimmed.hasPrefix("localhost") || trimmed.hasPrefix("127.0.0.1") {
            return "http://\(trimmed)"
        }
        
        // 其他情況使用 https://
        return "https://\(trimmed)"
    }


    /// 修正文字 (非同步版本)
    /// - Parameters:
    ///   - text: 需要修正的原文
    ///   - prompt: 提示詞
    ///   - provider: LLM 提供者
    ///   - apiKey: API Key
    ///   - url: API URL (Ollama 或自訂使用)
    ///   - model: 模型名稱
    /// - Returns: 修正後的文字
    /// - Throws: 網路或 API 錯誤
    func correctText(
        text: String,
        prompt: String,
        provider: LLMProvider,
        apiKey: String,
        url: String,
        model: String
    ) async throws -> String {
        // 驗證必要參數
        guard !text.isEmpty else {
            throw LLMServiceError.invalidConfiguration
        }

        switch provider {
        case .openAI:
            return try await callOpenAI(text: text, prompt: prompt, apiKey: apiKey, model: model)
        case .anthropic:
            return try await callAnthropic(text: text, prompt: prompt, apiKey: apiKey, model: model)
        case .ollama:
            return try await callOllama(text: text, prompt: prompt, url: url, model: model)
        case .custom:
            return try await callCustomAPI(text: text, prompt: prompt, apiKey: apiKey, url: url, model: model)
        }
    }

    // MARK: - 共用請求與解析邏輯
    
    private func performRequest(_ request: URLRequest, parser: (Data) throws -> String) async throws -> String {
        do {
            let (data, _) = try await networkProvider.data(for: request)
            return try parser(data)
        } catch let error as LLMServiceError {
            throw error
        } catch {
            throw LLMServiceError.networkError(error)
        }
    }
    
    private func parseOpenAILikeResponse(data: Data) throws -> String {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LLMServiceError.invalidResponse
            }
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            } else if let error = json["error"] as? [String: Any],
                      let message = error["message"] as? String {
                throw LLMServiceError.apiError(message)
            }
            throw LLMServiceError.invalidResponse
        } catch let error as LLMServiceError {
            throw error
        } catch {
            throw LLMServiceError.invalidResponse
        }
    }
    
    private func parseAnthropicResponse(data: Data) throws -> String {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LLMServiceError.invalidResponse
            }
            if let content = json["content"] as? [[String: Any]],
               let firstContent = content.first,
               let text = firstContent["text"] as? String {
                return text
            } else if let error = json["error"] as? [String: Any],
                      let message = error["message"] as? String {
                throw LLMServiceError.apiError(message)
            }
            throw LLMServiceError.invalidResponse
        } catch let error as LLMServiceError {
            throw error
        } catch {
            throw LLMServiceError.invalidResponse
        }
    }

    // MARK: - OpenAI API

    private func callOpenAI(
        text: String,
        prompt: String,
        apiKey: String,
        model: String
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw LLMServiceError.invalidConfiguration }
        let modelName = model.isEmpty ? "gpt-4o-mini" : model
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw LLMServiceError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return try await performRequest(request, parser: parseOpenAILikeResponse)
    }

    // MARK: - Anthropic API

    private func callAnthropic(
        text: String,
        prompt: String,
        apiKey: String,
        model: String
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw LLMServiceError.invalidConfiguration }
        let modelName = model.isEmpty ? "claude-3-haiku-20240307" : model
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw LLMServiceError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelName,
            "max_tokens": 1024,
            "system": prompt,
            "messages": [
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return try await performRequest(request, parser: parseAnthropicResponse)
    }

    // MARK: - Ollama API

    private func callOllama(
        text: String,
        prompt: String,
        url: String,
        model: String
    ) async throws -> String {
        var baseURL = url.isEmpty ? "http://localhost:11434" : normalizeURL(url)
        if baseURL.hasSuffix("/") { baseURL.removeLast() }
        let endpoint = baseURL.hasSuffix("/v1/chat/completions") ? baseURL : "\(baseURL)/v1/chat/completions"
        guard let apiURL = URL(string: endpoint) else { throw LLMServiceError.invalidConfiguration }

        let modelName = model.isEmpty ? "llama3" : model

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return try await performRequest(request, parser: parseOpenAILikeResponse)
    }

    // MARK: - 自訂 API

    private func callCustomAPI(
        text: String,
        prompt: String,
        apiKey: String,
        url: String,
        model: String
    ) async throws -> String {
        guard !url.isEmpty else { throw LLMServiceError.invalidConfiguration }
        let normalizedURL = normalizeURL(url)
        guard let apiURL = URL(string: normalizedURL) else { throw LLMServiceError.invalidConfiguration }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": text]
            ]
        ]
        if !model.isEmpty { body["model"] = model }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return try await performRequest(request, parser: parseOpenAILikeResponse)
    }
}
