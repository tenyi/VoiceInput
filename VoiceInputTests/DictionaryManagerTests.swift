import XCTest
@testable import VoiceInput

// MARK: - DictionaryManager 單元測試

/// 測試 DictionaryManager 的 SQLite 儲存、CRUD 操作與文字置換邏輯
///
/// 每個測試案例使用獨立的暫存資料庫路徑，確保測試互不干擾
final class DictionaryManagerTests: XCTestCase {

    /// 受測物件
    var manager: DictionaryManager!

    /// 每個測試使用獨立資料庫路徑（避免測試間互相污染）
    var dbURL: URL!

    // MARK: - 測試生命週期

    override func setUp() {
        super.setUp()
        // 在暫存目錄建立唯一的資料庫檔案
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DictionaryManagerTests_\(UUID().uuidString).sqlite")
        manager = DictionaryManager(databasePath: dbURL.path)
    }

    override func tearDown() {
        manager = nil
        // 刪除暫存資料庫
        try? FileManager.default.removeItem(at: dbURL)
        dbURL = nil
        super.tearDown()
    }

    // MARK: - 新增測試

    /// 新增一筆規則後，items 應包含該規則
    func testAddItem() {
        manager.addItem(original: "test", replacement: "tested")
        XCTAssertEqual(manager.items.count, 1)
        XCTAssertEqual(manager.items.first?.original, "test")
        XCTAssertEqual(manager.items.first?.replacement, "tested")
        XCTAssertTrue(manager.items.first?.isEnabled ?? false, "新增的規則預設應為啟用")
    }

    /// 新增多筆規則後，順序應與新增順序一致
    func testAddMultipleItemsMaintainsOrder() {
        manager.addItem(original: "alpha", replacement: "A")
        manager.addItem(original: "beta", replacement: "B")
        manager.addItem(original: "gamma", replacement: "C")

        XCTAssertEqual(manager.items.count, 3)
        XCTAssertEqual(manager.items[0].original, "alpha")
        XCTAssertEqual(manager.items[1].original, "beta")
        XCTAssertEqual(manager.items[2].original, "gamma")
    }

    // MARK: - 刪除測試

    /// 透過物件刪除後，items 應為空
    func testDeleteItemByObject() {
        manager.addItem(original: "test", replacement: "tested")
        let item = manager.items.first!
        manager.deleteItem(item)
        XCTAssertTrue(manager.items.isEmpty)
    }

    /// 透過 IndexSet 刪除（供 SwiftUI List onDelete 使用）
    func testDeleteItemByIndexSet() {
        manager.addItem(original: "first",  replacement: "1")
        manager.addItem(original: "second", replacement: "2")
        manager.addItem(original: "third",  replacement: "3")
        manager.deleteItem(at: IndexSet(integer: 1)) // 刪除 "second"
        XCTAssertEqual(manager.items.count, 2)
        XCTAssertEqual(manager.items[0].original, "first")
        XCTAssertEqual(manager.items[1].original, "third")
    }

    // MARK: - 更新測試

    /// 更新置換字串後，items 應反映變更
    func testUpdateItemReplacement() {
        manager.addItem(original: "test", replacement: "tested")
        var item = manager.items.first!
        item.replacement = "updated"
        manager.updateItem(item)
        XCTAssertEqual(manager.items.first?.replacement, "updated")
    }

    /// 停用規則後，isEnabled 應為 false
    func testUpdateItemDisable() {
        manager.addItem(original: "test", replacement: "tested")
        var item = manager.items.first!
        item.isEnabled = false
        manager.updateItem(item)
        XCTAssertFalse(manager.items.first?.isEnabled ?? true)
    }

    // MARK: - 持久化測試

    /// 重建 manager（使用同一資料庫路徑）後，資料應持久化
    func testPersistenceAcrossManagerInstances() {
        manager.addItem(original: "save", replacement: "me")

        // 建立另一個指向同一資料庫的 manager
        let newManager = DictionaryManager(databasePath: dbURL.path)
        XCTAssertEqual(newManager.items.count, 1)
        XCTAssertEqual(newManager.items.first?.original, "save")
        XCTAssertEqual(newManager.items.first?.replacement, "me")
    }

    // MARK: - 文字置換測試

    /// 基本置換功能
    func testBasicReplacement() {
        manager.addItem(original: "foo", replacement: "bar")
        let result = manager.replaceText("This is foo.")
        XCTAssertEqual(result, "This is bar.")
    }

    /// 置換應大小寫不區分
    func testCaseInsensitiveReplacement() {
        manager.addItem(original: "foo", replacement: "bar")
        XCTAssertEqual(manager.replaceText("This is FOO."), "This is bar.")
        XCTAssertEqual(manager.replaceText("This is Foo."), "This is bar.")
    }

    /// 同時置換多個規則
    func testMultipleSimultaneousReplacements() {
        manager.addItem(original: "foo", replacement: "bar")
        manager.addItem(original: "baz", replacement: "qux")
        let result = manager.replaceText("foo and baz")
        XCTAssertEqual(result, "bar and qux")
    }

    /// 較長的規則優先於較短的規則（避免短規則破壞長規則）
    func testLongerRuleHasPriorityOverShorterRule() {
        manager.addItem(original: "apple",     replacement: "fruit")
        manager.addItem(original: "apple pie", replacement: "dessert")

        // "apple pie" 應優先於 "apple"，結果應為 "dessert"，而非 "fruit pie"
        XCTAssertEqual(manager.replaceText("I like apple pie"), "I like dessert")
    }

    /// 停用的規則不應被套用
    func testDisabledRuleIsSkipped() {
        manager.addItem(original: "foo", replacement: "bar")
        var item = manager.items.first!
        item.isEnabled = false
        manager.updateItem(item)

        let result = manager.replaceText("This is foo.")
        XCTAssertEqual(result, "This is foo.", "停用的規則不應進行置換")
    }

    /// 規則不存在時，文字應原樣返回
    func testNoMatchReturnsOriginalText() {
        manager.addItem(original: "foo", replacement: "bar")
        let result = manager.replaceText("This is baz.")
        XCTAssertEqual(result, "This is baz.")
    }

    /// 無規則時，文字應原樣返回
    func testEmptyDictionaryReturnsOriginalText() {
        let result = manager.replaceText("hello world")
        XCTAssertEqual(result, "hello world")
    }
}
