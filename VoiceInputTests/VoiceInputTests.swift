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
        // Use a temporary UserDefaults suite for testing to avoid pollution
        let suiteName = "TestDefaults-\(UUID().uuidString)"
        guard let mockDefaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "VoiceInputTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create mock UserDefaults"])
        }
        mockDefaults.removePersistentDomain(forName: suiteName) // Ensure clean slate

        let mockKeychain = MockKeychain()
        // Pre-fill keychain to avoid race condition with didSet/debounce
        mockKeychain.save("built-in-key", service: "com.tenyi.voiceinput", account: "llmAPIKey.OpenAI")
        
        let llmSettings = LLMSettingsViewModel(keychain: mockKeychain, userDefaults: mockDefaults)
        llmSettings.llmPrompt = ""
        llmSettings.llmProvider = LLMProvider.openAI.rawValue
        // llmSettings.llmAPIKey = "built-in-key" // Removed, relying on loaded value
        llmSettings.llmURL = ""
        llmSettings.llmModel = "gpt-4o-mini"
        llmSettings.selectedCustomProviderId = nil
        
        // Force reload to ensure value is picked up
        llmSettings.loadAPIKey(for: .openAI)

        let config = llmSettings.resolveEffectiveConfiguration()

        print("DEBUG: config.provider = \(config.provider)")
        print("DEBUG: config.apiKey = \(config.apiKey)")
        print("DEBUG: config.model = \(config.model)")
        print("DEBUG: config.prompt = \(config.prompt)")

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
            model: "custom-model",
            prompt: ""
        )

        let mockKeychain = MockKeychain()
        let suiteName = "TestDefaults-\(UUID().uuidString)"
        guard let mockDefaults = UserDefaults(suiteName: suiteName) else {
             throw NSError(domain: "VoiceInputTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create mock UserDefaults"])
        }
        mockDefaults.removePersistentDomain(forName: suiteName)
        
        let llmSettings = LLMSettingsViewModel(keychain: mockKeychain, userDefaults: mockDefaults)
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

    // MARK: - ViewModel Mock 依賴注入測試

    @Test
    @MainActor
    func viewModel_toggleRecording_changesStateAndCallsAudioEngine() async throws {
        // Arrange
        let mockHotkey = MockHotkeyManager()
        let mockAudio = MockAudioEngine()
        let mockInput = MockInputSimulator()
        let suiteName = "TestDefaults-\(UUID().uuidString)"
        guard let mockDefaults = UserDefaults(suiteName: suiteName) else {
             throw NSError(domain: "VoiceInputTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create mock UserDefaults"])
        }
        mockDefaults.removePersistentDomain(forName: suiteName)

        // C1.2:注入 TestClock 跳過 stopRecordingAndTranscribe 內的 0.5s 等待
        let testClock = TestClock()

        let viewModel = VoiceInputViewModel(
            hotkeyManager: mockHotkey,
            audioEngine: mockAudio,
            inputSimulator: mockInput,
            userDefaults: mockDefaults,
            clock: testClock
        )

        #expect(viewModel.appState == .idle)
        #expect(mockAudio.isRecording == false)

        // Act: Start recording
        viewModel.toggleRecording()

        // 狀態變化是同步的(handleStartRecordingRequest → startRecording → appState = .recording)
        // MockAudioEngine.startRecording 內 isRecording = true 也是同步
        #expect(viewModel.appState == .recording)
        #expect(mockAudio.isRecording == true)

        // C1.2:等待 300ms debounce 過期(recordingStartTime 使用真實 Date,無法用 TestClock 跳過)
        // 改用 polling yield 精準等待,避免固定 Task.sleep 帶來的 flaky
        let debounceDeadline = Date().addingTimeInterval(0.4)
        while Date() < debounceDeadline {
            try? await Task.yield()
        }

        // Act: Stop recording
        viewModel.toggleRecording()

        // C1.2:同步斷言 appState = .transcribing(stopRecordingAndTranscribe 內同步設定)
        #expect(viewModel.appState == .transcribing)
        #expect(mockAudio.isRecording == false)
    }

    // MARK: - API Key 切換測試

    @Test
    @MainActor
    func llmSettings_switchProvider_loadsCorrectAPIKey() async throws {
        // Arrange
        let mockKeychain = MockKeychain()
        let suiteName = "TestDefaults-\(UUID().uuidString)"
        guard let mockDefaults = UserDefaults(suiteName: suiteName) else {
             throw NSError(domain: "VoiceInputTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create mock UserDefaults"])
        }
        mockDefaults.removePersistentDomain(forName: suiteName)
        
        // 預先在 Keychain 中存入兩個不同的 API Key
        mockKeychain.save("openai-secret-key", service: "com.tenyi.voiceinput", account: "llmAPIKey.OpenAI")
        mockKeychain.save("anthropic-secret-key", service: "com.tenyi.voiceinput", account: "llmAPIKey.Anthropic")
        
        let llmSettings = LLMSettingsViewModel(keychain: mockKeychain, userDefaults: mockDefaults)
        
        // Act & Assert 1: 初始化或切換到 OpenAI
        llmSettings.llmProvider = LLMProvider.openAI.rawValue
        llmSettings.loadAPIKey(for: .openAI) // 模擬 View 出現或 Provider 變更時觸發的載入
        #expect(llmSettings.llmAPIKey == "openai-secret-key")
        
        // Act & Assert 2: 切換到 Anthropic
        llmSettings.llmProvider = LLMProvider.anthropic.rawValue
        llmSettings.loadAPIKey(for: .anthropic)
        #expect(llmSettings.llmAPIKey == "anthropic-secret-key")
    }
}
import Foundation
@testable import VoiceInput

class MockKeychain: KeychainProtocol {
    private var storage: [String: String] = [:]
    
    func save(_ value: String, service: String, account: String) {
        let key = "\(service)-\(account)"
        storage[key] = value
    }
    
    func read(service: String, account: String) -> String? {
        let key = "\(service)-\(account)"
        return storage[key]
    }
    
    func delete(service: String, account: String) {
        let key = "\(service)-\(account)"
        storage.removeValue(forKey: key)
    }
}
