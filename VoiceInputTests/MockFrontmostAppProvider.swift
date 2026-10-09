@testable import VoiceInput

/// 回傳固定 bundle ID 並記錄呼叫次數的前景 App 提供者
final class MockFrontmostAppProvider: FrontmostAppProviding {
    private let bundleID: String?
    private(set) var callCount = 0

    init(bundleID: String?) {
        self.bundleID = bundleID
    }

    func frontmostBundleIdentifier() -> String? {
        callCount += 1
        return bundleID
    }
}
