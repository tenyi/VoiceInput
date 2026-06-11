import Foundation
import Testing
@testable import VoiceInput

/// HistoryManager 單元測試
/// 重點覆蓋 B4.1-B4.4: 新增/刪除/清空/損壞資料載入
/// 使用 MockFileSystem 避免依賴真實磁碟
@Suite("HistoryManager")
struct HistoryManagerTests {

    // MARK: - B4.1 addHistoryIfNeeded 路徑測試

    /// 文字成功加入歷史紀錄
    @Test("addHistoryIfNeeded 正常文字成功加入")
    @MainActor
    func addHistory_normalText_added() {
        let fs = MockFileSystem()
        let manager = HistoryManager(fileSystem: fs)

        manager.addHistoryIfNeeded("你好世界")

        #expect(manager.transcriptionHistory.count == 1)
        #expect(manager.transcriptionHistory[0].text == "你好世界")
    }

    /// 空白字串不加入歷史
    @Test("addHistoryIfNeeded 空白字串不加入")
    @MainActor
    func addHistory_emptyText_notAdded() {
        let fs = MockFileSystem()
        let manager = HistoryManager(fileSystem: fs)

        manager.addHistoryIfNeeded("   ")

        #expect(manager.transcriptionHistory.isEmpty)
    }

    /// 超過 10 筆時最舊的會被移除
    @Test("addHistoryIfNeeded 超過 10 筆時保留最近 10 筆")
    @MainActor
    func addHistory_over10_retainsLatest10() {
        let fs = MockFileSystem()
        let manager = HistoryManager(fileSystem: fs)

        for i in 1...11 {
            manager.addHistoryIfNeeded("第 \(i) 筆")
        }

        #expect(manager.transcriptionHistory.count == 10)
        // 最新的在最前面
        #expect(manager.transcriptionHistory[0].text == "第 11 筆")
        // 最舊的「第 1 筆」應被移除
        #expect(manager.transcriptionHistory.last?.text == "第 2 筆")
    }

    // MARK: - B4.2 deleteHistoryItem 測試

    /// 刪除單筆後其餘項目順序正確
    @Test("deleteHistoryItem 刪除單筆後其餘順序正確")
    @MainActor
    func deleteHistory_removesTargetItem() {
        let fs = MockFileSystem()
        let manager = HistoryManager(fileSystem: fs)
        manager.addHistoryIfNeeded("AAA")
        manager.addHistoryIfNeeded("BBB")
        manager.addHistoryIfNeeded("CCC")

        // 刪除中間那筆
        let targetItem = manager.transcriptionHistory[1]
        manager.deleteHistoryItem(targetItem)

        #expect(manager.transcriptionHistory.count == 2)
        #expect(manager.transcriptionHistory[0].text == "CCC")
        #expect(manager.transcriptionHistory[1].text == "AAA")
    }

    /// 刪除不存在的項目不影響現有資料
    @Test("deleteHistoryItem 刪除不存在項目不影響現有資料")
    @MainActor
    func deleteHistory_nonExistent_noChange() {
        let fs = MockFileSystem()
        let manager = HistoryManager(fileSystem: fs)
        manager.addHistoryIfNeeded("only item")

        let fakeItem = TranscriptionHistoryItem(text: "不存在", createdAt: Date())
        manager.deleteHistoryItem(fakeItem)

        #expect(manager.transcriptionHistory.count == 1)
        #expect(manager.transcriptionHistory[0].text == "only item")
    }

    // MARK: - B4.3 clearHistory 測試

    /// 注意: HistoryManager 沒有 clearHistory 方法,測試手動清空的行為
    /// 透過 deleteHistoryItem 逐一刪除來驗證空列表狀態
    @Test("刪除所有項目後列表為空")
    @MainActor
    func deleteAll_resultsInEmptyList() {
        let fs = MockFileSystem()
        let manager = HistoryManager(fileSystem: fs)
        manager.addHistoryIfNeeded("A")
        manager.addHistoryIfNeeded("B")

        for item in manager.transcriptionHistory {
            manager.deleteHistoryItem(item)
        }

        #expect(manager.transcriptionHistory.isEmpty)
    }

    // MARK: - B4.4 loadHistory 損壞資料測試

    /// 載入損壞 JSON 時回退到空陣列(對應 H-2 修復)
    @Test("loadTranscriptionHistory 損壞 JSON 回退到空陣列")
    @MainActor
    func loadHistory_corruptedData_fallsBackToEmpty() {
        let fs = MockFileSystem()
        let fileURL = URL(fileURLWithPath: "/mock/ApplicationSupport/VoiceInput/transcription_history.json")
        // 寫入無效 JSON
        fs.files[fileURL] = Data("this is not valid json".utf8)

        let manager = HistoryManager(fileSystem: fs)

        #expect(manager.transcriptionHistory.isEmpty)
    }
}
