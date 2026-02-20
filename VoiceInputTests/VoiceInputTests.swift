//
//  VoiceInputTests.swift
//  VoiceInputTests
//
//  Created by Tenyi on 2026/2/14.
//

import Foundation
import Testing
import CoreGraphics
@testable import VoiceInput

@Suite(.serialized)
struct VoiceInputTests {
    @Test
    @MainActor
    func effectiveLLMConfig_usesBuiltInValuesWhenNoCustomProvider() async throws {
        let llmSettings = LLMSettingsViewModel()
        llmSettings.llmPrompt = ""
        llmSettings.llmProvider = LLMProvider.openAI.rawValue
        llmSettings.llmAPIKey = "built-in-key"
        llmSettings.llmURL = ""
        llmSettings.llmModel = "gpt-4o-mini"
        llmSettings.selectedCustomProviderId = nil

        let config = llmSettings.resolveEffectiveConfiguration()

        #expect(config.provider == .openAI)
        #expect(config.apiKey == "built-in-key")
        #expect(config.model == "gpt-4o-mini")
        #expect(config.prompt == LLMSettingsViewModel.defaultLLMPrompt)
    }

    @Test
    @MainActor
    func effectiveLLMConfig_customProviderWithEmptyPromptFallsBackToBuiltInOrDefaultPrompt() async throws {
        let custom = CustomLLMProvider(
            name: "MyCustom",
            url: "https://custom.example.com/v1/chat/completions",
            apiKey: "custom-key",
            model: "custom-model"
        )

        let llmSettings = LLMSettingsViewModel()
        llmSettings.customProviders = [custom]
        llmSettings.selectedCustomProviderId = custom.id.uuidString
        llmSettings.llmPrompt = "built-in prompt"

        let withBuiltInPrompt = llmSettings.resolveEffectiveConfiguration()
        #expect(withBuiltInPrompt.prompt == "built-in prompt")

        llmSettings.llmPrompt = ""
        let withDefaultPrompt = llmSettings.resolveEffectiveConfiguration()
        #expect(withDefaultPrompt.prompt == LLMSettingsViewModel.defaultLLMPrompt)
    }

    // MARK: - T6-1 Trigger Mode 狀態機測試（Press-and-Hold）

    @Test
    @MainActor
    func pressAndHold_pressedWhenIdle_emitsStart() async throws {
        let controller = HotkeyInteractionController(mode: .pressAndHold)
        var startCount = 0
        var stopCount = 0
        controller.onStartRecording = { startCount += 1 }
        controller.onStopAndTranscribe = { stopCount += 1 }

        controller.isRecording = false
        controller.hotkeyPressed()

        #expect(startCount == 1)
        #expect(stopCount == 0)
    }

    @Test
    @MainActor
    func pressAndHold_releasedWhenRecording_emitsStop() async throws {
        let controller = HotkeyInteractionController(mode: .pressAndHold)
        var startCount = 0
        var stopCount = 0
        controller.onStartRecording = { startCount += 1 }
        controller.onStopAndTranscribe = { stopCount += 1 }

        controller.isRecording = true
        controller.hotkeyReleased()

        #expect(startCount == 0)
        #expect(stopCount == 1)
    }

    @Test
    @MainActor
    func pressAndHold_releasedWhenIdle_doesNothing() async throws {
        let controller = HotkeyInteractionController(mode: .pressAndHold)
        var startCount = 0
        var stopCount = 0
        controller.onStartRecording = { startCount += 1 }
        controller.onStopAndTranscribe = { stopCount += 1 }

        controller.isRecording = false
        controller.hotkeyReleased()

        #expect(startCount == 0)
        #expect(stopCount == 0)
    }

    // MARK: - T6-1 Trigger Mode 狀態機測試（Toggle）

    @Test
    @MainActor
    func toggle_pressedWhenIdle_emitsStart() async throws {
        let controller = HotkeyInteractionController(mode: .toggle)
        var startCount = 0
        var stopCount = 0
        controller.onStartRecording = { startCount += 1 }
        controller.onStopAndTranscribe = { stopCount += 1 }

        controller.isRecording = false
        controller.hotkeyPressed()

        #expect(startCount == 1)
        #expect(stopCount == 0)
    }

    @Test
    @MainActor
    func toggle_pressedWhenRecording_emitsStop() async throws {
        let controller = HotkeyInteractionController(mode: .toggle)
        var startCount = 0
        var stopCount = 0
        controller.onStartRecording = { startCount += 1 }
        controller.onStopAndTranscribe = { stopCount += 1 }

        controller.isRecording = true
        controller.hotkeyPressed()

        #expect(startCount == 0)
        #expect(stopCount == 1)
    }

    @Test
    @MainActor
    func toggle_released_doesNothing() async throws {
        let controller = HotkeyInteractionController(mode: .toggle)
        var startCount = 0
        var stopCount = 0
        controller.onStartRecording = { startCount += 1 }
        controller.onStopAndTranscribe = { stopCount += 1 }

        controller.hotkeyReleased()

        #expect(startCount == 0)
        #expect(stopCount == 0)
    }
}
