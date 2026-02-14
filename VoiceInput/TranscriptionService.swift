import Foundation
import Speech
import AVFoundation

/// 語音轉文字服務協議
protocol TranscriptionServiceProtocol {
    /// 啟動服務
    func start()
    /// 停止服務
    func stop()
    /// 處理音訊緩衝區並回傳轉錄文字
    func process(buffer: AVAudioPCMBuffer, completion: @escaping (String?) -> Void)
}

/// 使用 Apple SFSpeechRecognizer 的轉錄服務實作
class SFSpeechTranscriptionService: TranscriptionServiceProtocol {
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
            print("語音識別語言已更新為: \(identifier)")
        }
    }
    
    /// 初始化並啟動識別請求
    func start() {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { 
            print("無法建立識別請求 (Unable to create request)")
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
    func process(buffer: AVAudioPCMBuffer, completion: @escaping (String?) -> Void) {
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.append(buffer)
        
        if recognitionTask == nil {
            guard let recognizer = speechRecognizer, recognizer.isAvailable else {
                print("語音識別器無法使用 (Speech recognizer not available)")
                return
            }
            
            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let result = result {
                    // 回傳最佳轉錄結果
                    completion(result.bestTranscription.formattedString)
                }
                if let error = error {
                    print("識別錯誤 (Recognition error): \(error)")
                    self.stop()
                }
            }
        }
    }
}
