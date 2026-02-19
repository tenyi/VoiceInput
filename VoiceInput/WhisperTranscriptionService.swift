import Foundation
import AVFoundation
import os

// MARK: - 錯誤類型

/// WhisperTranscriptionService 可能拋出的錯誤
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
        case .modelLoadFailed:     return "無法載入語音辨識模型"
        case .transcriptionFailed: return "音訊轉錄失敗"
        case .whisperCoreFailed:   return "語音辨識核心發生錯誤"
        case .unknownError:        return "發生未知錯誤"
        case .invalidModelPath:    return "模型路徑無效"
        case .notInitialized:      return "Whisper 未初始化"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelLoadFailed:     return "請確認模型檔案存在且路徑正確"
        case .transcriptionFailed: return "請檢查音訊錄製是否正常，然後再試一次"
        case .whisperCoreFailed:   return "這可能是模型格式不相容或語音辨識核心異常"
        case .unknownError:        return "請重啟應用程式"
        case .invalidModelPath:    return "請確認模型路徑是否正確"
        case .notInitialized:      return "請等待模型載入完成"
        }
    }
}

// MARK: - WhisperTranscriptionService

/// 使用 whisper.xcframework C API 的轉錄服務
///
/// 執行緒安全策略（修正版）：
/// - 原版使用 `@MainActor` + `stateQueue.sync` 混用：
///   `@MainActor` 方法在主執行緒執行，`stateQueue.sync` 在主執行緒同步等待另一個 queue，
///   若 stateQueue 的任務需要排隊等待，理論上不會死鎖（stateQueue 不回呼主執行緒），
///   但設計上容易誤解，且在主執行緒上做 sync 等待是一種不良實踐。
/// - 修正：移除 `@MainActor`，統一由 `stateQueue` 保護所有可變狀態。
///   所有回呼（onTranscriptionResult）統一在主執行緒觸發，確保 UI 更新安全。
final class WhisperTranscriptionService: TranscriptionServiceProtocol {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "WhisperService")

    // MARK: - Protocol 要求

    /// 轉錄結果回呼（設定後由 notifyResult() 在主執行緒觸發）
    var onTranscriptionResult: ((Result<String, Error>) -> Void)?

    /// 最終結果完成回調（Whisper 完成最終轉錄後觸發，供 ViewModel 決定何時收尾）
    var onFinalResult: (() -> Void)?

    // MARK: - Whisper 模型

    /// Whisper 推論上下文（模型載入後使用）
    private var whisperContext: WhisperContext?

    /// 模型 URL（用於 deinit 時停止 security-scoped 存取）
    private let modelURL: URL

    /// 使用者選擇的辨識語言
    private var selectedLanguage: String

    /// 是否已成功取得 security-scoped resource 存取
    private let securityScopedAccess: Bool

    // MARK: - 音訊緩衝狀態（由 stateQueue 保護）

    /// 累積的 PCM 音訊樣本（Float32，16kHz 單聲道）
    private var accumulatedBuffer: [Float] = []

    /// Whisper 推論所需的取樣率（16kHz）
    private let sampleRate: Float = 16000.0

    /// 觸發 partial 轉錄所需的最短音訊長度（秒）
    private let partialTranscriptionMinDuration: Double = 1.0

    /// 是否正在接受音訊（錄音中）
    private var isRunning = false

    /// 是否有轉錄任務正在執行（避免同時啟動多個轉錄）
    private var isTranscribing = false

    /// 是否有最終轉錄等待中（stop 時仍在轉錄，待完成後再做最終轉錄）
    private var pendingFinalTranscription = false

    /// 保護上述所有可變狀態的串行 queue
    /// 注意：不使用 @MainActor，避免在主執行緒上做 sync 等待
    private let stateQueue = DispatchQueue(label: "VoiceInput.WhisperTranscriptionService.state", qos: .userInitiated)

    // MARK: - 初始化

    init(modelURL: URL, language: String = "zh-TW") {
        self.modelURL = modelURL
        self.selectedLanguage = language

        // 取得 security-scoped resource 存取（App Sandbox 環境必要）
        securityScopedAccess = modelURL.startAccessingSecurityScopedResource()
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "WhisperService")
            .info("Security-scoped resource 存取: \(self.securityScopedAccess)")

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "WhisperService")
                .error("Whisper 模型檔案不存在: \(modelURL.path)")
            return
        }

        do {
            self.whisperContext = try WhisperContext(modelPath: modelURL.path)
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "WhisperService")
                .info("Whisper 模型載入成功: \(modelURL.lastPathComponent)")
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "WhisperService")
                .error("Whisper 模型載入失敗: \(error.localizedDescription)")
            notifyResult(.failure(error))
        }
    }

    deinit {
        // 釋放 security-scoped resource 存取
        if securityScopedAccess {
            modelURL.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - TranscriptionServiceProtocol

    /// 開始接受音訊緩衝（重置所有狀態）
    func start() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            isRunning = true
            isTranscribing = false
            pendingFinalTranscription = false
            accumulatedBuffer.removeAll()
            logger.debug("WhisperTranscriptionService 開始錄音")
        }
    }

    /// 停止接受音訊緩衝，並啟動最終轉錄
    func stop() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            isRunning = false

            if isTranscribing {
                // 有轉錄進行中，標記 pending，等完成後再處理最終音訊
                pendingFinalTranscription = true
                logger.debug("停止錄音，等待進行中的轉錄完成後再做最終轉錄")
            } else if !accumulatedBuffer.isEmpty {
                // 有音訊，直接啟動最終轉錄
                Task { await self.transcribeFinalIfNeeded() }
            } else {
                // 無音訊可轉錄（例如錄音時間極短或靜音）
                // 仍要觸發最終回調，避免 ViewModel 卡在轉寫狀態等待 5 秒超時
                self.notifyFinalResult()
                logger.debug("停止錄音，無音訊緩衝，直接觸發最終完成回調")
            }
        }
    }

    /// 處理音訊緩衝（由 AudioEngine tap 回調在背景執行緒呼叫）
    func process(buffer: AVAudioPCMBuffer) {
        // 轉換格式（非同步，避免阻塞 audio tap 執行緒）
        guard let converted = convertTo16kHz(buffer: buffer), !converted.isEmpty else {
            logger.error("音訊格式轉換失敗，跳過此緩衝")
            return
        }

        stateQueue.async { [weak self] in
            guard let self, isRunning else { return }

            accumulatedBuffer.append(contentsOf: converted)

            let duration = Double(accumulatedBuffer.count) / Double(sampleRate)
            if duration > partialTranscriptionMinDuration && !isTranscribing {
                Task { await self.transcribeChunkIfNeeded() }
            }
        }
    }

    // MARK: - 內部轉錄邏輯

    /// Partial 轉錄（錄音期間的即時回饋）
    private func transcribeChunkIfNeeded() async {
        guard let context = whisperContext else {
            notifyResult(.failure(WhisperError.notInitialized))
            return
        }

        // 在 stateQueue 上原子性地取得緩衝快照並標記轉錄開始
        let frames: [Float]? = stateQueue.sync {
            guard !isTranscribing, !accumulatedBuffer.isEmpty else { return nil }
            isTranscribing = true
            return accumulatedBuffer // 快照（不清空，讓後續繼續累積）
        }
        guard let frames else { return }

        do {
            let text = try await context.transcribe(samples: frames, language: selectedLanguage)
            if !text.isEmpty { notifyResult(.success(text)) }
        } catch {
            logger.error("Chunk 轉錄失敗: \(error.localizedDescription)")
            notifyResult(.failure(error))
        }

        finalizeTranscriptionCycle()
    }

    /// 最終轉錄（stop() 後處理剩餘所有音訊）
    private func transcribeFinalIfNeeded() async {
        guard let context = whisperContext else {
            notifyResult(.failure(WhisperError.notInitialized))
            notifyFinalResult()  // 即使失敗也要觸發，避免 ViewModel 永遠等待
            return
        }

        let frames: [Float]? = stateQueue.sync {
            guard !isTranscribing, !accumulatedBuffer.isEmpty else { return nil }
            isTranscribing = true
            pendingFinalTranscription = false
            return accumulatedBuffer
        }
        guard let frames else {
            // 無音訊可轉錄，仍要觸發完成回調
            notifyFinalResult()
            return
        }

        do {
            let text = try await context.transcribe(samples: frames, language: selectedLanguage)
            if !text.isEmpty { notifyResult(.success(text)) }
        } catch {
            logger.error("最終轉錄失敗: \(error.localizedDescription)")
            notifyResult(.failure(error))
        }

        finalizeTranscriptionCycle()
    }

    /// 轉錄完成後的收尾邏輯：重置 isTranscribing，並處理 pending 最終轉錄
    private func finalizeTranscriptionCycle() {
        // 在 stateQueue 上原子性地重置 isTranscribing，並讀取當前狀態
        let (shouldRunFinal, isStopped) = stateQueue.sync { () -> (Bool, Bool) in
            isTranscribing = false
            let pending = !isRunning && pendingFinalTranscription && !accumulatedBuffer.isEmpty
            return (pending, !isRunning)
        }

        if shouldRunFinal {
            // 有 pending 的最終轉錄任務（stop() 時有 partial 正在進行），繼續執行最終轉錄
            Task { await transcribeFinalIfNeeded() }
        } else if isStopped {
            // 已停止錄音（!isRunning）且不需要再跑最終轉錄
            // → 這次 finalizeTranscriptionCycle 是由 transcribeFinalIfNeeded 觸發的，
            //   代表最終轉錄已完成，可以安全通知 ViewModel 收尾
            notifyFinalResult()
        }
        // 注意：如果 isStopped == false（仍在錄音中），代表這是 partial 轉錄的收尾
        // 不應觸發 notifyFinalResult()，讓 ViewModel 繼續等待
    }

    // MARK: - 工具方法

    /// 在主執行緒觸發轉錄結果回呼（確保 UI 安全）
    private func notifyResult(_ result: Result<String, Error>) {
        let callback = onTranscriptionResult
        DispatchQueue.main.async {
            callback?(result)
        }
    }

    /// 在主執行緒觸發「最終轉錄完成」回呼（通知 ViewModel 可以安全收尾）
    private func notifyFinalResult() {
        let callback = onFinalResult
        DispatchQueue.main.async {
            callback?()
        }
    }

    // MARK: - 音訊格式轉換

    /// 將 AVAudioPCMBuffer 轉換為 16kHz Float32 單聲道陣列（Whisper 需求格式）
    /// 此方法不存取任何可變狀態，執行緒安全
    private func convertTo16kHz(buffer: AVAudioPCMBuffer) -> [Float]? {
        let format = buffer.format

        // 若來源已是 16kHz 單聲道 Float32，直接複製
        if format.sampleRate == 16000, format.channelCount == 1,
           let channelData = buffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        }

        // 建立 16kHz Float32 單聲道輸出格式
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

        // 依取樣率比例計算輸出容量
        let ratio = 16000.0 / format.sampleRate
        let capacity = UInt32(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        // 執行格式轉換
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
