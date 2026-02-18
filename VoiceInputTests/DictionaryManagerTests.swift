
import XCTest
@testable import VoiceInput

final class DictionaryManagerTests: XCTestCase {
    var manager: DictionaryManager!
    var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // Create a temporary user defaults suite
        userDefaults = UserDefaults(suiteName: "DictionaryManagerTests")
        userDefaults.removePersistentDomain(forName: "DictionaryManagerTests")
        manager = DictionaryManager(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: "DictionaryManagerTests")
        userDefaults = nil
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
    
    func testPersistence() {
        manager.addItem(original: "save", replacement: "me")
        // Create a new manager with the same user defaults
        let newManager = DictionaryManager(userDefaults: userDefaults)
        XCTAssertEqual(newManager.items.count, 1)
        XCTAssertEqual(newManager.items.first?.original, "save")
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
