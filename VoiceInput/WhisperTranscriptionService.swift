import Foundation
import AVFoundation
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
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "WhisperService")

    var onTranscriptionResult: ((Result<String, Error>) -> Void)?

    private var whisperContext: WhisperContext?
    private var modelURL: URL?
    private var selectedLanguage: String
    private var securityScopedAccess = false

    private var accumulatedBuffer: [Float] = []
    private let sampleRate: Float = 16000.0
    private let partialTranscriptionMinDuration: Double = 1.0

    private var isRunning = false
    private var isTranscribing = false
    private var pendingFinalTranscription = false
    private let stateQueue = DispatchQueue(label: "VoiceInput.WhisperTranscriptionService.state")

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
        stateQueue.sync {
            isRunning = true
            isTranscribing = false
            pendingFinalTranscription = false
            accumulatedBuffer.removeAll()
        }
    }

    func stop() {
        let shouldTranscribeNow = stateQueue.sync { () -> Bool in
            isRunning = false
            if isTranscribing {
                pendingFinalTranscription = true
                return false
            }
            return !accumulatedBuffer.isEmpty
        }

        if shouldTranscribeNow {
            Task {
                await transcribeFinalIfNeeded()
            }
        }
    }

    func process(buffer: AVAudioPCMBuffer) {
        let running = stateQueue.sync { isRunning }
        guard running else { return }

        guard let converted = convertTo16kHz(buffer: buffer), !converted.isEmpty else {
            logger.error("音訊格式轉換失敗")
            return
        }

        let shouldStartChunk = stateQueue.sync { () -> Bool in
            guard isRunning else { return false }
            accumulatedBuffer.append(contentsOf: converted)
            let duration = Double(accumulatedBuffer.count) / Double(sampleRate)
            return duration > partialTranscriptionMinDuration && !isTranscribing
        }

        if shouldStartChunk {
            Task {
                await transcribeChunkIfNeeded()
            }
        }
    }

    // MARK: - Internal Transcription

    private func transcribeChunkIfNeeded() async {
        guard let context = whisperContext else {
            onTranscriptionResult?(.failure(WhisperError.notInitialized))
            return
        }

        let frames = stateQueue.sync { () -> [Float]? in
            guard !isTranscribing, !accumulatedBuffer.isEmpty else { return nil }
            isTranscribing = true
            return accumulatedBuffer
        }

        guard let frames else { return }

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

        let frames = stateQueue.sync { () -> [Float]? in
            guard !isTranscribing, !accumulatedBuffer.isEmpty else { return nil }
            isTranscribing = true
            pendingFinalTranscription = false
            return accumulatedBuffer
        }

        guard let frames else { return }

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
        let shouldRunFinal = stateQueue.sync { () -> Bool in
            isTranscribing = false
            return !isRunning && pendingFinalTranscription && !accumulatedBuffer.isEmpty
        }

        if shouldRunFinal {
            Task {
                await transcribeFinalIfNeeded()
            }
        }
    }

    // MARK: - Audio Conversion

    private func convertTo16kHz(buffer: AVAudioPCMBuffer) -> [Float]? {
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
