import Foundation
import os

#if canImport(whisper)
import whisper
#else
#error("Unable to import whisper module. Please check whisper.xcframework linkage.")
#endif

actor WhisperContext {
    private var context: OpaquePointer?
    private var languageCString: [CChar]?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "WhisperContext")

    init(modelPath: String) throws {
        var params = whisper_context_default_params()
#if targetEnvironment(simulator)
        params.use_gpu = false
#else
        params.flash_attn = true
#endif

        guard let context = whisper_init_from_file_with_params(modelPath, params) else {
            logger.error("無法載入 whisper 模型: \(modelPath)")
            throw WhisperError.modelLoadFailed
        }

        self.context = context
    }

    deinit {
        if let context {
            whisper_free(context)
        }
    }

    func transcribe(samples: [Float], language: String?) throws -> String {
        guard let context else {
            throw WhisperError.notInitialized
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true
        params.single_segment = false
        params.temperature = 0.2
        params.offset_ms = 0
        params.n_threads = Int32(Self.pCoreCount)

        if let code = whisperLanguageCode(from: language) {
            languageCString = Array(code.utf8CString)
            params.language = languageCString?.withUnsafeBufferPointer { $0.baseAddress }
        } else {
            languageCString = nil
            params.language = nil
        }

        whisper_reset_timings(context)
        let result = samples.withUnsafeBufferPointer { buffer in
            whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
        }
        languageCString = nil

        guard result == 0 else {
            logger.error("whisper_full 失敗，result=\(result)")
            throw WhisperError.whisperCoreFailed
        }

        let count = whisper_full_n_segments(context)
        var text = ""
        text.reserveCapacity(Int(count) * 8)
        for i in 0..<count {
            if let segment = whisper_full_get_segment_text(context, i) {
                text += String(cString: segment)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func whisperLanguageCode(from selectedLanguage: String?) -> String? {
        guard let selectedLanguage else { return nil }

        switch selectedLanguage {
        case "zh-TW", "zh-CN":
            return "zh"
        case "en-US":
            return "en"
        case "ja-JP":
            return "ja"
        default:
            return nil
        }
    }

    /// L-2 修復:使用 Apple Silicon P-core 數量作為 whisper 執行緒數,
    /// 而非全部核心 - 2。whisper.cpp 主要受計算瓶頸限制,P-core 效能遠優於 E-core。
    private static let pCoreCount: Int = {
        var size = MemoryLayout<Int32>.size
        var count: Int32 = 0
        sysctlbyname("hw.perflevel0.physicalcpu", &count, &size, nil, 0)
        // Fallback:若 sysctl 回傳 0 (非 Apple Silicon),使用全部核心 - 2
        return count > 0 ? Int(count) : max(1, ProcessInfo.processInfo.processorCount - 2)
    }()
}
