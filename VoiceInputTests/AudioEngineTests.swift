import Foundation
import Testing
import AVFoundation
@testable import VoiceInput

/// AudioEngine 單元測試
/// 重點覆蓋 B1.3 / B1.4 失敗路徑與 J2 H-3 修復回歸保護
@Suite("AudioEngine")
struct AudioEngineTests {

    // MARK: - 失敗路徑測試

    /// 缺少權限時,startRecording 應立即拋出 AudioEngineError.permissionNotGranted
    /// 對應 B1.3 子驗收:「startRecording 失敗路徑測試(無可用裝置)」
    @Test("startRecording 缺少權限時拋出 permissionNotGranted")
    @MainActor
    func startRecording_withoutPermission_throwsPermissionNotGranted() {
        // Arrange
        let mockSession = MockAVCaptureSession()
        let engine = AudioEngine(sessionFactory: { mockSession })
        engine.permissionGranted = false

        // Act & Assert
        #expect(throws: AudioEngineError.permissionNotGranted) {
            try engine.startRecording { _ in }
        }
        // 確認 mock session 完全沒被觸碰
        #expect(mockSession.startRunningCallCount == 0)
        #expect(mockSession.addedInputs.isEmpty)
        #expect(mockSession.addedOutputs.isEmpty)
    }

    /// 設備不可用時,startRecording 應拋出 NSError code 2,
    /// 且 H-3 修復確保 bufferCallback 不會被留下(避免 dangling callback)
    @Test("startRecording 設備不可用時拋 NSError code 2 且 bufferCallback 為 nil")
    @MainActor
    func startRecording_deviceUnavailable_throwsAndCallbackIsNil() {
        // Arrange
        let mockSession = MockAVCaptureSession()
        let engine = AudioEngine(sessionFactory: { mockSession })
        engine.permissionGranted = true
        // 注入 override 讓 getSelectedDevice 回傳 nil,模擬「無可用裝置」
        engine.getSelectedDeviceOverride = { nil }

        // Act
        var capturedError: NSError?
        do {
            try engine.startRecording { _ in }
        } catch let error as NSError {
            capturedError = error
        } catch {
            Issue.record("應拋出 NSError,但拋出 \(type(of: error))")
        }

        // Assert
        #expect(capturedError?.domain == "AudioEngineError")
        #expect(capturedError?.code == 2)
        // H-3 修復驗證:拋錯後 bufferCallback 不應被設置
        // (若回歸,callback 會留下,下次 startRecording 會覆寫,造成 callback 流失)
        #expect(engine.bufferCallback == nil)
        // 確認 session 沒被啟動
        #expect(mockSession.startRunningCallCount == 0)
    }

    // MARK: - stopRecording 測試 (B1.5)

    /// stopRecording 應呼叫 captureSession.stopRunning() 並把屬性清空
    /// 對應 B1.5 驗收:「驗證 session 被停止,callback 清空」
    @Test("stopRecording 呼叫 session stopRunning 並清空狀態")
    @MainActor
    func stopRecording_stopsSessionAndClearsState() {
        // Arrange
        let mockSession = MockAVCaptureSession()
        let engine = AudioEngine(sessionFactory: { mockSession })
        // 手動注入 mock session 模擬「錄音中」狀態
        // (避免在 CI 環境需真實設備才能走到 stopRecording)
        engine.captureSession = mockSession
        engine.bufferCallback = { _ in }
        engine.isRecording = true

        // Act
        engine.stopRecording()

        // Assert: 同步可驗證的部分
        // 1. session 確實被通知停止
        #expect(mockSession.stopRunningCallCount == 1)
        // 2. captureSession 屬性已清空(避免下次 startRecording 誤用舊 session)
        #expect(engine.captureSession == nil)
    }

    // MARK: - 裝置選擇測試 (B1.6)

    /// 系統預設路徑:當 `selectedDeviceID == nil` 時,
    /// `getSelectedDevice()` 應回傳 `AVCaptureDevice.default(for: .audio)`
    @Test("getSelectedDevice 系統預設路徑回傳 AVCaptureDevice.default")
    @MainActor
    func getSelectedDevice_systemDefault_returnsDefaultDevice() {
        // Arrange
        let engine = AudioEngine()
        engine.selectedDeviceID = nil
        engine.getSelectedDeviceOverride = nil

        // Act
        let result = engine.getSelectedDevice()
        let expected = AVCaptureDevice.default(for: .audio)

        // Assert: 兩者 uniqueID 應一致(不論環境是否有真實設備)
        #expect(result?.uniqueID == expected?.uniqueID)
    }

    /// 指定裝置路徑:當 `selectedDeviceID` 指向不存在的裝置時,
    /// `getSelectedDevice()` 應回傳 nil(discovery 找不到)
    @Test("getSelectedDevice 指定不存在裝置時回傳 nil")
    @MainActor
    func getSelectedDevice_nonExistentDeviceID_returnsNil() {
        // Arrange
        let engine = AudioEngine()
        // 使用不可能存在的 uniqueID 觸發「discovery 找不到」路徑
        engine.selectedDeviceID = "non-existent-device-id-for-testing-12345"
        engine.getSelectedDeviceOverride = nil

        // Act
        let result = engine.getSelectedDevice()

        // Assert
        #expect(result == nil)
    }
}
