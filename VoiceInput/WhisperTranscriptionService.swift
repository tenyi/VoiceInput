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
    /// C-1 修復：部分轉寫的滑動視窗大小（30 秒 = 16000 Hz * 30s）
    /// 限制每次部分轉寫的音訊量,避免錄製時間越長轉錄成本越高(O(n²) -> O(n))
    nonisolated private let partialWindowFrames: Int = 16000 * 30
    /// C-2 修復：等待 in-flight buffer 處理的逾時秒數
    nonisolated private let stopInFlightTimeout: TimeInterval = 2.0
    /// 每 30 秒音訊窗的辨識耗時超過此值即視為慢模型，停用錄音中的部分轉寫，
    /// 避免放開快捷鍵時還要等進行中的部分轉寫跑完才能開始最終轉寫
    nonisolated private let slowTranscriptionThreshold: TimeInterval = 1.0

    private var isRunning = false
    private var isTranscribing = false
    private var pendingFinalTranscription = false
    /// C-2 修復：追蹤正在進行的 process() 呼叫數量,stop() 須等待其歸零才快照 buffer
    private var inFlightProcessingCount = 0
    /// H-6 修復:模型是否已載入完成。process() 期間若 isReady=false,只 buffer 不轉錄。
    private var isModelReady = false
    /// H-6 修復:模型載入失敗的錯誤(供 stop() 結束時回報)
    private var modelLoadError: Error?
    /// 進行中的模型載入；最終轉寫需等它完成
    private var modelLoadTask: Task<Void, Never>?
    /// 是否在錄音中執行部分轉寫（慢模型會自動關閉）
    private var isPartialTranscriptionEnabled = true
    /// stop() 傳入的完成回呼，最終轉寫結束時呼叫
    private var stopCompletion: (() -> Void)?

    init(modelURL: URL, language: String = "zh-TW") {
        self.modelURL = modelURL
        self.selectedLanguage = language

        securityScopedAccess = modelURL.startAccessingSecurityScopedResource()
        logger.info("開始訪問 security-scoped resource: \(self.securityScopedAccess)")

        // H-6 修復:模型載入移到 start() 內以非同步 Task 執行,避免 init 同步阻塞主執行緒。
        // 此處只做檔案存在檢查,實際 whisper_full 載入在 start() 內的非同步 Task 中進行。
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            logger.error("模型文件不存在: \(modelURL.path)")
            modelLoadError = WhisperError.invalidModelPath
            return
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

        // H-6 修復:模型未就緒時於背景載入(通常已由 preload() 預先載入)
        loadModelIfNeeded()
    }

    func preload() {
        loadModelIfNeeded()
    }

    /// H-6 修復:在背景執行緒載入 WhisperContext 並預熱,完成後設 isModelReady 並回報結果。
    private func loadModelIfNeeded() {
        guard whisperContext == nil, modelLoadError == nil, modelLoadTask == nil, let modelURL else { return }
        let path = modelURL.path
        let language = selectedLanguage

        modelLoadTask = Task { [weak self] in
            // 大模型載入需數秒,放到背景執行緒避免凍結 UI
            let result = await Task.detached(priority: .userInitiated) { () -> Result<WhisperContext, Error> in
                do {
                    let context = try WhisperContext(modelPath: path)
                    // 預熱:第一次推論需初始化 GPU 資源,先以 1 秒靜音跑一次
                    _ = try? await context.transcribe(samples: [Float](repeating: 0, count: 16000), language: language)
                    return .success(context)
                } catch {
                    return .failure(error)
                }
            }.value

            guard let self else { return }
            switch result {
            case .success(let context):
                self.whisperContext = context
                self.isModelReady = true
                self.logger.info("Whisper 模型非同步載入成功")
            case .failure(let error):
                self.modelLoadError = error
                // L-5 修復:載入失敗時重置 isRunning,避免下次 start() 認為引擎仍在運行
                self.isRunning = false
                self.logger.error("Whisper 模型非同步載入失敗: \(error.localizedDescription)")
                self.onTranscriptionResult?(.failure(error))
            }
        }
    }

    /// 以耗時判斷模型速度,慢模型停用部分轉寫
    private func recordTranscriptionDuration(_ elapsed: TimeInterval, frameCount: Int) {
        guard isPartialTranscriptionEnabled else { return }
        // whisper 以 30 秒為一個音訊窗處理,依窗數換算單窗耗時
        let windows = max(1.0, (Double(frameCount) / Double(partialWindowFrames)).rounded(.up))
        if elapsed / windows > slowTranscriptionThreshold {
            isPartialTranscriptionEnabled = false
            logger.info("Whisper 辨識較慢(\(elapsed, format: .fixed(precision: 2))s),停用錄音中的部分轉寫")
        }
    }

    /// 呼叫並清除 stop() 的完成回呼
    private func completeStop() {
        let completion = stopCompletion
        stopCompletion = nil
        completion?()
    }

    func stop(completion: @escaping () -> Void) {
        isRunning = false
        stopCompletion = completion

        // C-2 修復:將最終轉寫邏輯排入 Task,先等待 in-flight 的 process()
        // 全部完成 append 後再快照 buffer,避免在 stop 期間靜默丟失音訊。
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // 等待所有 in-flight process() 完成(逾時保護)
            let deadline = Date().addingTimeInterval(self.stopInFlightTimeout)
            while self.inFlightProcessingCount > 0 && Date() < deadline {
                try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
            }

            if self.isTranscribing {
                // 轉寫正在進行中,標記等待最後一次轉寫完成
                self.pendingFinalTranscription = true
            } else {
                // 此時所有 in-flight 已完成,buffer 已是完整快照
                await self.transcribeFinalIfNeeded()
            }
        }
    }

    nonisolated func process(buffer: AVAudioPCMBuffer) {
        // H-1 修復:移除多餘的 audioProcessingQueue 中繼 hop。
        // 原本 CoreAudio tap → audioProcessingQueue.async → Task @MainActor 是雙重 hop,
        // 但 audioProcessingQueue 本身沒做任何計算,只是無謂排程延遲。
        // Task 建立成本極低,直接從 tap 執行緒建立 Task @MainActor 即可。
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // C-2 修復:追蹤 in-flight 數量,讓 stop() 能等待所有
            // 已在轉換管線中的 buffer 完成 append 後再快照。
            self.inFlightProcessingCount += 1
            defer { self.inFlightProcessingCount -= 1 }

            // 轉換音訊格式至 16kHz 單聲道 Float
            guard let converted = await self.audioConverterActor.convertTo16kHz(buffer: buffer), !converted.isEmpty else {
                return
            }

            // C-2 修復:即使 isRunning 已被 stop() 設為 false,仍 append buffer。
            // 因為這些 buffer 是在 stop() 之前就已進入管線,丟掉會造成資料缺漏。
            // stop() 會等待 inFlightProcessingCount 歸零再快照。
            self.accumulatedBuffer.append(contentsOf: converted)

            // 只有仍在錄音時才觸發部分轉寫(避免 stop 後仍跑昂貴的 whisper)
            guard self.isRunning else { return }

            // H-6 修復:模型尚未載入完成時,只 buffer 不觸發轉錄(避免 notInitialized 錯誤)
            guard self.isModelReady, self.isPartialTranscriptionEnabled else { return }

            let duration = Double(self.accumulatedBuffer.count) / Double(self.sampleRate)
            let shouldStartChunk = duration > self.partialTranscriptionMinDuration && !self.isTranscribing
            if shouldStartChunk {
                Task {
                    await self.transcribeChunkIfNeeded()
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

        // C-1 修復:只轉寫最近 30 秒的滑動視窗,而非整段 buffer。
        // 避免每 1 秒都重跑整段累積音訊,將成本從 O(n²) 降為 O(n)。
        // 最終轉寫 (transcribeFinalIfNeeded) 仍會處理完整 buffer 以保證正確性。
        let totalFrames = accumulatedBuffer.count
        let startIndex = max(totalFrames - partialWindowFrames, 0)
        let frames = Array(accumulatedBuffer[startIndex..<totalFrames])

        do {
            let startedAt = Date()
            let text = try await context.transcribe(samples: frames, language: selectedLanguage)
            recordTranscriptionDuration(Date().timeIntervalSince(startedAt), frameCount: frames.count)
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
        // 模型可能仍在載入(剛啟動就錄音),等載入完成
        await modelLoadTask?.value

        guard !isTranscribing else {
            pendingFinalTranscription = true
            return
        }
        guard !accumulatedBuffer.isEmpty else {
            completeStop()
            return
        }
        guard let context = whisperContext else {
            onTranscriptionResult?(.failure(modelLoadError ?? WhisperError.notInitialized))
            completeStop()
            return
        }

        isTranscribing = true
        pendingFinalTranscription = false
        let frames = accumulatedBuffer

        do {
            let startedAt = Date()
            let text = try await context.transcribe(samples: frames, language: selectedLanguage)
            recordTranscriptionDuration(Date().timeIntervalSince(startedAt), frameCount: frames.count)
            if !text.isEmpty {
                onTranscriptionResult?(.success(text))
            }
        } catch {
            logger.error("Whisper final 轉錄失敗: \(error.localizedDescription)")
            onTranscriptionResult?(.failure(error))
        }

        finalizeTranscriptionCycle()
        completeStop()
    }

    private func finalizeTranscriptionCycle() {
        isTranscribing = false
        let shouldRunFinal = !isRunning && pendingFinalTranscription

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
        var hasSuppliedData = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if hasSuppliedData {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasSuppliedData = true
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
