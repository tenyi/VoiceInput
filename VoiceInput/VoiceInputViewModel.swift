import Foundation
import SwiftUI
import Combine

/// 應用程式狀態
enum AppState {
    case idle       // 待機中
    case recording  // 錄音中（按住 hotkey）
    case transcribing // 轉寫中
}

/// 負責管理 VoiceInput 應用程式狀態的 ViewModel
class VoiceInputViewModel: ObservableObject {
    // MARK: - 持久化設定 (AppStorage)
    @AppStorage("selectedLanguage") var selectedLanguage: String = "zh-TW"
    @AppStorage("whisperModelPath") var whisperModelPath: String = ""
    @AppStorage("autoInsertText") var autoInsertText: Bool = true
    @AppStorage("selectedHotkey") var selectedHotkey: String = HotkeyOption.rightCommand.rawValue

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

    init() {
        setupAudioEngine()
        setupHotkeys()
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

        stopRecordingAndTranscribe()
    }

    /// 開始錄音
    private func startRecording() {
        // 確保 WindowManager 已有 viewModel 設定
        if WindowManager.shared.viewModel == nil {
            WindowManager.shared.viewModel = self
        }

        // 更新轉錄服務語言
        if let sfService = transcriptionService as? SFSpeechTranscriptionService {
            sfService.updateLocale(identifier: selectedLanguage)
        }

        // 顯示浮動視窗（錄音模式）
        WindowManager.shared.showFloatingWindow(isRecording: true)

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
            appState = .recording
        } catch {
            // 錄音啟動失敗
            WindowManager.shared.hideFloatingWindow()
            appState = .idle
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
}
