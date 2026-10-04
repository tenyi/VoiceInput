//
//  SettingsComponents.swift
//  VoiceInput
//
//  設定視窗共用的視覺元件：
//  - SettingsPane：側邊欄分頁定義（標題、圖示、色彩、副標題）
//  - SettingsIconBadge：仿 macOS 系統設定的彩色圓角圖示方塊
//  - SettingsPaneHeader：每個分頁頂端的主視覺卡片
//  - SettingsRowLabel：帶有彩色圖示的表單列標籤
//  - SettingsStatusBadge：狀態膠囊（已授權／未授權等）
//  - PermissionRow：權限狀態列
//

import SwiftUI

// MARK: - 設定分頁定義

/// 設定視窗側邊欄的分頁列舉
/// 集中管理每個分頁的標題、SF Symbol 與代表色，確保側邊欄與頁首卡片一致
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case transcription
    case model
    case llm
    case dictionary
    case history

    /// Identifiable 需要的唯一識別碼
    var id: String { rawValue }

    /// 分頁標題（沿用既有的分頁本地化字串）
    var title: String {
        switch self {
        case .general: return String(localized: "settings.tab.general")
        case .transcription: return String(localized: "settings.tab.transcription")
        case .model: return String(localized: "settings.tab.model")
        case .llm: return String(localized: "settings.tab.llm")
        case .dictionary: return String(localized: "settings.tab.dictionary")
        case .history: return String(localized: "settings.tab.history")
        }
    }

    /// 分頁副標題（顯示於頁首卡片，簡述此頁用途）
    var subtitle: String {
        switch self {
        case .general: return String(localized: "settings.pane.general.subtitle")
        case .transcription: return String(localized: "settings.pane.transcription.subtitle")
        case .model: return String(localized: "settings.pane.model.subtitle")
        case .llm: return String(localized: "settings.pane.llm.subtitle")
        case .dictionary: return String(localized: "settings.pane.dictionary.subtitle")
        case .history: return String(localized: "settings.pane.history.subtitle")
        }
    }

    /// 分頁對應的 SF Symbol 名稱
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .transcription: return "text.bubble.fill"
        case .model: return "cpu.fill"
        case .llm: return "sparkles"
        case .dictionary: return "character.book.closed.fill"
        case .history: return "clock.arrow.circlepath"
        }
    }

    /// 分頁代表色（用於圖示方塊的漸層底色）
    var tint: Color {
        switch self {
        case .general: return .gray
        case .transcription: return .blue
        case .model: return .orange
        case .llm: return .purple
        case .dictionary: return .teal
        case .history: return .indigo
        }
    }
}

// MARK: - 彩色圓角圖示方塊

/// 仿 macOS 系統設定的彩色圓角圖示
/// 以代表色漸層為底、白色符號置中；屬於純裝飾，因此對輔助技術隱藏
struct SettingsIconBadge: View {
    /// SF Symbol 名稱
    let symbol: String
    /// 底色
    let tint: Color
    /// 方塊邊長（pt）
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            // 符號大小約為方塊的 55%，在小尺寸時仍保有足夠留白
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                // 連續曲率圓角（squircle），與系統設定圖示一致
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(tint.gradient)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - 分頁頁首卡片

/// 每個設定分頁最上方的主視覺卡片：大圖示 + 標題 + 說明，右側可放置附加控制項（例如總開關）
struct SettingsPaneHeader<Accessory: View>: View {
    /// 對應的分頁
    let pane: SettingsPane
    /// 右側附加控制項
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        Section {
            HStack(alignment: .center, spacing: 14) {
                SettingsIconBadge(symbol: pane.symbol, tint: pane.tint, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(pane.title)
                        .font(.title3.weight(.semibold))
                    Text(pane.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                accessory()
            }
            .padding(.vertical, 6)
            // 將標題與說明合併為單一無障礙元素，附加控制項仍可獨立操作
            .accessibilityElement(children: .contain)
        }
    }
}

extension SettingsPaneHeader where Accessory == EmptyView {
    /// 不需要附加控制項時的便利建構子
    init(pane: SettingsPane) {
        self.pane = pane
        self.accessory = { EmptyView() }
    }
}

// MARK: - 表單列標籤

/// 帶彩色小圖示的表單列標籤，用於 Picker / Toggle 等控制項的 label
struct SettingsRowLabel: View {
    /// 標籤文字
    let title: String
    /// SF Symbol 名稱
    let symbol: String
    /// 圖示底色
    let tint: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            SettingsIconBadge(symbol: symbol, tint: tint, size: 20)
        }
    }
}

// MARK: - 狀態膠囊

/// 小型狀態膠囊（圖示 + 文字），以淡色底強調狀態而不搶走主要內容的視覺重心
struct SettingsStatusBadge: View {
    /// 顯示文字
    let text: String
    /// SF Symbol 名稱
    let symbol: String
    /// 主色
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

// MARK: - 權限狀態列

/// 權限狀態列：左側彩色圖示與名稱、右側授權狀態膠囊；整列可點擊以重新請求權限
struct PermissionRow: View {
    /// 權限名稱
    let title: String
    /// 圖示
    let symbol: String
    /// 圖示底色
    let tint: Color
    /// 是否已授權
    let isGranted: Bool
    /// 點擊時執行的動作（重新請求權限）
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SettingsRowLabel(title: title, symbol: symbol, tint: tint)
                    .foregroundStyle(.primary)

                Spacer()

                if isGranted {
                    SettingsStatusBadge(
                        text: String(localized: "general.permission.granted"),
                        symbol: "checkmark.circle.fill",
                        tint: .green
                    )
                } else {
                    SettingsStatusBadge(
                        text: String(localized: "general.permission.notGranted"),
                        symbol: "exclamationmark.circle.fill",
                        tint: .orange
                    )
                }
            }
            // 讓整列（包含空白處）都能接收點擊
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
