import AVFoundation
import Speech
import Combine
@preconcurrency import AVFAudio
import os
import CoreAudio

/// AudioEngine 錯誤類型
enum AudioEngineError: Int, Error, LocalizedError, CustomNSError {
    case permissionNotGranted = 1
    case deviceNotAvailable = 2
    case sessionConfigurationFailed = 3
    case inputNotSupported = 4

    static var errorDomain: String { "AudioEngineError" }
    var errorCode: Int { rawValue }

    var errorDescription: String? {
        switch self {
        case .permissionNotGranted:
            return "麥克風或語音辨識權限尚未取得"
        case .deviceNotAvailable:
            return "無法取得指定的音訊輸入裝置"
        case .sessionConfigurationFailed:
            return "無法將音訊輸入加入到 session 中"
        case .inputNotSupported:
            return "設備不支持音訊輸入"
        }
    }
}

/// 負責處理麥克風輸入與權限管理的音訊引擎
/// This class handles microphone input and permission management.
class AudioEngine: NSObject, ObservableObject, AudioEngineProtocol, AVCaptureAudioDataOutputSampleBufferDelegate {
    /// 單例實例
    static let shared = AudioEngine()
    
    /// 日誌記錄器
    nonisolated private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "AudioEngine")

    /// AVCaptureSession 實例,用於處理音訊流
    /// B1.2.5:型別改為 protocol,以支援測試注入 MockAVCaptureSession
    /// B1.5:從 private 改為 internal,以便測試注入 mock session 模擬「錄音中」狀態
    var captureSession: CaptureSessionProtocol?
    /// 音訊資料輸出
    private var audioDataOutput: AVCaptureAudioDataOutput?

    /// 是否正在錄音
    @Published var isRecording = false
    /// 是否已取得麥克風權限（錄音的唯一必要權限）
    @Published var permissionGranted = false

    /// 可用的音訊輸入設備列表
    @Published var availableInputDevices: [AudioInputDevice] = []
    /// 當前選擇的音訊輸入設備 (nil = 使用系統預設)
    @Published var selectedDeviceID: String?

    /// 權限管理員
    /// J1.3:型別從 `PermissionManager` 改為 `PermissionManagerProtocol`,以支援測試注入 mock
    private let permissionManager: PermissionManagerProtocol

    /// 儲存兩個設備通知的 observer token（connected + disconnected），確保 deinit 時能完整移除
    private var deviceObservers: [NSObjectProtocol] = []

    /// 音訊回調
    /// B1.3:從 private 改為 internal,以便測試驗證 H-3 修復(失敗路徑不留下 callback)
    /// 主執行緒寫入、截取佇列讀取,以 callbackLock 保護
    var bufferCallback: ((AVAudioPCMBuffer) -> Void)? {
        get {
            callbackLock.lock()
            defer { callbackLock.unlock() }
            return _bufferCallback
        }
        set {
            callbackLock.lock()
            _bufferCallback = newValue
            callbackLock.unlock()
        }
    }
    nonisolated(unsafe) private var _bufferCallback: ((AVAudioPCMBuffer) -> Void)?
    nonisolated private let callbackLock = NSLock()
    /// 截取佇列
    private let captureQueue = DispatchQueue(label: "com.voiceinput.audiocapture")
    /// Session 控制佇列:stopRunning() 為阻塞呼叫,不在主執行緒執行
    let sessionQueue = DispatchQueue(label: "com.voiceinput.audiosession")

    /// Capture session 工廠;測試可注入 mock,生產環境使用 AVCaptureSession
    /// B1.2.5:把 `AVCaptureSession()` 直接建構抽成注入點,讓 startRecording 可被單元測試
    private let sessionFactory: () -> CaptureSessionProtocol

    /// 設備選擇覆寫;測試可注入 closure 回傳 nil 觸發「無可用裝置」失敗路徑
    /// B1.3:AVCaptureDevice 為 ObjC 抽象類別,無法 mock;透過此 override 注入
    /// 生產環境留 nil,走原本的 selectedDeviceID / AVCaptureDevice.default 邏輯
    var getSelectedDeviceOverride: (() -> AVCaptureDevice?)?

    /// - Parameters:
    ///   - sessionFactory: 自訂 capture session 建構邏輯;預設為 `AVCaptureSession()`。
    ///     測試可注入 `MockAVCaptureSession` 以攔截 `startRunning` / `stopRunning`。
    ///   - permissionManager: 權限管理員;預設為 `PermissionManager.shared`。
    ///     測試可注入 mock 來驗證 `checkPermission` 流程(J1.3)。
    init(
        sessionFactory: @escaping () -> CaptureSessionProtocol = { AVCaptureSession() },
        permissionManager: PermissionManagerProtocol = PermissionManager.shared
    ) {
        self.sessionFactory = sessionFactory
        self.permissionManager = permissionManager
        self.getSelectedDeviceOverride = nil
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
        // 仍一次請求所有權限（引導使用者完成設定），但錄音只取決於麥克風：
        // 語音辨識權限只有 Apple 引擎需要，輔助功能權限只有插入文字時需要（插入前另行檢查）
        permissionManager.requestAllPermissionsIfNeeded { [weak self] _ in
            guard let self else { return }
            let granted = self.permissionManager.checkMicrophoneStatus() == .authorized
            self.permissionGranted = granted
            completion?(granted)
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
            name: NSLocalizedString("audio.device.systemDefault", value: "系統預設", comment: "System default audio device"),
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

        // 已斷開裝置的選擇由 VoiceInputViewModel.reconcileSelectedInputDevice() 統一校正,
        // 避免 AudioEngine 與 ViewModel 的選擇不同步
        DispatchQueue.main.async {
            self.availableInputDevices = devices
        }
    }

    // MARK: - 錄音控制

    /// 取得目前選擇的 AVCaptureDevice（用於名稱回退比對）
    /// B1.6:從 private 改為 internal,以便測試直接驗證裝置選擇邏輯
    func getSelectedDevice() -> AVCaptureDevice? {
        // B1.3:測試可透過 getSelectedDeviceOverride 注入回傳值,跳過真實硬體
        if let override = getSelectedDeviceOverride {
            return override()
        }

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
        if ProcessInfo.processInfo.isRunningForPreview {
            logger.info("Xcode Preview 模式下，跳過實際錄音啟動")
            return
        }

        guard permissionGranted else {
            throw AudioEngineError.permissionNotGranted
        }

        // 先停止現有的引擎（如果有的話）
        if let session = captureSession, session.isRunning {
            session.stopRunning()
        }

        // H-3 修復:在所有可能 throw 的步驟完成後才設定 callback,
        // 避免失敗時留下 dangling callback (閉包捕獲的 self 造成記憶體洩漏)。

        let session = sessionFactory()

        // 找到指定的實體麥克風裝置
        guard let device = getSelectedDevice() else {
            logger.error("無法取得指定的音訊輸入裝置")
            throw AudioEngineError.deviceNotAvailable
        }
        
        logger.info("準備啟動錄音，目標麥克風: \(device.localizedName)")

        // 建立輸入
        let audioInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(audioInput) else {
            logger.error("無法將音訊輸入加入到 session 中")
            throw AudioEngineError.sessionConfigurationFailed
        }
        session.addInput(audioInput)

        // 建立輸出
        let audioOutput = AVCaptureAudioDataOutput()
        guard session.canAddOutput(audioOutput) else {
            logger.error("無法將音訊輸出加入到 session 中")
            throw AudioEngineError.inputNotSupported
        }
        audioOutput.setSampleBufferDelegate(self, queue: captureQueue)
        session.addOutput(audioOutput)

        self.captureSession = session
        self.audioDataOutput = audioOutput
        // H-3 修復:所有可能 throw 的步驟都通過後才設定 callback
        self.bufferCallback = callback

        session.startRunning()
        
        DispatchQueue.main.async {
            self.isRecording = true
        }
    }

    /// 停止錄音
    /// Stops recording.
    func stopRecording() {
        // 同步清除 callback,避免延遲清除時誤刪下一次錄音的 callback
        bufferCallback = nil
        if let session = captureSession {
            sessionQueue.async {
                session.stopRunning()
            }
        }
        captureSession = nil
        audioDataOutput = nil

        DispatchQueue.main.async {
            self.isRecording = false
        }
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    /// 於截取佇列觸發;callback 一律派送回主執行緒執行,
    /// 因為下游(ViewModel / TranscriptionManager / SFSpeech 服務)皆為 MainActor 隔離
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        callbackLock.lock()
        let currentCallback = _bufferCallback
        callbackLock.unlock()
        guard let callback = currentCallback else { return }

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
            DispatchQueue.main.async {
                callback(pcmBuffer)
            }
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
