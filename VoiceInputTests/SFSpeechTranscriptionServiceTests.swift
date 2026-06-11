import Foundation
import Speech
import AVFoundation
import Testing
@testable import VoiceInput

// MARK: - Mocks

/// Mock 系統 SFSpeechRecognitionTask
final class MockSFSpeechRecognitionTask: SFSpeechRecognitionTask {
    var cancelCalled = false
    
    override func cancel() {
        cancelCalled = true
    }
}

/// Mock 系統 SFSpeechRecognizer
@MainActor
final class MockSFSpeechRecognizer: SFSpeechRecognizer {
    private let _isAvailable: Bool
    private let _locale: Locale
    
    override var isAvailable: Bool {
        return _isAvailable
    }
    
    override var locale: Locale {
        return _locale
    }
    
    var recognitionTaskCalled = false
    var lastRequest: SFSpeechAudioBufferRecognitionRequest?
    var taskToReturn: MockSFSpeechRecognitionTask?
    var resultHandlerToExecute: ((SFSpeechRecognitionResult?, Error?) -> Void)?
    
    init?(locale: Locale, isAvailable: Bool = true) {
        self._isAvailable = isAvailable
        self._locale = locale
        super.init(locale: locale)
    }
    
    override func recognitionTask(
        with request: SFSpeechRecognitionRequest,
        resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognitionTaskCalled = true
        if let bufferRequest = request as? SFSpeechAudioBufferRecognitionRequest {
            lastRequest = bufferRequest
        }
        resultHandlerToExecute = resultHandler
        
        let task = taskToReturn ?? MockSFSpeechRecognitionTask()
        return task
    }
}

// MARK: - Test Suite

@Suite("SFSpeechTranscriptionServiceTests")
@MainActor
struct SFSpeechTranscriptionServiceTests {
    
