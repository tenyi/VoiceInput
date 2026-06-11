import Cocoa
@testable import VoiceInput

/// 測試用的 NSPasteboard mock
/// 可控制 changeCount 以模擬外部並行修改剪貼簿的情境
final class MockPasteboard: PasteboardProtocol {
    // MARK: - 測試觀察屬性

    /// clearContents 被呼叫次數
    private(set) var clearContentsCallCount = 0
    /// 所有 setString 呼叫的參數紀錄
    private(set) var setStringCalls: [(string: String, type: NSPasteboard.PasteboardType)] = []
    /// 所有 writeObjects 呼叫的參數紀錄
    private(set) var writeObjectsCalls: [[NSPasteboardWriting]] = []

    // MARK: - 可注入行為

    /// 模擬 changeCount;測試可手動遞增以模擬外部修改
    var mockChangeCount: Int = 0
    /// 模擬 pasteboardItems;測試可設定初始剪貼簿內容
    var mockPasteboardItems: [NSPasteboardItem]? = nil

    // MARK: - PasteboardProtocol

    var changeCount: Int { mockChangeCount }
    var pasteboardItems: [NSPasteboardItem]? { mockPasteboardItems }

    func clearContents() -> Int {
        clearContentsCallCount += 1
        return 0
    }

    func setString(_ string: String, forType: NSPasteboard.PasteboardType) -> Bool {
        setStringCalls.append((string, forType))
        return true
    }

    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool {
        writeObjectsCalls.append(objects)
        return true
    }
}
