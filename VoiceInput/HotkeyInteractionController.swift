import Foundation
import os

// MARK: - T4-1：錄音觸發模式

/// 錄音觸發模式
/// - pressAndHold：按住說話、放開送出（預設）
/// - toggle：按一次開始錄音、再按一次停止並送出
enum RecordingTriggerMode: String, CaseIterable {
    case pressAndHold = "pressAndHold"
    case toggle = "toggle"

    /// 顯示名稱
    var displayName: String {
        switch self {
        case .pressAndHold: return "按住說話（放開送出）"
        case .toggle: return "單鍵切換（再按停止）"
        }
    }
}

// MARK: - T4-2：HotkeyInteractionController（快捷鍵互動策略層）

/// 負責將 HotkeyManager 的原始按鍵事件，依「觸發模式」轉換為語意事件
/// （startRecording / stopAndTranscribe），解耦 ViewModel 對按鍵細節的依賴
///
/// 設計原則：
/// - 輸入：`hotkeyPressed()` / `hotkeyReleased()`（來自 HotkeyManager）
/// - 輸出：`onStartRecording` / `onStopAndTranscribe`（供 ViewModel 執行）
/// - 模式切換可即時生效，不需重啟 App
class HotkeyInteractionController {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput",
        category: "HotkeyInteractionController"
    )

    // MARK: - 輸出回調（ViewModel 訂閱這兩個）

    /// 開始錄音的回調
    var onStartRecording: (() -> Void)?

    /// 停止錄音並轉寫的回調
    var onStopAndTranscribe: (() -> Void)?

    // MARK: - 狀態

    /// 目前的觸發模式
    var mode: RecordingTriggerMode {
        didSet {
            logger.info("觸發模式已切換: \(self.mode.rawValue)")
        }
    }

    /// 是否正在錄音（由 ViewModel 更新，用於 Toggle 模式的判斷）
    var isRecording: Bool = false

    /// Toggle 模式防重入旗標：避免連按過快造成重複 start/stop
    private var isTransitioning: Bool = false

    // MARK: - 初始化

    init(mode: RecordingTriggerMode = .pressAndHold) {
        self.mode = mode
    }

    // MARK: - T4-3：快捷鍵事件入口

    /// 快捷鍵按下事件
    func hotkeyPressed() {
        logger.info("[HotkeyInteractionController] pressed, mode=\(self.mode.rawValue), isRecording=\(self.isRecording)")

        switch mode {
        case .pressAndHold:
            // Press-and-Hold：按下時開始錄音（若目前閒置）
            if !isRecording {
                triggerStart()
            }

        case .toggle:
            // Toggle 模式：按下時依狀態決定開始或停止
            // 若正在轉場（防重入），忽略
            guard !isTransitioning else {
                logger.info("[Toggle] 忽略按下事件：正在轉場中")
                return
            }

            if !isRecording {
                // 閒置 → 開始錄音
                isTransitioning = true
                triggerStart()
                // 短暫 debounce，避免極速雙擊
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.isTransitioning = false
                }
            } else {
                // 錄音中 → 停止並轉寫
                isTransitioning = true
                triggerStop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.isTransitioning = false
                }
            }
        }
    }

    /// 快捷鍵放開事件
    func hotkeyReleased() {
        logger.info("[HotkeyInteractionController] released, mode=\(self.mode.rawValue), isRecording=\(self.isRecording)")

        switch mode {
        case .pressAndHold:
            // Press-and-Hold：放開時停止錄音（若目前錄音中）
            if isRecording {
                triggerStop()
            }

        case .toggle:
            // Toggle 模式：放開鍵不觸發任何動作（只是狀態同步）
            logger.info("[Toggle] 放開事件忽略（Toggle 模式不依賴放開觸發）")
        }
    }

    // MARK: - 私有輔助

    /// 觸發開始錄音
    private func triggerStart() {
        logger.info("[HotkeyInteractionController] → startRecording")
        onStartRecording?()
    }

    /// 觸發停止並轉寫
    private func triggerStop() {
        logger.info("[HotkeyInteractionController] → stopAndTranscribe")
        onStopAndTranscribe?()
    }
}
