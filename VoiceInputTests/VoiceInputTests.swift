//
//  VoiceInputTests.swift
//  VoiceInputTests
//
//  Created by Tenyi on 2026/2/14.
//

import Testing
@testable import VoiceInput

struct VoiceInputTests {
    @Test func effectiveLLMConfig_usesBuiltInValuesWhenNoCustomProvider() async throws {
        let config = VoiceInputViewModel.resolveEffectiveLLMConfiguration(
            prompt: "",
            provider: .openAI,
            apiKey: "built-in-key",
            url: "",
            model: "gpt-4o-mini",
            selectedCustomProvider: nil
        )

        #expect(config.provider == .openAI)
        #expect(config.apiKey == "built-in-key")
        #expect(config.model == "gpt-4o-mini")
        #expect(config.prompt == VoiceInputViewModel.defaultLLMPrompt)
    }

    @Test func effectiveLLMConfig_customProviderOverridesProviderAPIKeyURLModelAndPrompt() async throws {
        let custom = CustomLLMProvider(
            name: "MyCustom",
            apiURL: "https://custom.example.com/v1/chat/completions",
            apiKey: "custom-key",
            model: "custom-model",
            prompt: "custom prompt"
        )

        let config = VoiceInputViewModel.resolveEffectiveLLMConfiguration(
            prompt: "built-in prompt",
            provider: .openAI,
            apiKey: "built-in-key",
            url: "https://api.openai.com/v1/chat/completions",
            model: "gpt-4o",
            selectedCustomProvider: custom
        )

        #expect(config.provider == .custom)
        #expect(config.apiKey == "custom-key")
        #expect(config.url == "https://custom.example.com/v1/chat/completions")
        #expect(config.model == "custom-model")
        #expect(config.prompt == "custom prompt")
    }

    @Test func effectiveLLMConfig_customProviderWithEmptyPromptFallsBackToBuiltInOrDefaultPrompt() async throws {
        let custom = CustomLLMProvider(
            name: "MyCustom",
            apiURL: "https://custom.example.com/v1/chat/completions",
            apiKey: "custom-key",
            model: "custom-model",
            prompt: ""
        )

        let withBuiltInPrompt = VoiceInputViewModel.resolveEffectiveLLMConfiguration(
            prompt: "built-in prompt",
            provider: .anthropic,
            apiKey: "built-in-key",
            url: "",
            model: "claude",
            selectedCustomProvider: custom
        )
        #expect(withBuiltInPrompt.prompt == "built-in prompt")

        let withDefaultPrompt = VoiceInputViewModel.resolveEffectiveLLMConfiguration(
            prompt: "",
            provider: .anthropic,
            apiKey: "built-in-key",
            url: "",
            model: "claude",
            selectedCustomProvider: custom
        )
        #expect(withDefaultPrompt.prompt == VoiceInputViewModel.defaultLLMPrompt)
    }
}
