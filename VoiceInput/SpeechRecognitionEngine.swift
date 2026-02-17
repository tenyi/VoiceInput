import Foundation

/// 語音識別引擎選項
enum SpeechRecognitionEngine: String, CaseIterable, Identifiable {
    case apple = "Apple 系統語音辨識"
    case whisper = "Whisper (Local)"

    var id: String { self.rawValue }
}
