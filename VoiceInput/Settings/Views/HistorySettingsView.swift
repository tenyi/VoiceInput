import SwiftUI

struct HistorySettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel
    @EnvironmentObject var historyManager: HistoryManager

    var body: some View {
        Form {
            Section {
                if historyManager.transcriptionHistory.isEmpty {
                    Text("目前沒有歷史輸入")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(historyManager.transcriptionHistory) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.createdAt.formatted(date: .omitted, time: .standard))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Button {
                                    historyManager.copyHistoryText(item.text)
                                } label: {
                                    Label("複製", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)

                                Button {
                                    historyManager.deleteHistoryItem(item)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("刪除此筆紀錄")
                            }

                            Text(item.text)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("最近 10 筆輸入")
            } footer: {
                Text("可快速複製或刪除歷史文字")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

