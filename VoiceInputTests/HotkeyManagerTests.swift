import Foundation
import Testing
import Cocoa
@testable import VoiceInput

/// B6: HotkeyManager 單元測試套件
/// 使用 .serialized 避免併發執行時對全域單例 shared 產生狀態競爭
@Suite("HotkeyManagerTests", .serialized)
@MainActor
struct HotkeyManagerTests {

    /// 測試 Fn 鍵的狀態轉換
    @Test("測試 Fn 快捷鍵的按下與放開")
    func testFnHotkey() {
        let manager = HotkeyManager.shared
        manager.setHotkey(.fn)
        manager.resetStateForTesting()

        // 1. 模擬按下 Fn 鍵
        let pressedTransition = manager.processFlagsChangedEvent(
            keyCode: Int64(HotkeyOption.fn.scancode),
            flags: .maskSecondaryFn
        )
        #expect(pressedTransition == .pressed)

        // 2. 模擬重複觸發（狀態未變），應回傳 .none
        let repeatTransition = manager.processFlagsChangedEvent(
            keyCode: Int64(HotkeyOption.fn.scancode),
            flags: .maskSecondaryFn
        )
        #expect(repeatTransition == .none)

        // 3. 模擬放開 Fn 鍵
        let releasedTransition = manager.processFlagsChangedEvent(
            keyCode: Int64(HotkeyOption.fn.scancode),
            flags: []
        )
        #expect(releasedTransition == .released)
    }

    /// 測試左 Command 鍵的狀態轉換
    @Test("測試左 Command 快捷鍵的按下與放開")
    func testLeftCommandHotkey() {
        let manager = HotkeyManager.shared
        manager.setHotkey(.leftCommand)
        manager.resetStateForTesting()

        // 1. 模擬按下左 Command 鍵 (Device Flag Mask: 0x000008)
        let pressedTransition = manager.processFlagsChangedEvent(
            keyCode: Int64(HotkeyOption.leftCommand.scancode),
            flags: CGEventFlags(rawValue: 0x000008)
        )
        #expect(pressedTransition == .pressed)

        // 2. 模擬放開左 Command 鍵
        let releasedTransition = manager.processFlagsChangedEvent(
            keyCode: Int64(HotkeyOption.leftCommand.scancode),
            flags: CGEventFlags(rawValue: 0)
        )
        #expect(releasedTransition == .released)
    }

    /// 測試右 Command 鍵的狀態轉換
    @Test("測試右 Command 快捷鍵的按下與放開")
    func testRightCommandHotkey() {
        let manager = HotkeyManager.shared
        manager.setHotkey(.rightCommand)
        manager.resetStateForTesting()

        // 1. 模擬按下右 Command 鍵 (Device Flag Mask: 0x000010)
        let pressedTransition = manager.processFlagsChangedEvent(
            keyCode: Int64(HotkeyOption.rightCommand.scancode),
            flags: CGEventFlags(rawValue: 0x000010)
        )
        #expect(pressedTransition == .pressed)

        // 2. 模擬放開右 Command 鍵
        let releasedTransition = manager.processFlagsChangedEvent(
            keyCode: Int64(HotkeyOption.rightCommand.scancode),
            flags: CGEventFlags(rawValue: 0)
        )
        #expect(releasedTransition == .released)
    }

    /// 測試左 Option 鍵的狀態轉換
    @Test("測試左 Option 快捷鍵的按下與放開")
    func testLeftOptionHotkey() {
        let manager = HotkeyManager.shared
        manager.setHotkey(.leftOption)
        manager.resetStateForTesting()

        // 1. 模擬按下左 Option 鍵 (Device Flag Mask: 0x000020)
        let pressedTransition = manager.processFlagsChangedEvent(
            keyCode: Int64(HotkeyOption.leftOption.scancode),
            flags: CGEventFlags(rawValue: 0x000020)
        )
        #expect(pressedTransition == .pressed)

        // 2. 模擬放開左 Option 鍵
        let releasedTransition = manager.processFlagsChangedEvent(
            keyCode: Int64(HotkeyOption.leftOption.scancode),
            flags: CGEventFlags(rawValue: 0)
        )
        #expect(releasedTransition == .released)
    }

    /// 測試右 Option 鍵的狀態轉換
    @Test("測試右 Option 快捷鍵的按下與放開")
    func testRightOptionHotkey() {
        let manager = HotkeyManager.shared
        manager.setHotkey(.rightOption)
        manager.resetStateForTesting()

        // 1. 模擬按下右 Option 鍵 (Device Flag Mask: 0x000040)
        let pressedTransition = manager.processFlagsChangedEvent(
            keyCode: Int64(HotkeyOption.rightOption.scancode),
            flags: CGEventFlags(rawValue: 0x000040)
        )
        #expect(pressedTransition == .pressed)

        // 2. 模擬放開右 Option 鍵
        let releasedTransition = manager.processFlagsChangedEvent(
            keyCode: Int64(HotkeyOption.rightOption.scancode),
            flags: CGEventFlags(rawValue: 0)
        )
        #expect(releasedTransition == .released)
    }

    /// 測試非當前快捷鍵事件的過濾
    @Test("測試非當前快捷鍵事件過濾邏輯")
    func testNonTargetKeyFilter() {
        let manager = HotkeyManager.shared
        manager.setHotkey(.rightCommand)
        manager.resetStateForTesting()

        // 當設定為右 Command 時，收到 Fn 鍵的事件，應回傳 .none 被過濾掉
        let transition = manager.processFlagsChangedEvent(
            keyCode: Int64(HotkeyOption.fn.scancode),
            flags: .maskSecondaryFn
        )
        #expect(transition == .none)
    }

    /// 測試快捷鍵動態切換後狀態機能正常監聽新快捷鍵
    @Test("測試快捷鍵動態切換")
    func testDynamicHotkeySwitch() {
        let manager = HotkeyManager.shared
        
        // 1. 先設為左 Command
        manager.setHotkey(.leftCommand)
        manager.resetStateForTesting()

        // 左 Command 事件應有效
        let transition1 = manager.processFlagsChangedEvent(
            keyCode: Int64(HotkeyOption.leftCommand.scancode),
            flags: CGEventFlags(rawValue: 0x000008)
        )
        #expect(transition1 == .pressed)

        // 2. 切換為右 Command，且重置狀態
        manager.setHotkey(.rightCommand)
        manager.resetStateForTesting()

        // 此時左 Command 事件應被過濾
        let transition2 = manager.processFlagsChangedEvent(
            keyCode: Int64(HotkeyOption.leftCommand.scancode),
            flags: CGEventFlags(rawValue: 0x000008)
        )
        #expect(transition2 == .none)

        // 右 Command 事件應有效
        let transition3 = manager.processFlagsChangedEvent(
            keyCode: Int64(HotkeyOption.rightCommand.scancode),
            flags: CGEventFlags(rawValue: 0x000010)
        )
        #expect(transition3 == .pressed)
    }
}
