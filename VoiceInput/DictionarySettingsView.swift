
import SwiftUI

struct DictionarySettingsView: View {
    @StateObject private var dictionaryManager = DictionaryManager.shared
    @State private var originalText: String = ""
    @State private var replacementText: String = ""
    @State private var isCaseSensitive: Bool = false
    @State private var editingItem: DictionaryItem?
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("定義文字置換規則，將會自動替換特定的單詞或片語。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        TextField("原始文字 (例如：cloud code)", text: $originalText)
                            .textFieldStyle(.roundedBorder)
                        
                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)
                        
                        TextField("置換後文字 (例如：Claude Code)", text: $replacementText)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Aa", isOn: $isCaseSensitive)
                            .toggleStyle(.button)
                            .help("區分大小寫")
                            
                        Button(action: addOrUpdateItem) {
                            Image(systemName: editingItem == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(editingItem == nil ? .green : .blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(originalText.isEmpty || replacementText.isEmpty)
                        .help(editingItem == nil ? "新增規則" : "更新規則")
                        
                        if editingItem != nil {
                            Button(action: cancelEdit) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                            .help("取消編輯")
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("新增/編輯規則")
            }
            
            Section {
                if dictionaryManager.items.isEmpty {
                    Text("尚未新增任何規則")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    // Header Row
                    HStack {
                        Text("原始文字")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Spacer()
                            .frame(width: 20)
                        
                        Text("置換後")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                             .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Spacer()
                            .frame(width: 60) // Alignment for buttons
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                    
                    ForEach(dictionaryManager.items) { item in
                        HStack {
                            Text(item.original)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            
                            Text(item.replacement)
                                .font(.body)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            if item.isCaseSensitive {
                                Text("Aa")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            
                            Spacer()
                            
                            // Edit Button
                            Button(action: { startEditing(item) }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            .help("編輯")
                            
                            // Delete Button
                            Button(action: { dictionaryManager.deleteItem(item) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .help("刪除")
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(editingItem?.id == item.id ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(4)
                        
                        Divider()
                    }
                }
            } header: {
                Text("已定義規則")
            }
        }
        .padding()
    }
    
    private func addOrUpdateItem() {
        if let editingItem = editingItem {
            var updatedItem = editingItem
            updatedItem.original = originalText
            updatedItem.replacement = replacementText
            updatedItem.isCaseSensitive = isCaseSensitive
            dictionaryManager.updateItem(updatedItem)
            cancelEdit()
        } else {
            // Support comma separated values for adding multiple items at once (from screenshot hint)
            let originals = originalText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for original in originals where !original.isEmpty {
                dictionaryManager.addItem(original: original, replacement: replacementText, isCaseSensitive: isCaseSensitive)
            }
            
            originalText = ""
            replacementText = ""
            isCaseSensitive = false
        }
    }
    
    private func startEditing(_ item: DictionaryItem) {
        editingItem = item
        originalText = item.original
        replacementText = item.replacement
        isCaseSensitive = item.isCaseSensitive
    }
    
    private func cancelEdit() {
        editingItem = nil
        originalText = ""
        replacementText = ""
        isCaseSensitive = false
    }
}
