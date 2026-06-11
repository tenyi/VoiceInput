import Cocoa

/// NSPasteboard 抽象協定,用於分離剪貼簿操作與測試環境
/// 設計目的:在單元測試中注入 mock,避免依賴系統全域剪貼簿
protocol PasteboardProtocol: AnyObject {
    /// 剪貼簿變更計數(每次修改會遞增,用於偵測外部修改)
    var changeCount: Int { get }
    /// 目前剪貼簿中的項目
    var pasteboardItems: [NSPasteboardItem]? { get }
    /// 清空剪貼簿內容
    @discardableResult
    func clearContents() -> Int
    /// 寫入字串到剪貼簿
    @discardableResult
    func setString(_ string: String, forType: NSPasteboard.PasteboardType) -> Bool
    /// 寫入多個物件到剪貼簿
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: PasteboardProtocol {}
