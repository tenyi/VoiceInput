import SwiftUI
import AppKit
import Combine

/// 負責管理應用程式的所有視窗 (包括浮動面板)
class WindowManager: ObservableObject {
    static let shared = WindowManager()

    private var floatingWindow: NSPanel?
    private var hostingController: NSHostingController<AnyView>?

    // 注入 ViewModel (需要在 VoiceInputApp 初始化時設定)
    var viewModel: VoiceInputViewModel?

    private init() {}

    /// 顯示浮動面板
    /// - Parameter isRecording: true 為錄音模式，false 為轉寫模式
    /// Shows the floating window at the center of the screen or active display.
    func showFloatingWindow(isRecording: Bool) {
        if floatingWindow == nil {
            createFloatingWindow()
        }

        guard let window = floatingWindow else { return }

        // 確保視窗顯示並置頂
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// 隱藏浮動面板
    /// Hides the floating window.
    func hideFloatingWindow() {
        floatingWindow?.orderOut(nil)
    }
    
    /// 建立浮動面板
    private func createFloatingWindow() {
        guard let viewModel = viewModel else {
            print("WindowManager: ViewModel not set")
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
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80), // 初始大小，會自動調整
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
        
        // 設定視窗置中
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - 150
            let y = screenRect.midY - 100 // 稍微偏上方
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        self.floatingWindow = window
    }
}

/// 浮動面板的 UI (SwiftUI)
struct FloatingPanelView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel

    var body: some View {
        HStack(spacing: 12) {
            // 根據狀態顯示不同的圖示和動畫
            statusIcon

            // 顯示文字
            statusText
        }
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
        switch viewModel.appState {
        case .idle:
            Image(systemName: "mic.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)

        case .recording:
            // 錄音中：波形動畫
            Image(systemName: "waveform")
                .font(.system(size: 20))
                .foregroundColor(.red)
                .symbolEffect(.variableColor.iterative.reversing, isActive: true)

        case .transcribing:
            // 轉寫中：旋轉載入動畫
            Image(systemName: "arrow.2.circlepath")
                .font(.system(size: 20))
                .foregroundColor(.orange)
                .symbolEffect(.rotate, isActive: true)
        }
    }

    /// 根據狀態顯示不同的文字
    @ViewBuilder
    private var statusText: some View {
        switch viewModel.appState {
        case .idle:
            Text("等待輸入...")
                .foregroundColor(.white)
                .font(.system(size: 14, weight: .medium))

        case .recording:
            Text(viewModel.transcribedText.isEmpty ? "聆聽中..." : viewModel.transcribedText)
                .foregroundColor(.white)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 200, alignment: .leading)

        case .transcribing:
            Text("轉寫中...")
                .foregroundColor(.orange)
                .font(.system(size: 14, weight: .medium))
        }
    }

    /// 背景顏色根據狀態變化
    private var backgroundColor: Color {
        switch viewModel.appState {
        case .idle:
            return Color.black.opacity(0.75)
        case .recording:
            return Color.red.opacity(0.8)
        case .transcribing:
            return Color.orange.opacity(0.8)
        }
    }
}
