import Foundation
import SwiftUI
import Combine
import AppKit
import os
import UniformTypeIdentifiers

// MARK: - LLM Provider 選項
/// LLM 服務提供者
enum LLMProvider: String, CaseIterable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case ollama = "Ollama"
    case custom = "自訂 API"

    /// 是否為內建 Provider
    var isBuiltIn: Bool {
        return self != .custom
    }
}

// MARK: - 自訂 LLM Provider
/// 自訂 LLM Provider 配置（用於儲存用戶添加的 Provider）
struct CustomLLMProvider: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String           // 顯示名稱（如 "Qwen", "Kimi"）
    var apiURL: String        // API 端點 URL
    var apiKey: String        // API Key
    var model: String         // 模型名稱
    var prompt: String        // 自訂提示詞（可選）

    init(id: UUID = UUID(), name: String, apiURL: String, apiKey: String = "", model: String = "", prompt: String = "") {
        self.id = id
        self.name = name
        self.apiURL = apiURL
        self.apiKey = apiKey
        self.model = model
        self.prompt = prompt
    }

    /// 顯示名稱
    var displayName: String {
        return name
    }
}

/// 應用程式狀態
enum AppState {
    case idle       // 待機中
    case recording  // 錄音中（按住 hotkey）
    case transcribing // 轉寫中
}

