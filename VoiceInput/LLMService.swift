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
    case httpError(statusCode: Int, body: String?)  // C-4 修復:HTTP 狀態碼錯誤

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
        case .httpError(let statusCode, let body):
            // 友善的狀態碼說明,協助使用者排查 API Key / 額度 / 伺服器問題
            let prefix: String
            switch statusCode {
            case 401: prefix = "認證失敗 (請檢查 API Key)"
            case 403: prefix = "權限不足"
            case 404: prefix = "端點不存在 (請檢查 URL 或模型名稱)"
            case 429: prefix = "請求過於頻繁或額度用盡"
            case 500...599: prefix = "伺服器錯誤"
            default: prefix = "HTTP 錯誤"
            }
            if let body, !body.isEmpty {
                return "\(prefix) (狀態碼 \(statusCode)): \(body)"
            }
            return "\(prefix) (狀態碼 \(statusCode))"
        }
    }
}

/// LLM 服務類別，統一處理不同 provider 的 API 呼叫
class LLMService {
    /// 單例模式，使用 let 防止外部替換
    static let shared = LLMService()

    /// M-1 修復:Anthropic API 版本號抽為常數,避免 magic string 散落
    private static let anthropicAPIVersion = "2023-06-01"

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

        // H-1 修復:擴大本地/區域網路判定,涵蓋 RFC1918 私有 IP 與 .local 主機名,
        // 避免自架 LLM (192.168.x.x、10.x.x.x、nas.local:11434 等) 被強制加上 https://
        if Self.isLocalOrPrivateHost(trimmed) {
            return "http://\(trimmed)"
        }

        // 其他情況使用 https://
        return "https://\(trimmed)"
    }

    /// 測試專用入口:把 private `normalizeURL` 暴露成 internal 讓 @testable 測試能呼叫。
    /// 正式 API 路徑(`callOpenAI` / `callOllama` 等)會自己呼叫 private 版本。
    func normalizeURLForTesting(_ url: String) -> String {
        return normalizeURL(url)
    }

    /// 判斷是否為本地/區域網路位址(走 http 而非 https)
    private static func isLocalOrPrivateHost(_ host: String) -> Bool {
        let lower = host.lowercased()

        // localhost / loopback
        if lower.hasPrefix("localhost") || lower.hasPrefix("127.") {
            return true
        }
        // mDNS 主機名 (.local)
        if lower.hasSuffix(".local") {
            return true
        }
        // RFC1918 私有 IPv4 位址:10.0.0.0/8、172.16.0.0/12、192.168.0.0/16
        if lower.hasPrefix("10.") || lower.hasPrefix("192.168.") {
            return true
        }
        if lower.hasPrefix("172.") {
            // 172.16.0.0 - 172.31.255.255
            let parts = lower.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
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
            let (data, response) = try await networkProvider.data(for: request)
            // C-4 修復:檢查 HTTP 狀態碼,避免 401/429/5xx 被誤判為 invalidResponse
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                let bodyMessage = Self.extractErrorMessage(from: data)
                throw LLMServiceError.httpError(statusCode: httpResponse.statusCode, body: bodyMessage)
            }
            return try parser(data)
        } catch let error as LLMServiceError {
            throw error
        } catch {
            throw LLMServiceError.networkError(error)
        }
    }

    /// 嘗試從 HTTP error body 解析錯誤訊息(支援 OpenAI / Anthropic 格式)
    private static func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // OpenAI 格式: { "error": { "message": "..." } }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return sanitizeErrorMessage(message)
        }
        // Anthropic 格式: { "error": { "message": "..." } } (相同)
        // 通用格式: { "message": "..." } 或 { "detail": "..." }
        if let message = json["message"] as? String {
            return sanitizeErrorMessage(message)
        }
        if let detail = json["detail"] as? String {
            return sanitizeErrorMessage(detail)
        }
        return nil
    }

    /// 截斷過長的錯誤訊息並移除 markdown 格式標記，避免 UI 顯示異常
    private static func sanitizeErrorMessage(_ message: String) -> String {
        var result = message
        // 移除 markdown code block 標記
        result = result.replacingOccurrences(of: "```", with: "")
        // 截斷至 200 字元，避免過長的錯誤訊息塞爆 UI
        if result.count > 200 {
            result = String(result.prefix(200)) + "…"
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
                return stripThinkTags(content)
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
                return stripThinkTags(text)
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

    /// 過濾 LLM 回傳內容中的<think>...</think> 標籤及其思考過程
    /// 某些模型（如 Claude）會在回傳時夾帶思考過程，這不是實際結果
    // MARK: - Think Tag Regex

    /// L-3 修復:預編譯 think tag regex,避免每次呼叫 stripThinkTags 都重新編譯
    private static let thinkTagRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: [])
    }()

    /// 過濾 LLM 回傳內容中的<think>...</think> 標籤及其思考過程
    /// 某些模型（如 Claude）會在回傳時夾帶思考過程，這不是實際結果
    /// - Parameter text: 原始回傳文字
    /// - Returns: 過濾並去除多餘空白後的文字
    private func stripThinkTags(_ text: String) -> String {
        let regex = Self.thinkTagRegex
        let range = NSRange(text.startIndex..., in: text)
        let result = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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

        // 如果序列化失敗，向上拋出明確錯誤而非發送空 body 造成難以追蹤的 API 錯誤
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
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
        request.setValue(Self.anthropicAPIVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelName,
            "max_tokens": 1024,
            "system": prompt,
            "messages": [
                ["role": "user", "content": text]
            ]
        ]
        // 如果序列化失敗，向上拋出明確錯誤而非發送空 body
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
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

        // H-2 修復:支援 Ollama 原生端點 (/api/chat),不再強制拼接 /v1/chat/completions
        // Ollama 預設原生 API 為 /api/chat,Ollama OpenAI 相容層才走 /v1/chat/completions
        let isNativeOllamaAPI = baseURL.hasSuffix("/api/chat")
        let endpoint: String
        if isNativeOllamaAPI {
            endpoint = baseURL
        } else if baseURL.hasSuffix("/v1/chat/completions") {
            endpoint = baseURL
        } else if baseURL.hasSuffix("/v1") {
            endpoint = "\(baseURL)/chat/completions"
        } else {
            endpoint = "\(baseURL)/v1/chat/completions"
        }
        guard let apiURL = URL(string: endpoint) else { throw LLMServiceError.invalidConfiguration }

        let modelName = model.isEmpty ? "llama3" : model

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 原生 Ollama 與 OpenAI 相容層的 body 格式相同(都是 messages 陣列)
        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3
        ]

        // 如果序列化失敗，向上拋出明確錯誤而非發送空 body
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // 原生 Ollama 與 OpenAI 相容層回應格式相同(都有 choices[0].message.content)
        // 因此複用 parseOpenAILikeResponse
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

        // 如果序列化失敗，向上拋出明確錯誤而非發送空 body
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performRequest(request, parser: parseOpenAILikeResponse)
    }
}
