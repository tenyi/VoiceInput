import Foundation

/// 時鐘抽象協定,用於將 `DispatchQueue.main.asyncAfter` 重構為可注入的時間控制
/// A1.1:定義統一介面,讓所有延遲操作可透過依賴注入替換為 TestClock
protocol Clock: Sendable {
    /// 暫停當前任務指定的時間長度
    /// - Parameter duration: 等待的時間長度
    func sleep(for duration: Duration) async
}

/// 生產環境使用的系統時鐘,實際等待指定時間
struct SystemClock: Clock {
    nonisolated init() {}
    func sleep(for duration: Duration) async {
        let nanoseconds = UInt64(duration.components.attoseconds / 1_000_000_000)
            + UInt64(duration.components.seconds) * 1_000_000_000
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}

/// 測試環境使用的可控時鐘,sleep 立即返回不實際等待
/// 測試可透過此實作跳過所有時間延遲,讓非同步流程同步完成
final class TestClock: Clock {
    /// 記錄 sleep 被呼叫的次數
    private(set) var sleepCallCount = 0
    /// 記錄每次 sleep 傳入的 duration
    private(set) var sleepDurations: [Duration] = []

    func sleep(for duration: Duration) async {
        sleepCallCount += 1
        sleepDurations.append(duration)
        // 不實際等待,立即返回
    }
}
