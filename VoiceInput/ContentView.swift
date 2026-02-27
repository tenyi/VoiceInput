//
//  ContentView.swift
//  VoiceInput
//
//  Created by Tenyi on 2026/2/14.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var modelManager: ModelManager
    @State private var selectedTab: MainTab = .main

    private enum MainTab: String, CaseIterable, Identifiable {
        case main
        case history
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .main: return String(localized: "content.tab.main")
            case .history: return String(localized: "content.tab.history")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("分頁", selection: $selectedTab) {
                Text(MainTab.main.displayName).tag(MainTab.main)
                Text(MainTab.history.displayName).tag(MainTab.history)
            }
            .pickerStyle(.segmented)
            .padding([.top, .horizontal])

            if selectedTab == .main {
                mainView
            } else {
                historyView
            }
        }
        .frame(width: 360, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $viewModel.permissionManager.showingPermissionAlert) {
            if let permissionType = viewModel.permissionManager.pendingPermissionType {
                PermissionAlertView(
                    permissionType: permissionType,
                    onDismiss: {
                        viewModel.permissionManager.showingPermissionAlert = false
                        // 重新檢查權限
                        viewModel.permissionManager.checkAllPermissions()
                    }
                )
            }
        }
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            // 標題與狀態
            headerView

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 設定區塊：轉錄設定
                    transcriptionSettings

                    // 設定區塊：模型設定 (Whisper)
                    modelSettings

                    // 設定區塊：一般設定
                    generalSettings

                    // 最近轉錄結果預覽
                    transcriptionPreview
                }
                .padding()
            }

            Divider()

            footerView
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("VoiceInput")
                    .font(.system(size: 18, weight: .bold))
                Text(viewModel.isRecording
                     ? String(localized: "content.status.recording")
                     : String(localized: "content.status.ready"))
                    .font(.caption)
                    .foregroundColor(viewModel.isRecording ? .red : .secondary)
            }
            Spacer()

            Toggle("", isOn: $viewModel.autoInsertText)
                .toggleStyle(.switch)
                .labelsHidden()
                .help(String(localized: "content.autoInsert.help"))
        }
        .padding()
    }
    
    private var transcriptionSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "content.section.transcription"), systemImage: "text.bubble")
                .font(.headline)

            Picker(String(localized: "transcription.language.picker"), selection: $viewModel.selectedLanguage) {
                ForEach(viewModel.availableLanguages.keys.sorted(), id: \.self) { key in
                    Text(viewModel.availableLanguages[key] ?? key).tag(key)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    private var modelSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "content.section.model"), systemImage: "cpu")
                .font(.headline)

            Text(modelManager.whisperModelPath.isEmpty
                 ? String(localized: "content.model.noModel")
                 : URL(fileURLWithPath: modelManager.whisperModelPath).lastPathComponent)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)

            Text(String(localized: "content.model.defaultHint"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "content.section.hotkey"), systemImage: "keyboard")
                .font(.headline)

            HStack {
                Text(String(localized: "content.hotkey.label"))
                Spacer()
                if let option = HotkeyOption(rawValue: viewModel.selectedHotkey) {
                    Text(option.displayName)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().stroke(Color.secondary, lineWidth: 1))
                }
            }
            .font(.subheadline)
        }
    }
    
    private var transcriptionPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "content.section.recent"), systemImage: "clock.arrow.circlepath")
                .font(.headline)
            
            Text(viewModel.transcribedText)
                .font(.system(.body, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                .background(Color.black.opacity(0.05))
                .cornerRadius(6)
        }
    }
    
    private var footerView: some View {
        HStack {
            Button(String(localized: "content.button.about")) {
                showAbout()
            }
            .buttonStyle(.link)

            Spacer()

            Button(action: {
                viewModel.toggleRecording()
            }) {
                HStack {
                    Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                    Text(viewModel.isRecording
                         ? String(localized: "content.button.stopRecording")
                         : String(localized: "content.button.startRecording"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(viewModel.isRecording ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "content.historyView.title"))
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            if historyManager.transcriptionHistory.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text(String(localized: "content.historyView.empty"))
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(historyManager.transcriptionHistory) { item in
                            historyRow(item)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func historyRow(_ item: TranscriptionHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.createdAt.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    historyManager.copyHistoryText(item.text)
                } label: {
                    Label(String(localized: "content.history.copy"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)

                Button {
                    historyManager.deleteHistoryItem(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "content.history.delete.help"))
            }

            Text(item.text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(Color.black.opacity(0.05))
        .cornerRadius(8)
    }
    
    // MARK: - Actions

    /// 顯示關於資訊
    private func showAbout() {
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
    }

}


#Preview {
    ContentView()
        .environmentObject(VoiceInputViewModel())
        .environmentObject(LLMSettingsViewModel())
        .environmentObject(ModelManager())
        .environmentObject(HistoryManager())
}
