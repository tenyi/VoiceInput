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
    static let shared = LLMService()

    private init() {}
    
    /// 正規化 URL,確保包含有效的 scheme
    /// - Parameter urlString: 原始 URL 字串
    /// - Returns: 正規化後的 URL 字串
    /// 正規化 URL，確保包含有效的 scheme
    /// 設計為 static，方便外部（如單元測試）直接呼叫，不需要 LLMService.shared
    /// - Parameter urlString: 原始 URL 字串
    /// - Returns: 正規化後的 URL 字串
    static func normalizeURL(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // 若已有 scheme，直接返回
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }

        // localhost / 127.0.0.1 使用 http（本機不加密）
        if trimmed.hasPrefix("localhost") || trimmed.hasPrefix("127.0.0.1") {
            return "http://\(trimmed)"
        }

        // 其他遠端主機使用 https
        return "https://\(trimmed)"
    }


    /// 修正文字
    /// - Parameters:
    ///   - text: 需要修正的原文
    ///   - prompt: 提示詞
    ///   - provider: LLM 提供者
    ///   - apiKey: API Key
    ///   - url: API URL (Ollama 或自訂使用)
    ///   - model: 模型名稱
    ///   - completion: 回調
    func correctText(
        text: String,
        prompt: String,
        provider: LLMProvider,
        apiKey: String,
        url: String,
        model: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // 驗證必要參數
        guard !text.isEmpty else {
            completion(.failure(LLMServiceError.invalidConfiguration))
            return
        }

        switch provider {
        case .openAI:
            callOpenAI(text: text, prompt: prompt, apiKey: apiKey, model: model, completion: completion)
        case .anthropic:
            callAnthropic(text: text, prompt: prompt, apiKey: apiKey, model: model, completion: completion)
        case .ollama:
            callOllama(text: text, prompt: prompt, url: url, model: model, completion: completion)
        case .custom:
            callCustomAPI(text: text, prompt: prompt, apiKey: apiKey, url: url, model: model, completion: completion)
        }
    }

    // MARK: - OpenAI API

    private func callOpenAI(
        text: String,
        prompt: String,
        apiKey: String,
        model: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // 驗證 API Key
        guard !apiKey.isEmpty else {
            completion(.failure(LLMServiceError.invalidConfiguration))
            return
        }

        let modelName = model.isEmpty ? "gpt-4o" : model
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            completion(.failure(LLMServiceError.invalidConfiguration))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages: [[String: Any]] = [
            ["role": "system", "content": prompt],
            ["role": "user", "content": text]
        ]

        // 不加入 temperature，新式模型可能不支援此參數
        let body: [String: Any] = [
            "model": modelName,
            "messages": messages
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(LLMServiceError.networkError(error)))
                return
            }

            guard let data = data else {
                completion(.failure(LLMServiceError.noContent))
                return
            }

            // 解析 JSON 回應
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    completion(.success(content))
                } else {
                    // 檢查是否有 error 欄位
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = json["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        completion(.failure(LLMServiceError.apiError(message)))
                    } else {
                        completion(.failure(LLMServiceError.invalidResponse))
                    }
                }
            } catch {
                completion(.failure(LLMServiceError.invalidResponse))
            }
        }.resume()
    }

    // MARK: - Anthropic API

    private func callAnthropic(
        text: String,
        prompt: String,
        apiKey: String,
        model: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // 驗證 API Key
        guard !apiKey.isEmpty else {
            completion(.failure(LLMServiceError.invalidConfiguration))
            return
        }

        let modelName = model.isEmpty ? "claude-3-5-sonnet-20241022" : model
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            completion(.failure(LLMServiceError.invalidConfiguration))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = prompt
        let userMessage = text

        let body: [String: Any] = [
            "model": modelName,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(LLMServiceError.networkError(error)))
                return
            }

            guard let data = data else {
                completion(.failure(LLMServiceError.noContent))
                return
            }

            // 解析 JSON 回應
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let content = json["content"] as? [[String: Any]],
                   let firstContent = content.first,
                   let text = firstContent["text"] as? String {
                    completion(.success(text))
                } else {
                    // 檢查是否有 error 欄位
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = json["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        completion(.failure(LLMServiceError.apiError(message)))
                    } else {
                        completion(.failure(LLMServiceError.invalidResponse))
                    }
                }
            } catch {
                completion(.failure(LLMServiceError.invalidResponse))
            }
        }.resume()
    }

    // MARK: - Ollama API

    private func callOllama(
        text: String,
        prompt: String,
        url: String,
        model: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // 驗證 URL，預設使用 http://localhost:11434
        var baseURL = url.isEmpty ? "http://localhost:11434" : LLMService.normalizeURL(url)
        
        // 移除結尾的斜線，避免拼接路徑時產生雙斜線
        if baseURL.hasSuffix("/") {
            baseURL.removeLast()
        }
        
        // 確保 URL 結尾是 /v1/chat/completions
        let endpoint = baseURL.hasSuffix("/v1/chat/completions") ? baseURL : "\(baseURL)/v1/chat/completions"
        guard let apiURL = URL(string: endpoint) else {

            completion(.failure(LLMServiceError.invalidConfiguration))
            return
        }

        let modelName = model.isEmpty ? "gemma3:4b" : model

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 使用 OpenAI 相容格式的 messages
        let messages: [[String: Any]] = [
            ["role": "system", "content": prompt],
            ["role": "user", "content": text]
        ]

        // 不加入 temperature，新式模型可能不支援此參數
        let body: [String: Any] = [
            "model": modelName,
            "messages": messages
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(LLMServiceError.networkError(error)))
                return
            }

            guard let data = data else {
                completion(.failure(LLMServiceError.noContent))
                return
            }

            // 解析 JSON 回應 (OpenAI 相容格式)
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    completion(.success(content))
                } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let error = json["error"] as? [String: Any],
                          let message = error["message"] as? String {
                    completion(.failure(LLMServiceError.apiError(message)))
                } else {
                    completion(.failure(LLMServiceError.invalidResponse))
                }
            } catch {
                completion(.failure(LLMServiceError.invalidResponse))
            }
        }.resume()
    }

    // MARK: - 自訂 API

    private func callCustomAPI(
        text: String,
        prompt: String,
        apiKey: String,
        url: String,
        model: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // 驗證 URL
        guard !url.isEmpty else {
            completion(.failure(LLMServiceError.invalidConfiguration))
            return
        }
        
        let normalizedURL = LLMService.normalizeURL(url)
        guard let apiURL = URL(string: normalizedURL) else {
            completion(.failure(LLMServiceError.invalidConfiguration))
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 如果有 API Key，加入 Authorization header
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        // OpenRouter 需要 HTTP-Referer header
        // if normalizedURL.contains("openrouter.ai") {
        //     request.setValue("https://github.com/tenyi/VoiceInput", forHTTPHeaderField: "HTTP-Referer")
        //     request.setValue("VoiceInput", forHTTPHeaderField: "X-Title")
        // }

        // 組合訊息，支援不同的 API 格式
        let messages: [[String: Any]] = [
            ["role": "system", "content": prompt],
            ["role": "user", "content": text]
        ]

        var body: [String: Any] = [
            "messages": messages
        ]

        // 如果有指定模型，加入 model 參數
        if !model.isEmpty {
            body["model"] = model
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(LLMServiceError.networkError(error)))
                return
            }

            guard let data = data else {
                completion(.failure(LLMServiceError.noContent))
                return
            }

            // 嘗試解析回應 (假設是 OpenAI 相容格式)
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    completion(.success(content))
                } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let error = json["error"] as? [String: Any],
                          let message = error["message"] as? String {
                    completion(.failure(LLMServiceError.apiError(message)))
                } else {
                    completion(.failure(LLMServiceError.invalidResponse))
                }
            } catch {
                completion(.failure(LLMServiceError.invalidResponse))
            }
        }.resume()
    }
}
