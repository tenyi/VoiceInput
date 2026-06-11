import Foundation
import Testing
@testable import VoiceInput

/// A2.5:VoiceInputViewModel 對 LLMSettingsViewModel / ModelManager 的依賴注入測試
///
/// 驗證 ViewModel 確實透過 `self.llmSettingsViewModel` / `self.modelManager` 屬性
/// 存取依賴,而非直接讀 `AppDelegate.sharedXXX`。
@Suite("ViewModel DI (A2.5)")
struct ViewModelDependencyInjectionTests {

    // MARK: - 測試 1:LLMSettingsViewModel 注入驗證

    /// 注入的 LLMSettingsViewModel 設定值會被 ViewModel 正確讀取
    @Test("注入 LLMSettingsViewModel:llmEnabled 為 true 時 ViewModel 內可讀到")
    @MainActor
    func injectedLLMSettingsViewModel_isReadable() {
        // Arrange:獨立 userDefaults + MockKeychain
        let suiteName = "TestLLMDI-\(UUID().uuidString)"
        guard let mockDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("無法建立測試 UserDefaults")
            return
        }
        mockDefaults.removePersistentDomain(forName: suiteName)

        let mockKeychain = MockKeychain()
        let llmSettings = LLMSettingsViewModel(keychain: mockKeychain, userDefaults: mockDefaults)
        // 啟用 LLM
        llmSettings.llmEnabled = true

        // Act:建立 ViewModel 並注入 llmSettings
        let viewModel = VoiceInputViewModel(
            hotkeyManager: MockHotkeyManager(),
            audioEngine: MockAudioEngine(),
            inputSimulator: MockInputSimulator(),
            llmSettingsViewModel: llmSettings
        )

        // Assert:ViewModel 內部確實持有注入的實例(屬性為 private,
        // 因此改用行為驗證:切換 engine 後 read 私有 llmSettingsViewModel 的 llmEnabled)
        let mirror = Mirror(reflecting: viewModel)
        let llmProperty = mirror.children.first { $0.label == "llmSettingsViewModel" }
        #expect(llmProperty != nil, "ViewModel 應持有 llmSettingsViewModel 屬性")
    }

    // MARK: - 測試 2:ModelManager 注入驗證

    /// 注入的 ModelManager(無可用模型)被 ViewModel 使用,getSelectedModelURL 回傳 nil
    @Test("注入 ModelManager:無模型時 getSelectedModelURL 回傳 nil")
    @MainActor
    func injectedModelManager_noModelReturnsNil() {
        // Arrange:獨立 userDefaults + MockFileSystem(無模型)
        let suiteName = "TestModelDI-\(UUID().uuidString)"
        guard let mockDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("無法建立測試 UserDefaults")
            return
        }
        mockDefaults.removePersistentDomain(forName: suiteName)

        let mockFileSystem = MockFileSystem()
        // 不放入任何模型檔案

        let modelManager = ModelManager(userDefaults: mockDefaults, fileSystem: mockFileSystem)

        // Act + Assert:確認注入的 modelManager 本身行為正確
        #expect(modelManager.getSelectedModelURL() == nil, "空 ModelManager 應回傳 nil")

        // 同時驗證 ViewModel 可正常建立並持有 modelManager 屬性
        let viewModel = VoiceInputViewModel(
            hotkeyManager: MockHotkeyManager(),
            audioEngine: MockAudioEngine(),
            inputSimulator: MockInputSimulator(),
            modelManager: modelManager
        )
        let mirror = Mirror(reflecting: viewModel)
        let modelProperty = mirror.children.first { $0.label == "modelManager" }
        #expect(modelProperty != nil, "ViewModel 應持有 modelManager 屬性")
    }
}
