import Foundation
import Combine
import SwiftUI

struct DictionaryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var original: String
    var replacement: String
    var isEnabled: Bool

    init(id: UUID = UUID(), original: String, replacement: String, isEnabled: Bool = true) {
        self.id = id
        self.original = original
        self.replacement = replacement
        self.isEnabled = isEnabled
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

    func addItem(original: String, replacement: String) {
        let newItem = DictionaryItem(original: original, replacement: replacement)
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
            // 使用 caseInsensitive 進行比對嗎？ 題目範例 cloud code -> Claude Code，看起來需要 case-insensitive 比較好，
            // 但中文通常沒差。Swift replacingOccurrences 預設是 case-sensitive。
            // 考慮到 voice input 出來的英文可能是全小寫或首字大寫，用 case-insensitive 比較好。
            // 但 replacingOccurrences(of:with:options:) 如果用 .caseInsensitiveSearch，替換時會把找到的那段換成 replacement。
            
            // 簡單起見，先用 case-insensitive
             processedText = processedText.replacingOccurrences(
                of: item.original,
                with: item.replacement,
                options: .caseInsensitive
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
