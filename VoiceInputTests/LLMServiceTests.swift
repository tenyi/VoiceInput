import Testing
@testable import VoiceInput

// MARK: - LLMService.normalizeURL 測試

/// 測試 LLMService 的 URL 正規化邏輯
/// 使用 static func 直接呼叫，不依賴 LLMService.shared singleton，確保測試不啟動 App
struct LLMServiceTests {

    // MARK: - 已有 scheme 的 URL

    @Test func normalizeURL_httpsIsPassedThrough() {
        #expect(LLMService.normalizeURL("https://api.openai.com/v1/chat/completions")
                == "https://api.openai.com/v1/chat/completions")
    }

    @Test func normalizeURL_httpIsPassedThrough() {
        #expect(LLMService.normalizeURL("http://localhost:11434/api/chat")
                == "http://localhost:11434/api/chat")
    }

    // MARK: - 無 scheme 的 URL

    @Test func normalizeURL_localhostGetsHttp() {
        // localhost 應使用 http（本機不需要 TLS）
        #expect(LLMService.normalizeURL("localhost:11434/api/chat")
                == "http://localhost:11434/api/chat")
    }

    @Test func normalizeURL_loopbackIPGetsHttp() {
        #expect(LLMService.normalizeURL("127.0.0.1:8080/v1")
                == "http://127.0.0.1:8080/v1")
    }

    @Test func normalizeURL_remoteHostGetsHttps() {
        // 遠端主機應使用 https
        #expect(LLMService.normalizeURL("api.custom-provider.com/v1/chat")
                == "https://api.custom-provider.com/v1/chat")
    }

    @Test func normalizeURL_tripsWhitespace() {
        // 前後空白應被清除
        #expect(LLMService.normalizeURL("  https://api.openai.com  ")
                == "https://api.openai.com")
    }

    @Test func normalizeURL_emptyStringGetsHttps() {
        // 空字串補上 https://（讓呼叫方的 URL 驗證去處理）
        #expect(LLMService.normalizeURL("") == "https://")
    }

    // MARK: - 大小寫不影響 scheme 判斷

    @Test func normalizeURL_uppercaseHTTPSIsPassedThrough() {
        #expect(LLMService.normalizeURL("HTTPS://example.com")
                == "HTTPS://example.com")
    }

    @Test func normalizeURL_mixedCaseHTTPSIsPassedThrough() {
        #expect(LLMService.normalizeURL("Https://example.com")
                == "Https://example.com")
    }
}

// MARK: - VoiceInputViewModel 補充測試

/// 補充 VoiceInputViewModel.resolveEffectiveLLMConfiguration 的邊界案例
struct VoiceInputViewModelAdditionalTests {

    // MARK: - Ollama Provider

    @Test func effectiveLLMConfig_ollamaProviderPreservesURL() {
        let config = VoiceInputViewModel.resolveEffectiveLLMConfiguration(
            prompt: "",
            provider: .ollama,
            apiKey: "",
            url: "http://localhost:11434",
            model: "llama3",
            selectedCustomProvider: nil
        )
        #expect(config.provider == .ollama)
        #expect(config.url == "http://localhost:11434")
        #expect(config.model == "llama3")
    }

    // MARK: - 預設 Prompt 的 Fallback

    @Test func effectiveLLMConfig_emptyPromptFallsBackToDefault() {
        let config = VoiceInputViewModel.resolveEffectiveLLMConfiguration(
            prompt: "",
            provider: .openAI,
            apiKey: "key",
            url: "",
            model: "gpt-4o",
            selectedCustomProvider: nil
        )
        // 空 prompt 應 fallback 到 defaultLLMPrompt，而非空字串
        #expect(config.prompt == VoiceInputViewModel.defaultLLMPrompt)
        #expect(!config.prompt.isEmpty)
    }

    @Test func effectiveLLMConfig_nonEmptyPromptIsPreserved() {
        let customPrompt = "請幫我修正以下文字的文法："
        let config = VoiceInputViewModel.resolveEffectiveLLMConfiguration(
            prompt: customPrompt,
            provider: .openAI,
            apiKey: "key",
            url: "",
            model: "gpt-4o",
            selectedCustomProvider: nil
        )
        #expect(config.prompt == customPrompt)
    }

    // MARK: - Custom Provider 的邏輯

    @Test func effectiveLLMConfig_customProviderSetsProviderToCustom() {
        let custom = CustomLLMProvider(
            name: "測試",
            apiURL: "https://test.example.com/v1",
            apiKey: "test-key",
            model: "test-model",
            prompt: "test prompt"
        )
        let config = VoiceInputViewModel.resolveEffectiveLLMConfiguration(
            prompt: "",
            provider: .openAI, // 即使指定 openAI，自訂 provider 應覆蓋
            apiKey: "openai-key",
            url: "",
            model: "gpt-4o",
            selectedCustomProvider: custom
        )
        // 自訂 provider 存在時，應強制使用 .custom
        #expect(config.provider == .custom)
        #expect(config.apiKey == "test-key")
        #expect(config.model == "test-model")
    }

    @Test func effectiveLLMConfig_customProviderWithEmptyPromptFallsBackToBuiltIn() {
        let custom = CustomLLMProvider(
            name: "測試",
            apiURL: "https://test.example.com/v1",
            apiKey: "test-key",
            model: "test-model",
            prompt: "" // 空 prompt
        )
        let builtInPrompt = "請修正文法"
        let config = VoiceInputViewModel.resolveEffectiveLLMConfiguration(
            prompt: builtInPrompt,
            provider: .openAI,
            apiKey: "openai-key",
            url: "",
            model: "gpt-4o",
            selectedCustomProvider: custom
        )
        // 自訂 prompt 為空時，應 fallback 到 built-in prompt
        #expect(config.prompt == builtInPrompt)
    }
}
