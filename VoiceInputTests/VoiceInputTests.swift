//
//  VoiceInputTests.swift
//  VoiceInputTests
//
//  Created by Tenyi on 2026/2/14.
//

import Testing
import CoreGraphics
@testable import VoiceInput

@Suite(.serialized)
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

    // MARK: - T2-2 Hotkey 可重播測試案例

    @Test
    @MainActor
    func hotkeyManager_rightCommandMixedWithLeftCommand_stillReleasesOnRightKeyUp() async throws {
        let manager = HotkeyManager.shared
        manager.stopMonitoring()
        manager.onHotkeyPressed = nil
        manager.onHotkeyReleased = nil
        manager.setHotkey(.rightCommand)
        manager.resetStateForTesting()

        let rightCode = Int64(HotkeyOption.rightCommand.scancode)
        let leftCode = Int64(HotkeyOption.leftCommand.scancode)

        #expect(
            manager.processFlagsChangedEvent(keyCode: rightCode, flags: .maskCommand) == .pressed
        )
        #expect(
            manager.processFlagsChangedEvent(keyCode: leftCode, flags: .maskCommand) == .none
        )
        #expect(
            manager.processFlagsChangedEvent(keyCode: rightCode, flags: .maskCommand) == .released
        )
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
