import Foundation
import Speech
import AVFoundation
import os

/// 語音轉文字服務協議
protocol TranscriptionServiceProtocol {
    /// 轉錄結果回調
    var onTranscriptionResult: ((Result<String, Error>) -> Void)? { get set }

    /// 啟動服務
    func start()
    /// 停止服務（優雅停止：等待最終結果）
    func stop()
    /// 處理音訊緩衝區
    func process(buffer: AVAudioPCMBuffer)
}

/// 使用 Apple SFSpeechRecognizer 的轉錄服務實作
class SFSpeechTranscriptionService: TranscriptionServiceProtocol {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "TranscriptionService")

    /// 轉錄結果回調
    var onTranscriptionResult: ((Result<String, Error>) -> Void)?

    /// 語音識別器，預設使用繁體中文 (zh-TW)
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
    /// 識別請求，處理音訊緩衝區
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    /// 識別任務，用於追蹤識別進度
    private var recognitionTask: SFSpeechRecognitionTask?
    /// 最終結果等待 timeout 計時器（T1-2：避免永久卡住）
    private var finalizeTimeoutTimer: Timer?
    /// 是否已進入「等待最終結果」狀態（防止重複清理）
    private var isWaitingForFinal = false

    /// 更新語言設定
    func updateLocale(identifier: String) {
        if speechRecognizer?.locale.identifier != identifier {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier))
            logger.info("語音識別語言已更新為: \(identifier)")
        }
    }

    /// 初始化並啟動識別請求
    func start() {
        // 確保舊狀態已清理（避免重複啟動）
        cleanupRecognition()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            logger.error("無法建立識別請求 (Unable to create request)")
            return
        }
        // 啟用部分結果回報 (即時顯示)
        recognitionRequest.shouldReportPartialResults = true
        isWaitingForFinal = false
    }

    /// 優雅停止識別任務：
    /// 1. 先呼叫 endAudio() 告知不再有新音訊
    /// 2. 等待 isFinal callback（最多 1.5 秒）
    /// 3. 超時後才強制 cancel()（T1-2）
    func stop() {
        logger.info("SFSpeechTranscriptionService: 開始優雅停止流程")
        // 通知 SFSpeech 不再有新音訊，觸發最終辨識
        recognitionRequest?.endAudio()
        isWaitingForFinal = true

        // T1-2：設定 timeout，超時才強制 cancel 並清理
        finalizeTimeoutTimer?.invalidate()
        finalizeTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self = self, self.isWaitingForFinal else { return }
            self.logger.warning("SFSpeechTranscriptionService: 等待最終結果逾時，強制 cancel")
            self.cleanupRecognition()
        }
    }

    /// 處理接收到的音訊緩衝區
    func process(buffer: AVAudioPCMBuffer) {
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.append(buffer)

        if recognitionTask == nil {
            guard let recognizer = speechRecognizer, recognizer.isAvailable else {
                let error = NSError(domain: "SFSpeechTranscriptionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "語音識別器無法使用"])
                logger.error("語音識別器無法使用 (Speech recognizer not available)")
                onTranscriptionResult?(.failure(error))
                return
            }

            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }

                // 優先處理識別結果
                if let result = result {
                    let transcription = result.bestTranscription.formattedString

                    // 只要有轉錄內容就回報 (串流式更新)
                    // SFSpeechRecognizer 會持續回調部分結果
                    if !transcription.isEmpty {
                        self.logger.info("轉錄結果: \(transcription)")
                        self.onTranscriptionResult?(.success(transcription))
                    }

                    if result.isFinal {
                        // 收到最終結果，取消 timeout 並清理資源
                        self.logger.info("SFSpeechTranscriptionService: 收到 isFinal，清理資源")
                        self.cleanupRecognition()
                        return
                    }
                }

                // 處理錯誤
                if let error = error {
                    // 檢查是否為「無語音」類型的錯誤
                    let errorMessage = error.localizedDescription.lowercased()
                    let noSpeechErrors = ["no speech detected", "speech unavailable", "nothing was recorded", "unable to find speech"]

                    if noSpeechErrors.contains(where: { errorMessage.contains($0) }) {
                        self.logger.info("未檢測到語音 (No speech detected)")
                        // 視情況決定是否回報空字串，或忽略
                    } else {
                        self.logger.error("識別錯誤 (Recognition error): \(error.localizedDescription)")
                        self.onTranscriptionResult?(.failure(error))
                    }
                    self.cleanupRecognition()
                }
            }
        }
    }

    /// 統一清理路徑：取消 timeout、cancel task、釋放 request
    private func cleanupRecognition() {
        finalizeTimeoutTimer?.invalidate()
        finalizeTimeoutTimer = nil
        isWaitingForFinal = false
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        logger.info("SFSpeechTranscriptionService: 資源已清理")
    }
}
