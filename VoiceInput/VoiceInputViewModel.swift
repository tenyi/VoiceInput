import Foundation
import SwiftUI
import Combine
import AppKit
import os
import UniformTypeIdentifiers

// Removed LLMProvider enum and CustomLLMProvider struct as they are now in LLMSettingsViewModel.swift

/// 應用程式狀態
enum AppState {
    case idle       // 待機中
    case recording  // 錄音中（按住 hotkey）
    case transcribing // 轉寫中
    case enhancing  // LLM 增強中
}

/// 應用程式狀態訊息常數
enum AppStatusMessage {
    static let waitingForInput = "等待輸入..."
    static let missingWhisperModel = "請先在設定中選擇有效的 Whisper 模型檔案 (.bin)"
    static let recordingFailedPrefix = "錄音啟動失敗："
}

/// 負責管理 VoiceInput 應用程式狀態的 ViewModel
@MainActor
class VoiceInputViewModel: ObservableObject {
    nonisolated private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "VoiceInputViewModel")

    // MARK: - 持久化設定 (Refactored from AppStorage for DI support)
    @Published var selectedLanguage: String {
        didSet { userDefaults.set(selectedLanguage, forKey: "selectedLanguage") }
    }
    @Published var autoInsertText: Bool {
        didSet { userDefaults.set(autoInsertText, forKey: "autoInsertText") }
    }
    @Published var selectedHotkey: String {
        didSet { userDefaults.set(selectedHotkey, forKey: "selectedHotkey") }
    }
    /// T4-1：錄音觸發模式（按住說話 / 單鍵切換）
    @Published var recordingTriggerMode: String {
        didSet { userDefaults.set(recordingTriggerMode, forKey: "recordingTriggerMode") }
    }
    @Published var selectedSpeechEngine: String {
        didSet { userDefaults.set(selectedSpeechEngine, forKey: "selectedSpeechEngine") }
    }
    @Published private var selectedInputDeviceStorage: String {
        didSet { userDefaults.set(selectedInputDeviceStorage, forKey: "selectedInputDeviceID") }
    }
    
    private let userDefaults: UserDefaults

    // MARK: - Speech Engine 選項

    // MARK: - 運行時狀態
    /// 當前應用程式狀態
    @Published var appState: AppState = .idle

    /// 是否正在錄音
    var isRecording: Bool { appState == .recording }
    /// 是否正在轉寫
    var isTranscribing: Bool { appState == .transcribing }

    /// 已轉錄的文字內容
    @Published var transcribedText = AppStatusMessage.waitingForInput
    
    /// LLM 修正錯誤訊息（用於在懸浮視窗顯示）
    @Published var lastLLMError: String?
    /// 權限狀態
    @Published var permissionGranted = false
    /// 錄音開始時間（用於防抖，避免極短暫的錄音）
    private var recordingStartTime: Date?

    /// 音訊引擎 (依賴注入)
    private var audioEngine: AudioEngineProtocol

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
        Task { @MainActor [weak self] in
            self?.reconcileSelectedInputDevice()
        }
    }
    /// T4-2：快捷鍵互動策略層，負責將按鍵事件轉換為開始/停止語意
    private var hotkeyController: HotkeyInteractionController = HotkeyInteractionController()
    
    /// 快捷鍵管理器 (依賴注入)
    private var hotkeyManager: HotkeyManagerProtocol

    /// 轉錄管理器 - 負責轉錄狀態管理
    // 注意：不使用 @ObservedObject，因為該 wrapper 只在 SwiftUI View 中有效。
    // 子物件的 objectWillChange 透過 Combine 在 setupTranscriptionManager() 中手動橋接。
    var transcriptionManager = TranscriptionManager()
    
    /// Combine 訂閱
    /// Combine 訂閱
    private var cancellables = Set<AnyCancellable>()
    /// 輸入模擬器 (依賴注入)
    private var inputSimulator: InputSimulatorProtocol

    /// 權限管理員
    // 注意：不使用 @ObservedObject，因為該 wrapper 只在 SwiftUI View 中有效。
    // 子物件的 objectWillChange 透過 Combine 在 setupTranscriptionManager() 中手動橋接。
    var permissionManager = PermissionManager.shared

    /// 可選語言清單
    let availableLanguages = [
        "zh-TW": "繁體中文 (Taiwan)",
        "zh-CN": "簡體中文 (China)",
        "en-US": "English (US)",
        "ja-JP": "日本語 (Japan)"
    ]

    /// 取得目前的語音辨識引擎
    var currentSpeechEngine: SpeechRecognitionEngine {
        SpeechRecognitionEngine(rawValue: selectedSpeechEngine) ?? .apple
    }

    init(
        hotkeyManager: HotkeyManagerProtocol,
        audioEngine: AudioEngineProtocol,
        inputSimulator: InputSimulatorProtocol,
        userDefaults: UserDefaults = .standard
    ) {
        self.hotkeyManager = hotkeyManager
        self.audioEngine = audioEngine
        self.inputSimulator = inputSimulator
        self.userDefaults = userDefaults
        
        // Initialize properties from UserDefaults
        self.selectedLanguage = userDefaults.string(forKey: "selectedLanguage") ?? "zh-TW"
        self.autoInsertText = userDefaults.object(forKey: "autoInsertText") != nil ? userDefaults.bool(forKey: "autoInsertText") : true
        self.selectedHotkey = userDefaults.string(forKey: "selectedHotkey") ?? HotkeyOption.rightCommand.rawValue
        self.recordingTriggerMode = userDefaults.string(forKey: "recordingTriggerMode") ?? RecordingTriggerMode.pressAndHold.rawValue
        self.selectedSpeechEngine = userDefaults.string(forKey: "selectedSpeechEngine") ?? SpeechRecognitionEngine.apple.rawValue
        self.selectedInputDeviceStorage = userDefaults.string(forKey: "selectedInputDeviceID") ?? ""
        
        // Initialize runtime properties
        self.selectedInputDeviceID = selectedInputDeviceStorage.isEmpty ? nil : selectedInputDeviceStorage
        self.audioEngine.selectedDeviceID = self.selectedInputDeviceID

        setupAudioEngine()
        setupHotkeys()
        refreshAudioDevices()
        setupTranscriptionManager()
    }

    convenience init() {
        self.init(
            hotkeyManager: HotkeyManager.shared,
            audioEngine: AudioEngine.shared,
            inputSimulator: InputSimulator.shared
        )
    }
    
    private func setupTranscriptionManager() {
        // 設定文字處理器：簡轉繁與字典替換
        transcriptionManager.textProcessor = { [weak self] text in
            var processedText = text
            if self?.selectedLanguage == "zh-TW" {
                processedText = text.toTraditionalChinese()
            }
            return DictionaryManager.shared.replaceText(processedText)
        }
        
        // 將 transcriptionManager 的 text 同步到 ViewModel 供 UI 綁定
        transcriptionManager.$transcribedText
            .receive(on: RunLoop.main)
            .sink { [weak self] newText in
                self?.transcribedText = newText
            }
            .store(in: &cancellables)
        
        // 橋接子 ObservableObject 的 objectWillChange 到父 ViewModel，
        // 確保 SwiftUI 觀察到子物件狀態變更時能正確觸發 View 更新。
        // （@ObservedObject 只在 SwiftUI View 中有效，class 內需手動橋接）
        transcriptionManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        permissionManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
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

    /// 設定快捷鍵監聽（T4-3：摿 HotkeyManager 事件接入 HotkeyInteractionController）
    private func setupHotkeys() {
        // 套用儲存的快捷鍵設定
        if let savedHotkey = HotkeyOption(rawValue: selectedHotkey) {
            hotkeyManager.setHotkey(savedHotkey)
        }

        // 套用儲存的觸發模式設定
        let savedMode = RecordingTriggerMode(rawValue: recordingTriggerMode) ?? .pressAndHold
        hotkeyController.mode = savedMode

        // Controller 輸出回調接入 ViewModel 的主流程
        hotkeyController.onStartRecording = { [weak self] in
            self?.handleStartRecordingRequest()
        }
        hotkeyController.onStopAndTranscribe = { [weak self] in
            self?.handleStopRecordingRequest()
        }

        // HotkeyManager 原始按鍵事件 → 轉發給 Controller
        hotkeyManager.onHotkeyPressed = { [weak self] in
            Task { @MainActor [weak self] in
                self?.hotkeyController.hotkeyPressed()
            }
        }
        hotkeyManager.onHotkeyReleased = { [weak self] in
            Task { @MainActor [weak self] in
                self?.hotkeyController.hotkeyReleased()
            }
        }

        hotkeyManager.startMonitoring()
    }

    /// 更新快捷鍵設定
    /// - Parameter option: 新的快捷鍵選項
    func updateHotkey(_ option: HotkeyOption) {
        selectedHotkey = option.rawValue
        hotkeyManager.setHotkey(option)
    }

    /// T4-3：更新觸發模式（即時生效，不需重啟 App）
    func updateRecordingTriggerMode(_ mode: RecordingTriggerMode) {
        recordingTriggerMode = mode.rawValue
        hotkeyController.mode = mode
        logger.info("觸發模式已切換為: \(mode.rawValue)")
    }

    // MARK: - 快捷鍵處理

    /// Controller 回調：處理開始錄音請求
    private func handleStartRecordingRequest() {
        logger.info("[HotkeyFlow] 收到 start 請求，mode=\(self.recordingTriggerMode), appState=\(String(describing: self.appState))")
        // 如果不在閒置狀態，忽略
        guard appState == .idle else {
            logger.info("[HotkeyFlow] 忽略 start：非 idle，appState=\(String(describing: self.appState))")
            return
        }

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

    /// Controller 回調：處理停止錄音請求
    private func handleStopRecordingRequest() {
        logger.info("[HotkeyFlow] 收到 stop 請求，mode=\(self.recordingTriggerMode), appState=\(String(describing: self.appState))")
        // 只有在錄音狀態才處理
        guard appState == .recording else {
            logger.info("[HotkeyFlow] 忽略 stop：非 recording，appState=\(String(describing: self.appState))")
            return
        }

        // 防抖：錄音時間少於 300ms 則忽略放開事件
        if let startTime = recordingStartTime,
           Date().timeIntervalSince(startTime) < 0.3 {
            logger.warning("錄音時間過短（< 300ms），忽略停止請求")
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

        // 配置 TranscriptionManager
        switch currentSpeechEngine {
        case .apple:
            transcriptionManager.configure(engine: .apple, modelURL: nil, language: selectedLanguage)
        case .whisper:
            // 檢查模型路徑是否存在
            guard let modelURL = AppDelegate.sharedModelManager.getSelectedModelURL() else {
                 transcribedText = AppStatusMessage.missingWhisperModel
                 WindowManager.shared.showFloatingWindow(isRecording: true)
                 appState = .recording // 暫時進入狀態以顯示錯誤
                 
                 DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                     guard let self else { return }
                     WindowManager.shared.hideFloatingWindow()
                     self.appState = .idle
                     self.transcribedText = AppStatusMessage.waitingForInput
                 }
                 return
            }
            transcriptionManager.configure(engine: .whisper, modelURL: modelURL, language: selectedLanguage)
        }

        // 顯示浮動視窗（錄音模式）
        WindowManager.shared.showFloatingWindow(isRecording: true)

        transcribedText = ""
        transcriptionManager.startTranscription()

        // 記錄錄音開始時間（用於防抖）
        recordingStartTime = Date()

        // 錄音啟動成功，通知 Controller
        appState = .recording
        hotkeyController.isRecording = true

        do {
            try audioEngine.startRecording { [weak self] buffer in
                self?.transcriptionManager.processAudioBuffer(buffer)
            }
        } catch {
            // 錄音啟動失敗，恢復狀態
            appState = .idle
            transcribedText = "\(AppStatusMessage.recordingFailedPrefix)\(error.localizedDescription)"
            // 延遲 2 秒後再隱藏視窗，讓使用者能看清錯誤
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self else { return }
                WindowManager.shared.hideFloatingWindow()
                self.transcribedText = AppStatusMessage.waitingForInput
            }
        }
    }

    /// 停止錄音並開始轉寫
    private func stopRecordingAndTranscribe() {
        // 停止錄音
        logger.info("[HotkeyFlow] stopRecordingAndTranscribe：開始停止錄音與轉寫")
        audioEngine.stopRecording()
        transcriptionManager.stopTranscription()
        // 通知 Controller 錄音已結束
        hotkeyController.isRecording = false

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
            if AppDelegate.sharedLLMSettingsViewModel.llmEnabled {
                // 啟用 LLM 修正：設置為增強中狀態
                appState = .enhancing

                performLLMCorrection { [weak self] in
                    self?.appState = .transcribing
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
        // 透過 AppDelegate 的靜態 sharedLLMSettingsViewModel 取得設定，
        // 避免在 ViewModel 中直接依賴 EnvironmentObject
        let config = AppDelegate.sharedLLMSettingsViewModel.resolveEffectiveConfiguration()

        Task {
            do {
                let correctedText = try await LLMService.shared.correctText(
                    text: transcribedText,
                    prompt: config.prompt,
                    provider: config.provider,
                    apiKey: config.apiKey,
                    url: config.url,
                    model: config.model
                )
                
                await MainActor.run { [weak self] in
                    // 若選擇繁體中文，將簡體中文轉換為繁體中文
                    var processedText = correctedText
                    if self?.selectedLanguage == "zh-TW" {
                        processedText = correctedText.toTraditionalChinese()
                    }
                    
                    // 應用字典置換
                    processedText = DictionaryManager.shared.replaceText(processedText)
                    self?.transcribedText = processedText
                    
                    completion()
                }
            } catch {
                await MainActor.run { [weak self] in
                    // 若修正失敗，保留原文繼續執行，並記錄錯誤訊息
                    self?.lastLLMError = error.localizedDescription
                    self?.logger.error("LLM 修正失敗: \\(error.localizedDescription)")
                    
                    completion()
                }
            }
        }
    }

    /// 執行插入文字並隱藏視窗
    private func proceedToInsertAndHide() {
        Task { @MainActor in
            AppDelegate.sharedHistoryManager.addHistoryIfNeeded(transcribedText)
        }

        // 自動插入文字到當前應用程式
        if autoInsertText && !transcribedText.isEmpty && transcribedText != "等待輸入..." {
            // 檢查輔助功能權限
            // 注意：PermissionManager completion 不保證在主執行緒回呼，
            // 因此用 Task @MainActor 確保後續存取 @MainActor 屬性的安全性。
            permissionManager.requestPermissionIfNeeded(.accessibility) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
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

    /// 隱藏浮動視窗
    private func hideWindow() {
        // 顯示最終結果一段時間後隱藏
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            WindowManager.shared.hideFloatingWindow()
            self?.appState = .idle
            self?.transcribedText = AppStatusMessage.waitingForInput
        }
    }

    /// 切換錄音狀態 (開始/停止) - 保留作為按鈕使用
    func toggleRecording() {
        if isRecording {
            handleStopRecordingRequest()
        } else if appState == .idle {
            handleStartRecordingRequest()
        }
    }
}

// MARK: - 簡轉繁擴展
/// 使用 ICU 將簡體中文轉換為繁體中文
extension String {
    /// 將簡體中文轉換為繁體中文
    /// 使用 Core Foundation 的 CFStringTransform 實現
    func toTraditionalChinese() -> String {
        let input = NSMutableString(string: self)
        var range = CFRangeMake(0, input.length)
        // 使用 ICU Transform: Simplified Chinese to Traditional Chinese
        // "Hant" 是將簡體中文轉換為繁體中文的轉換名稱
        let transformName = "Hant" as CFString
        CFStringTransform(input, &range, transformName, false)
        return input as String
    }
}
