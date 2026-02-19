import Foundation
import Speech
import AVFoundation
import os

/// 語音轉文字服務協議
protocol TranscriptionServiceProtocol {
    /// 轉錄結果回調（部分結果與最終結果皆透過此回調回傳）
    var onTranscriptionResult: ((Result<String, Error>) -> Void)? { get set }

    /// 最終結果回調：當 isFinal == true 時觸發，供外部決定何時結束等待
    var onFinalResult: (() -> Void)? { get set }

    /// 啟動服務
    func start()
    /// 停止服務（優雅完成，等待最終識別結果）
    func stop()
    /// 處理音訊緩衝區
    func process(buffer: AVAudioPCMBuffer)
}

/// 使用 Apple SFSpeechRecognizer 的轉錄服務實作
class SFSpeechTranscriptionService: TranscriptionServiceProtocol {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "TranscriptionService")

    /// 轉錄結果回調（部分結果與最終結果）
    var onTranscriptionResult: ((Result<String, Error>) -> Void)?

    /// 最終結果完成回調（isFinal == true 時觸發）
    var onFinalResult: (() -> Void)?

    /// 語音識別器，預設使用繁體中文 (zh-TW)
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
    /// 識別請求，處理音訊緩衝區
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    /// 識別任務，用於追蹤識別進度
    private var recognitionTask: SFSpeechRecognitionTask?
    /// 防止 stop() 被重複呼叫的旗標
    private var isStopping = false

    /// 更新語言設定
    func updateLocale(identifier: String) {
        if speechRecognizer?.locale.identifier != identifier {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier))
            logger.info("語音識別語言已更新為: \(identifier)")
        }
    }

    /// 初始化並啟動識別請求
    func start() {
        // 每次啟動前重置停止旗標，並清空舊的識別任務
        isStopping = false
        recognitionTask?.cancel()
        recognitionTask = nil

        // 建立新的識別請求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            logger.error("無法建立識別請求 (Unable to create request)")
            return
        }
        // 啟用部分結果回報（即時顯示）
        recognitionRequest.shouldReportPartialResults = true
    }

    /// 停止識別任務（優雅完成：使用 finish() 而非 cancel()）
    /// - 重要：finish() 是非同步的，系統會繼續處理剩餘音訊並觸發最終回調
    /// - 不在此處清空 recognitionTask，讓最終回調 (isFinal = true) 正常完成後再清空
    func stop() {
        // 防止重複呼叫（例如 error handler 中也有 stop 的情境）
        guard !isStopping else {
            logger.debug("stop() 已呼叫中，忽略重複呼叫")
            return
        }
        isStopping = true

        // 通知 Apple 音訊已結束，觸發最終識別計算
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        // 使用 finish() 優雅完成：讓 Apple 後端繼續計算剩餘音訊的最終文字
        // ⚠️ 不要用 cancel()，cancel() 會立即丟棄所有計算中的長文字結果
        recognitionTask?.finish()
        // 注意：recognitionTask 不在此清空，等待 isFinal 回調後再清空
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
                    // 使用 segments 組合來獲取完整文本，確保不會掉字
                    // formattedString 有時會因 Apple 內部優化而遺漏部分內容
                    let segments = result.bestTranscription.segments
                    let transcription: String
                    if !segments.isEmpty {
                        transcription = segments.map { $0.substring }.joined()
                        self.logger.debug("使用 segments 組合轉錄文本，片段數: \(segments.count)")
                    } else {
                        // 回退方案：使用 formattedString
                        transcription = result.bestTranscription.formattedString
                        self.logger.debug("segments 為空，回退使用 formattedString")
                    }

                    // 只要有轉錄內容就回報（串流式更新）
                    if !transcription.isEmpty {
                        self.logger.info("轉錄結果 (isFinal=\(result.isFinal)): \(transcription)")
                        self.onTranscriptionResult?(.success(transcription))
                    }

                    if result.isFinal {
                        // 最終結果已到達，清空識別任務並觸發完成回調
                        self.logger.info("收到最終識別結果 (isFinal = true)，識別完成")
                        self.recognitionTask = nil
                        self.onFinalResult?()
                        return
                    }
                }

                // 處理錯誤（錯誤與 result 可能同時存在，Apple API 的設計）
                if let error = error {
                    // 清空識別任務（避免重入）
                    self.recognitionTask = nil

                    // 檢查是否為「無語音」類型的錯誤（正常情境，不算錯誤）
                    let errorMessage = error.localizedDescription.lowercased()
                    let noSpeechErrors = ["no speech detected", "speech unavailable", "nothing was recorded", "unable to find speech"]

                    if noSpeechErrors.contains(where: { errorMessage.contains($0) }) {
                        self.logger.info("未檢測到語音 (No speech detected)")
                        // 視同正常完成，觸發最終回調（讓 UI 可以收尾）
                        self.onFinalResult?()
                    } else {
                        self.logger.error("識別錯誤 (Recognition error): \(error.localizedDescription)")
                        self.onTranscriptionResult?(.failure(error))
                        // 錯誤發生時也觸發最終回調，避免 UI 永遠卡在轉寫狀態
                        self.onFinalResult?()
                    }
                }
            }
        }
    }
}