    /// 建立輔助方法
    private func createDummyBuffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 0
        return buffer
    }
    
    /// B8.2: 測試當語音識別器不可用時的授權/可用性錯誤處理
    @Test("當語音識別器不可用時 process 會回傳錯誤")
    func testIsAvailableFalse_returnsError() async {
        let mockRecognizerFactory: (Locale) -> SFSpeechRecognizer? = { locale in
            return MockSFSpeechRecognizer(locale: locale, isAvailable: false)
        }
        
        let service = SFSpeechTranscriptionService(speechRecognizerFactory: mockRecognizerFactory)
        
        var receivedResult: Result<String, Error>?
        service.onTranscriptionResult = { result in
            receivedResult = result
        }
        
        // 必須先呼叫 start() 以初始化 recognitionRequest
        service.start()
        
        // 餵入 Dummy 緩衝區觸發 recognitionTask 流程
        let buffer = createDummyBuffer()
        service.process(buffer: buffer)
        
        #expect(receivedResult != nil, "應收到轉譯結果回調")
        switch receivedResult {
        case .failure(let error as NSError):
            #expect(error.domain == "SFSpeechTranscriptionService")
            #expect(error.code == 1)
            #expect(error.localizedDescription == "語音識別器無法使用")
        default:
            Issue.record("應回傳失敗 result")
        }
    }
    
    /// B8.3: 測試 handleRecognitionResult 處理部分結果
    @Test("handleRecognitionResult 處理部分結果（非 Final）")
    func testHandleRecognitionResult_partial() async {
        let service = SFSpeechTranscriptionService()
        
        var receivedResults: [String] = []
        service.onTranscriptionResult = { result in
            if case .success(let text) = result {
                receivedResults.append(text)
            }
        }
        
        // 模擬收到第一個非最終結果
        service.handleRecognitionResult(transcription: "天氣", isFinal: false)
        // 模擬收到第二個非最終結果
        service.handleRecognitionResult(transcription: "天氣很好", isFinal: false)
        
        #expect(receivedResults.count == 2)
        #expect(receivedResults[0] == "天氣")
        #expect(receivedResults[1] == "天氣很好")
    }
    
    /// B8.3: 測試 handleRecognitionResult 處理最終結果
    @Test("handleRecognitionResult 處理最終結果（isFinal）並清理狀態")
    func testHandleRecognitionResult_isFinal() async {
        let service = SFSpeechTranscriptionService()
        
        var receivedText: String?
        service.onTranscriptionResult = { result in
            if case .success(let text) = result {
                receivedText = text
            }
        }
        
        service.start()
        service.handleRecognitionResult(transcription: "今天的風兒有點喧囂", isFinal: true)
        
        #expect(receivedText == "今天的風兒有點喧囂")
        // 檢查 cleanup 之後，狀態是否正常被重設
        // 可以藉由嘗試對 service 呼叫 stop 看是否安全，或是再次呼叫 cleanup
        service.cleanupRecognition() // 應可安全重複呼叫
    }
    
    /// B8.4: 測試 handleRecognitionError 過濾無語音類型的錯誤
    @Test("handleRecognitionError 過濾無語音錯誤而不拋出失敗")
    func testHandleRecognitionError_noSpeech_filtered() async {
        let service = SFSpeechTranscriptionService()
        
        var receivedResult: Result<String, Error>?
        service.onTranscriptionResult = { result in
            receivedResult = result
        }
        
        service.start()
        
        // 模擬 no speech 錯誤
        let noSpeechError = NSError(domain: "SFSpeech", code: 4, userInfo: [NSLocalizedDescriptionKey: "No speech detected"])
        service.handleRecognitionError(noSpeechError)
        
        #expect(receivedResult == nil, "無語音錯誤應被過濾，不應觸發 failure 回調")
    }
    
    /// B8.4: 測試 handleRecognitionError 拋出其他一般性錯誤
    @Test("handleRecognitionError 遇到一般錯誤時觸發失敗回調")
    func testHandleRecognitionError_otherError_reported() async {
        let service = SFSpeechTranscriptionService()
        
        var receivedResult: Result<String, Error>?
        service.onTranscriptionResult = { result in
            receivedResult = result
        }
        
        service.start()
        
        // 模擬一般識別錯誤
        let otherError = NSError(domain: "SFSpeech", code: 201, userInfo: [NSLocalizedDescriptionKey: "Network timeout"])
        service.handleRecognitionError(otherError)
        
        #expect(receivedResult != nil, "一般錯誤應觸發回調")
        switch receivedResult {
        case .failure(let error as NSError):
            #expect(error.domain == "SFSpeech")
            #expect(error.code == 201)
        default:
            Issue.record("應回傳 failure")
        }
    }
    
    /// B8.3 / B8.4: 測試停止 (stop) 優雅停止流程與 timeout 強制清理
    @Test("stop() 啟動逾時器，並在逾時後強制清理")
    func testStop_triggersTimeoutAndCleanup() async throws {
        // 設定極短的 finalizeTimeout（例如 0.05 秒）以縮短測試時間
        let service = SFSpeechTranscriptionService(finalizeTimeout: 0.05)
        
        service.start()
        
        // 觸發 stop 啟動優雅停止
        service.stop()
        
        // 等待逾時器觸發 (等待 0.1 秒，大於 0.05 秒)
        try await Task.sleep(for: .milliseconds(100))
        
        // 逾時器觸發後會呼叫 cleanupRecognition，此時會將內部計時器等清空
        // 這邊我們確認 cleanupRecognition 能重置 isWaitingForFinal 等狀態
        // 再次呼叫 stop 不會造成崩潰
        service.stop()
    }
    
    /// 測試 updateLocale 更新語音識別語言
    @Test("updateLocale 成功更新語音識別語言")
    func testUpdateLocale() async {
        var createdLocales: [Locale] = []
        let mockRecognizerFactory: (Locale) -> SFSpeechRecognizer? = { locale in
            createdLocales.append(locale)
            return MockSFSpeechRecognizer(locale: locale, isAvailable: true)
        }
        
        let service = SFSpeechTranscriptionService(speechRecognizerFactory: mockRecognizerFactory)
        
        // 預設 init 會建立一次 "zh-TW"
        #expect(createdLocales.count == 1)
        #expect(createdLocales[0].identifier == "zh-TW")
        
        // 更新為英文
        service.updateLocale(identifier: "en-US")
        #expect(createdLocales.count == 2)
        #expect(createdLocales[1].identifier == "en-US")
        
        // 更新為同一個 identifier，不應該重複建立
        service.updateLocale(identifier: "en-US")
        #expect(createdLocales.count == 2)
    }
}
