import SwiftUI
import AppKit
import Combine
import os

/// 負責管理應用程式的所有視窗 (包括浮動面板)
class WindowManager: ObservableObject {
    static let shared = WindowManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "WindowManager")

    private var floatingWindow: NSPanel?
    private var hostingController: NSHostingController<AnyView>?

    // 注入 ViewModel (需要在 VoiceInputApp 初始化時設定)
    var viewModel: VoiceInputViewModel?

    private init() {}

    /// 顯示浮動面板
    /// - Parameter isRecording: true 為錄音模式，false 為轉寫模式
    func showFloatingWindow(isRecording: Bool) {
        if floatingWindow == nil {
            createFloatingWindow()
        }

        guard let window = floatingWindow else { return }

        // 更新位置到滑鼠所在的螢幕
        updateWindowPosition()
        
        // 確保視窗顯示並置頂
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// 隱藏浮動面板
    func hideFloatingWindow() {
        floatingWindow?.orderOut(nil)
    }
    
    /// 更新視窗位置到滑鼠所在的螢幕中央
    private func updateWindowPosition() {
        guard let window = floatingWindow else { return }
        
        // 獲取目前滑鼠所在的螢幕
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let targetScreen = screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? screens.first
        
        if let screen = targetScreen {
            let screenRect = screen.visibleFrame
            let windowWidth = window.frame.width
            let x = screenRect.midX - (windowWidth / 2)
            let y = screenRect.midY - 40 + 100 // 稍微偏上方
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
    
    /// 建立浮動面板
    private func createFloatingWindow() {
        guard let viewModel = viewModel else {
            logger.error("WindowManager: ViewModel not set")
            return
        }
        
        // 建立 SwiftUI 視圖，並注入環境物件
        let contentView = FloatingPanelView()
            .environmentObject(viewModel)
            
        // 使用 AnyView 封裝以適配 NSHostingController
        let hostingController = NSHostingController(rootView: AnyView(contentView))
        self.hostingController = hostingController
        
        // 初始化 NSPanel
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 116), // 初始大小，會依內容調整
            styleMask: [.borderless, .nonactivatingPanel], // 無邊框、不搶佔焦點
            backing: .buffered,
            defer: false
        )
        
        window.contentViewController = hostingController
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating // 浮動層級 (在一般視窗之上)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] // 支援全螢幕 Space
        window.isMovableByWindowBackground = true // 允許拖曳
        
        self.floatingWindow = window
        
        // 進行初始定位
        updateWindowPosition()
    }
}

/// 浮動面板的 UI (SwiftUI)
struct FloatingPanelView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel
    
    private var panelMinWidth: CGFloat {
        if viewModel.lastLLMError != nil {
            return 360
        }
        switch viewModel.appState {
        case .enhancing:
            return 320
        case .recording:
            return 360
        default:
            return 260
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // 根據狀態顯示不同的圖示和動畫
            statusIcon

            // 顯示文字
            statusText
                .layoutPriority(1)
        }
        .frame(minWidth: panelMinWidth, maxWidth: 560, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(backgroundColor)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
        .padding(20) // 陰影與邊距緩衝
    }

    /// 根據狀態顯示不同的圖示
    @ViewBuilder
    private var statusIcon: some View {
        // 如果有 LLM 錯誤，顯示警告圖示
        if viewModel.lastLLMError != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)
        } else {
            normalStatusIcon
        }
    }

    /// 正常狀態的圖示顯示
    @ViewBuilder
    private var normalStatusIcon: some View {
        switch viewModel.appState {
        case .idle:
            Image(systemName: "mic.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)

        case .recording:
            // 錄音中：原本好看的波形動畫
            Image(systemName: "waveform")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .symbolEffect(.variableColor.iterative.reversing, isActive: true)

        case .transcribing:
            // 轉寫中：旋轉載入動畫
            Image(systemName: "arrow.2.circlepath")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .symbolEffect(.rotate, isActive: true)

        case .enhancing:
            // LLM 增強中：閃電動畫
            Image(systemName: "bolt.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .symbolEffect(.variableColor.iterative.reversing, isActive: true)
        }
    }

    /// 根據狀態顯示不同的文字
    @ViewBuilder
    private var statusText: some View {
        // 如果有 LLM 錯誤訊息，優先顯示錯誤
        if viewModel.lastLLMError != nil {
            errorStatusView
        } else {
            normalStatusView
        }
    }

    /// 正常狀態的文字顯示
    @ViewBuilder
    private var normalStatusView: some View {
        switch viewModel.appState {
        case .idle:
            Text("等待輸入...")
                .foregroundColor(.white)
                .font(.system(size: 14, weight: .medium))

        case .recording:
            Text(viewModel.transcribedText.isEmpty ? "聆聽中..." : viewModel.transcribedText)
                .foregroundColor(.white)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
                .frame(maxWidth: 300, alignment: .leading)

        case .transcribing:
            Text("轉寫中...")
                .foregroundColor(.white)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: 300, alignment: .leading)

        case .enhancing:
            VStack(alignment: .leading, spacing: 2) {
                Text("增強中...")
                    .foregroundColor(.white)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                if !viewModel.transcribedText.isEmpty {
                    Text(viewModel.transcribedText)
                        .foregroundColor(.white.opacity(0.7))
                        .font(.system(size: 12))
                        .lineLimit(2)
                }
            }
            .frame(minWidth: 220, maxWidth: 420, alignment: .leading)
        }
    }

    /// 錯誤狀態的文字顯示
    @ViewBuilder
    private var errorStatusView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LLM 修正失敗")
                .foregroundColor(.white)
                .font(.system(size: 12, weight: .semibold))
            if let errorMessage = viewModel.lastLLMError {
                Text(errorMessage)
                    .foregroundColor(.white.opacity(0.8))
                    .font(.system(size: 11))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
    }

    /// 背景顏色根據狀態變化
    private var backgroundColor: Color {
        // 如果有 LLM 錯誤，顯示警告背景色
        if viewModel.lastLLMError != nil {
            return Color.orange.opacity(0.9)
        }

        switch viewModel.appState {
        case .idle:
            return Color.black.opacity(0.75)
        case .recording:
            return Color.black.opacity(0.75)
        case .transcribing:
            return Color.black.opacity(0.75)
        case .enhancing:
            return Color.blue.opacity(0.85)
        }
    }
}
