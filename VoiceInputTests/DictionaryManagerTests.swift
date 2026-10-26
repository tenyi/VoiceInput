
import XCTest
@testable import VoiceInput

final class DictionaryManagerTests: XCTestCase {
    var manager: DictionaryManager!
    var userDefaults: UserDefaults!
    private var storageKey: String!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        // Create an isolated storage key per test case
        suiteName = "test.suite.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        
        storageKey = "userDictionaryItems"
        manager = DictionaryManager(userDefaults: userDefaults, storageKey: storageKey)
    }

    override func tearDown() {
        if let suiteName = suiteName {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        userDefaults = nil
        storageKey = nil
        suiteName = nil
        manager = nil
        super.tearDown()
    }

    func testAddItem() {
        manager.addItem(original: "test", replacement: "tested")
        XCTAssertEqual(manager.items.count, 1)
        XCTAssertEqual(manager.items.first?.original, "test")
        XCTAssertEqual(manager.items.first?.replacement, "tested")
    }

    func testVocabularyTerms_excludesDisabledAndDeduplicates() {
        manager.addItems([
            DictionaryItem(original: "a", replacement: "VoiceInput"),
            DictionaryItem(original: "b", replacement: " VoiceInput "),
            DictionaryItem(original: "c", replacement: "Whisper", isEnabled: false),
            DictionaryItem(original: "d", replacement: "Typeless"),
            DictionaryItem(original: "e", replacement: "  ")
        ])
        XCTAssertEqual(manager.vocabularyTerms(), ["VoiceInput", "Typeless"])
    }

    func testDeleteItem() {
        manager.addItem(original: "test", replacement: "tested")
        let item = manager.items.first!
        manager.deleteItem(item)
        XCTAssertTrue(manager.items.isEmpty)
    }
    
    func testUpdateItem() {
        manager.addItem(original: "test", replacement: "tested")
        var item = manager.items.first!
        item.replacement = "updated"
        manager.updateItem(item)
        XCTAssertEqual(manager.items.first?.replacement, "updated")
    }

    func testReplacement() {
        manager.addItem(original: "foo", replacement: "bar")
        let result = manager.replaceText("This is foo.")
        XCTAssertEqual(result, "This is bar.")
    }

    func testCaseInsensitiveReplacement() {
        manager.addItem(original: "foo", replacement: "bar", isCaseSensitive: false)
        let result = manager.replaceText("This is FOO.")
        XCTAssertEqual(result, "This is bar.")
    }

    func testCaseSensitiveReplacement() {
        manager.addItem(original: "foo", replacement: "bar", isCaseSensitive: true)
        let result = manager.replaceText("This is FOO.")
        // 因為有區分大小寫，所以不會替換
        XCTAssertEqual(result, "This is FOO.")
        
        let result2 = manager.replaceText("This is foo.")
        XCTAssertEqual(result2, "This is bar.")
    }

    func testMultipleReplacements() {
        manager.addItem(original: "foo", replacement: "bar")
        manager.addItem(original: "baz", replacement: "qux")
        let result = manager.replaceText("foo and baz")
        XCTAssertEqual(result, "bar and qux")
    }
    
    func testLongerMatchPriority() {
        manager.addItem(original: "apple", replacement: "fruit")
        manager.addItem(original: "apple pie", replacement: "dessert")
        
        let result = manager.replaceText("I like apple pie")
        XCTAssertEqual(result, "I like dessert")
    }

    /// 英文詞條不應比對到單字內部
    func testLatinEntryDoesNotMatchInsideWord() {
        manager.addItem(original: "ai", replacement: "AI")
        XCTAssertEqual(manager.replaceText("he said ai"), "he said AI")
    }

    /// 中英混排時英文詞條仍能比對(中文字不視為邊界阻擋)
    func testLatinEntryMatchesNextToCJK() {
        manager.addItem(original: "ai", replacement: "AI")
        XCTAssertEqual(manager.replaceText("用ai寫程式"), "用AI寫程式")
    }

    /// 中文詞條維持子字串比對
    func testCJKEntryMatchesSubstring() {
        manager.addItem(original: "語音書入", replacement: "語音輸入")
        XCTAssertEqual(manager.replaceText("我用語音書入法"), "我用語音輸入法")
    }
}
