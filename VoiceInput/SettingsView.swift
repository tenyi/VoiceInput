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
                        Label(String(localized: "settings.tab.general"), systemImage: "gear")
                    }

                TranscriptionSettingsView()
                    .tabItem {
                        Label(String(localized: "settings.tab.transcription"), systemImage: "text.bubble")
                    }

                ModelSettingsView()
                    .tabItem {
                        Label(String(localized: "settings.tab.model"), systemImage: "cpu")
                    }

                LLMSettingsView()
                    .tabItem {
                        Label(String(localized: "settings.tab.llm"), systemImage: "brain")
                    }

                DictionarySettingsView()
                    .tabItem {
                        Label(String(localized: "settings.tab.dictionary"), systemImage: "character.book.closed")
                    }

                HistorySettingsView()
                    .tabItem {
                        Label(String(localized: "settings.tab.history"), systemImage: "clock.arrow.circlepath")
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

