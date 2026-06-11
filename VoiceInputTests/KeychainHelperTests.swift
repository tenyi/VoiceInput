import Foundation
import XCTest
@testable import VoiceInput

/// 測試 KeychainHelper 的真實 keychain 整合行為。
/// 每個測試用 UUID-based service name 確保隔離,並在 setUp/tearDown 清理。
///
/// 注意:這需要在 macOS 環境且有 keychain 存取權限(開發者環境預設有)。
/// 若未來導入 CI,需在 runner 上設定 keychain 或把這些測試加上 tag skip。
final class KeychainHelperTests: XCTestCase {

    private let keychain = KeychainHelper.shared
    private var testService: String = ""
    private let testAccount = "test-account"

    override func setUp() {
        super.setUp()
        // 每個測試用唯一 service 名稱,避免測試間互衝
        testService = "com.voiceinput.tests.\(UUID().uuidString)"
    }

    override func tearDown() {
        // 清理:即使測試失敗也嘗試刪除測試用 keychain 項目
        try? keychain.delete(service: testService, account: testAccount)
        try? keychain.delete(service: testService, account: "other-account")
        super.tearDown()
    }

    // MARK: - Save / Read

    func test_save_thenRead_returnsSavedValue() throws {
        try keychain.save("secret-value", service: testService, account: testAccount)
        let read = try keychain.read(service: testService, account: testAccount)
        XCTAssertEqual(read, "secret-value")
    }

    func test_save_overwriteExistingValue() throws {
        try keychain.save("first", service: testService, account: testAccount)
        try keychain.save("second", service: testService, account: testAccount)
        let read = try keychain.read(service: testService, account: testAccount)
        XCTAssertEqual(read, "second")
    }

    func test_read_nonExistentReturnsNil() throws {
        let read = try keychain.read(service: testService, account: testAccount)
        XCTAssertNil(read, "不存在的項目應回傳 nil,而不是拋出錯誤")
    }

    func test_read_emptyValueIsPreserved() throws {
        try keychain.save("", service: testService, account: testAccount)
        let read = try keychain.read(service: testService, account: testAccount)
        XCTAssertEqual(read, "")
    }

    func test_save_unicodeValueIsPreserved() throws {
        let value = "密碼 🔐 \n換行"
        try keychain.save(value, service: testService, account: testAccount)
        let read = try keychain.read(service: testService, account: testAccount)
        XCTAssertEqual(read, value)
    }

    // MARK: - 多個 account 互不干擾

    func test_save_multipleAccountsCoexist() throws {
        try keychain.save("a-value", service: testService, account: testAccount)
        try keychain.save("b-value", service: testService, account: "other-account")
        XCTAssertEqual(try keychain.read(service: testService, account: testAccount), "a-value")
        XCTAssertEqual(try keychain.read(service: testService, account: "other-account"), "b-value")
    }

    // MARK: - Delete

    func test_delete_removesItem() throws {
        try keychain.save("to-delete", service: testService, account: testAccount)
        try keychain.delete(service: testService, account: testAccount)
        let read = try keychain.read(service: testService, account: testAccount)
        XCTAssertNil(read)
    }

    func test_delete_nonExistentDoesNotThrow() throws {
        // 刪除不存在的項目不應拋出錯誤
        XCTAssertNoThrow(try keychain.delete(service: testService, account: testAccount))
    }

    // MARK: - TOCTOU 競態防護(C-5 修復)

    /// 同時 save 同一個 (service, account) 不應產生 duplicateItem 錯誤。
    /// 這是 C-5 修復驗證:即使 SecItemAdd 階段另一執行緒搶先新增,
    /// SecItemUpdate 重試路徑也應回傳成功。
    func test_concurrentSavesToSameAccount_allSucceed() throws {
        let iterations = 10
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for i in 0..<iterations {
            group.enter()
            queue.async {
                do {
                    try self.keychain.save("value-\(i)", service: self.testService, account: self.testAccount)
                } catch {
                    XCTFail("並行 save 應不拋出,實際為 \(error)")
                }
                group.leave()
            }
        }
        group.wait()

        // 最終值應是某一次寫入的結果
        let final = try keychain.read(service: testService, account: testAccount)
        XCTAssertNotNil(final)
        XCTAssertTrue(final?.hasPrefix("value-") ?? false)
    }

    // MARK: - 並發讀寫

    func test_concurrentReadsAndWrites_doNotCrash() throws {
        try keychain.save("initial", service: testService, account: testAccount)

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.mixed", attributes: .concurrent)

        for i in 0..<20 {
            group.enter()
            queue.async {
                if i % 2 == 0 {
                    try? self.keychain.save("value-\(i)", service: self.testService, account: self.testAccount)
                } else {
                    _ = try? self.keychain.read(service: self.testService, account: self.testAccount)
                }
                group.leave()
            }
        }
        group.wait()
    }
}

// MARK: - KeychainError LocalizedError 內容

final class KeychainErrorTests: XCTestCase {

    func test_encodingFailed_description() {
        XCTAssertEqual(KeychainError.encodingFailed.errorDescription, "資料編碼失敗")
    }

    func test_itemNotFound_description() {
        XCTAssertEqual(KeychainError.itemNotFound.errorDescription, "找不到 Keychain 項目")
    }

    func test_duplicateItem_description() {
        XCTAssertEqual(KeychainError.duplicateItem.errorDescription, "Keychain 項目已存在")
    }

    func test_unexpectedStatus_description_includesStatusCode() {
        let err = KeychainError.unexpectedStatus(-25291)
        XCTAssertTrue(err.errorDescription?.contains("-25291") ?? false)
    }
}
