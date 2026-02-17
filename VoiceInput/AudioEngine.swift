import AVFoundation
import Speech
import Combine
import AVFAudio
import os
import CoreAudio

/// 負責處理麥克風輸入與權限管理的音訊引擎
/// This class handles microphone input and permission management.
class AudioEngine: ObservableObject {
    /// 單例實例
    static let shared = AudioEngine()
    
    /// 日誌記錄器
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "AudioEngine")

    /// AVAudioEngine 實例，用於處理音訊流
    private var audioEngine = AVAudioEngine()
    /// 麥克風輸入節點
    private var inputNode: AVAudioInputNode?

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

    private var deviceObserver: NSObjectProtocol?

    private init() {
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

    deinit {
        if let observer = deviceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - 設備監聽

    /// 設置設備連接/斷開通知監聽
    private func setupDeviceNotificationObserver() {
        // 監聽設備連接
        deviceObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAvailableDevices()
        }

        // 監聽設備斷開
        NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAvailableDevices()
        }
    }

    // MARK: - 設備列表

    /// 刷新可用的音訊輸入設備列表
    func refreshAvailableDevices() {
        // 使用 AVCaptureDevice 獲取可用的音訊輸入設備
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
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

    /// 獲取當前選擇的設備
    private func getSelectedDevice() -> AVCaptureDevice? {
        guard let deviceID = selectedDeviceID else {
            return AVCaptureDevice.default(for: .audio)
        }

        // 查找指定 ID 的設備
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )

        return discoverySession.devices.first { $0.uniqueID == deviceID }
    }

    // MARK: - 錄音控制

    /// 開始錄音
    /// Starts recording audio.
    /// - Parameter callback: 錄音數據的回調閉包 (Callback for audio buffer)
    func startRecording(callback: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard permissionGranted else { return }

        // 先停止現有的引擎（如果有的話）
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        // 重新創建 AVAudioEngine 以確保使用最新的設備設置
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode

        // 獲取選擇的設備並設置
        if let device = getSelectedDevice() {
            // 嘗試設置輸入設備
            // 注意: 在 macOS 上，AVAudioEngine 會自動使用系統默認設備
            // 如果需要指定設備，需要使用 Core Audio API
            // 這裡我們使用簡化的方式：通過重新配置 inputNode
            setInputDevice(device)
        }

        let recordingFormat = inputNode?.outputFormat(forBus: 0)

        // 安裝 Tap 以擷取音訊緩衝區
        inputNode?.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, when) in
            callback(buffer)
        }

        try audioEngine.start()
        isRecording = true
    }

    /// 設置輸入設備
    /// 使用 Core Audio API 將指定的設備設置為系統默認輸入設備
    private func setInputDevice(_ device: AVCaptureDevice) {
        // 獲取所有音訊設備並查找匹配的設備 ID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            logger.error("無法獲取音訊設備列表大小，錯誤碼: \(status)")
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &devices
        )

        guard status == noErr else {
            logger.error("無法獲取音訊設備列表，錯誤碼: \(status)")
            return
        }

        // 查找匹配的設備 ID
        var targetDeviceID: AudioDeviceID = 0

        for dev in devices {
            // 獲取設備名稱
            var namePropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var deviceName: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)

            let nameStatus = AudioObjectGetPropertyData(
                dev,
                &namePropertyAddress,
                0,
                nil,
                &nameSize,
                &deviceName
            )

            if nameStatus == noErr && deviceName == device.localizedName as CFString {
                targetDeviceID = dev
                break
            }
        }

        guard targetDeviceID != 0 else {
            logger.warning("找不到匹配的音訊設備: \(device.localizedName)")
            return
        }

        // 設置為系統默認輸入設備
        var defaultInputPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableDeviceID = targetDeviceID
        status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputPropertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )

        if status == noErr {
            logger.info("已成功切換輸入設備: \(device.localizedName)")
        } else {
            logger.error("無法切換輸入設備: \(device.localizedName), 錯誤碼: \(status)")
        }
    }

    /// 停止錄音
    /// Stops recording.
    func stopRecording() {
        inputNode?.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false
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
