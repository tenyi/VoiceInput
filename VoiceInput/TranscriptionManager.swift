import Foundation
import AVFoundation
import Combine
import os

/// 負責管理語音轉文字服務的管理器
/// 管理 SFSpeech 和 Whisper 兩種轉錄服務的切換與執行
class TranscriptionManager: ObservableObject {
    /// 日誌記錄器
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "TranscriptionManager")

    /// 轉錄服務實例
    @Published private(set) var transcriptionService: TranscriptionServiceProtocol = SFSpeechTranscriptionService()

    /// 目前配置
    private var currentConfig: TranscriptionConfig?

    /// 文字處理器
    var textProcessor: ((String) -> String)?

    /// 是否正在轉錄中
    @Published private(set) var isTranscribing = false

    /// 轉錄結果文字
    @Published var transcribedText = ""

    /// 當前使用的語音識別引擎
    @Published var selectedEngine: SpeechRecognitionEngine = .apple

    /// 轉錄結果回調
    var onTranscriptionComplete: ((String) -> Void)?

    /// 選擇的 Whisper 模型 URL (用於 Whisper 引擎)
    private var whisperModelURL: URL?

    init() {
        // 設置默認的轉錄結果回調
        setupTranscriptionCallback()
    }

    // MARK: - 轉錄服務配置

    /// 配置轉錄服務
    /// - Parameters:
    ///   - engine: 語音識別引擎
    ///   - modelURL: Whisper 模型 URL (僅 Whisper 引擎需要)
    ///   - language: 轉寫語言
    func configure(engine: SpeechRecognitionEngine, modelURL: URL? = nil, language: String = "zh-TW") {
        self.selectedEngine = engine
        self.whisperModelURL = modelURL

        let targetConfig = TranscriptionConfig(
            engine: engine,
            modelPath: modelURL?.path ?? "",
            language: language
        )

        switch engine {
        case .apple:
            // 使用 Apple 系統內建語音辨識服務
            if !(transcriptionService is SFSpeechTranscriptionService) {
                transcriptionService = SFSpeechTranscriptionService()
                setupTranscriptionCallback()
            }
            if let sfService = transcriptionService as? SFSpeechTranscriptionService {
                sfService.updateLocale(identifier: language)
            }
            currentConfig = targetConfig
            logger.info("已切換到 Apple 語音辨識服務")

        case .whisper:
            // 使用 Whisper 模型進行轉錄
            guard let modelURL = modelURL else {
                logger.warning("Whisper 模型 URL 為空，降級到 Apple 語音辨識服務")
                configure(engine: .apple, language: language)
                return
            }

            let isTypeMismatch = !(transcriptionService is WhisperTranscriptionService)

            if currentConfig != targetConfig || isTypeMismatch {
                logger.info("Whisper 配置變更或服務型別不符，重建服務，模型路徑: \(modelURL.path)")
                transcriptionService = WhisperTranscriptionService(
                    modelURL: modelURL,
                    language: language
                )
                setupTranscriptionCallback()
                currentConfig = targetConfig
                logger.info("已切換到 Whisper 轉錄服務，模型: \(modelURL.lastPathComponent)")
            } else {
                logger.info("Whisper 配置未變更，重用現有服務")
            }
        }
    }

    /// 設置轉錄結果回調
    private func setupTranscriptionCallback() {
        transcriptionService.onTranscriptionResult = { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    guard !text.isEmpty else { return }

                    var processedText = text
                    if let processor = self?.textProcessor {
                        processedText = processor(processedText)
                    }
                    self?.transcribedText = processedText
                    self?.logger.info("轉錄成功: \(processedText.prefix(50))...")
                case .failure(let error):
                    self?.transcribedText = "識別錯誤：\(error.localizedDescription)"
                    self?.logger.error("轉錄失敗: \(error.localizedDescription)")
                }

                // 通知轉錄完成
                if let text = self?.transcribedText {
                    self?.onTranscriptionComplete?(text)
                }
            }
        }
    }

    // MARK: - 轉錄控制

    /// 開始轉錄
    func startTranscription() {
        isTranscribing = true
        transcribedText = ""
        transcriptionService.start()
        logger.info("開始轉錄")
    }

    /// 停止轉錄
    func stopTranscription() {
        transcriptionService.stop()
        isTranscribing = false
        logger.info("停止轉錄")
    }

    /// 處理音訊緩衝區
    /// - Parameter buffer: 音訊緩衝區
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        transcriptionService.process(buffer: buffer)
    }
}
