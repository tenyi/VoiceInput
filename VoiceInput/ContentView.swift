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

    var body: some View {
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
        .frame(width: 350, height: 500)
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
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("VoiceInput")
                    .font(.system(size: 18, weight: .bold))
                Text(viewModel.isRecording ? "錄音中..." : "準備就緒")
                    .font(.caption)
                    .foregroundColor(viewModel.isRecording ? .red : .secondary)
            }
            Spacer()
            
            Toggle("", isOn: $viewModel.autoInsertText)
                .toggleStyle(.switch)
                .labelsHidden()
                .help("轉錄完成後自動插入文字")
        }
        .padding()
    }
    
    private var transcriptionSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("轉錄設定", systemImage: "text.bubble")
                .font(.headline)
            
            Picker("辨識語言", selection: $viewModel.selectedLanguage) {
                ForEach(viewModel.availableLanguages.keys.sorted(), id: \.self) { key in
                    Text(viewModel.availableLanguages[key] ?? key).tag(key)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    private var modelSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Whisper 模型", systemImage: "cpu")
                .font(.headline)
            
            Text(viewModel.whisperModelPath.isEmpty ? "未選擇模型" : URL(fileURLWithPath: viewModel.whisperModelPath).lastPathComponent)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
            
            Text("留空則預設使用 Apple 系統語音辨識")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("快捷鍵", systemImage: "keyboard")
                .font(.headline)

            HStack {
                Text("錄音快捷鍵:")
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
            Label("最近轉錄", systemImage: "clock.arrow.circlepath")
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
            Button("關於") {
                showAbout()
            }
            .buttonStyle(.link)
            
            Spacer()
            
            Button(action: {
                viewModel.toggleRecording()
            }) {
                HStack {
                    Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                    Text(viewModel.isRecording ? "停止錄音" : "開始錄音")
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
    
    // MARK: - Actions

    /// 顯示關於資訊
    private func showAbout() {
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
    }

}


#Preview {
    ContentView()
        .environmentObject(VoiceInputViewModel())
}
