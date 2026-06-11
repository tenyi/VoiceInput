import Foundation
import Testing
import Cocoa
@testable import VoiceInput

/// InputSimulator 單元測試
/// 重點覆蓋 B3.3 剪貼簿備份與還原 / B3.4 文字輸入 / B3.5 競態保護
@Suite("InputSimulator")
struct InputSimulatorTests {

    // MARK: - B3.3 剪貼簿備份與還原

    /// pasteText 應清空剪貼簿並寫入新文字
    @Test("pasteText 清空剪貼簿並寫入新文字")
    @MainActor
    func pasteText_clearsAndWritesNewText() {
        let mockPasteboard = MockPasteboard()
        let simulator = InputSimulator()
        simulator.pasteboard = mockPasteboard
        simulator.simulateKeyEventsOverride = { }

        simulator.pasteText("hello world")

        #expect(mockPasteboard.clearContentsCallCount == 1)
        #expect(mockPasteboard.setStringCalls.count == 1)
        #expect(mockPasteboard.setStringCalls[0].string == "hello world")
        #expect(mockPasteboard.setStringCalls[0].type == .string)
    }

    /// restoreClipboardIfNeeded:空快照時不呼叫 writeObjects
    @Test("restoreClipboardIfNeeded 空快照時不寫回任何項目")
    @MainActor
    func restoreClipboard_emptySnapshots_noWriteBack() {
        let mockPasteboard = MockPasteboard()
        mockPasteboard.mockChangeCount = 5
        let simulator = InputSimulator()
        simulator.pasteboard = mockPasteboard

        simulator.restoreClipboardIfNeeded(initialChangeCount: 5, snapshots: [])

        // clearContents 被呼叫(writeObjects 不被呼叫)
        #expect(mockPasteboard.clearContentsCallCount == 1)
        #expect(mockPasteboard.writeObjectsCalls.isEmpty)
    }

    /// restoreClipboardIfNeeded:有快照且 changeCount 未變時,還原原始項目
    @Test("restoreClipboardIfNeeded 有快照且 changeCount 不變時還原原始內容")
    @MainActor
    func restoreClipboard_withSnapshots_restoresOriginal() {
        let mockPasteboard = MockPasteboard()
        mockPasteboard.mockChangeCount = 3

        // 模擬原始剪貼簿有一個 string 項目
        let originalItem = NSPasteboardItem()
        originalItem.setString("old text", forType: .string)
        let snapshots: [[NSPasteboard.PasteboardType: Data]] = [
            [.string: Data("old text".utf8)]
        ]

        let simulator = InputSimulator()
        simulator.pasteboard = mockPasteboard

        simulator.restoreClipboardIfNeeded(initialChangeCount: 3, snapshots: snapshots)

        // clearContents + writeObjects 都被呼叫
        #expect(mockPasteboard.clearContentsCallCount == 1)
        #expect(mockPasteboard.writeObjectsCalls.count == 1)
    }

    // MARK: - B3.4 文字輸入測試

    /// insertText 應呼叫 simulateKeyEventsOverride(mock 攔截 CGEvent)
    @Test("insertText 觸發 simulateKeyEventsOverride")
    @MainActor
    func insertText_triggersKeyEventsOverride() {
        let simulator = InputSimulator()
        simulator.pasteboard = MockPasteboard()
        var keyEventsCalled = false
        simulator.simulateKeyEventsOverride = { keyEventsCalled = true }

        simulator.insertText("test")

        #expect(keyEventsCalled)
    }

    /// insertText 應透過 pasteText 將文字寫入剪貼簿
    @Test("insertText 將文字寫入剪貼簿")
    @MainActor
    func insertText_writesTextToPasteboard() {
        let mockPasteboard = MockPasteboard()
        let simulator = InputSimulator()
        simulator.pasteboard = mockPasteboard
        simulator.simulateKeyEventsOverride = { }

        simulator.insertText("你好世界")

        #expect(mockPasteboard.setStringCalls.count == 1)
        #expect(mockPasteboard.setStringCalls[0].string == "你好世界")
    }

    // MARK: - B3.5 剪貼簿競態測試

    /// changeCount 被外部修改時,restoreClipboardIfNeeded 不應還原
    @Test("restoreClipboardIfNeeded changeCount 被外部修改時不還原")
    @MainActor
    func restoreClipboard_changeCountChanged_doesNotRestore() {
        let mockPasteboard = MockPasteboard()
        // 模擬外部修改:changeCount 已從 3 變為 7
        mockPasteboard.mockChangeCount = 7
        let snapshots: [[NSPasteboard.PasteboardType: Data]] = [
            [.string: Data("old text".utf8)]
        ]

        let simulator = InputSimulator()
        simulator.pasteboard = mockPasteboard

        simulator.restoreClipboardIfNeeded(initialChangeCount: 3, snapshots: snapshots)

        // changeCount 不符 → 不呼叫 clearContents 也不呼叫 writeObjects
        #expect(mockPasteboard.clearContentsCallCount == 0)
        #expect(mockPasteboard.writeObjectsCalls.isEmpty)
    }
}
