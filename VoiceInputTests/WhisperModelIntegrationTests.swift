import Foundation
import AVFoundation
import Testing
@testable import VoiceInput

@MainActor
struct WhisperModelIntegrationTests {
    @Test
    func whisperModels_canLoadAndTranscribeLocalAudio() async throws {
        let context = try TestContext.make()

        if let skipReason = context.skipReason {
            print("SKIP WhisperModelIntegrationTests: \(skipReason)")
            return
        }

        #expect(!context.modelURLs.isEmpty, "找不到任何 .bin 模型檔，請確認 models 目錄")

        guard let audioURL = context.audioURL else {
            Issue.record("測試上下文建立失敗：audioURL 為空")
            return
        }

        for modelURL in context.modelURLs {
            let transcription = try await Self.runTranscription(
                modelURL: modelURL,
                audioURL: audioURL
            )

            let trimmed = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(
                !trimmed.isEmpty,
                "模型 \(modelURL.lastPathComponent) 成功執行但未產生任何轉錄文字"
            )
        }
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
                try await Task.sleep(nanoseconds: 90_000_000_000)
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
        let audioURL: URL?
        let skipReason: String?

        static func make() throws -> TestContext {
            let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            let projectRoot = testsDirectory.deletingLastPathComponent()
            let modelsDirectory = projectRoot.appendingPathComponent("models", isDirectory: true)
            let audioURL = testsDirectory.appendingPathComponent("test.m4a", isDirectory: false)

            // T6-2：若測試音檔不存在，明確標記為跳過（不視為失敗）
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                return TestContext(
                    modelURLs: [],
                    audioURL: nil,
                    skipReason: "找不到測試音檔：\(audioURL.path)"
                )
            }

            let modelURLs = try FileManager.default
                .contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "bin" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            return TestContext(modelURLs: modelURLs, audioURL: audioURL, skipReason: nil)
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
        case audioBufferAllocationFailed
        case timeout(model: String)

        var errorDescription: String? {
            switch self {
            case .audioBufferAllocationFailed:
                return "無法建立音訊 buffer"
            case .timeout(let model):
                return "模型 \(model) 逾時，未在 90 秒內產生轉錄結果"
            }
        }
    }
}
