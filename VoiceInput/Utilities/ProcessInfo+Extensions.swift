import Foundation

extension ProcessInfo {
    /// 判斷目前是否正在 Xcode Preview 中執行
    var isRunningForPreview: Bool {
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
