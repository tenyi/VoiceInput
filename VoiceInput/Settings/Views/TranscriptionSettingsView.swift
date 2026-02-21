import SwiftUI

struct TranscriptionSettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel
    
    var body: some View {
        Form {
            Section {
                Picker("辨識語言", selection: $viewModel.selectedLanguage) {
                    ForEach(viewModel.availableLanguages.keys.sorted(), id: \.self) { key in
                        Text(viewModel.availableLanguages[key] ?? key).tag(key)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("語言設定")
            }
        }
        .padding()
    }
}

