//
//  VoiceInputApp.swift
//  VoiceInput
//
//  Created by Tenyi on 2026/2/14.
//

import SwiftUI
import SwiftData

@main
struct VoiceInputApp: App {
    @StateObject private var viewModel = VoiceInputViewModel()

    var body: some Scene {
        MenuBarExtra("VoiceInput", systemImage: viewModel.isRecording ? "waveform.circle.fill" : "mic.fill") {
            ContentView()
                .environmentObject(viewModel)
                .task {
                    // 使用 task 取代 onAppear，確保在視圖渲染前就設定 ViewModel
                    WindowManager.shared.viewModel = viewModel
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(viewModel)
        }
    }
}
