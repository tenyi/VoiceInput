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
    func customLLMProvider_legacyDataDecodesAsOpenAICompatible() throws {
        let legacyJSON = """
        [{"id":"\(UUID().uuidString)","name":"Old","url":"https://a.example.com","model":"m","prompt":""}]
        """
        let providers = try JSONDecoder().decode([CustomLLMProvider].self, from: Data(legacyJSON.utf8))
        #expect(providers.first?.apiFormat == .openAICompatible)

        let anthropic = CustomLLMProvider(name: "A", url: "u", model: "m", prompt: "", apiFormat: .anthropic)
        let roundTrip = try JSONDecoder().decode(CustomLLMProvider.self, from: JSONEncoder().encode(anthropic))
        #expect(roundTrip == anthropic)
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

    @Test
    @MainActor
    func effectiveLLMConfig_customProviderWithNonEmptyPromptUsesCustomPrompt() async throws {
        let custom = CustomLLMProvider(
            name: "CustomWithPrompt",
            url: "https://custom.example.com/v1/chat/completions",
            model: "custom-model",
            prompt: "專屬自訂提示詞"
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
        llmSettings.llmPrompt = "全域提示詞"

        let config = llmSettings.resolveEffectiveConfiguration()
        #expect(config.prompt == "專屬自訂提示詞")

        // 風格補充與詞彙應附加在 Custom Provider 提示詞之後
        let withStyle = llmSettings.resolveEffectiveConfiguration(targetBundleID: "com.apple.mail", vocabulary: ["VoiceInput"])
        #expect(withStyle.prompt == LLMPromptBuilder.buildSystemPrompt(base: "專屬自訂提示詞", style: .email, vocabulary: ["VoiceInput"]))
    }

    @Test
    @MainActor
    func effectiveLLMConfig_contextAwareToggleControlsStyle() async throws {
        let suiteName = "TestDefaults-\(UUID().uuidString)"
        guard let mockDefaults = UserDefaults(suiteName: suiteName) else {
             throw NSError(domain: "VoiceInputTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create mock UserDefaults"])
        }
        mockDefaults.removePersistentDomain(forName: suiteName)

        let llmSettings = LLMSettingsViewModel(keychain: MockKeychain(), userDefaults: mockDefaults)
        llmSettings.llmPrompt = "BASE"

        #expect(llmSettings.llmContextAwareEnabled)
        let enabled = llmSettings.resolveEffectiveConfiguration(targetBundleID: "com.tinyspeck.slackmacgap")
        #expect(enabled.prompt == LLMPromptBuilder.buildSystemPrompt(base: "BASE", style: .chat, vocabulary: []))

        llmSettings.llmContextAwareEnabled = false
        let disabled = llmSettings.resolveEffectiveConfiguration(targetBundleID: "com.tinyspeck.slackmacgap")
        #expect(disabled.prompt == "BASE")
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
    func viewModel_startRecording_capturesFrontmostApp() async throws {
        let suiteName = "TestDefaults-\(UUID().uuidString)"
        guard let mockDefaults = UserDefaults(suiteName: suiteName) else {
             throw NSError(domain: "VoiceInputTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create mock UserDefaults"])
        }
        mockDefaults.removePersistentDomain(forName: suiteName)
        let mockFrontmost = MockFrontmostAppProvider(bundleID: "com.apple.mail")

        let viewModel = VoiceInputViewModel(
            hotkeyManager: MockHotkeyManager(),
            audioEngine: MockAudioEngine(),
            inputSimulator: MockInputSimulator(),
            userDefaults: mockDefaults,
            clock: TestClock(),
            frontmostAppProvider: mockFrontmost
        )

        #expect(mockFrontmost.callCount == 0)
        viewModel.toggleRecording()
        #expect(viewModel.appState == .recording)
        #expect(mockFrontmost.callCount == 1)
    }

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

    /// 建立使用 mock 轉錄服務的 ViewModel,並完成一次「開始 → 停止」錄音
    @MainActor
    private func makeViewModelAndStopRecording(
        service: MockTranscriptionService,
        clock: Clock
    ) async throws -> VoiceInputViewModel {
        let suiteName = "TestDefaults-\(UUID().uuidString)"
        guard let mockDefaults = UserDefaults(suiteName: suiteName) else {
             throw NSError(domain: "VoiceInputTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create mock UserDefaults"])
        }
        mockDefaults.removePersistentDomain(forName: suiteName)

        let viewModel = VoiceInputViewModel(
            hotkeyManager: MockHotkeyManager(),
            audioEngine: MockAudioEngine(),
            inputSimulator: MockInputSimulator(),
            userDefaults: mockDefaults,
            clock: clock
        )
        viewModel.transcriptionManager.serviceFactory = { _, _, _ in service }

        viewModel.toggleRecording()
        let debounceDeadline = Date().addingTimeInterval(0.4)
        while Date() < debounceDeadline {
            try? await Task.yield()
        }
        viewModel.toggleRecording()
        return viewModel
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 1.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test
    @MainActor
    func viewModel_stopRecording_waitsForFinalTranscription() async throws {
        let service = MockTranscriptionService()
        service.completesStopImmediately = false
        let viewModel = try await makeViewModelAndStopRecording(service: service, clock: TimeoutHoldingClock())

        // 最終結果未回來前,維持轉寫狀態(舊版固定 0.5 秒後就結束)
        try await Task.sleep(for: .milliseconds(200))
        #expect(viewModel.appState == .transcribing)

        service.completeStop()
        await waitUntil { viewModel.appState == .idle }
        #expect(viewModel.appState == .idle)
    }

    @Test
    @MainActor
    func viewModel_stopRecording_finishesAfterTimeoutWithoutFinalResult() async throws {
        let service = MockTranscriptionService()
        service.completesStopImmediately = false
        // TestClock 立即返回,等同逾時
        let viewModel = try await makeViewModelAndStopRecording(service: service, clock: TestClock())

        await waitUntil { viewModel.appState == .idle }
        #expect(viewModel.appState == .idle)
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

/// 逾時等級(>= 10 秒)的 sleep 會一直等待,其餘立即返回
private struct TimeoutHoldingClock: Clock {
    func sleep(for duration: Duration) async {
        guard duration >= .seconds(10) else { return }
        try? await Task.sleep(for: .seconds(3600))
    }
}
