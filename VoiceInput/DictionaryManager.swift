import Foundation
import Combine
import SwiftUI

struct DictionaryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var original: String
    var replacement: String
    var isEnabled: Bool
    var isCaseSensitive: Bool

    init(id: UUID = UUID(), original: String, replacement: String, isEnabled: Bool = true, isCaseSensitive: Bool = false) {
        self.id = id
        self.original = original
        self.replacement = replacement
        self.isEnabled = isEnabled
        self.isCaseSensitive = isCaseSensitive
    }
    
    // 定義 CodingKeys 來協助解碼相容舊有資料
    enum CodingKeys: String, CodingKey {
        case id, original, replacement, isEnabled, isCaseSensitive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.original = try container.decode(String.self, forKey: .original)
        self.replacement = try container.decode(String.self, forKey: .replacement)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.isCaseSensitive = try container.decodeIfPresent(Bool.self, forKey: .isCaseSensitive) ?? false
    }
}

class DictionaryManager: ObservableObject {
    @Published var items: [DictionaryItem] = []

    private let storageKey: String
    private let userDefaults: UserDefaults

    static let shared = DictionaryManager()

    // C-6 修復:replaceText 在背景執行緒被呼叫,讀取 items 需先取快照避免
    // 與主執行緒的 mutation 競爭。透過 queue 序列化讀寫。
    private let accessQueue = DispatchQueue(label: "com.voiceinput.dictionary.access", attributes: .concurrent)

    // H-11 修復:Regex 預編譯快取,key 為 (original, isCaseSensitive) tuple,
    // 避免每次 replaceText 都重新編譯 NSRegularExpression。
    private var regexCache: [RegexCacheKey: NSRegularExpression] = [:]

    init(userDefaults: UserDefaults = .standard, storageKey: String = "userDictionaryItems") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        loadItems()
    }

    func addItem(original: String, replacement: String, isCaseSensitive: Bool = false) {
        let newItem = DictionaryItem(original: original, replacement: replacement, isCaseSensitive: isCaseSensitive)
        items.append(newItem)
        saveItems()
    }

    /// H-10 修復:批量新增多個項目,只在最後 saveItems 一次。
    /// 避免 N 次完整 JSON 編碼 + UserDefaults 寫入(例如批次貼上 1000 筆 = 1000 次編碼)。
    func addItems(_ newItems: [DictionaryItem]) {
        guard !newItems.isEmpty else { return }
        items.append(contentsOf: newItems)
        saveItems()
    }

    func deleteItem(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        saveItems()
    }

    func deleteItem(_ item: DictionaryItem) {
        items.removeAll { $0.id == item.id }
        saveItems()
    }

    func updateItem(_ item: DictionaryItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
            saveItems()
        }
    }

    /// 執行文字置換
    /// 依據原始字串長度由長至短排序，避免短的關鍵字破壞長的關鍵字
    /// C-6 修復:此方法可從轉錄管線(背景執行緒)呼叫,以 concurrent read 取快照後離開 queue。
    /// H-11 修復:用預編譯的 NSRegularExpression 一次替換所有啟用項目,避免 N×M 字串掃描。
    func replaceText(_ text: String) -> String {
        // 在 concurrent queue 上以 .concurrent 讀取,寫入端透過 barrier 序列化。
        // 這保證讀取時看到一致的快照,避免與背景 mutation 競爭。
        let snapshot: [DictionaryItem] = accessQueue.sync {
            items
        }

        let activeItems = snapshot.filter { $0.isEnabled }
        guard !activeItems.isEmpty else { return text }

        // 排序：長度長的優先置換,避免短的關鍵字破壞長的關鍵字
        let sortedItems = activeItems.sorted { $0.original.count > $1.original.count }

        var processedText = text

        for item in sortedItems {
            let regex = cachedRegex(for: item)
            processedText = regex.stringByReplacingMatches(
                in: processedText,
                options: [],
                range: NSRange(processedText.startIndex..., in: processedText),
                withTemplate: NSRegularExpression.escapedTemplate(for: item.replacement)
            )
        }
        return processedText
    }

    /// H-11 修復:取得 (or 建立並快取) 預編譯 NSRegularExpression
    private func cachedRegex(for item: DictionaryItem) -> NSRegularExpression {
        let key = RegexCacheKey(original: item.original, isCaseSensitive: item.isCaseSensitive)
        if let cached = regexCache[key] {
            return cached
        }
        var options: NSRegularExpression.Options = []
        if !item.isCaseSensitive {
            options.insert(.caseInsensitive)
        }
        // NSRegularExpression 初始化失敗時(罕見),fallback 用簡單字串比對
        let regex: NSRegularExpression
        if let compiled = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: item.original), options: options) {
            regex = compiled
        } else {
            // 罕見情況:建立一個永不匹配的 regex
            regex = try! NSRegularExpression(pattern: "(?!)", options: [])
        }
        regexCache[key] = regex
        return regex
    }

    private func saveItems() {
        // 透過 barrier 寫入,確保與背景讀取不會看到不一致的中間狀態
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if let encoded = try? JSONEncoder().encode(self.items) {
                self.userDefaults.set(encoded, forKey: self.storageKey)
            }
            // 寫入後清除 regex 快取(項目可能已變動,快取不再有效)
            self.regexCache.removeAll(keepingCapacity: false)
        }
    }

    private func loadItems() {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([DictionaryItem].self, from: data) {
            items = decoded
        }
    }
}

/// H-11 修復:RegexCache 的 key,符合 Hashable 讓 DispatchQueue barrier 也能共用
private struct RegexCacheKey: Hashable {
    let original: String
    let isCaseSensitive: Bool
}
