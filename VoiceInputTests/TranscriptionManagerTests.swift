import Foundation
import Testing
import AVFoundation
@testable import VoiceInput

/// B5: TranscriptionManager 單元測試套件
@Suite("TranscriptionManagerTests")
struct TranscriptionManagerTests {

    /// B5.2: 測試語音引擎配置與切換，包含降級邏輯
    @Test("測試語音引擎配置與切換邏輯")
    @MainActor
    func testConfigureEngine() async {
        let manager = TranscriptionManager()
        let appleMock = MockTranscriptionService()
        let whisperMock = MockTranscriptionService()

        // 注入工廠，根據引擎回傳對應的 Mock 服務
        manager.serviceFactory = { engine, url, lang in
            switch engine {
            case .apple: return appleMock
            case .whisper: return whisperMock
            }
        }

        // 1. 配置為 Apple 引擎
        manager.configure(engine: .apple, language: "zh-TW")
        #expect(manager.selectedEngine == .apple)
        #expect(manager.transcriptionService as? MockTranscriptionService === appleMock)

        // 2. 配置為 Whisper 引擎（提供有效的模型 URL）
        let dummyModelURL = URL(fileURLWithPath: "/path/to/model.bin")
        manager.configure(engine: .whisper, modelURL: dummyModelURL, language: "zh-TW")
        #expect(manager.selectedEngine == .whisper)
        #expect(manager.transcriptionService as? MockTranscriptionService === whisperMock)

        // 3. 配置為 Whisper 引擎但模型 URL 為空，應觸發降級為 Apple 引擎
        manager.configure(engine: .whisper, modelURL: nil, language: "zh-TW")
        #expect(manager.selectedEngine == .apple, "未提供 modelURL 時應降級到 Apple 引擎")
        #expect(manager.transcriptionService as? MockTranscriptionService === appleMock)
    }

    /// B5.4: 測試開始與停止轉譯流程以及音訊傳遞
    @Test("測試開始、停止與音訊傳遞流程")
    @MainActor
    func testTranscriptionControlFlow() async {
        let manager = TranscriptionManager()
        let mockService = MockTranscriptionService()
        manager.serviceFactory = { _, _, _ in mockService }

        // 配置服務
        manager.configure(engine: .apple)

        // 1. 測試開始轉譯
        manager.startTranscription()
        #expect(manager.isTranscribing == true)
        #expect(manager.transcribedText == "")
        #expect(mockService.startCallCount == 1)

        // 2. 測試傳遞音訊緩衝區
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000.0, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        manager.processAudioBuffer(buffer)
        #expect(mockService.processCallCount == 1)
        #expect(mockService.processedBuffers.first === buffer)

        // 3. 測試停止轉譯
        manager.stopTranscription()
        #expect(manager.isTranscribing == false)
        #expect(mockService.stopCallCount == 1)
    }

    /// B5.3: 測試轉譯成功與失敗的回傳處理
    @Test("測試轉譯成功與錯誤處理流程")
    @MainActor
    func testTranscriptionResultsAndErrors() async throws {
        let manager = TranscriptionManager()
        let mockService = MockTranscriptionService()
        manager.serviceFactory = { _, _, _ in mockService }

        manager.configure(engine: .apple)

        var completedText: String?
        manager.onTranscriptionComplete = { text in
            completedText = text
        }

        // 1. 測試轉譯成功，且套用文字處理器 (textProcessor)
        manager.textProcessor = { text in
            return text + " [已處理]"
        }

        mockService.simulateResult(.success("測試語音輸入"))
        
        // 由於 callback 內含 DispatchQueue.main.async，需等待 RunLoop 執行完畢
        try? await Task.sleep(for: .milliseconds(50))

        #expect(manager.transcribedText == "測試語音輸入 [已處理]")
        #expect(completedText == "測試語音輸入 [已處理]")

        // 2. 測試轉譯失敗，應加上錯誤前綴
        let dummyError = NSError(domain: "TestDomain", code: 404, userInfo: [NSLocalizedDescriptionKey: "連線失敗"])
        mockService.simulateResult(.failure(dummyError))

        try? await Task.sleep(for: .milliseconds(50))

        #expect(manager.transcribedText.contains(AppStatusMessage.recognitionErrorPrefix))
        #expect(manager.transcribedText.contains("連線失敗"))
        #expect(completedText?.contains(AppStatusMessage.recognitionErrorPrefix) == true)
    }
}
