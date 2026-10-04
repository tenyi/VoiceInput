//
//  SettingsView.swift
//  VoiceInput
//
//  Created by Tenyi on 2026/2/14.
//
//  設定視窗主畫面：仿 macOS 系統設定的「側邊欄 + 分組表單」版面
//

import SwiftUI
import UniformTypeIdentifiers
import os

struct SettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel

    /// 目前選取的側邊欄分頁（預設為「一般」）
    @State private var selection: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            // 側邊欄：彩色圖示 + 分頁名稱
            List(SettingsPane.allCases, selection: $selection) { pane in
                NavigationLink(value: pane) {
                    Label {
                        Text(pane.title)
                    } icon: {
                        SettingsIconBadge(symbol: pane.symbol, tint: pane.tint, size: 22)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            // 設定視窗的側邊欄固定顯示，移除收合按鈕（與系統設定一致）
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detailView(for: selection ?? .general)
        }
        .navigationTitle(String(localized: "settings.window.title"))
        .frame(minWidth: 680, minHeight: 480)
    }

    /// 依分頁回傳對應的設定內容
    @ViewBuilder
    private func detailView(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralSettingsView()
        case .transcription: TranscriptionSettingsView()
        case .model: ModelSettingsView()
        case .llm: LLMSettingsView()
        case .dictionary: DictionarySettingsView()
        case .history: HistorySettingsView()
        }
    }
}

// MARK: - Subviews

#Preview {
    SettingsView()
        .environmentObject(VoiceInputViewModel())
        .environmentObject(LLMSettingsViewModel())
        .environmentObject(ModelManager())
        .environmentObject(HistoryManager())
}
