import AVFoundation
import Speech
import Combine
import AVFAudio
import os
import CoreAudio

/// 負責處理麥克風輸入與權限管理的音訊引擎
/// This class handles microphone input and permission management.
class AudioEngine: ObservableObject, AudioEngineProtocol {
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
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAvailableDevices()
        }

        // 監聽設備斷開
        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
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
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        // 重新創建 AVAudioEngine 以確保使用最新的設備設置
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode

        // 若使用者指定設備，嘗試設置為預設輸入設備
        // 先用 UID 比對，若不一致再用設備名稱回退，避免不同 API 的識別碼格式不一致
        if let selectedDeviceID {
            let fallbackName = getSelectedDevice()?.localizedName
            let switched = setInputDevice(uniqueID: selectedDeviceID, fallbackName: fallbackName)
            if !switched {
                logger.warning("指定輸入設備切換失敗，將沿用系統當前預設輸入設備")
            }
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
    /// 使用 Core Audio API 將指定設備設置為系統默認輸入設備
    /// - Parameters:
    ///   - uniqueID: 首選識別碼（AVCapture uniqueID）
    ///   - fallbackName: 當 UID 不匹配時，用設備名稱做回退比對
    /// - Returns: 是否成功切換
    private func setInputDevice(uniqueID: String, fallbackName: String?) -> Bool {
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
            return false
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
            return false
        }

        // 先嘗試用 CoreAudio Device UID 匹配
        var targetDeviceID: AudioDeviceID = 0

        for dev in devices {
            var uidPropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var deviceUID: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>>.size)

            let uidStatus = AudioObjectGetPropertyData(
                dev,
                &uidPropertyAddress,
                0,
                nil,
                &uidSize,
                &deviceUID
            )

            if uidStatus == noErr, let uidString = deviceUID?.takeUnretainedValue() as String?, uidString == uniqueID {
                targetDeviceID = dev
                break
            }
        }

        // UID 對不上時，回退用設備名稱匹配（兼容不同 API 的識別碼格式）
        if targetDeviceID == 0, let fallbackName {
            for dev in devices {
                var namePropertyAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyDeviceNameCFString,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )

                var deviceName: Unmanaged<CFString>?
                var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
                let nameStatus = AudioObjectGetPropertyData(
                    dev,
                    &namePropertyAddress,
                    0,
                    nil,
                    &nameSize,
                    &deviceName
                )

                if nameStatus == noErr, let nameStr = deviceName?.takeUnretainedValue() as String?, nameStr == fallbackName {
                    targetDeviceID = dev
                    logger.info("UID 比對失敗，已以設備名稱回退匹配: \(fallbackName)")
                    break
                }
            }
        }

        guard targetDeviceID != 0 else {
            logger.warning("找不到匹配的音訊設備 uniqueID: \(uniqueID), fallbackName: \(fallbackName ?? "nil")")
            return false
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
            logger.info("已成功切換輸入設備 uniqueID: \(uniqueID)")
            return true
        } else {
            logger.error("無法切換輸入設備 uniqueID: \(uniqueID), 錯誤碼: \(status)")
            return false
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
