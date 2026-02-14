import AVFoundation
import Speech
import Combine
import AVFAudio

/// 負責處理麥克風輸入與權限管理的音訊引擎
/// This class handles microphone input and permission management.
class AudioEngine: ObservableObject {
    /// AVAudioEngine 實例，用於處理音訊流
    private var audioEngine = AVAudioEngine()
    /// 麥克風輸入節點
    private var inputNode: AVAudioInputNode?

    /// 是否正在錄音
    @Published var isRecording = false
    /// 是否已取得麥克風與語音識別權限
    @Published var permissionGranted = false

    /// 檢查並請求麥克風與語音識別權限
    /// Checks and requests microphone and speech recognition permissions.
    func checkPermission() {
        // 先請求麥克風權限
        requestMicrophonePermission { [weak self] micGranted in
            // 再請求語音識別權限
            SFSpeechRecognizer.requestAuthorization { authStatus in
                DispatchQueue.main.async {
                    // 必須兩個權限都同意才能使用
                    self?.permissionGranted = micGranted && (authStatus == .authorized)
                    if !self!.permissionGranted {
                        print("權限不足 - 麥克風: \(micGranted), 語音識別: \(authStatus == .authorized)")
                    }
                }
            }
        }
    }

    /// 請求麥克風使用權限
    /// Requests microphone usage permission.
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        // 檢查目前的授權狀態
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            // 尚未決定，請求權限
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            // 被拒絕或受限
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    /// 開始錄音
    /// Starts recording audio.
    /// - Parameter callback: 錄音數據的回調閉包 (Callback for audio buffer)
    func startRecording(callback: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard permissionGranted else { return }
        
        inputNode = audioEngine.inputNode
        let recordingFormat = inputNode?.outputFormat(forBus: 0)
        
        // 安裝 Tap 以擷取音訊緩衝區
        inputNode?.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, when) in
            callback(buffer)
        }
        
        try audioEngine.start()
        isRecording = true
    }
    
    /// 停止錄音
    /// Stops recording.
    func stopRecording() {
        inputNode?.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false
    }
}
