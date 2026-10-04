import SwiftUI

struct TranscriptionSettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel
    
    var body: some View {
        Form {
            // 頁首卡片
            SettingsPaneHeader(pane: .transcription)

            Section {
                Picker(selection: $viewModel.selectedLanguage) {
                    ForEach(viewModel.availableLanguages.keys.sorted(), id: \.self) { key in
                        Text(viewModel.availableLanguages[key] ?? key).tag(key)
                    }
                } label: {
                    SettingsRowLabel(
                        title: String(localized: "transcription.language.picker"),
                        symbol: "globe",
                        tint: .blue
                    )
                }
                .pickerStyle(.menu)
            } header: {
                Text(String(localized: "transcription.section.language"))
            }
        }
        .formStyle(.grouped)
    }
}
