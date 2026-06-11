import XCTest
@testable import VoiceInput

// MARK: - HistoryManager 保存失敗測試

/// H-2 測試:驗證 HistoryManager 保存失敗時 lastSaveError 被設定
@MainActor
final class HistoryManagerSaveErrorTests: XCTestCase {

    /// 寫入永遠失敗的 mock file system
    struct FailingWriteFileSystem: FileSystemProtocol {
        let appSupport: URL? = URL(fileURLWithPath: NSTemporaryDirectory())

        var applicationSupportDirectory: URL? { appSupport }

        func fileExists(atPath path: String) -> Bool { false }
        func data(contentsOf url: URL) throws -> Data { Data() }
        func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]?) throws {}
        func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "模擬磁碟已滿"])
        }
        func removeItem(at url: URL) throws {}
        func copyItem(at srcURL: URL, to dstURL: URL) throws {}
        func getFileSize(at url: URL) throws -> Int64 { 0 }
    }

    func test_saveFailure_setsLastSaveError() {
        let manager = HistoryManager(fileSystem: FailingWriteFileSystem())
        // addHistoryIfNeeded 會同步呼叫 saveTranscriptionHistory
        manager.addHistoryIfNeeded("測試文字")
        XCTAssertNotNil(manager.lastSaveError, "保存失敗時 lastSaveError 應被設定")
        XCTAssertTrue(manager.lastSaveError?.contains("保存失敗") ?? false,
                       "lastSaveError 應包含「保存失敗」,實際: \(manager.lastSaveError ?? "")")
    }

    func test_saveFailure_preservesInMemoryData() {
        let manager = HistoryManager(fileSystem: FailingWriteFileSystem())
        manager.addHistoryIfNeeded("第一筆")
        // 即使保存失敗,記憶體中的資料仍應保留
        XCTAssertEqual(manager.transcriptionHistory.count, 1)
        XCTAssertEqual(manager.transcriptionHistory.first?.text, "第一筆")
    }

    func test_successfulSave_clearsLastError() {
        let manager = HistoryManager(fileSystem: DefaultFileSystem.shared)
        // 正常寫入不應設定 lastSaveError
        manager.addHistoryIfNeeded("正常文字 \(UUID().uuidString)")
        XCTAssertNil(manager.lastSaveError)
    }
}

// MARK: - ModelManager 載入損壞資料測試

/// H-2 測試:驗證 ModelManager decode 失敗時保留既有資料並設定 lastSaveError
@MainActor
final class ModelManagerLoadErrorTests: XCTestCase {

    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.modelmanager.\(UUID().uuidString)"
    }

    override func tearDown() {
        if let suiteName {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        suiteName = nil
        super.tearDown()
    }

    func test_loadModels_corruptedData_setsError() {
        let ud = UserDefaults(suiteName: suiteName)!
        // 注入損壞的 JSON 資料
        ud.set(Data("this is not json".utf8), forKey: "importedModels")

        let manager = ModelManager(userDefaults: ud, fileSystem: DefaultFileSystem.shared)

        XCTAssertNotNil(manager.lastSaveError, "載入損壞資料時 lastSaveError 應被設定")
        XCTAssertTrue(manager.lastSaveError?.contains("讀取失敗") ?? false,
                       "lastSaveError 應包含「讀取失敗」,實際: \(manager.lastSaveError ?? "")")
    }

    func test_loadModels_corruptedData_preservesEmptyModels() {
        let ud = UserDefaults(suiteName: suiteName)!
        ud.set(Data("corrupted!!!".utf8), forKey: "importedModels")

        let manager = ModelManager(userDefaults: ud, fileSystem: DefaultFileSystem.shared)

        // decode 失敗時不應清空 importedModels (保留既有資料)
        XCTAssertTrue(manager.importedModels.isEmpty, "decode 失敗時 importedModels 應維持初始空陣列")
    }

    func test_loadModels_validData_noError() {
        let ud = UserDefaults(suiteName: suiteName)!
        let validModels = [ImportedModel(name: "test-model", fileName: "test.bin", fileSize: 1024)]
        let validData = try! JSONEncoder().encode(validModels)
        ud.set(validData, forKey: "importedModels")

        let manager = ModelManager(userDefaults: ud, fileSystem: DefaultFileSystem.shared)

        XCTAssertNil(manager.lastSaveError, "載入有效資料時 lastSaveError 不應被設定")
        XCTAssertEqual(manager.importedModels.count, 1)
        XCTAssertEqual(manager.importedModels.first?.name, "test-model")
        XCTAssertEqual(manager.importedModels.first?.fileName, "test.bin")
    }
}
