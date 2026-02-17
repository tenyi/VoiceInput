import Foundation
import Speech
import AVFoundation
import SwiftWhisper
import os

// MARK: - 錯誤類型
/// Whisper 相關錯誤
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
            return "這可能是由於音訊錄製問題或系統資源不足導致"
        case .unknownError:
            return "請重啟應用程式"
        case .invalidModelPath:
            return "請確認模型路徑是否正確"
        case .notInitialized:
            return "請等待模型載入完成"
        }
    }
}

/// 使用 Whisper.cpp 的轉錄服務實作
class WhisperTranscriptionService: TranscriptionServiceProtocol, WhisperDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "WhisperService")

    var onTranscriptionResult: ((Result<String, Error>) -> Void)?

    private var whisper: Whisper?
    private var modelUrl: URL?
    private var securityScopedAccess = false

    // 用於累積音訊
    private var accumulatedBuffer: [Float] = []
    private let sampleRate: Float = 16000.0 // Whisper 需要 16kHz

    private var isRunning = false
    private var isTranscribing = false
    private var pendingFinalTranscription = false
    private let stateQueue = DispatchQueue(label: "VoiceInput.WhisperTranscriptionService.state")

    init(modelURL: URL, language: String = "zh") {
        self.modelUrl = modelURL

        // 開始訪問 security-scoped resource
        securityScopedAccess = modelURL.startAccessingSecurityScopedResource()
        logger.info("開始訪問 security-scoped resource: \(self.securityScopedAccess)")
        logger.info("模型 URL: \(modelURL.path)")
        logger.info("模型 URL 是否存在: \(FileManager.default.fileExists(atPath: modelURL.path))")

        // 檢查文件是否存在
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            logger.error("模型文件不存在: \(modelURL.path)")
            return
        }

        // 檢查文件大小
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: modelURL.path)
            if let fileSize = attributes[.size] as? Int64 {
                logger.info("模型文件大小: \(fileSize) bytes")
            }
        } catch {
            logger.warning("無法取得文件大小: \(error.localizedDescription)")
        }

        // 使用 SwiftWhisper 套件載入模型
        do {
            logger.info("正在載入 Whisper 模型...")

            let whisper = try Whisper(fromFileURL: modelURL)
            whisper.delegate = self

            // 設定參數
            whisper.params.language = .auto // 自動檢測語言

            self.whisper = whisper
            logger.info("Whisper 模型載入成功")
        } catch {
            logger.error("無法載入 Whisper 模型: \(error.localizedDescription)")
            onTranscriptionResult?(.failure(error))
        }
    }

    deinit {
        // 停止訪問 security-scoped resource
        if securityScopedAccess, let url = modelUrl {
            url.stopAccessingSecurityScopedResource()
            logger.info("已停止訪問 security-scoped resource")
        }
    }

    func start() {
        stateQueue.sync {
            isRunning = true
            isTranscribing = false
            pendingFinalTranscription = false
            accumulatedBuffer.removeAll()
        }
        logger.info("Whisper 服務已啟動")
    }

    func stop() {
        let shouldTranscribeNow = stateQueue.sync { () -> Bool in
            isRunning = false
            logger.info("Whisper 服務停止，累積音訊 frame 數: \(self.accumulatedBuffer.count)")

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
        guard running else {
            logger.debug("Whisper 服務未運行，跳過處理")
            return
        }

        guard whisper != nil else {
            logger.error("Whisper 實例為 nil，無法處理音訊")
            return
        }

        // 1. 格式轉換: 將輸入 buffer 轉換為 16kHz mono float
        guard let convertedData = convertTo16kHz(buffer: buffer) else {
            logger.error("音訊格式轉換失敗")
            return
        }

        let shouldStartTranscription = stateQueue.sync { () -> Bool in
            guard isRunning else { return false }
            accumulatedBuffer.append(contentsOf: convertedData)
            logger.debug("已累積音訊，目前 frame 數: \(self.accumulatedBuffer.count)")

            let duration = Double(accumulatedBuffer.count) / Double(sampleRate)
            return duration > 1.0 && !isTranscribing
        }

        if shouldStartTranscription {
            Task {
                await transcribeChunkIfNeeded()
            }
        }
    }

    // MARK: - 轉錄方法

    private func transcribeChunkIfNeeded() async {
        guard let whisperInstance = self.whisper else {
            logger.error("Whisper 實例為 nil，無法轉錄")
            return
        }

        let frames = stateQueue.sync { () -> [Float]? in
            guard !isTranscribing, !accumulatedBuffer.isEmpty else { return nil }
            isTranscribing = true
            return accumulatedBuffer
        }

        guard let frames else {
            return
        }

        logger.info("開始轉錄，音訊 frame 數量: \(frames.count)")

        do {
            try await whisperInstance.transcribe(audioFrames: frames)
            logger.info("轉錄完成")
        } catch {
            logger.error("轉錄失敗: \(error.localizedDescription)")
            onTranscriptionResult?(.failure(error))
        }

        finalizeTranscriptionCycle()
    }

    private func transcribeFinalIfNeeded() async {
        guard let whisperInstance = self.whisper else {
            logger.warning("transcribeFinalIfNeeded: Whisper 為 nil")
            return
        }

        let frames = stateQueue.sync { () -> [Float]? in
            guard !isTranscribing, !accumulatedBuffer.isEmpty else { return nil }
            isTranscribing = true
            pendingFinalTranscription = false
            return accumulatedBuffer
        }

        guard let frames else {
            logger.warning("transcribeFinalIfNeeded: buffer 為空或已在轉錄中")
            return
        }

        logger.info("transcribeFinalIfNeeded: 開始最終轉錄，frame 數: \(frames.count)")
        do {
            try await whisperInstance.transcribe(audioFrames: frames)
            logger.info("transcribeFinalIfNeeded: 最終轉錄完成")
        } catch {
            logger.error("transcribeFinalIfNeeded: 最終轉錄失敗: \(error.localizedDescription)")
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

    // MARK: - WhisperDelegate

    func whisper(_ whisper: Whisper, didUpdateProgress progress: Double, inRange range: Range<Int>?) {
        logger.debug("Whisper 進度: \(progress * 100)%")
    }

    func whisper(_ whisper: Whisper, didProcessNewSegments segments: [Segment], atIndex index: Int) {
        let text = segments.map { $0.text }.joined(separator: " ")
        logger.info("Whisper 部分結果: \(text)")
        onTranscriptionResult?(.success(text))
    }

    func whisper(_ whisper: Whisper, didCompleteWithSegments segments: [Segment]) {
        let text = segments.map { $0.text }.joined(separator: " ")
        logger.info("Whisper 最終結果: \(text)")
        onTranscriptionResult?(.success(text))
    }

    func whisper(_ whisper: Whisper, didErrorWith error: Error) {
        logger.error("Whisper 錯誤: \(error.localizedDescription)")
        onTranscriptionResult?(.failure(error))
    }

    // MARK: - Audio Conversion

    private func convertTo16kHz(buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let format = buffer.format as AVAudioFormat? else { return nil }

        // 如果已經是 16kHz, mono, float32，直接回傳
        if format.sampleRate == 16000 && format.channelCount == 1 {
            return Array(UnsafeBufferPointer(start: buffer.floatChannelData?[0], count: Int(buffer.frameLength)))
        }

        // 建立轉換器
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: outputFormat) else {
            return nil
        }

        let ratio = 16000 / format.sampleRate
        let capacity = UInt32(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            logger.error("音訊轉換錯誤: \(error.localizedDescription)")
            return nil
        }

        return Array(UnsafeBufferPointer(start: outputBuffer.floatChannelData?[0], count: Int(outputBuffer.frameLength)))
    }
}
