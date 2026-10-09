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

    /// 為 true 時 stop 立即完成;為 false 時保留回呼,由測試呼叫 completeStop()
    var completesStopImmediately = true
    /// 尚未呼叫的 stop 完成回呼
    private var pendingStopCompletion: (() -> Void)?

    /// 停止服務
    func stop(completion: @escaping () -> Void) {
        stopCallCount += 1
        if completesStopImmediately {
            completion()
        } else {
            pendingStopCompletion = completion
        }
    }

    /// 模擬最終結果完成
    func completeStop() {
        pendingStopCompletion?()
        pendingStopCompletion = nil
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