/// 單筆轉錄歷史紀錄
struct TranscriptionHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// 負責管理 VoiceInput 應用程式狀態的 ViewModel
class VoiceInputViewModel: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "VoiceInputViewModel")

    // MARK: - 持久化設定 (AppStorage)
    @AppStorage("selectedLanguage") var selectedLanguage: String = "zh-TW"
    @AppStorage("whisperModelPath") var whisperModelPath: String = ""


    @AppStorage("autoInsertText") var autoInsertText: Bool = true
    @AppStorage("selectedHotkey") var selectedHotkey: String = HotkeyOption.rightCommand.rawValue
    @AppStorage("selectedSpeechEngine") var selectedSpeechEngine: String = SpeechRecognitionEngine.apple.rawValue
    @AppStorage("selectedInputDeviceID") private var selectedInputDeviceStorage: String = ""

    // MARK: - 已導入的模型列表
    @AppStorage("importedModels") private var importedModelsData: Data = Data()
    @Published var importedModels: [ImportedModel] = []

    // MARK: - 模型匯入狀態
    /// 是否正在匯入模型
    @Published var isImportingModel = false
    /// 匯入進度 (0.0 ~ 1.0)
    @Published var modelImportProgress: Double = 0.0
    /// 匯入錯誤訊息
    @Published var modelImportError: String?
    /// 匯入速度（格式化字串）
    @Published var modelImportSpeed: String = ""
    /// 預估剩餘時間
    @Published var modelImportRemainingTime: String = ""

    /// 公開的模型目錄 URL（供 UI 使用）
    var publicModelsDirectory: URL {
        return modelsDirectory
    }

    /// 取得模型儲存目錄
    private var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoiceInput/Models", isDirectory: true)
    }

    /// 轉錄歷史檔案路徑
    private var transcriptionHistoryFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("VoiceInput", isDirectory: true)
            .appendingPathComponent("transcription_history.json", isDirectory: false)
    }

    // MARK: - Speech Engine 選項

    // MARK: - LLM 修正設定
    /// 是否啟用 LLM 修正
    @AppStorage("llmEnabled") var llmEnabled: Bool = false
    /// LLM 服務提供者
    @AppStorage("llmProvider") var llmProvider: String = LLMProvider.openAI.rawValue
    /// API URL (Ollama 或自訂 API 使用)
    @AppStorage("llmURL") var llmURL: String = "" {
        didSet {
            saveCurrentBuiltInProviderSettings()
        }
    }
    
    /// API Key (已遷移至 Keychain)
    @Published var llmAPIKey: String = "" {
        didSet {
            saveCurrentBuiltInProviderAPIKey()
        }
    }
    
    /// 模型名稱 (如 gpt-4o, claude-3-5-sonnet, llama3 等)
    @AppStorage("llmModel") var llmModel: String = "" {
        didSet {
            saveCurrentBuiltInProviderSettings()
        }
    }
    /// 自訂提示詞
    @AppStorage("llmPrompt") var llmPrompt: String = ""

    // MARK: - 運行時狀態
    /// 當前應用程式狀態
    @Published var appState: AppState = .idle

    /// 是否正在錄音
    var isRecording: Bool { appState == .recording }
    /// 是否正在轉寫
    var isTranscribing: Bool { appState == .transcribing }

    /// 已轉錄的文字內容
    @Published var transcribedText = "等待輸入..."
    /// 最近轉錄歷史（最多 10 筆）
    @Published var transcriptionHistory: [TranscriptionHistoryItem] = []
    /// LLM 修正錯誤訊息（用於在懸浮視窗顯示）
    @Published var lastLLMError: String?
    /// 權限狀態
    @Published var permissionGranted = false
    /// 錄音開始時間（用於防抖，避免極短暫的錄音）
    private var recordingStartTime: Date?

    /// 音訊引擎 (使用單例)
    private var audioEngine = AudioEngine.shared

    /// 可用的音訊輸入設備列表
    var availableInputDevices: [AudioInputDevice] {
        audioEngine.availableInputDevices
    }

    /// 當前選擇的音訊輸入設備 ID
    @Published var selectedInputDeviceID: String? {
        didSet {
            audioEngine.selectedDeviceID = selectedInputDeviceID
            selectedInputDeviceStorage = selectedInputDeviceID ?? ""
        }
    }

    /// 刷新音訊設備列表
    func refreshAudioDevices() {
        audioEngine.refreshAvailableDevices()
        DispatchQueue.main.async { [weak self] in
            self?.reconcileSelectedInputDevice()
        }
    }
    /// 轉錄服務 (目前支援 SFSpeech)
    private var transcriptionService: TranscriptionServiceProtocol = SFSpeechTranscriptionService()
    /// 轉錄管理器 - 負責轉錄狀態管理
    @ObservedObject var transcriptionManager = TranscriptionManager()
    /// 輸入模擬器 (用於插入文字)
    private var inputSimulator = InputSimulator.shared

    /// 權限管理員
    @ObservedObject var permissionManager = PermissionManager.shared

    /// 可選語言清單
    let availableLanguages = [
        "zh-TW": "繁體中文 (Taiwan)",
        "zh-CN": "簡體中文 (China)",
        "en-US": "English (US)",
        "ja-JP": "日本語 (Japan)"
    ]

    /// 可選快捷鍵清單
    let availableHotkeys = HotkeyOption.allCases

    // MARK: - 自訂 LLM Provider 管理

    /// 自訂 Provider 列表（儲存多個用戶添加的 Provider）
    @AppStorage("customLLMProviders") private var customProvidersData: Data = Data()
    @Published var customProviders: [CustomLLMProvider] = []
    @AppStorage("builtInProviderSettings") private var builtInProviderSettingsData: Data = Data()
    private var builtInProviderSettings: [String: BuiltInProviderSetting] = [:]

    /// 目前選擇的自訂 Provider ID（若選擇內建 Provider 則為 nil）
    @AppStorage("selectedCustomProviderId") var selectedCustomProviderId: String?

    /// 取得目前的 LLM Provider
    var currentLLMProvider: LLMProvider {
        // 如果有選擇自訂 Provider，使用自訂 API 類型
        if selectedCustomProviderId != nil {
            return .custom
        }
        return LLMProvider(rawValue: llmProvider) ?? .openAI
    }

    /// 取得目前選擇的自訂 Provider（若無則返回 nil）
    var selectedCustomProvider: CustomLLMProvider? {
        guard let idString = selectedCustomProviderId,
              let uuid = UUID(uuidString: idString) else {
            return nil
        }
        return customProviders.first { $0.id == uuid }
    }

    /// 取得所有可用的 Provider 顯示名稱列表（包含內建和自訂）
    var allProviderDisplayNames: [String] {
        var names: [String] = []
        // 內建 Provider
        for provider in LLMProvider.allCases {
            names.append(provider.rawValue)
        }
        // 自訂 Provider
        for custom in customProviders {
            names.append(custom.displayName)
        }
        return names
    }

    /// 儲存自訂 Provider 列表
    private func saveCustomProviders() {
        do {
            customProvidersData = try JSONEncoder().encode(customProviders)
        } catch {
            logger.error("無法保存自訂 Provider 列表: \(error.localizedDescription)")
        }
    }

    /// 載入自訂 Provider 列表
    private func loadCustomProviders() {
        guard !customProvidersData.isEmpty else { return }
        do {
            customProviders = try JSONDecoder().decode([CustomLLMProvider].self, from: customProvidersData)
            logger.info("已載入 \(self.customProviders.count) 個自訂 Provider")
        } catch {
            logger.error("無法載入自訂 Provider 列表: \(error.localizedDescription)")
        }
    }

    /// 添加新的自訂 Provider
    func addCustomProvider(_ provider: CustomLLMProvider) {
        customProviders.append(provider)
        saveCustomProviders()
        logger.info("已添加自訂 Provider: \(provider.name)")
    }

    /// 更新自訂 Provider
    func updateCustomProvider(_ provider: CustomLLMProvider) {
        if let index = customProviders.firstIndex(where: { $0.id == provider.id }) {
            customProviders[index] = provider
            saveCustomProviders()
            logger.info("已更新自訂 Provider: \(provider.name)")
        }
    }

    /// 刪除自訂 Provider
    func deleteCustomProvider(_ provider: CustomLLMProvider) {
        customProviders.removeAll { $0.id == provider.id }
        // 如果刪除的是當前選擇的 Provider，清除選擇
        if selectedCustomProviderId == provider.id.uuidString {
            selectedCustomProviderId = nil
        }
        saveCustomProviders()
        logger.info("已刪除自訂 Provider: \(provider.name)")
    }

    private func loadBuiltInProviderSettings() {
        guard !builtInProviderSettingsData.isEmpty else { return }
        do {
            builtInProviderSettings = try JSONDecoder().decode([String: BuiltInProviderSetting].self, from: builtInProviderSettingsData)
        } catch {
            builtInProviderSettings = [:]
            logger.error("無法載入內建 Provider 設定: \(error.localizedDescription)")
        }
    }

    private func saveBuiltInProviderSettings() {
        do {
            builtInProviderSettingsData = try JSONEncoder().encode(builtInProviderSettings)
        } catch {
            logger.error("無法保存內建 Provider 設定: \(error.localizedDescription)")
        }
    }

    func saveCurrentBuiltInProviderSettings() {
        guard selectedCustomProviderId == nil else { return }
        guard let provider = LLMProvider(rawValue: llmProvider), provider != .custom else { return }

        builtInProviderSettings[provider.rawValue] = BuiltInProviderSetting(
            url: llmURL,
            model: llmModel
        )
        saveBuiltInProviderSettings()
    }

    func loadBuiltInProviderSettings(for provider: LLMProvider) {
        guard provider != .custom else { return }

        if let saved = builtInProviderSettings[provider.rawValue] {
            llmURL = saved.url
            llmModel = saved.model
            return
        }

        if provider == .ollama && llmURL.isEmpty {
            llmURL = "http://localhost:11434/v1/chat/completions"
        }
    }

    private func builtInProviderAPIKeyAccount(for provider: LLMProvider) -> String {
        "llmAPIKey.\(provider.rawValue)"
    }

    private func loadLegacyLLMAPIKeyIfNeeded() {
        if let savedKey = KeychainHelper.shared.read(service: "com.tenyi.voiceinput", account: "llmAPIKey"), !savedKey.isEmpty {
            llmAPIKey = savedKey
            return
        }

        let legacyKey = UserDefaults.standard.string(forKey: "llmAPIKey") ?? ""
        if !legacyKey.isEmpty {
            llmAPIKey = legacyKey
            KeychainHelper.shared.save(legacyKey, service: "com.tenyi.voiceinput", account: "llmAPIKey")
            UserDefaults.standard.removeObject(forKey: "llmAPIKey")
        }
    }

    func saveCurrentBuiltInProviderAPIKey() {
        guard selectedCustomProviderId == nil else { return }
        guard let provider = LLMProvider(rawValue: llmProvider), provider != .custom else { return }

        KeychainHelper.shared.save(
            llmAPIKey,
            service: "com.tenyi.voiceinput",
            account: builtInProviderAPIKeyAccount(for: provider)
        )
    }

    func loadBuiltInProviderAPIKey(for provider: LLMProvider) {
        guard provider != .custom else { return }

        if let savedKey = KeychainHelper.shared.read(
            service: "com.tenyi.voiceinput",
            account: builtInProviderAPIKeyAccount(for: provider)
        ) {
            llmAPIKey = savedKey
            return
        }

        // 舊版單一 Key 的相容遷移（第一次切換到該 provider 時複製一份）
        if let legacyKey = KeychainHelper.shared.read(service: "com.tenyi.voiceinput", account: "llmAPIKey"),
           !legacyKey.isEmpty {
            llmAPIKey = legacyKey
            KeychainHelper.shared.save(
                legacyKey,
                service: "com.tenyi.voiceinput",
                account: builtInProviderAPIKeyAccount(for: provider)
            )
            return
        }

        llmAPIKey = ""
    }

    /// 清除目前選擇的 Provider（切回內建 Provider）
    func clearSelectedProvider() {
        selectedCustomProviderId = nil
    }

    /// 取得目前的語音辨識引擎
    var currentSpeechEngine: SpeechRecognitionEngine {
        SpeechRecognitionEngine(rawValue: selectedSpeechEngine) ?? .apple
    }

    /// LLM 修正的預設提示詞
    static let defaultLLMPrompt = "你是一個文字校稿員。請修正以下語音辨識結果中的錯誤（包括錯字、漏字、標點符號等），但不要改變原意。只需回傳修正後的文字，reply in zh-TW，不要有其他說明。"

    private struct BuiltInProviderSetting: Codable {
        var url: String
        var model: String
    }

    init() {
        selectedInputDeviceID = selectedInputDeviceStorage.isEmpty ? nil : selectedInputDeviceStorage
        audioEngine.selectedDeviceID = selectedInputDeviceID

        loadCustomProviders()  // 載入自訂 Provider 列表
        loadBuiltInProviderSettings()
        if selectedCustomProviderId == nil {
            loadBuiltInProviderAPIKey(for: currentLLMProvider)
            loadBuiltInProviderSettings(for: currentLLMProvider)
        } else {
            loadLegacyLLMAPIKeyIfNeeded()
        }
        loadImportedModels()
        loadTranscriptionHistory()
        setupAudioEngine()
        setupHotkeys()
        refreshAudioDevices()
    }

    // MARK: - 模型導入功能

    /// 載入已導入的模型列表
    private func loadImportedModels() {
        guard !importedModelsData.isEmpty else { return }
        do {
            importedModels = try JSONDecoder().decode([ImportedModel].self, from: importedModelsData)
            logger.info("已載入 \(self.importedModels.count) 個已導入的模型")
        } catch {
            logger.error("無法載入已導入的模型列表: \(error.localizedDescription)")
        }
    }

    /// 保存已導入的模型列表
    private func saveImportedModels() {
        do {
            importedModelsData = try JSONEncoder().encode(importedModels)
        } catch {
            logger.error("無法保存模型列表: \(error.localizedDescription)")
        }
    }

    /// 載入轉錄歷史（最多保留 10 筆）
    private func loadTranscriptionHistory() {
        let fileURL = transcriptionHistoryFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            transcriptionHistory = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([TranscriptionHistoryItem].self, from: data)
            transcriptionHistory = Array(decoded.sorted(by: { $0.createdAt > $1.createdAt }).prefix(10))
        } catch {
            logger.error("無法載入轉錄歷史: \(error.localizedDescription)")
            transcriptionHistory = []
        }
    }

    /// 保存轉錄歷史（最多保留 10 筆）
    private func saveTranscriptionHistory() {
        do {
            let historyToSave = Array(transcriptionHistory.prefix(10))
            let data = try JSONEncoder().encode(historyToSave)
            let fileURL = transcriptionHistoryFileURL
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("無法保存轉錄歷史: \(error.localizedDescription)")
        }
    }

    /// 導入模型（從檔案選擇器選擇）
    func importModel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "bin")].compactMap { $0 }
        panel.message = "選擇 Whisper 模型檔案 (.bin)"

        panel.begin { [weak self] result in
            guard let self = self, result == .OK, let sourceURL = panel.url else { return }

            DispatchQueue.main.async {
                self.importModelFromURL(sourceURL)
            }
        }
    }

    /// 從指定 URL 導入模型
    func importModelFromURL(_ sourceURL: URL) {
        // 進入匯入狀態
        self.isImportingModel = true
        self.modelImportError = nil
        self.modelImportProgress = 0.0
        self.modelImportSpeed = "準備中..."
        self.modelImportRemainingTime = "計算中..."

        // 取得模型名稱（不含副檔名）
        let modelName = sourceURL.deletingPathExtension().lastPathComponent
        let destinationFileName = "\(modelName).bin"
        let destinationURL = modelsDirectory.appendingPathComponent(destinationFileName)

        // 檢查是否已存在
        if importedModels.contains(where: { $0.fileName == destinationFileName }) {
            self.modelImportError = "模型已存在: \(destinationFileName)"
            self.isImportingModel = false
            return
        }

        // 在背景執行複製操作
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                // 確保目錄存在
                try FileManager.default.createDirectory(at: self.modelsDirectory, withIntermediateDirectories: true, attributes: nil)

                // 使用 FileCoordinator 進行安全複製 (也可以簡單使用 FileManager callback，但 swift 標準庫沒有進度回調的 copy)
                // 這裡我們模擬進度或直接複製。因為 FileManager.copyItem 是同步且無進度的。
                // 為了更好的 UX，我們先檢查檔案大小
                let fileSize = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                
                // 開始複製
                DispatchQueue.main.async {
                     self.modelImportSpeed = "正在複製..."
                     self.modelImportProgress = 0.5 // 假進度，因為 copyItem 無法追蹤
                }
                
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

                // 建立新模型物件
                let newModel = ImportedModel(name: modelName, fileName: destinationFileName, fileSize: Int64(fileSize))
                
                DispatchQueue.main.async {
                    // 新增到列表
                    self.importedModels.append(newModel)
                    self.saveImportedModels()
                    
                    // 自動選擇新導入的模型
                    self.selectImportedModel(newModel)
                    
                    self.logger.info("模型導入成功: \(destinationFileName)，儲存於: \(destinationURL.path)")
                    
                    // 完成
                    self.modelImportProgress = 1.0
                    self.modelImportSpeed = "完成"
                    self.modelImportRemainingTime = ""
                    
                    // 延遲一下讓用戶看到 100%
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isImportingModel = false
                        self.modelImportProgress = 0.0
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.logger.error("模型導入失敗: \(error.localizedDescription)")
                    self.modelImportError = "導入失敗: \(error.localizedDescription)"
                    self.isImportingModel = false
                }
            }
        }
    }

    /// 刪除模型
    func deleteModel(_ model: ImportedModel) {
        let modelURL = modelsDirectory.appendingPathComponent(model.fileName)

        do {
            // 刪除檔案
            if FileManager.default.fileExists(atPath: modelURL.path) {
                try FileManager.default.removeItem(at: modelURL)
            }

            // 從列表移除
            importedModels.removeAll { $0.id == model.id }
            saveImportedModels()

            // 如果當前選擇的模型被刪除，清除選擇
            if whisperModelPath == modelURL.path {
                whisperModelPath = ""
            }

            logger.info("模型已刪除: \(model.fileName)")
        } catch {
            logger.error("刪除模型失敗: \(error.localizedDescription)")
        }
    }

    /// 選擇已導入的模型
    func selectImportedModel(_ model: ImportedModel) {
        let modelURL = modelsDirectory.appendingPathComponent(model.fileName)
        whisperModelPath = modelURL.path
        logger.info("已選擇模型: \(model.fileName)")
    }

    /// 取得目前選擇模型的 URL
    func getSelectedModelURL() -> URL? {
        if !whisperModelPath.isEmpty {
            return URL(fileURLWithPath: whisperModelPath)
        }
        return nil
    }

    /// 設定音訊引擎與檢查權限
    private func setupAudioEngine() {
        // 檢查所有權限狀態
        permissionManager.checkAllPermissions()

        // 請求必要的權限
        audioEngine.checkPermission { [weak self] granted in
            self?.permissionGranted = granted
        }
    }

    /// 校正已選擇的輸入設備：
    /// 若設備仍存在則保留，若不存在則回退到系統預設。
    private func reconcileSelectedInputDevice() {
        guard let selectedID = selectedInputDeviceID else { return }

        let exists = availableInputDevices.contains { $0.id == selectedID }
        if !exists {
            selectedInputDeviceID = nil
        }
    }

    /// 設定快捷鍵監聽
    private func setupHotkeys() {
        // 套用儲存的快捷鍵設定
        if let savedHotkey = HotkeyOption(rawValue: selectedHotkey) {
            HotkeyManager.shared.setHotkey(savedHotkey)
        }

        // 按下快捷鍵時開始錄音
        HotkeyManager.shared.onHotkeyPressed = { [weak self] in
            DispatchQueue.main.async {
                self?.handleHotkeyPressed()
            }
        }

        // 放開快捷鍵時停止錄音並開始轉寫
        HotkeyManager.shared.onHotkeyReleased = { [weak self] in
            DispatchQueue.main.async {
                self?.handleHotkeyReleased()
            }
        }

        HotkeyManager.shared.startMonitoring()
    }

    /// 更新快捷鍵設定
    /// - Parameter option: 新的快捷鍵選項
    func updateHotkey(_ option: HotkeyOption) {
        selectedHotkey = option.rawValue
        HotkeyManager.shared.setHotkey(option)
    }

    // MARK: - 快捷鍵處理

    /// 處理快捷鍵按下（開始錄音）
    private func handleHotkeyPressed() {
        // 如果正在轉寫中，忽略
        guard appState == .idle else { return }

        // 檢查權限
        guard audioEngine.permissionGranted else {
            permissionManager.requestAllPermissionsIfNeeded { [weak self] granted in
                if granted {
                    self?.startRecording()
                }
            }
            return
        }

        startRecording()
    }

    /// 處理快捷鍵放開（停止錄音，開始轉寫）
    private func handleHotkeyReleased() {
        // 只有在錄音狀態才處理
        guard appState == .recording else { return }

        // 防抖：錄音時間少於 300ms 則忽略放開事件
        if let startTime = recordingStartTime,
           Date().timeIntervalSince(startTime) < 0.3 {
            logger.warning("錄音時間過短（< 300ms），忽略放開事件")
            return
        }

        stopRecordingAndTranscribe()
    }

    /// 開始錄音
    private func startRecording() {
        // 確保 WindowManager 已有 viewModel 設定
        if WindowManager.shared.viewModel == nil {
            WindowManager.shared.viewModel = self
        }

        // 根據選擇的引擎初始化服務
        switch currentSpeechEngine {
        case .apple:
            // 確保使用 SFSpeechTranscriptionService
            if !(transcriptionService is SFSpeechTranscriptionService) {
                transcriptionService = SFSpeechTranscriptionService()
            }
            // 更新轉錄服務語言
            if let sfService = transcriptionService as? SFSpeechTranscriptionService {
                sfService.updateLocale(identifier: selectedLanguage)
            }
            
        case .whisper:
            // 檢查模型路徑是否存在
            guard !whisperModelPath.isEmpty, FileManager.default.fileExists(atPath: whisperModelPath) else {
                 transcribedText = "請先在設定中選擇有效的 Whisper 模型檔案 (.bin)"
                 WindowManager.shared.showFloatingWindow(isRecording: true)
                 appState = .recording // 暫時進入狀態以顯示錯誤
                 
                 DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                     WindowManager.shared.hideFloatingWindow()
                     self.appState = .idle
                     self.transcribedText = "等待輸入..."
                 }
                 return
            }

             // 初始化或重用 Whisper 服務
            // 若當前服務不是 Whisper 或模型路徑改變，則重新初始化
            // 這裡簡化邏輯：每次開始錄音前檢查是否需要切換
             if !(transcriptionService is WhisperTranscriptionService) {
                 if let modelURL = resolveModelURL() {
                     logger.info("正在初始化 Whisper 服務，模型路徑: \(modelURL.path)")

                     // 創建 WhisperTranscriptionService，它會自己管理 security-scoped resource
                     transcriptionService = WhisperTranscriptionService(modelURL: modelURL)

                     // 檢查是否創建成功
                     if let whisperService = transcriptionService as? WhisperTranscriptionService {
                         logger.info("WhisperTranscriptionService 創建成功")
                     } else {
                         logger.error("WhisperTranscriptionService 創建失敗")
                         transcribedText = "Whisper 服務初始化失敗，請重新選擇模型"
                         WindowManager.shared.showFloatingWindow(isRecording: true)
                         DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                             WindowManager.shared.hideFloatingWindow()
                             self.transcribedText = "等待輸入..."
                         }
                         return
                     }
                 } else {
                     logger.error("無法解析模型 URL")
                     transcribedText = "無法解析模型 URL，請重新選擇模型"
                     WindowManager.shared.showFloatingWindow(isRecording: true)
                     DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                         WindowManager.shared.hideFloatingWindow()
                         self.transcribedText = "等待輸入..."
                     }
                     return
                 }
             }

        }

        // 顯示浮動視窗（錄音模式）
        WindowManager.shared.showFloatingWindow(isRecording: true)

        transcribedText = ""
        // 設定轉錄結果回調
        transcriptionService.onTranscriptionResult = { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    // 只有非空文字才更新，否則保持空白
                    if !text.isEmpty {
                        self?.transcribedText = text
                    }
                case .failure(let error):
                    // 真正的錯誤才顯示錯誤訊息
                    self?.transcribedText = "識別錯誤：\(error.localizedDescription)"
                }
            }
        }

        transcriptionService.start()

        // 記錄錄音開始時間（用於防抖）
        recordingStartTime = Date()

        // 立即設定狀態為錄音中，確保按鍵放開時能正確處理
        appState = .recording

        do {
            try audioEngine.startRecording { [weak self] buffer in
                self?.transcriptionService.process(buffer: buffer)
            }
        } catch {
            // 錄音啟動失敗，恢復狀態
            appState = .idle
            transcribedText = "錄音啟動失敗：\(error.localizedDescription)"
            // 延遲 2 秒後再隱藏視窗，讓使用者能看清錯誤
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                WindowManager.shared.hideFloatingWindow()
                self.transcribedText = "等待輸入..."
            }
        }
    }

    /// 停止錄音並開始轉寫
    private func stopRecordingAndTranscribe() {
        // 停止錄音
        audioEngine.stopRecording()
        transcriptionService.stop()

        // 切換到轉寫狀態
        appState = .transcribing

        // 顯示浮動視窗（轉寫模式）
        WindowManager.shared.showFloatingWindow(isRecording: false)

        // 延遲一點時間讓用户看到轉寫動畫
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.finishTranscribing()
        }
    }

    /// 完成轉寫，插入文字並隱藏視窗
    private func finishTranscribing() {
        // 檢查是否有有效文字（排除空字串和錯誤訊息）
        let hasValidText = !transcribedText.isEmpty &&
                          !transcribedText.hasPrefix("識別錯誤：") &&
                          transcribedText != "等待輸入..."

        // 有有效文字的情況
        if hasValidText {
            if llmEnabled {
                // 啟用 LLM 修正：進行修正後再插入
                performLLMCorrection { [weak self] in
                    self?.proceedToInsertAndHide()
                }
            } else {
                // 未啟用 LLM：直接插入文字並隱藏
                proceedToInsertAndHide()
            }
        } else {
            // 無有效文字，直接隱藏視窗
            hideWindow()
        }
    }

    /// 執行 LLM 文字修正
    private func performLLMCorrection(completion: @escaping () -> Void) {
        let config = resolveEffectiveLLMConfiguration()

        LLMService.shared.correctText(
            text: transcribedText,
            prompt: config.prompt,
            provider: config.provider,
            apiKey: config.apiKey,
            url: config.url,
            model: config.model
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let correctedText):
                    self?.transcribedText = correctedText
                case .failure(let error):
                    // 若修正失敗，保留原文繼續執行，並記錄錯誤訊息
                    self?.lastLLMError = error.localizedDescription
                    self?.logger.error("LLM 修正失敗: \(error.localizedDescription)")
                }
                completion()
            }
        }
    }

    /// 執行插入文字並隱藏視窗
    private func proceedToInsertAndHide() {
        addTranscriptionHistoryIfNeeded(transcribedText)

        // 自動插入文字到當前應用程式
        if autoInsertText && !transcribedText.isEmpty && transcribedText != "等待輸入..." {
            // 檢查輔助功能權限
            permissionManager.requestPermissionIfNeeded(.accessibility) { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    self.insertText()
                }

                // 如果有 LLM 錯誤，先顯示錯誤訊息一段時間後再隱藏
                if self.lastLLMError != nil {
                    // 設定狀態為顯示錯誤（保持懸浮視窗可見）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.lastLLMError = nil // 清除錯誤訊息
                        self?.hideWindow()
                    }
                } else {
                    self.hideWindow()
                }
            }
        } else {
            // 如果有 LLM 錯誤，先顯示錯誤訊息一段時間後再隱藏
            if lastLLMError != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.lastLLMError = nil
                    self?.hideWindow()
                }
            } else {
                hideWindow()
            }
        }
    }

    /// 插入文字到當前焦點
    private func insertText() {
        // 延遲確保焦點切換
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.inputSimulator.insertText(self.transcribedText)
        }
    }

    /// 添加轉錄歷史（僅保留最近 10 筆）
    private func addTranscriptionHistoryIfNeeded(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "等待輸入...", !trimmed.hasPrefix("識別錯誤：") else {
            return
        }

        let item = TranscriptionHistoryItem(text: trimmed, createdAt: Date())
        transcriptionHistory.insert(item, at: 0)
        if transcriptionHistory.count > 10 {
            transcriptionHistory = Array(transcriptionHistory.prefix(10))
        }
        saveTranscriptionHistory()
    }

    /// 刪除指定歷史紀錄
    func deleteHistoryItem(_ item: TranscriptionHistoryItem) {
        transcriptionHistory.removeAll { $0.id == item.id }
        saveTranscriptionHistory()
    }

    /// 複製歷史文字到剪貼簿
    func copyHistoryText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// 隱藏浮動視窗
    private func hideWindow() {
        // 顯示最終結果一段時間後隱藏
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            WindowManager.shared.hideFloatingWindow()
            self?.appState = .idle
            self?.transcribedText = "等待輸入..."
        }
    }

    /// 切換錄音狀態 (開始/停止) - 保留作為按鈕使用
    func toggleRecording() {
        if isRecording {
            handleHotkeyReleased()
        } else if appState == .idle {
            handleHotkeyPressed()
        }
    }

    /// 測試 LLM 設定是否正確
    /// - Parameters:
    ///   - text: 測試文字
    ///   - completion: 回調，回傳修正後的文字或錯誤
    func testLLM(
        text: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let config = resolveEffectiveLLMConfiguration()

        LLMService.shared.correctText(
            text: text,
            prompt: config.prompt,
            provider: config.provider,
            apiKey: config.apiKey,
            url: config.url,
            model: config.model,
            completion: completion
        )
    }

    static func resolveEffectiveLLMConfiguration(
        prompt: String,
        provider: LLMProvider,
        apiKey: String,
        url: String,
        model: String,
        selectedCustomProvider: CustomLLMProvider?
    ) -> EffectiveLLMConfiguration {
        var resolvedPrompt = prompt.isEmpty ? VoiceInputViewModel.defaultLLMPrompt : prompt
        var resolvedProvider = provider
        var resolvedAPIKey = apiKey
        var resolvedURL = url
        var resolvedModel = model

        if let customProvider = selectedCustomProvider {
            resolvedProvider = .custom
            resolvedAPIKey = customProvider.apiKey
            resolvedURL = customProvider.apiURL
            resolvedModel = customProvider.model
            if !customProvider.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resolvedPrompt = customProvider.prompt
            }
        }

        return EffectiveLLMConfiguration(
            prompt: resolvedPrompt,
            provider: resolvedProvider,
            apiKey: resolvedAPIKey,
            url: resolvedURL,
            model: resolvedModel
        )
    }

    private func resolveEffectiveLLMConfiguration() -> EffectiveLLMConfiguration {
        VoiceInputViewModel.resolveEffectiveLLMConfiguration(
            prompt: llmPrompt,
            provider: currentLLMProvider,
            apiKey: llmAPIKey,
            url: llmURL,
            model: llmModel,
            selectedCustomProvider: selectedCustomProvider
        )
    }

    private func resolveModelURL() -> URL? {
        // 直接使用路徑解析，因為所有模型現在都應該在 App Sandbox 內
        guard !whisperModelPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: whisperModelPath)
        
        // 簡單驗證檔案是否存在
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        } else {
             logger.warning("模型檔案不存在: \(url.path)")
             return nil
        }
    }

    /// 在 Finder 中顯示模型檔案
    func showModelInFinder(_ model: ImportedModel) {
        let modelURL = modelsDirectory.appendingPathComponent(model.fileName)
        NSWorkspace.shared.selectFile(modelURL.path, inFileViewerRootedAtPath: modelsDirectory.path)
    }
}
    struct EffectiveLLMConfiguration {
        let prompt: String
        let provider: LLMProvider
        let apiKey: String
        let url: String
        let model: String
    }
