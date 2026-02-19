import Foundation

// MARK: - T3-1：轉錄服務配置（用於比對引擎/模型/語言，決定是否重建服務）

/// 轉錄服務的完整配置描述
/// 只要任一欄位變更，就應重建轉錄服務實例
struct TranscriptionConfig: Equatable {
    /// 辨識引擎類型（Apple SFSpeech / Whisper）
    let engine: SpeechRecognitionEngine
    /// Whisper 模型檔案路徑（Apple 引擎不使用）
    let modelPath: String
    /// 辨識語言（如 "zh-TW", "en-US"）
    let language: String
}
