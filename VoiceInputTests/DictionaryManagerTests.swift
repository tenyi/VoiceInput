
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
        manager.addItem(original: "foo", replacement: "bar")
        let result = manager.replaceText("This is FOO.")
        XCTAssertEqual(result, "This is bar.")
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
}
