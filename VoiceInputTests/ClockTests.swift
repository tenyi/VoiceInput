import Foundation
import Testing
@testable import VoiceInput

/// A1.1 + A1.9:Clock 協定與實作測試
@Suite("Clock")
struct ClockTests {

    /// TestClock.sleep 不實際等待,立即返回
    @Test("TestClock.sleep 立即返回不等待")
    func testClock_sleep_returnsImmediately() async {
        let clock = TestClock()

        let start = Date()
        await clock.sleep(for: .seconds(10))
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed < 1.0, "TestClock.sleep 應立即返回,實際等待了 \(elapsed) 秒")
        #expect(clock.sleepCallCount == 1)
        #expect(clock.sleepDurations.count == 1)
    }

    /// TestClock 記錄每次 sleep 的 duration
    @Test("TestClock 記錄 sleep duration")
    func testClock_recordsSleepDuration() async {
        let clock = TestClock()

        await clock.sleep(for: .seconds(2.0))
        await clock.sleep(for: .milliseconds(500))

        #expect(clock.sleepCallCount == 2)
        #expect(clock.sleepDurations.count == 2)
    }

    /// SystemClock 真的會等待
    @Test("SystemClock.sleep 實際等待指定時間")
    func systemClock_sleep_actuallyWaits() async {
        let clock = SystemClock()

        let start = Date()
        await clock.sleep(for: .milliseconds(100))
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed >= 0.05, "SystemClock.sleep 應實際等待,elapsed=\(elapsed)")
    }
}
