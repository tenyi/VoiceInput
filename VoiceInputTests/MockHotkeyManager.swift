import Foundation
@testable import VoiceInput

class MockHotkeyManager: HotkeyManagerProtocol {
    var onHotkeyPressed: (() -> Void)?
    var onHotkeyReleased: (() -> Void)?
    
    var currentHotkey: HotkeyOption = .rightCommand
    var isMonitoring = false
    
    func setHotkey(_ option: HotkeyOption) {
        currentHotkey = option
    }
    
    func startMonitoring() {
        isMonitoring = true
    }
    
    func stopMonitoring() {
        isMonitoring = false
    }
    
    // Test Helpers
    func simulatePress() {
        onHotkeyPressed?()
    }
    
    func simulateRelease() {
        onHotkeyReleased?()
    }
}
