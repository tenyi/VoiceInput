//
//  VoiceInputApp.swift
//  VoiceInput
//
//  Created by Tenyi on 2026/2/14.
//

import SwiftUI
import AppKit
import OSLog

@main
struct VoiceInputApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // M-6 修復:viewModel 由 AppDelegate 持有生命週期,App 層只是觀察者,用 @ObservedObject
    @ObservedObject private var viewModel = AppDelegate.sharedViewModel

    var body: some Scene {
        MenuBarExtra("VoiceInput", systemImage: viewModel.isRecording ? "waveform.circle.fill" : "mic.fill") {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(AppDelegate.sharedLLMSettingsViewModel)
                .environmentObject(AppDelegate.sharedModelManager)
                .environmentObject(AppDelegate.sharedHistoryManager)
                .task {
                    WindowManager.shared.viewModel = viewModel
                }
        }
        .menuBarExtraStyle(.window)

        // SettingsWindow 由 AppDelegate 手動管理以確保大小與位置正確
    }
}

/// App 代理人，負責處理應用程式生命週期事件
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "AppDelegate")

    static let sharedViewModel = VoiceInputViewModel()
    static let sharedLLMSettingsViewModel = LLMSettingsViewModel()
    static let sharedModelManager = ModelManager()
    static let sharedHistoryManager = HistoryManager()

    /// 儲存設定視窗的引用
    var settingsWindow: NSWindow?

    /// A1.7:時鐘抽象;測試可注入 TestClock 跳過啟動延遲,生產環境使用 SystemClock
    var clock: Clock = SystemClock()

    /// 啟動後延遲顯示設定視窗的時間(秒)
    private static let settingsWindowDelay: Double = 0.3

    /// 當應用程式完成啟動時呼叫
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 確保應用程式成為活躍應用程式
        NSApp.activate(ignoringOtherApps: true)

        // H-8 修復:在應用程式完全啟動後才啟動快捷鍵監聽,
        // 避免 static let sharedViewModel 在 init 階段就建立 CGEventTap,
        // 在 App 還沒準備好時接收鍵盤事件。
        Self.sharedViewModel.startHotkeyMonitoring()

        // 建立並顯示設定視窗
        // A1.7:透過注入的 clock 取代 DispatchQueue.main.asyncAfter
        Task { @MainActor [weak self] in
            await self?.clock.sleep(for: .seconds(Self.settingsWindowDelay))
            self?.showSettingsWindow()
        }
    }

    /// 顯示設定視窗
    func showSettingsWindow() {
        // 如果視窗已經存在，直接顯示
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 建立新的視窗
        let settingsView = SettingsView()
            .environmentObject(Self.sharedViewModel)
            .environmentObject(Self.sharedLLMSettingsViewModel)
            .environmentObject(Self.sharedModelManager)
            .environmentObject(Self.sharedHistoryManager)

        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 450),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        window.title = NSLocalizedString("settings.window.title", comment: "Settings window title")
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.minSize = NSSize(width: 400, height: 350)

        // 確保視窗大小設置完成後再置中
        window.setFrameAutosaveName("SettingsWindow")

        // 手動置中（確保水平和垂直都置中）
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }

        // 顯示視窗
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 儲存引用
        self.settingsWindow = window
    }

    /// 當使用者點擊 Dock 圖示時
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showSettingsWindow()
        }
        return true
    }

    /// 當應用程式即將關閉時
    func applicationWillTerminate(_ notification: Notification) {
        // L-6 修復:同步 flush debounce 中的 Keychain 寫入,避免 _exit(0) 遺失
        Self.sharedLLMSettingsViewModel.flushPendingKeychainWrites()

        // 確保所有的非同步設定寫入已送出
        UserDefaults.standard.synchronize()
        logger.info("為避免 ggml-metal C++ 資源釋放當機，應用程式正以 _exit(0) 安全退出")

        // 繞過 whisper.cpp / ggml-metal 中的全域 C++ 物件解構過程
        // 以避免在一般 exit() 進入清理階段時發生 ggml_abort 當機
        _exit(0)
    }
}
