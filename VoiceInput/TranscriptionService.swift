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
    /// 停止服務
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
    
    /// 更新語言設定
    func updateLocale(identifier: String) {
        if speechRecognizer?.locale.identifier != identifier {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier))
            logger.info("語音識別語言已更新為: \(identifier)")
        }
    }
    
    /// 初始化並啟動識別請求
    func start() {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { 
            logger.error("無法建立識別請求 (Unable to create request)")
            return 
        }
        // 啟用部分結果回報 (即時顯示)
        recognitionRequest.shouldReportPartialResults = true
    }
    
    /// 停止識別任務
    func stop() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
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
                    self.stop()
                }
            }
        }
    }
}
