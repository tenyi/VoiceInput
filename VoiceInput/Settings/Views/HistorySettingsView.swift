import SwiftUI

struct HistorySettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel
    @EnvironmentObject var historyManager: HistoryManager

    var body: some View {
        Form {
            Section {
                if historyManager.transcriptionHistory.isEmpty {
                    Text(String(localized: "history.empty"))
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
                                    Label(String(localized: "history.copy"), systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)

                                Button {
                                    historyManager.deleteHistoryItem(item)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(String(localized: "history.delete.help"))
                            }

                            Text(item.text)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
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
        .padding()
    }
}

