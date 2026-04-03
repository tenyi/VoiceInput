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

    /// 使用 errorDescription 作為穩定的識別符，避免每次存取 Identifiable.id 都產生新 UUID
    var id: String { errorDescription ?? "unknownError" }
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
    /// 音訊緩衝區最大容量（5 分鐘 = 16000 Hz * 60s * 5）
    nonisolated private let maxBufferCapacity: Int = 16000 * 60 * 5
    /// 開始部分轉寫的最短音訊時長（秒）
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
        // 預留 5 分鐘的音訊容量（使用 maxBufferCapacity），
        // 避免先前預留 1 小時（~230MB）造成不必要的大量記憶體佔用。
        // 使用 keepingCapacity:false 讓 Swift 依實際使用量動態擴增。
        accumulatedBuffer.removeAll(keepingCapacity: false)
        accumulatedBuffer.reserveCapacity(maxBufferCapacity)
    }

    func stop() {
        isRunning = false
        if isTranscribing {
            // 轉寫正在進行中，標記等待最後一次轉寫完成
            pendingFinalTranscription = true
        } else if !accumulatedBuffer.isEmpty {
            // 轉寫未進行但有緩衝資料，直接執行最後轉寫並等待完成
            // 捕獲必要資料的副本，避免在 async 作業期間物件被釋放
            let frames = accumulatedBuffer
            let language = selectedLanguage
            Task { [weak self] in
                // 確保 self 在 Task 完成前不被釋放
                guard let self = self else { return }
                await self.performFinalTranscription(frames: frames, language: language)
            }
        }
    }

    /// 執行最終轉寫（由 stop() 呼叫）
    private func performFinalTranscription(frames: [Float], language: String) async {
        guard let context = whisperContext else {
            onTranscriptionResult?(.failure(WhisperError.notInitialized))
            return
        }

        guard !isTranscribing else { return }
        isTranscribing = true
        pendingFinalTranscription = false

        do {
            let text = try await context.transcribe(samples: frames, language: language)
            if !text.isEmpty {
                onTranscriptionResult?(.success(text))
            }
        } catch {
            logger.error("Whisper final 轉錄失敗: \(error.localizedDescription)")
            onTranscriptionResult?(.failure(error))
        }

        finalizeTranscriptionCycle()
    }

    nonisolated func process(buffer: AVAudioPCMBuffer) {
        // 使用獨立的背景序列佇列處理，避免阻塞 CoreAudio 的 tap 執行緒
        audioProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 轉換音訊格式至 16kHz 單聲道 Float，改透過安全的 Actor 執行
            Task {
                guard let converted = await self.audioConverterActor.convertTo16kHz(buffer: buffer), !converted.isEmpty else {
                    return
                }

                // 切換至 MainActor 後再存取 isRunning 等 actor-isolated 狀態
                await MainActor.run { [weak self] in
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

    // MARK: - Audio Conversion Optimization
    nonisolated private let audioConverterActor = AudioConverterActor()
}

/// 用於隔離非 Sendable 的 AVAudioConverter 資源的 Actor
actor AudioConverterActor {
    private var audioConverter: AVAudioConverter?
    private var conversionBuffer: AVAudioPCMBuffer?

    func convertTo16kHz(buffer: AVAudioPCMBuffer) -> [Float]? {
        let format = buffer.format

        // 若輸入已經是 16kHz 單聲道，直接返回資料
        if format.sampleRate == 16000, format.channelCount == 1, let channelData = buffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        }

        // 初始化或重用轉換器與緩衝區
        if audioConverter == nil || audioConverter?.inputFormat != format {
            guard let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            ) else { return nil }
            
            audioConverter = AVAudioConverter(from: format, to: outputFormat)
        }

        guard let converter = audioConverter else { return nil }

        let ratio = 16000.0 / format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        // 若無現有緩衝區或容量不足，則重新分配
        if conversionBuffer == nil || conversionBuffer!.frameCapacity < capacity {
            conversionBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity)
        }

        guard let outputBuffer = conversionBuffer else { return nil }
        
        // 重置長度準備寫入
        outputBuffer.frameLength = capacity

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
