import Foundation
import Speech
import AVFoundation
import SwiftWhisper // 假設已安裝 SwiftWhisper 套件
import os

/// 使用 Whisper.cpp 的轉錄服務實作
class WhisperTranscriptionService: TranscriptionServiceProtocol, WhisperDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "WhisperService")

    var onTranscriptionResult: ((Result<String, Error>) -> Void)?

    private var whisper: Whisper?
    private var modelUrl: URL?
    private var securityScopedAccess = false
    
    // 用於累積音訊並進行批次處理
    private var accumulatedBuffer: [Float] = []
    private let sampleRate: Float = 16000.0 // Whisper 需要 16kHz
    
    // 簡單的 VAD 或分段邏輯 (這裡先用計時器或緩衝區大小來模擬串流)
    private var lastTranscriptionTime: Date = Date()
    // 每次累積多少秒的音訊後進行一次快速轉錄
    private let segmentDuration: TimeInterval = 0.5 
    
    private var isRunning = false
    
    init(modelURL: URL, language: String = "zh") {
        self.modelUrl = modelURL

        // 開始訪問 security-scoped resource
        securityScopedAccess = modelURL.startAccessingSecurityScopedResource()
        logger.info("開始訪問 security-scoped resource: \(self.securityScopedAccess)")
        logger.info("模型 URL: \(modelURL.path)")
        logger.info("模型 URL 是否存在: \(FileManager.default.fileExists(atPath: modelURL.path))")

        do {
            logger.info("正在載入 Whisper 模型...")

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

            let whisper = try Whisper(fromFileURL: modelURL)
            whisper.delegate = self

            // 設定參數
            whisper.params.language = .auto // 或指定語言
            // whisper.params.translate = false
            // whisper.params.print_special = false
            // whisper.params.print_progress = false
            // whisper.params.print_realtime = false
            // whisper.params.no_timestamps = true

            self.whisper = whisper
            logger.info("Whisper 模型載入成功")
        } catch {
            logger.error("無法載入 Whisper 模型: \(error.localizedDescription)")
            print("[WhisperTranscriptionService] 載入模型錯誤: \(error)")
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
        isRunning = true
        accumulatedBuffer.removeAll()
        lastTranscriptionTime = Date()
        logger.info("Whisper 服務已啟動")
    }
    
    func stop() {
        isRunning = false
        logger.info("Whisper 服務停止，累積音訊 frame 數: \(self.accumulatedBuffer.count)")
        // 停止時進行最後一次轉錄
        if !accumulatedBuffer.isEmpty {
            Task {
                await transcribe()
            }
        }
        logger.info("Whisper 服務已停止")
    }
    
    func process(buffer: AVAudioPCMBuffer) {
        guard isRunning else {
            logger.debug("Whisper 服務未運行，跳過處理")
            return
        }

        guard whisper != nil else {
            logger.error("Whisper 實例為 nil，無法處理音訊")
            print("[WhisperTranscriptionService] process: Whisper 為 nil!")
            return
        }

        // 1. 格式轉換: 將輸入 buffer (可能是 44.1/48kHz, stereo) 轉換為 16kHz mono float
        guard let convertedData = convertTo16kHz(buffer: buffer) else {
            logger.error("音訊格式轉換失敗")
            return
        }

        // 2. 累積音訊
        accumulatedBuffer.append(contentsOf: convertedData)
        logger.debug("已累積音訊，目前 frame 數: \(self.accumulatedBuffer.count)")

        // 3. 檢查是否達到處理門檻 (例如每 0.5 秒或累積一定量)
        let duration = Double(accumulatedBuffer.count) / Double(sampleRate)
        if duration > 1.0 { // 累積超過 1 秒才開始嘗試轉錄，避免太頻繁
             // 在此專案中，我們可能希望更即時的回饋。
             // 由於 whisper.cpp 的轉錄是阻塞的 (或是非同步但耗時)，
             // 對於即時串流，通常策略是：
             // A. 累積到一個句子結束 (VAD) -> 轉錄
             // B. 固定時間窗口 (Sliding Window) -> 轉錄

             // 或是我們簡單地：每次都轉錄整個累積 buffer (效能較差但最簡單)
             // 或是使用 SwiftWhisper 的 stream 支援 (如果有的話，或是自己切分)

            // 這裡採用: 只有在停止時才做完整轉錄? 不，需求是即時回饋。
            // 由於 SwiftWhisper 主要是針對檔案或整段 buffer，
            // 我們可以嘗試將目前的 buffer copy 出來進行轉錄。

            // 優化策略: 背景執行轉錄
            Task {
                await transcribeAsync()
            }
        }
    }
    
    private var isTranscribing = false

    private func transcribeAsync() async {
        guard !isTranscribing, !accumulatedBuffer.isEmpty else {
            logger.warning("跳過轉錄: isTranscribing=\(self.isTranscribing), bufferEmpty=\(self.accumulatedBuffer.isEmpty)")
            return
        }

        guard let whisperInstance = self.whisper else {
            logger.error("Whisper 實例為 nil，無法轉錄")
            print("[WhisperTranscriptionService] Whisper 實例為 nil!")
            return
        }

        isTranscribing = true

        let frames = accumulatedBuffer // Copy
        logger.info("開始轉錄，音訊 frame 數量: \(frames.count)")

        // 執行轉錄 (這可能會花一點時間)
        do {
            try await whisperInstance.transcribe(audioFrames: frames)
            logger.info("轉錄完成")
        } catch {
            logger.error("轉錄失敗: \(error.localizedDescription)")
            print("[WhisperTranscriptionService] 轉錄錯誤: \(error)")
            onTranscriptionResult?(.failure(error))
        }

        isTranscribing = false
    }
    
    // 異步版本 (用於 stop 時)
    private func transcribe() async {
         guard let whisperInstance = self.whisper, !accumulatedBuffer.isEmpty else {
             logger.warning("transcribe: Whisper 為 nil 或 buffer 為空")
             return
         }
         logger.info("transcribe: 開始最終轉錄，frame 數: \(self.accumulatedBuffer.count)")
         do {
             try await whisperInstance.transcribe(audioFrames: accumulatedBuffer)
             logger.info("transcribe: 最終轉錄完成")
         } catch {
             logger.error("transcribe: 最終轉錄失敗: \(error.localizedDescription)")
             onTranscriptionResult?(.failure(error))
         }
    }

    // MARK: - WhisperDelegate

    func whisper(_ whisper: Whisper, didUpdateProgress progress: Double, inRange range: Range<Int>?) {
        logger.debug("Whisper 進度: \(progress * 100)%")
    }

    func whisper(_ whisper: Whisper, didProcessNewSegments segments: [Segment], atIndex index: Int) {
        // 收到新的轉錄片段
        let text = segments.map { $0.text }.joined(separator: " ")
        logger.info("Whisper 部分結果: \(text)")
        print("[WhisperTranscriptionService] 部分結果: \(text)")
        onTranscriptionResult?(.success(text))
    }

    func whisper(_ whisper: Whisper, didCompleteWithSegments segments: [Segment]) {
        // 完成
        let text = segments.map { $0.text }.joined(separator: " ")
        logger.info("Whisper 最終結果: \(text)")
        print("[WhisperTranscriptionService] 最終結果: \(text)")
        onTranscriptionResult?(.success(text))
    }

    func whisper(_ whisper: Whisper, didErrorWith error: Error) {
        logger.error("Whisper 錯誤: \(error.localizedDescription)")
        print("[WhisperTranscriptionService] Whisper 錯誤: \(error)")
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
