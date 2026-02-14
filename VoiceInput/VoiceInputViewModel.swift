import Foundation
import SwiftUI
import Combine

/// 負責管理 VoiceInput 應用程式狀態的 ViewModel
class VoiceInputViewModel: ObservableObject {
    // MARK: - 持久化設定 (AppStorage)
    @AppStorage("selectedLanguage") var selectedLanguage: String = "zh-TW"
    @AppStorage("whisperModelPath") var whisperModelPath: String = ""
    @AppStorage("autoInsertText") var autoInsertText: Bool = true
    @AppStorage("selectedHotkey") var selectedHotkey: String = HotkeyOption.rightCommand.rawValue

    // MARK: - 運行時狀態
    /// 是否正在錄音
    @Published var isRecording = false
    /// 已轉錄的文字內容
    @Published var transcribedText = "等待輸入..."
    /// 權限狀態
    @Published var permissionGranted = false

    /// 音訊引擎
    private var audioEngine = AudioEngine()
    /// 轉錄服務 (目前支援 SFSpeech)
    private var transcriptionService: TranscriptionServiceProtocol = SFSpeechTranscriptionService()
    /// 輸入模擬器 (用於插入文字)
    private var inputSimulator = InputSimulator.shared

    /// 可選語言清單
    let availableLanguages = [
        "zh-TW": "繁體中文 (Taiwan)",
        "zh-CN": "简体中文 (China)",
        "en-US": "English (US)",
        "ja-JP": "日本語 (Japan)"
    ]

    /// 可選快捷鍵清單
    let availableHotkeys = HotkeyOption.allCases

    init() {
        setupAudioEngine()
        setupHotkeys()
    }

    /// 設定音訊引擎與檢查權限
    private func setupAudioEngine() {
        audioEngine.checkPermission()
    }

    /// 設定快捷鍵監聽
    private func setupHotkeys() {
        // 套用儲存的快捷鍵設定
        if let savedHotkey = HotkeyOption(rawValue: selectedHotkey) {
            HotkeyManager.shared.setHotkey(savedHotkey)
        }

        HotkeyManager.shared.onHotkeyPress = { [weak self] in
            DispatchQueue.main.async {
                self?.toggleRecording()
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
    
    /// 切換錄音狀態 (開始/停止)
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    /// 開始錄音流程
    private func startRecording() {
        guard !isRecording else { return }

        // 檢查權限
        guard audioEngine.permissionGranted else {
            print("無法開始錄音：權限未授予，請至系統偏好設定授予麥克風與語音識別權限")
            return
        }

        // 確保 WindowManager 已有 viewModel 設定
        if WindowManager.shared.viewModel == nil {
            WindowManager.shared.viewModel = self
        }

        // 更新轉錄服務語言 (若有變動)
        if let sfService = transcriptionService as? SFSpeechTranscriptionService {
            sfService.updateLocale(identifier: selectedLanguage)
        }

        // 顯示浮動視窗
        WindowManager.shared.showFloatingWindow()
        
        transcribedText = ""
        transcriptionService.start()
        do {
            try audioEngine.startRecording { [weak self] buffer in
                self?.transcriptionService.process(buffer: buffer) { text in
                    DispatchQueue.main.async {
                        if let text = text {
                            self?.transcribedText = text
                        }
                    }
                }
            }
            isRecording = true
        } catch {
            print("無法開始錄音: \(error)")
            WindowManager.shared.hideFloatingWindow()
        }
    }
    
    /// 停止錄音流程並處理文字輸出
    private func stopRecording() {
        guard isRecording else { return }
        
        audioEngine.stopRecording()
        transcriptionService.stop()
        isRecording = false
        
        // 隱藏浮動視窗 (延遲幾秒讓用戶看清楚結果)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            WindowManager.shared.hideFloatingWindow()
        }
        
        // 自動插入文字到當前應用程式
        if autoInsertText && !transcribedText.isEmpty && transcribedText != "等待輸入..." {
            // 稍作延遲以確保焦點切換回原本的 App
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.inputSimulator.insertText(self.transcribedText)
            }
        }
    }
}

