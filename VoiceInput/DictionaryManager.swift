import Foundation
import SQLite3
import Combine
import SwiftUI

// MARK: - 字典項目資料結構

/// 單條字典置換規則
struct DictionaryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var original: String    // 原始字串（需被置換的文字）
    var replacement: String // 置換後的字串
    var isEnabled: Bool     // 是否啟用此規則

    init(id: UUID = UUID(), original: String, replacement: String, isEnabled: Bool = true) {
        self.id = id
        self.original = original
        self.replacement = replacement
        self.isEnabled = isEnabled
    }
}

// MARK: - DictionaryManager

/// 管理使用者自訂字典置換規則的管理器
/// 使用 SQLite 儲存，取代 UserDefaults（UserDefaults 不適合存放大量結構化資料）
class DictionaryManager: ObservableObject {

    /// 單例實例
    static let shared = DictionaryManager()

    /// 已發布的字典項目列表，UI 可直接訂閱
    @Published var items: [DictionaryItem] = []

    // MARK: - SQLite 相關

    /// SQLite 資料庫連線指標
    private var db: OpaquePointer?

    /// 自訂資料庫路徑（測試用，nil 表示使用預設路徑）
    private var _customDatabasePath: String?

    /// 資料庫檔案路徑（若有自訂路徑則使用，否則使用 App Support 預設路徑）
    private var dbPath: String {
        if let custom = _customDatabasePath { return custom }
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("VoiceInput", isDirectory: true)
        // 確保目錄存在
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dictionary.sqlite").path
    }

    // MARK: - 初始化

    /// 單例初始化（使用預設 App Support 資料庫路徑）
    init() {
        openDatabase()
        createTableIfNeeded()
        loadItems()
        migrateFromUserDefaultsIfNeeded()
    }

    /// 可測試性初始化（指定自訂資料庫路徑，供單元測試使用）
    /// - Parameter databasePath: SQLite 資料庫的絕對路徑
    init(databasePath: String) {
        // 覆寫 dbPath 計算屬性的路徑（透過儲存屬性）
        self._customDatabasePath = databasePath
        openDatabase()
        createTableIfNeeded()
        loadItems()
        // 測試環境不執行遷移（避免讀取真實 UserDefaults）
    }

    deinit {
        // 關閉資料庫連線
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    // MARK: - 資料庫操作

    /// 開啟（或建立）SQLite 資料庫
    private func openDatabase() {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(dbPath, &db, flags, nil) != SQLITE_OK {
            let errMsg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            print("[DictionaryManager] 無法開啟資料庫: \(errMsg)")
            db = nil
        }
    }

    /// 建立字典資料表（若不存在）
    private func createTableIfNeeded() {
        // id TEXT PRIMARY KEY: UUID 字串
        // original TEXT: 原始字串
        // replacement TEXT: 置換字串
        // is_enabled INTEGER: 1=啟用, 0=停用
        // sort_order INTEGER: 排序順序，保持用戶新增順序
        let sql = """
        CREATE TABLE IF NOT EXISTS dictionary_items (
            id TEXT PRIMARY KEY NOT NULL,
            original TEXT NOT NULL,
            replacement TEXT NOT NULL,
            is_enabled INTEGER NOT NULL DEFAULT 1,
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        """
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            let errMsg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            print("[DictionaryManager] 建立資料表失敗: \(errMsg)")
        }
    }

    /// 從 UserDefaults 遷移舊資料（一次性遷移）
    private func migrateFromUserDefaultsIfNeeded() {
        let legacyKey = "userDictionaryItems"
        guard let data = UserDefaults.standard.data(forKey: legacyKey),
              !data.isEmpty else { return }

        // 嘗試解碼舊格式
        guard let legacyItems = try? JSONDecoder().decode([DictionaryItem].self, from: data) else {
            // 解碼失敗，直接清除舊資料避免重複遷移
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return
        }

        // 若資料庫已有資料，不重複遷移
        guard items.isEmpty else {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return
        }

        // 將舊資料寫入 SQLite
        for (index, item) in legacyItems.enumerated() {
            insertItem(item, sortOrder: index)
        }

        // 清除 UserDefaults 舊資料
        UserDefaults.standard.removeObject(forKey: legacyKey)

        // 重新載入以更新 items
        loadItems()
        print("[DictionaryManager] 已從 UserDefaults 遷移 \(legacyItems.count) 筆字典資料至 SQLite")
    }

    // MARK: - CRUD 操作

    // MARK: - 執行緒輔助

