import Foundation
@preconcurrency import AVFoundation
import os

// MARK: - 錯誤類型
enum WhisperError: Error, Identifiable {
    case modelLoadFailed
    case transcriptionFailed
    case whisperCoreFailed
    case unknownError
    case invalidModelPath
    case notInitialized

    var id: String { UUID().uuidString }
}

extension WhisperError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            return "無法載入語音辨識模型"
        case .transcriptionFailed:
            return "音訊轉錄失敗"
        case .whisperCoreFailed:
            return "語音辨識核心發生錯誤"
        case .unknownError:
            return "發生未知錯誤"
        case .invalidModelPath:
            return "模型路徑無效"
        case .notInitialized:
            return "Whisper 未初始化"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelLoadFailed:
            return "請確認模型檔案存在且路徑正確"
        case .transcriptionFailed:
            return "請檢查音訊錄製是否正常，然後再試一次"
        case .whisperCoreFailed:
            return "這可能是模型格式不相容或語音辨識核心異常"
        case .unknownError:
            return "請重啟應用程式"
        case .invalidModelPath:
            return "請確認模型路徑是否正確"
        case .notInitialized:
            return "請等待模型載入完成"
        }
    }
}

/// 使用 whisper.xcframework C API 的轉錄服務
@MainActor
final class WhisperTranscriptionService: TranscriptionServiceProtocol {
    nonisolated private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "WhisperService")

    var onTranscriptionResult: ((Result<String, Error>) -> Void)?

    private var whisperContext: WhisperContext?
    private var modelURL: URL?
    private var selectedLanguage: String
    private var securityScopedAccess = false

    private var accumulatedBuffer: [Float] = []
    nonisolated private let sampleRate: Float = 16000.0
    nonisolated private let partialTranscriptionMinDuration: Double = 1.0

    nonisolated private let audioProcessingQueue = DispatchQueue(label: "com.tenyi.voiceinput.audioprocessing", qos: .userInitiated)

    private var isRunning = false
    private var isTranscribing = false
    private var pendingFinalTranscription = false

    init(modelURL: URL, language: String = "zh-TW") {
        self.modelURL = modelURL
        self.selectedLanguage = language

        securityScopedAccess = modelURL.startAccessingSecurityScopedResource()
        logger.info("開始訪問 security-scoped resource: \(self.securityScopedAccess)")

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            logger.error("模型文件不存在: \(modelURL.path)")
            return
        }

        do {
            self.whisperContext = try WhisperContext(modelPath: modelURL.path)
            logger.info("Whisper 模型載入成功")
        } catch {
            logger.error("Whisper 模型載入失敗: \(error.localizedDescription)")
            self.onTranscriptionResult?(.failure(error))
        }
    }

    deinit {
        if securityScopedAccess, let modelURL {
            modelURL.stopAccessingSecurityScopedResource()
        }
    }

    func start() {
        isRunning = true
        isTranscribing = false
        pendingFinalTranscription = false
        accumulatedBuffer.removeAll()
    }

    func stop() {
        isRunning = false
        if isTranscribing {
            pendingFinalTranscription = true
        } else if !accumulatedBuffer.isEmpty {
            Task {
                await transcribeFinalIfNeeded()
            }
        }
    }

    nonisolated func process(buffer: AVAudioPCMBuffer) {
        // 使用 unsafe opt-out 來避免 Swift 6 Concurrency warning (AVAudioPCMBuffer isn't Sendable)
        nonisolated(unsafe) let sendableBuffer = buffer
        
        // 使用獨立的背景序列佇列處理，避免阻塞 CoreAudio 的 tap 執行緒
        audioProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 轉換音訊格式至 16kHz 單聲道 Float，失敗或空資料則略過
            guard let converted = self.convertTo16kHz(buffer: sendableBuffer), !converted.isEmpty else {
                return
            }

            // 切換至 MainActor 後再存取 isRunning 等 actor-isolated 狀態
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                self.accumulatedBuffer.append(contentsOf: converted)
                let duration = Double(self.accumulatedBuffer.count) / Double(self.sampleRate)
                let shouldStartChunk = duration > self.partialTranscriptionMinDuration && !self.isTranscribing
                if shouldStartChunk {
                    Task {
                        await self.transcribeChunkIfNeeded()
                    }
                }
            }
        }
    }

    // MARK: - Internal Transcription

    private func transcribeChunkIfNeeded() async {
        guard let context = whisperContext else {
            onTranscriptionResult?(.failure(WhisperError.notInitialized))
            return
        }

        guard !isTranscribing, !accumulatedBuffer.isEmpty else { return }
        isTranscribing = true
        let frames = accumulatedBuffer

        do {
            let text = try await context.transcribe(samples: frames, language: selectedLanguage)
            if !text.isEmpty {
                onTranscriptionResult?(.success(text))
            }
        } catch {
            logger.error("Whisper chunk 轉錄失敗: \(error.localizedDescription)")
            onTranscriptionResult?(.failure(error))
        }

        finalizeTranscriptionCycle()
    }

    private func transcribeFinalIfNeeded() async {
        guard let context = whisperContext else {
            onTranscriptionResult?(.failure(WhisperError.notInitialized))
            return
        }

        guard !isTranscribing, !accumulatedBuffer.isEmpty else { return }
        isTranscribing = true
        pendingFinalTranscription = false
        let frames = accumulatedBuffer

        do {
            let text = try await context.transcribe(samples: frames, language: selectedLanguage)
            if !text.isEmpty {
                onTranscriptionResult?(.success(text))
            }
        } catch {
            logger.error("Whisper final 轉錄失敗: \(error.localizedDescription)")
            onTranscriptionResult?(.failure(error))
        }

        finalizeTranscriptionCycle()
    }

    private func finalizeTranscriptionCycle() {
        isTranscribing = false
        let shouldRunFinal = !isRunning && pendingFinalTranscription && !accumulatedBuffer.isEmpty

        if shouldRunFinal {
            Task {
                await transcribeFinalIfNeeded()
            }
        }
    }

    // MARK: - Audio Conversion

    nonisolated private func convertTo16kHz(buffer: AVAudioPCMBuffer) -> [Float]? {
        let format = buffer.format

        if format.sampleRate == 16000, format.channelCount == 1, let channelData = buffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        }

        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: format, to: outputFormat)
        else {
            return nil
        }

        let ratio = 16000.0 / format.sampleRate
        let capacity = UInt32(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        guard error == nil, status != .error, let channelData = outputBuffer.floatChannelData?[0] else {
            return nil
        }

        return Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
    }
}
