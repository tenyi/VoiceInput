import AVFoundation

/// AVCaptureSession 抽象協定,用於分離實體視訊/音訊擷取管線與測試環境
/// 設計目的:在單元測試中注入 mock,避免依賴真實硬體啟動 capture pipeline
///
/// 注意:目前僅覆蓋 `AudioEngine.startRecording` 實際使用的方法;若日後
/// 需要更多 capture session 行為,再擴充此 protocol。
protocol CaptureSessionProtocol: AnyObject {
    /// 是否正在擷取
    var isRunning: Bool { get }

    /// 開始擷取(等同 AVCaptureSession.startRunning)
    func startRunning()

    /// 停止擷取(等同 AVCaptureSession.stopRunning)
    func stopRunning()

    /// 判斷是否能加入指定 input
    func canAddInput(_ input: AVCaptureInput) -> Bool

    /// 加入 input(例如麥克風裝置)
    func addInput(_ input: AVCaptureInput)

    /// 判斷是否能加入指定 output
    func canAddOutput(_ output: AVCaptureOutput) -> Bool

    /// 加入 output(例如音訊資料輸出)
    func addOutput(_ output: AVCaptureOutput)

    /// 開始批次設定(可一次加入多個 input/output 後再 commit)
    func beginConfiguration()

    /// 提交批次設定
    func commitConfiguration()
}

extension AVCaptureSession: CaptureSessionProtocol {}
