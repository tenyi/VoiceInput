import Foundation
import AVFoundation
import Testing
@testable import VoiceInput

@MainActor
struct WhisperModelIntegrationTests {

    // @Test("Whisper 模型推論整合測試（需要 models/ 目錄中的 .bin 檔案）")
    // func whisperModels_canLoadAndTranscribeLocalAudio() async throws {
    //     // 先定位資源
    //     let context = try TestContext.make()
        
    //     for modelURL in context.modelURLs {
    //         print("[DEBUG] Testing model: \(modelURL.lastPathComponent)")
    //         let transcription = try await Self.runTranscription(
    //             modelURL: modelURL,
    //             audioURL: context.audioURL
    //         )

    //         let trimmed = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
    //         print("[DEBUG] 模型 \(modelURL.lastPathComponent) 轉錄結果長度: \(trimmed.count)")
    //         print("[DEBUG] 轉錄內容: '\(trimmed)'")
            
    //         #expect(
    //             !trimmed.isEmpty,
    //             "模型 \(modelURL.lastPathComponent) 成功執行但未產生任何轉錄文字"
    //         )
    //     }
    // }

    /// 判斷是否有必要的測試資源（models 目錄 + 測試音檔）
    static nonisolated var hasTestResources: Bool {
        return (try? TestContext.make()) != nil
    }

    private static func runTranscription(modelURL: URL, audioURL: URL) async throws -> String {
        let service = WhisperTranscriptionService(modelURL: modelURL)
        let state = ContinuationState()

        return try await withCheckedThrowingContinuation { continuation in
            service.onTranscriptionResult = { result in
                switch result {
                case .success(let text):
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    state.resumeIfNeeded {
                        continuation.resume(returning: text)
                    }
                case .failure(let error):
                    state.resumeIfNeeded {
                        continuation.resume(throwing: error)
                    }
                }
            }

            do {
                service.start()
                try feedAudioFile(audioURL, into: service)
                service.stop()
            } catch {
                state.resumeIfNeeded {
                    continuation.resume(throwing: error)
                }
                return
            }

            Task {
                // 給予足夠的逾時時間（大型模型可能需要較久）
                try await Task.sleep(nanoseconds: 120_000_000_000)
                state.resumeIfNeeded {
                    continuation.resume(throwing: TestError.timeout(model: modelURL.lastPathComponent))
                }
            }
        }
    }

    private static func feedAudioFile(_ audioURL: URL, into service: WhisperTranscriptionService) throws {
        let audioFile = try AVAudioFile(forReading: audioURL)
        let format = audioFile.processingFormat
        let chunkSize: AVAudioFrameCount = 4096

        while true {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
                throw TestError.audioBufferAllocationFailed
            }

            try audioFile.read(into: buffer)
            if buffer.frameLength == 0 { break }
            service.process(buffer: buffer)
        }
    }
}

private extension WhisperModelIntegrationTests {
    struct TestContext {
        let modelURLs: [URL]
        let audioURL: URL

        static func make() throws -> TestContext {
            let fm = FileManager.default
            
            // 嘗試多個可能的路徑
            let possibleRoots: [URL] = [
                URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent(),
                URL(fileURLWithPath: fm.currentDirectoryPath),
                URL(fileURLWithPath: "/Users/tenyi/Projects/VoiceInput")
            ]
            
            var modelsDir: URL?
            var audioFile: URL?
            
            for root in possibleRoots {
                let mDir = root.appendingPathComponent("models", isDirectory: true)
                let aFile = root.appendingPathComponent("VoiceInputTests/test.wav", isDirectory: false)
                
                if fm.fileExists(atPath: mDir.path) && fm.fileExists(atPath: aFile.path) {
                    modelsDir = mDir
                    audioFile = aFile
                    break
                }
            }
            
            guard let finalModelsDir = modelsDir, let finalAudioFile = audioFile else {
                let msg = "無法定位測試資源。嘗試過的路徑: \(possibleRoots.map { $0.path })"
                throw TestError.missingTestAudio(msg)
            }

            let modelURLs = try fm
                .contentsOfDirectory(at: finalModelsDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "bin" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            if modelURLs.isEmpty {
                throw TestError.missingTestAudio("models 目錄中沒有 .bin 檔案：\(finalModelsDir.path)")
            }

            return TestContext(modelURLs: modelURLs, audioURL: finalAudioFile)
        }
    }

    final class ContinuationState: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false

        func resumeIfNeeded(_ body: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !resumed else { return }
            resumed = true
            body()
        }
    }

    enum TestError: LocalizedError {
        case missingTestAudio(String)
        case audioBufferAllocationFailed
        case timeout(model: String)

        var errorDescription: String? {
            switch self {
            case .missingTestAudio(let path):
                return "測試資源缺失：\(path)"
            case .audioBufferAllocationFailed:
                return "無法建立音訊 buffer"
            case .timeout(let model):
                return "模型 \(model) 逾時，未在 120 秒內產生轉錄結果"
            }
        }
    }
}
