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
}

/// 應用程式狀態
enum AppState {
    case idle       // 待機中
    case recording  // 錄音中（按住 hotkey）
    case transcribing // 轉寫中
}

/// 已導入的 Whisper 模型
struct ImportedModel: Identifiable, Codable {
    let id: UUID
    var name: String
    var fileName: String

    init(name: String, fileName: String) {
        self.id = UUID()
        self.name = name
        self.fileName = fileName
    }
}

/// 負責管理 VoiceInput 應用程式狀態的 ViewModel
class VoiceInputViewModel: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "VoiceInputViewModel")

    // MARK: - 持久化設定 (AppStorage)
    @AppStorage("selectedLanguage") var selectedLanguage: String = "zh-TW"
    @AppStorage("whisperModelPath") var whisperModelPath: String = ""
    @AppStorage("whisperModelBookmark") var whisperModelBookmark: Data = Data()

    @AppStorage("autoInsertText") var autoInsertText: Bool = true
    @AppStorage("selectedHotkey") var selectedHotkey: String = HotkeyOption.rightCommand.rawValue
    @AppStorage("selectedSpeechEngine") var selectedSpeechEngine: String = SpeechRecognitionEngine.apple.rawValue

    // MARK: - 已導入的模型列表
    @AppStorage("importedModels") private var importedModelsData: Data = Data()
    @Published var importedModels: [ImportedModel] = []

    /// 取得模型儲存目錄
    private var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoiceInput/Models", isDirectory: true)
    }

    // MARK: - Speech Engine 選項
    enum SpeechRecognitionEngine: String, CaseIterable, Identifiable {
        case apple = "Apple 系統語音辨識"
        case whisper = "Whisper (Local)"

        var id: String { self.rawValue }
    }

    // MARK: - LLM 修正設定
    /// 是否啟用 LLM 修正
    @AppStorage("llmEnabled") var llmEnabled: Bool = false
    /// LLM 服務提供者
    @AppStorage("llmProvider") var llmProvider: String = LLMProvider.openAI.rawValue
    /// API URL (Ollama 或自訂 API 使用)
    @AppStorage("llmURL") var llmURL: String = ""
    
    /// API Key (已遷移至 Keychain)
    @Published var llmAPIKey: String = "" {
        didSet {
            KeychainHelper.shared.save(llmAPIKey, service: "com.voiceinput.llm", account: "llmAPIKey")
        }
    }
    
    /// 模型名稱 (如 gpt-4o, claude-3-5-sonnet, llama3 等)
    @AppStorage("llmModel") var llmModel: String = ""
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
    /// 權限狀態
    @Published var permissionGranted = false
    /// 錄音開始時間（用於防抖，避免極短暫的錄音）
    private var recordingStartTime: Date?

    /// 音訊引擎 (使用單例)
    private var audioEngine = AudioEngine.shared
    /// 轉錄服務 (目前支援 SFSpeech)
    private var transcriptionService: TranscriptionServiceProtocol = SFSpeechTranscriptionService()
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

    /// 可用的 LLM Provider 清單
    let availableLLMProviders = LLMProvider.allCases

    /// 取得目前的 LLM Provider
    var currentLLMProvider: LLMProvider {
        LLMProvider(rawValue: llmProvider) ?? .openAI
    }

    /// 取得目前的語音辨識引擎
    var currentSpeechEngine: SpeechRecognitionEngine {
        SpeechRecognitionEngine(rawValue: selectedSpeechEngine) ?? .apple
    }

    /// LLM 修正的預設提示詞
    static let defaultLLMPrompt = "你是一個文字校正助手。請修正以下語音辨識結果中的錯誤（包括錯字、漏字、標點符號等），但不要改變原意。只需回傳修正後的文字，不要有其他說明。"

    init() {
        loadLLMAPIKey()
        loadImportedModels()
        setupAudioEngine()
        setupHotkeys()
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
        // 取得模型名稱（不含副檔名）
        let modelName = sourceURL.deletingPathExtension().lastPathComponent
        let destinationFileName = "\(modelName).bin"
        var destinationURL = modelsDirectory.appendingPathComponent(destinationFileName)

        // 檢查是否已存在
        if importedModels.contains(where: { $0.fileName == destinationFileName }) {
            logger.warning("模型已存在: \(destinationFileName)")
            return
        }

        do {
            // 確保目錄存在
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

            // 複製檔案
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            // 新增到列表
            let newModel = ImportedModel(name: modelName, fileName: destinationFileName)
            importedModels.append(newModel)
            saveImportedModels()

            logger.info("模型導入成功: \(destinationFileName)")
            print("[VoiceInputViewModel] 模型導入成功: \(destinationFileName)，儲存於: \(destinationURL.path)")
        } catch {
            logger.error("模型導入失敗: \(error.localizedDescription)")
            print("[VoiceInputViewModel] 模型導入失敗: \(error)")
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
                whisperModelBookmark = Data()
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
        whisperModelBookmark = Data()
        logger.info("已選擇模型: \(model.fileName)")
    }

    /// 取得目前選擇模型的 URL
    func getSelectedModelURL() -> URL? {
        if !whisperModelPath.isEmpty {
            return URL(fileURLWithPath: whisperModelPath)
        }
        return nil
    }

    /// 從 Keychain 載入 API Key
    private func loadLLMAPIKey() {
        if let savedKey = KeychainHelper.shared.read(service: "com.voiceinput.llm", account: "llmAPIKey") {
            self.llmAPIKey = savedKey
        } else {
            // 遷移邏輯：嘗試從 UserDefaults 讀取舊的明文 Key
            let legacyKey = UserDefaults.standard.string(forKey: "llmAPIKey") ?? ""
            if !legacyKey.isEmpty {
                self.llmAPIKey = legacyKey
                // 遷移成功後，建議手動同步一次 Keychain 並刪除舊資料
                KeychainHelper.shared.save(legacyKey, service: "com.voiceinput.llm", account: "llmAPIKey")
                UserDefaults.standard.removeObject(forKey: "llmAPIKey")
            }
        }
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

        // 只有在有有效文字且啟用 LLM 修正時才送到 LLM
        if llmEnabled && hasValidText {
            // 進行 LLM 修正
            performLLMCorrection { [weak self] in
                self?.proceedToInsertAndHide()
            }
        } else {
            // 無有效文字，直接隱藏視窗
            hideWindow()
        }
    }

    /// 執行 LLM 文字修正
    private func performLLMCorrection(completion: @escaping () -> Void) {
        // 取得提示詞，若未自訂則使用預設值
        let prompt = llmPrompt.isEmpty ? VoiceInputViewModel.defaultLLMPrompt : llmPrompt

        LLMService.shared.correctText(
            text: transcribedText,
            prompt: prompt,
            provider: currentLLMProvider,
            apiKey: llmAPIKey,
            url: llmURL,
            model: llmModel
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let correctedText):
                    self?.transcribedText = correctedText
                case .failure(let error):
                    // 若修正失敗，保留原文繼續執行
                    self?.logger.error("LLM 修正失敗: \(error.localizedDescription)")
                }
                completion()
            }
        }
    }

    /// 執行插入文字並隱藏視窗
    private func proceedToInsertAndHide() {
        // 自動插入文字到當前應用程式
        if autoInsertText && !transcribedText.isEmpty && transcribedText != "等待輸入..." {
            // 檢查輔助功能權限
            permissionManager.requestPermissionIfNeeded(.accessibility) { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    self.insertText()
                }
                self.hideWindow()
            }
        } else {
            hideWindow()
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

    // MARK: - Security Scoped Bookmark Handling
    
    private func saveBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            whisperModelBookmark = bookmarkData
        } catch {
            logger.error("無法建立書籤: \(error.localizedDescription)")
        }
    }
    
    private func resolveModelURL() -> URL? {
        // 如果沒有書籤資料，嘗試使用路徑 (僅限非 Sandbox 環境或暫時相容)
        if whisperModelBookmark.isEmpty {
            guard !whisperModelPath.isEmpty else { return nil }
            return URL(fileURLWithPath: whisperModelPath)
        }
        
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: whisperModelBookmark, 
                             options: .withSecurityScope, 
                             relativeTo: nil, 
                             bookmarkDataIsStale: &isStale)
            
            if isStale {
                logger.warning("書籤已過期，嘗試重新建立")
                saveBookmark(for: url)
            }
            return url
        } catch {
            logger.error("無法解析書籤: \(error.localizedDescription)")
            return nil
        }
    }

    /// 選擇 Whisper 模型檔案 (.bin)
    func selectModelFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "bin")].compactMap { $0 }
        
        panel.begin { result in
            if result == .OK, let url = panel.url {
                DispatchQueue.main.async {
                    self.whisperModelPath = url.path
                    self.saveBookmark(for: url)
                    self.logger.info("已選擇 Whisper 模型: \(url.path)")
                }
            }
        }
    }
}