    /// 統一的主執行緒排程方法：
    /// - 若呼叫端已在主執行緒（如 XCTest、SwiftUI 更新），立即同步執行，讓狀態立刻可見
    /// - 否則異步排程到主執行緒，確保 SwiftUI @Published 在主執行緒更新
    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    /// 從資料庫載入所有字典項目（依 sort_order 排序）
    private func loadItems() {
        guard let db = db else { return }

        let sql = "SELECT id, original, replacement, is_enabled FROM dictionary_items ORDER BY sort_order ASC, rowid ASC;"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        var result: [DictionaryItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            // 讀取各欄位
            let idStr   = String(cString: sqlite3_column_text(stmt, 0))
            let orig    = String(cString: sqlite3_column_text(stmt, 1))
            let repl    = String(cString: sqlite3_column_text(stmt, 2))
            let enabled = sqlite3_column_int(stmt, 3) == 1

            guard let uuid = UUID(uuidString: idStr) else { continue }
            result.append(DictionaryItem(id: uuid, original: orig, replacement: repl, isEnabled: enabled))
        }

        // 使用 runOnMain：XCTest 在主執行緒故同步更新，App 中從背景呼叫時才異步
        runOnMain { [weak self] in
            self?.items = result
        }
    }

    /// 插入新項目到資料庫
    private func insertItem(_ item: DictionaryItem, sortOrder: Int = Int.max) {
        guard let db = db else { return }

        // 若未指定 sortOrder，使用目前最大值 + 1
        let order: Int
        if sortOrder == Int.max {
            order = (items.count)
        } else {
            order = sortOrder
        }

        let sql = "INSERT OR REPLACE INTO dictionary_items (id, original, replacement, is_enabled, sort_order) VALUES (?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        // 綁定參數（SQLite 欄位索引從 1 開始）
        let idStr = item.id.uuidString as NSString
        sqlite3_bind_text(stmt, 1, idStr.utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (item.original as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (item.replacement as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 4, item.isEnabled ? 1 : 0)
        sqlite3_bind_int(stmt, 5, Int32(order))

        if sqlite3_step(stmt) != SQLITE_DONE {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("[DictionaryManager] 新增項目失敗: \(errMsg)")
        }
    }

    /// 更新資料庫中的既有項目
    private func updateItemInDB(_ item: DictionaryItem) {
        guard let db = db else { return }

        let sql = "UPDATE dictionary_items SET original = ?, replacement = ?, is_enabled = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        // 綁定參數
        sqlite3_bind_text(stmt, 1, (item.original as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (item.replacement as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 3, item.isEnabled ? 1 : 0)
        sqlite3_bind_text(stmt, 4, (item.id.uuidString as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("[DictionaryManager] 更新項目失敗: \(errMsg)")
        }
    }

    /// 從資料庫刪除指定 ID 的項目
    private func deleteItemFromDB(id: UUID) {
        guard let db = db else { return }

        let sql = "DELETE FROM dictionary_items WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("[DictionaryManager] 刪除項目失敗: \(errMsg)")
        }
    }

    // MARK: - 公開介面（與舊版 API 相容）

    /// 新增一條置換規則
    func addItem(original: String, replacement: String) {
        let newItem = DictionaryItem(original: original, replacement: replacement)
        insertItem(newItem, sortOrder: items.count)
        runOnMain { [weak self] in
            self?.items.append(newItem)
        }
    }

    /// 依 IndexSet 刪除項目（供 SwiftUI List onDelete 使用）
    func deleteItem(at offsets: IndexSet) {
        let toDelete = offsets.map { items[$0] }
        toDelete.forEach { deleteItemFromDB(id: $0.id) }
        runOnMain { [weak self] in
            self?.items.remove(atOffsets: offsets)
        }
    }

    /// 依物件刪除項目
    func deleteItem(_ item: DictionaryItem) {
        deleteItemFromDB(id: item.id)
        runOnMain { [weak self] in
            self?.items.removeAll { $0.id == item.id }
        }
    }

    /// 更新既有項目
    func updateItem(_ item: DictionaryItem) {
        updateItemInDB(item)
        runOnMain { [weak self] in
            guard let self = self else { return }
            if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                self.items[index] = item
            }
        }
    }

    // MARK: - 文字置換

    /// 執行文字置換
    /// 依原始字串長度由長至短排序，避免短關鍵字破壞長關鍵字的置換
    func replaceText(_ text: String) -> String {
        var processedText = text

        // 僅保留啟用的規則，並依長度由長至短排序，避免短規則提前消耗長規則的文字
        let activeItems = items
            .filter { $0.isEnabled }
            .sorted { $0.original.count > $1.original.count }

        for item in activeItems {
            // 使用 caseInsensitive 比對，以處理語音辨識可能產生大小寫不一致的情況
            // （例如："claude code" → "Claude Code"）
            processedText = processedText.replacingOccurrences(
                of: item.original,
                with: item.replacement,
                options: .caseInsensitive
            )
        }
        return processedText
    }
}
