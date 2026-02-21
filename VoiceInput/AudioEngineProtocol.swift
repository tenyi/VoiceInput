import AVFoundation

/// 音訊引擎協定，用於分離實體麥克風與測試環境
protocol AudioEngineProtocol: AnyObject {
    /// 是否正在錄音
    var isRecording: Bool { get set }
    /// 是否已取得麥克風與語音識別權限
    var permissionGranted: Bool { get set }
    /// 可用的音訊輸入設備列表
    var availableInputDevices: [AudioInputDevice] { get set }
    /// 當前選擇的音訊輸入設備
    var selectedDeviceID: String? { get set }

    /// 檢查並請求麥克風與語音識別權限
    func checkPermission(completion: ((Bool) -> Void)?)
    
    /// 刷新可用的音訊輸入設備列表
    func refreshAvailableDevices()
    
    /// 開始錄音
    func startRecording(callback: @escaping (AVAudioPCMBuffer) -> Void) throws
    
    /// 停止錄音
    func stopRecording()
}
