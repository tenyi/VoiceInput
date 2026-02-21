import AVFoundation
@testable import VoiceInput

class MockAudioEngine: AudioEngineProtocol {
    var isRecording: Bool = false
    var permissionGranted: Bool = true
    var availableInputDevices: [AudioInputDevice] = [
        AudioInputDevice(id: nil, name: "系統預設", isDefault: true),
        AudioInputDevice(id: "mock-mic", name: "Mock 麥克風", isDefault: false)
    ]
    var selectedDeviceID: String? = nil
    
    var startRecordingShouldThrow: Bool = false
    var startRecordingCallback: ((AVAudioPCMBuffer) -> Void)?
    
    func checkPermission(completion: ((Bool) -> Void)?) {
        completion?(permissionGranted)
    }
    
    func refreshAvailableDevices() {
        // Mock doesn't need to do actual discovery
    }
    
    func startRecording(callback: @escaping (AVAudioPCMBuffer) -> Void) throws {
        if startRecordingShouldThrow {
            throw NSError(domain: "MockAudioEngineError", code: -1, userInfo: nil)
        }
        isRecording = true
        startRecordingCallback = callback
    }
    
    func stopRecording() {
        isRecording = false
        startRecordingCallback = nil
    }
    
    // Test helper
    func simulateAudioInput() {
        guard let callback = startRecordingCallback else { return }
        // Create an empty mock buffer
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        callback(buffer)
    }
}
