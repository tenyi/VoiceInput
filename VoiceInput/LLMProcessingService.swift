import Foundation
import os

/// 負責處理從語音轉寫後，發送文字給 LLM 進行修正的服務
class LLMProcessingService {
    static let shared = LLMProcessingService()
    
    private init() {}
    
    /// 執行 LLM 文字修正
    func process(
        text: String,
        config: EffectiveLLMConfiguration,
        logger: Logger,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        Task {
            do {
                let correctedText = try await LLMService.shared.correctText(
                    text: text,
                    prompt: config.prompt,
                    provider: config.provider,
                    apiKey: config.apiKey,
                    url: config.url,
                    model: config.model
                )
                completion(.success(correctedText))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
