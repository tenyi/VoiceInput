//
//  SettingsView.swift
//  VoiceInput
//
//  Created by Tenyi on 2026/2/14.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("一般", systemImage: "gear")
                }
            
            TranscriptionSettingsView()
                .tabItem {
                    Label("轉錄", systemImage: "text.bubble")
                }
            
            ModelSettingsView()
                .tabItem {
                    Label("模型", systemImage: "cpu")
                }
        }
        .frame(width: 450, height: 280)
        .padding()
    }
}

// MARK: - Subviews

struct GeneralSettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel

    /// 目前選擇的快捷鍵
    @State private var selectedHotkey: HotkeyOption = HotkeyOption.rightCommand

    var body: some View {
        Form {
            Section {
                Toggle("轉錄完成後自動插入文字", isOn: $viewModel.autoInsertText)
                    .toggleStyle(.checkbox)

                Picker("錄音快捷鍵", selection: $selectedHotkey) {
                    ForEach(viewModel.availableHotkeys, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedHotkey) { _, newValue in
                    viewModel.updateHotkey(newValue)
                }
            } header: {
                Text("一般設定")
            } footer: {
               Text("按下快捷鍵即可開始/停止錄音。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .onAppear {
            // 載入已儲存的設定
            if let saved = HotkeyOption(rawValue: viewModel.selectedHotkey) {
                selectedHotkey = saved
            }
        }
    }
}

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

struct ModelSettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel
    
    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("模型檔案路徑 (.bin)", text: $viewModel.whisperModelPath)
                    
                    Button("瀏覽...") {
                        selectModelFile()
                    }
                }
            } header: {
                Text("Whisper 模型路徑")
            } footer: {
                Text("若留空則預設使用 Apple 系統語音辨識 framework。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    private func selectModelFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "bin")].compactMap { $0 }
        
        if panel.runModal() == .OK {
            viewModel.whisperModelPath = panel.url?.path ?? ""
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(VoiceInputViewModel())
}
