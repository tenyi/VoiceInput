import AppKit

/// 取得前景 App 資訊（可注入以利測試）
protocol FrontmostAppProviding {
    /// 目前前景 App 的 bundle ID；無法取得時回傳 nil
    func frontmostBundleIdentifier() -> String?
}

/// 以 NSWorkspace 取得前景 App
struct WorkspaceFrontmostAppProvider: FrontmostAppProviding {
    func frontmostBundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
