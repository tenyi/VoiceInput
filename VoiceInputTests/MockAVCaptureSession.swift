import AVFoundation
@testable import VoiceInput

/// 測試用的 AVCaptureSession mock
/// 可在測試中驗證 startRunning / stopRunning / addInput / addOutput 是否被呼叫
final class MockAVCaptureSession: CaptureSessionProtocol {
    // MARK: - 測試觀察屬性

    /// startRunning 被呼叫次數
    private(set) var startRunningCallCount = 0
    /// stopRunning 被呼叫次數
    private(set) var stopRunningCallCount = 0
    /// beginConfiguration 被呼叫次數
    private(set) var beginConfigurationCallCount = 0
    /// commitConfiguration 被呼叫次數
    private(set) var commitConfigurationCallCount = 0
    /// 所有 addInput 收到的 input(順序保留)
    private(set) var addedInputs: [AVCaptureInput] = []
    /// 所有 addOutput 收到的 output(順序保留)
    private(set) var addedOutputs: [AVCaptureOutput] = []

    // MARK: - 可注入行為

    /// 模擬 `isRunning` 狀態
    var isRunning: Bool = false
    /// 設定 canAddInput 預設回傳值
    var canAddInputResult: Bool = true
    /// 設定 canAddOutput 預設回傳值
    var canAddOutputResult: Bool = true

    // MARK: - CaptureSessionProtocol

    func startRunning() {
        startRunningCallCount += 1
        isRunning = true
    }

    func stopRunning() {
        stopRunningCallCount += 1
        isRunning = false
    }

    func canAddInput(_ input: AVCaptureInput) -> Bool {
        canAddInputResult
    }

    func addInput(_ input: AVCaptureInput) {
        addedInputs.append(input)
    }

    func canAddOutput(_ output: AVCaptureOutput) -> Bool {
        canAddOutputResult
    }

    func addOutput(_ output: AVCaptureOutput) {
        addedOutputs.append(output)
    }

    func beginConfiguration() {
        beginConfigurationCallCount += 1
    }

    func commitConfiguration() {
        commitConfigurationCallCount += 1
    }
}
