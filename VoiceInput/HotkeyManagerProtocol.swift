import Foundation

/// 快捷鍵管理器協定，用於解耦與測試隔離
protocol HotkeyManagerProtocol: AnyObject {
    /// 當快捷鍵被按下時的閉包
    var onHotkeyPressed: (() -> Void)? { get set }
    
    /// 當快捷鍵被放開時的閉包
    var onHotkeyReleased: (() -> Void)? { get set }
    
    /// 設定快捷鍵選項
    func setHotkey(_ option: HotkeyOption)
    
    /// 開始監聽快捷鍵
    func startMonitoring()
    
    /// 停止監聽快捷鍵
    func stopMonitoring()
}
