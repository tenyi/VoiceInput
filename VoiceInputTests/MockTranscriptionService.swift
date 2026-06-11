import Foundation
import AVFoundation
@testable import VoiceInput

/// 用於測試的 Mock 語音轉譯服務，實作 TranscriptionServiceProtocol
class MockTranscriptionService: TranscriptionServiceProtocol {
    /// 轉譯結果回調，由外部（TranscriptionManager）訂閱
    var onTranscriptionResult: ((Result<String, Error>) -> Void)?

    /// 記錄 start() 被呼叫的次數
    var startCallCount = 0
    /// 記錄 stop() 被呼叫的次數
    var stopCallCount = 0
    /// 記錄 process(buffer:) 被呼叫的次數
    var processCallCount = 0
    /// 記錄所有接收到的音訊緩衝區
    var processedBuffers: [AVAudioPCMBuffer] = []

    /// 啟動服務
    func start() {
        startCallCount += 1
    }

    /// 停止服務
    func stop() {
        stopCallCount += 1
    }

    /// 處理音訊緩衝區
    /// - Parameter buffer: 音訊緩衝區
    func process(buffer: AVAudioPCMBuffer) {
        processCallCount += 1
        processedBuffers.append(buffer)
    }

    /// 模擬轉譯結果輸出
    /// - Parameter result: 轉譯成功或失敗的結果
    func simulateResult(_ result: Result<String, Error>) {
        onTranscriptionResult?(result)
    }
}
