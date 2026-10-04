//
//  DictionarySettingsView.swift
//  VoiceInput
//
//  字典管理設定視圖：自訂轉錄後文字替換規則
//

import SwiftUI

struct DictionarySettingsView: View {
    @StateObject private var dictionaryManager = DictionaryManager.shared
    @State private var originalText: String = ""
    @State private var replacementText: String = ""
    @State private var isCaseSensitive: Bool = false
    @State private var editingItem: DictionaryItem?

    var body: some View {
        Form {
            // 頁首卡片
            SettingsPaneHeader(pane: .dictionary)

            // 新增 / 編輯規則區塊
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "dictionary.rule.description"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        TextField(String(localized: "dictionary.rule.original"), text: $originalText)
                            .textFieldStyle(.roundedBorder)

                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)
                            .font(.callout.weight(.medium))

                        TextField(String(localized: "dictionary.rule.replacement"), text: $replacementText)
                            .textFieldStyle(.roundedBorder)

                        Toggle("Aa", isOn: $isCaseSensitive)
                            .toggleStyle(.button)
                            .help(String(localized: "dictionary.rule.caseSensitive.help"))

                        Button(action: addOrUpdateItem) {
                            if editingItem == nil {
                                Label(String(localized: "dictionary.rule.add.help"), systemImage: "plus")
                            } else {
                                Label(String(localized: "dictionary.rule.update.help"), systemImage: "checkmark")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(originalText.trimmingCharacters(in: .whitespaces).isEmpty || replacementText.isEmpty)

                        if editingItem != nil {
                            Button(action: cancelEdit) {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.bordered)
                            .help(String(localized: "dictionary.rule.cancelEdit.help"))
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(editingItem == nil
                     ? String(localized: "dictionary.section.editRule")
                     : String(localized: "dictionary.rule.update.help"))
            }

            // 已設定規則列表
            Section {
                if dictionaryManager.items.isEmpty {
                    // 空狀態
                    VStack(spacing: 8) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text(String(localized: "dictionary.rules.empty"))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(dictionaryManager.items) { item in
                        HStack(spacing: 10) {
                            Text(item.original)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 20)

                            Text(item.replacement)
                                .font(.body.weight(.medium))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if item.isCaseSensitive {
                                Text("Aa")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                            }

                            Spacer(minLength: 4)

                            // 編輯按鈕
                            Button(action: { startEditing(item) }) {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.accentColor)
                            .help(String(localized: "dictionary.rules.edit.help"))
                            .accessibilityLabel(String(localized: "dictionary.rules.edit.help"))

                            // 刪除按鈕
                            Button(action: { dictionaryManager.deleteItem(item) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                            .help(String(localized: "dictionary.rules.delete.help"))
                            .accessibilityLabel(String(localized: "dictionary.rules.delete.help"))
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(
                            editingItem?.id == item.id
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                    }
                }
            } header: {
                HStack {
                    Text(String(localized: "dictionary.section.rules"))
                    Spacer()
                    if !dictionaryManager.items.isEmpty {
                        Text("\(dictionaryManager.items.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
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
