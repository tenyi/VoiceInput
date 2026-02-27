import AVFoundation
import Speech
import Combine
import AVFAudio
import os
import CoreAudio

/// 負責處理麥克風輸入與權限管理的音訊引擎
/// This class handles microphone input and permission management.
class AudioEngine: NSObject, ObservableObject, AudioEngineProtocol, AVCaptureAudioDataOutputSampleBufferDelegate {
    /// 單例實例
    static let shared = AudioEngine()
    
    /// 日誌記錄器
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "AudioEngine")

    /// AVCaptureSession 實例，用於處理音訊流
    private var captureSession: AVCaptureSession?
    /// 音訊資料輸出
    private var audioDataOutput: AVCaptureAudioDataOutput?

    /// 是否正在錄音
    @Published var isRecording = false
    /// 是否已取得麥克風與語音識別權限
    @Published var permissionGranted = false

    /// 可用的音訊輸入設備列表
    @Published var availableInputDevices: [AudioInputDevice] = []
    /// 當前選擇的音訊輸入設備 (nil = 使用系統預設)
    @Published var selectedDeviceID: String?

    /// 權限管理員
    private let permissionManager = PermissionManager.shared

    /// 儲存兩個設備通知的 observer token（connected + disconnected），確保 deinit 時能完整移除
    private var deviceObservers: [NSObjectProtocol] = []

    /// 音訊回調
    private var bufferCallback: ((AVAudioPCMBuffer) -> Void)?
    /// 截取佇列
    private let captureQueue = DispatchQueue(label: "com.voiceinput.audiocapture")

    private override init() {
        super.init()
        refreshAvailableDevices()
        setupDeviceNotificationObserver()
    }

    // MARK: - 權限管理

    /// 檢查並請求麥克風與語音識別權限
    /// 會依序彈出系統對話框請求權限，如果被拒絕則顯示提示視窗
    /// Checks and requests microphone and speech recognition permissions.
    func checkPermission(completion: ((Bool) -> Void)? = nil) {
        // 使用 PermissionManager 請求所有權限
        // 這會先檢查狀態，尚未決定時彈出系統對話框，已拒絕時顯示提示視窗
        permissionManager.requestAllPermissionsIfNeeded { [weak self] allGranted in
            self?.permissionGranted = allGranted
            completion?(allGranted)
        }
    }

    deinit {
        // 移除所有已註冊的 NotificationCenter observer，防止記憶體洩漏
        deviceObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - 設備監聽

    /// 設置設備連接/斷開通知監聽
    private func setupDeviceNotificationObserver() {
        // 監聽設備連接，並儲存 token 以便 deinit 時移除
        let connectedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAvailableDevices()
        }

        // 監聽設備斷開，同樣儲存 token 以防記憶體洩漏
        let disconnectedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAvailableDevices()
        }

        deviceObservers = [connectedObserver, disconnectedObserver]
    }

    // MARK: - 設備列表

    /// 刷新可用的音訊輸入設備列表
    func refreshAvailableDevices() {
        // 使用 AVCaptureDevice 獲取可用的音訊輸入設備
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        var devices: [AudioInputDevice] = []

        // 添加"系統預設"選項
        let defaultDevice = AudioInputDevice(
            id: nil,
            name: "系統預設",
            isDefault: true
        )
        devices.append(defaultDevice)

        // 添加所有可用的設備
        for device in discoverySession.devices {
            let audioDevice = AudioInputDevice(
                id: device.uniqueID,
                name: device.localizedName,
                isDefault: device == AVCaptureDevice.default(for: .audio)
            )
            devices.append(audioDevice)
        }

        DispatchQueue.main.async {
            self.availableInputDevices = devices

            // 如果當前選擇的設備已斷開，重置為系統預設
            if let selectedID = self.selectedDeviceID {
                let deviceExists = discoverySession.devices.contains { $0.uniqueID == selectedID }
                if !deviceExists {
                    self.selectedDeviceID = nil
                }
            }
        }
    }

    // MARK: - 錄音控制

    /// 取得目前選擇的 AVCaptureDevice（用於名稱回退比對）
    private func getSelectedDevice() -> AVCaptureDevice? {
        guard let deviceID = selectedDeviceID else {
            return AVCaptureDevice.default(for: .audio)
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        return discoverySession.devices.first { $0.uniqueID == deviceID }
    }

    /// 開始錄音
    /// Starts recording audio.
    /// - Parameter callback: 錄音數據的回調閉包 (Callback for audio buffer)
    func startRecording(callback: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard permissionGranted else { return }

        // 先停止現有的引擎（如果有的話）
        if let session = captureSession, session.isRunning {
            session.stopRunning()
        }

        self.bufferCallback = callback
        
        let session = AVCaptureSession()
        
        // 找到指定的實體麥克風裝置
        guard let device = getSelectedDevice() else {
            logger.error("無法取得指定的音訊輸入裝置")
            throw NSError(domain: "AudioEngineError", code: 2, userInfo: [NSLocalizedDescriptionKey: "無法綁定音訊裝置"])
        }
        
        logger.info("準備啟動錄音，目標麥克風: \(device.localizedName)")

        // 建立輸入
        let audioInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(audioInput) else {
            logger.error("無法將音訊輸入加入到 session 中")
            throw NSError(domain: "AudioEngineError", code: 3, userInfo: [NSLocalizedDescriptionKey: "設備不支持"])
        }
        session.addInput(audioInput)

        // 建立輸出
        let audioOutput = AVCaptureAudioDataOutput()
        guard session.canAddOutput(audioOutput) else {
            logger.error("無法將音訊輸出加入到 session 中")
            throw NSError(domain: "AudioEngineError", code: 4, userInfo: [NSLocalizedDescriptionKey: "系統不支持"])
        }
        audioOutput.setSampleBufferDelegate(self, queue: captureQueue)
        session.addOutput(audioOutput)

        self.captureSession = session
        self.audioDataOutput = audioOutput

        session.startRunning()
        
        DispatchQueue.main.async {
            self.isRecording = true
        }
    }

    /// 停止錄音
    /// Stops recording.
    func stopRecording() {
        captureSession?.stopRunning()
        captureSession = nil
        audioDataOutput = nil
        
        captureQueue.async { [weak self] in
            self?.bufferCallback = nil
        }
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let callback = bufferCallback else { return }

        // 解析 CMSampleBuffer 為 AVAudioPCMBuffer
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let format = AVAudioFormat(streamDescription: streamBasicDescription) else {
            logger.error("無法取得音訊格式描述")
            return
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            logger.error("無法分配 AVAudioPCMBuffer")
            return
        }
        pcmBuffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )

        if status == noErr {
            callback(pcmBuffer)
        } else {
            logger.error("複製 PCM 資料失敗，錯誤碼: \(status)")
        }
    }
}

/// 音訊輸入設備結構體
struct AudioInputDevice: Identifiable, Hashable {
    let id: String?  // nil 表示系統預設
    let name: String
    let isDefault: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AudioInputDevice, rhs: AudioInputDevice) -> Bool {
        lhs.id == rhs.id
    }
}
