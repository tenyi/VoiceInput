//
//  VoiceInputApp.swift
//  VoiceInput
//
//  Created by Tenyi on 2026/2/14.
//

import SwiftUI
import AppKit

@main
struct VoiceInputApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = AppDelegate.sharedViewModel

    var body: some Scene {
        MenuBarExtra("VoiceInput", systemImage: viewModel.isRecording ? "waveform.circle.fill" : "mic.fill") {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(AppDelegate.sharedLLMSettingsViewModel)
                .task {
                    WindowManager.shared.viewModel = viewModel
                }
        }
        .menuBarExtraStyle(.window)

        // SettingsWindow 由 AppDelegate 手動管理以確保大小與位置正確
    }
}

/// App 代理人，負責處理應用程式生命週期事件
class AppDelegate: NSObject, NSApplicationDelegate {
    static let sharedViewModel = VoiceInputViewModel()
    static let sharedLLMSettingsViewModel = LLMSettingsViewModel()

    /// 儲存設定視窗的引用
    private var settingsWindow: NSWindow?

    /// 當應用程式完成啟動時呼叫
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 確保應用程式成為活躍應用程式
        NSApp.activate(ignoringOtherApps: true)

        // 建立並顯示設定視窗
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.showSettingsWindow()
        }
    }

    /// 顯示設定視窗
    private func showSettingsWindow() {
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

        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 450),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        window.title = "VoiceInput 設定"
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
}
