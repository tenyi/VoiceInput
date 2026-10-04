import SwiftUI

struct HistorySettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel
    @EnvironmentObject var historyManager: HistoryManager

    var body: some View {
        Form {
            // 頁首卡片
            SettingsPaneHeader(pane: .history)

            Section {
                if historyManager.transcriptionHistory.isEmpty {
                    // 空狀態：置中圖示與說明
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text(String(localized: "history.empty"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(historyManager.transcriptionHistory) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Label(
                                    item.createdAt.formatted(date: .omitted, time: .standard),
                                    systemImage: "clock"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                Spacer()

                                Button {
                                    // M-4 修復:剪貼簿操作直接在 UI 層處理
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(item.text, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                                .help(String(localized: "history.copy"))
                                .accessibilityLabel(String(localized: "history.copy"))

                                Button {
                                    historyManager.deleteHistoryItem(item)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                                .help(String(localized: "history.delete.help"))
                                .accessibilityLabel(String(localized: "history.delete.help"))
                            }

                            Text(item.text)
                                .font(.body)
                                .lineSpacing(2)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text(String(localized: "history.section.recent"))
            } footer: {
                Text(String(localized: "history.footer"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
