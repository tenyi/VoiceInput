import Foundation
@testable import VoiceInput

class MockInputSimulator: InputSimulatorProtocol {
    var hasAccessibilityPermission = true
    var insertedText: String?
    
    var requestPermissionCallback: ((Bool) -> Void)?
    
    func checkAccessibilityPermission(showAlert: Bool) -> Bool {
        return hasAccessibilityPermission
    }
    
    func requestAccessibilityPermission(completion: @escaping (Bool) -> Void) {
        requestPermissionCallback = completion
        // If not blocked, simulate immediate return
        completion(hasAccessibilityPermission)
    }
    
    func insertText(_ text: String) {
        insertedText = text
    }
}
