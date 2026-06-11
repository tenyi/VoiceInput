import Foundation
import Testing
import AppKit
@testable import VoiceInput

/// B7: WindowManager 與 AppDelegate 視窗管理單元測試套件
@Suite("WindowManagerTests")
@MainActor
struct WindowManagerTests {

    /// B7.2: 測試顯示與隱藏浮動視窗的狀態轉移
    @Test("測試浮動視窗顯示與隱藏")
    func testShowAndHideFloatingWindow() async {
        let manager = WindowManager.shared
        
        let mockHotkey = MockHotkeyManager()
        let mockAudio = MockAudioEngine()
        let mockInput = MockInputSimulator()
        let mockDefaults = UserDefaults.standard
        let testClock = TestClock()

        let mockViewModel = VoiceInputViewModel(
            hotkeyManager: mockHotkey,
            audioEngine: mockAudio,
            inputSimulator: mockInput,
            userDefaults: mockDefaults,
            clock: testClock
        )
        manager.viewModel = mockViewModel

        // 建立一個真實的 NSPanel 作為 Mock 視窗注入，以便安全測試
        let mockPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        manager.floatingWindow = mockPanel

        // 預設應為隱藏狀態
        #expect(mockPanel.isVisible == false)

        // 1. 測試顯示視窗
        manager.showFloatingWindow(isRecording: true)
        #expect(mockPanel.isVisible == true)

        // 2. 測試隱藏視窗
        manager.hideFloatingWindow()
        #expect(mockPanel.isVisible == false)

        // 清理全域單例狀態，避免干擾其他測試
        manager.floatingWindow = nil
    }

    /// B7.3: 測試 AppDelegate 建立與顯示設定視窗
    @Test("測試設定視窗建立與顯示")
    func testShowSettingsWindow() async {
        let appDelegate = AppDelegate()

        // 預設設定視窗應為 nil
        #expect(appDelegate.settingsWindow == nil)

        // 1. 觸發顯示設定視窗
        appDelegate.showSettingsWindow()

        // 驗證視窗是否成功建立並顯示
        let window = appDelegate.settingsWindow
        #expect(window != nil, "設定視窗應被成功建立")
        #expect(window?.isVisible == true, "設定視窗應為顯示狀態")
        #expect(window?.title == "VoiceInput 設定", "設定視窗標題應正確")

        // 2. 再次觸發（應重複使用現有視窗，不重建）
        appDelegate.showSettingsWindow()
        #expect(appDelegate.settingsWindow === window, "再次呼叫時應重用同一個視窗實例")

        // 清理視窗資源，避免內存洩漏與殘留
        window?.close()
        appDelegate.settingsWindow = nil
    }
}
