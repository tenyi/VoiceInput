//
//  SettingsView.swift
//  VoiceInput
//
//  Created by Tenyi on 2026/2/14.
//

import SwiftUI
import UniformTypeIdentifiers
import os

struct SettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel

    var body: some View {
        ScrollView {
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

                LLMSettingsView()
                    .tabItem {
                        Label("LLM", systemImage: "brain")
                    }

                DictionarySettingsView()
                    .tabItem {
                        Label("字典", systemImage: "character.book.closed")
                    }

                HistorySettingsView()
                    .tabItem {
                        Label("歷史", systemImage: "clock.arrow.circlepath")
                    }
            }
            .frame(minWidth: 460, minHeight: 350)
            .padding()
        }
    }
}

// MARK: - Subviews

#Preview {
    SettingsView()
        .environmentObject(VoiceInputViewModel())
        .environmentObject(ModelManager())
        .environmentObject(HistoryManager())
}

