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
    /// Shows the floating window at the center of the screen or active display.
    func showFloatingWindow() {
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
            Image(systemName: viewModel.isRecording ? "waveform" : "mic.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .symbolEffect(.variableColor.iterative.reversing, isActive: viewModel.isRecording)
            
            Text(viewModel.isRecording ? (viewModel.transcribedText.isEmpty ? "聆聽中..." : viewModel.transcribedText) : "已暫停")
                .foregroundColor(.white)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 200, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.75))
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
        .padding(20) // 陰影與邊距緩衝
    }
}
