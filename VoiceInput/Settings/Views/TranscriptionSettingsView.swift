import SwiftUI

struct TranscriptionSettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel
    
    var body: some View {
        Form {
            Section {
                Picker(String(localized: "transcription.language.picker"), selection: $viewModel.selectedLanguage) {
                    ForEach(viewModel.availableLanguages.keys.sorted(), id: \.self) { key in
                        Text(viewModel.availableLanguages[key] ?? key).tag(key)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text(String(localized: "transcription.section.language"))
            }
        }
        .padding()
    }
}

