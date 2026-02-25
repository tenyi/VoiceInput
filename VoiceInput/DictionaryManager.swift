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
    func replaceText(_ text: String) -> String {
        var processedText = text
        // 排序：長度長的優先置換
        let activeItems = items.filter { $0.isEnabled }.sorted { $0.original.count > $1.original.count }

        for item in activeItems {
            let options: String.CompareOptions = item.isCaseSensitive ? [] : [.caseInsensitive]
             processedText = processedText.replacingOccurrences(
                of: item.original,
                with: item.replacement,
                options: options
            )
        }
        return processedText
    }

    private func saveItems() {
        if let encoded = try? JSONEncoder().encode(items) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }

    private func loadItems() {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([DictionaryItem].self, from: data) {
            items = decoded
        }
    }
}
