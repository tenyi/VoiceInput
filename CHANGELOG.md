# 變更日誌 (CHANGELOG.md)

所有本專案的重大變更都將記錄於此檔案中。

本專案遵循 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/) 版本格式。

---

## [1.0.0] - 2026-06-11

### 🚀 新增 (Added)
* **全量單元測試保護網**：補齊全專案 9 個核心服務（`AudioEngine`、`PermissionManager`、`InputSimulator`、`HistoryManager`、`KeychainHelper`、`TranscriptionManager`、`LLMService`、`HotkeyManager`、`WindowManager`、`SFSpeechTranscriptionService`）的 81 個單元測試案例，消除測試盲區。
* **可控時間測試機制**：新增 `Clock` / `SystemClock` / `TestClock` 抽象與實作，在測試中注入 `TestClock` 來跳過所有 `asyncAfter` 延遲，大幅度加速測試速度並提升穩定性。
* **Xcode Previews 安全護欄**：新增 `ProcessInfo.processInfo.isRunningForPreview` 守衛，阻止 Xcode 預覽環境下啟動全域 CGEventTap 或進行實際的麥克風錄音，避免佔用系統資源或導致 Swift Concurrency 鎖死。
* **自動化 10 輪測試驗證**：建立 [run-tests-10x.sh](file:///Users/tenyi/Projects/VoiceInput/run-tests-10x.sh) 連續測試套件穩定性驗證工具，以保證代碼與測試無 flaky 問題。
* **設定視窗與狀態本地化**：在 `en.lproj`、`zh-Hant.lproj`、`zh-Hans.lproj` 中補齊本地化翻譯，支援設定視窗標題隨系統語系動態變更。

### ⚙️ 變更 (Changed)
* **依賴注入 (DI) 重構**：重構 `VoiceInputViewModel` 支援 `HistoryManager`、`LLMSettingsViewModel`、`ModelManager` 的建構子注入，消除 ViewModel 與 AppDelegate 單例的硬耦合。
* **熱鍵效能精簡**：簡化全域 `CGEventTap` 事件監聽遮罩，僅保留對修飾鍵 `flagsChanged` 事件的監聽，移除了無效的 keyUp/keyDown 偵測，顯著降低系統 CPU 開銷。
* **AppStatusMessage 動態化**：重構 `AppStatusMessage` 常數為動態 `NSLocalizedString` 計算屬性，在無損相容原有 `String` 型別 API 的前提下，實現執行期 UI 狀態字串的動態本地化。
* **LLM 服務升級**：將 `LLMService` 的 Anthropic API 版本參數抽離為常量，並升級到最新推薦標準。

### 🐛 修復 (Fixed)
* **Swift 6 編譯警告歸零**：修復全專案在 Swift 6 / Concurrency / Actor Isolation 下的所有編譯警告，實現 0 warnings 乾淨編譯。
* **Keychain 競態修復**：使用 `NSLock` 鎖序列化 `KeychainHelper` 的 write 流程，防止在多執行緒環境下 `SecItemUpdate` 與 `SecItemAdd` 之間發生 TOCTOU 競態導致的寫入錯誤。
* **敏感資訊截斷與防漏**：修正了 `LLMServiceError` 在收到非 JSON 或超長 HTTP 錯誤響應時，會截斷並進行安全性過濾後再拋給 UI，防止洩露敏感堆疊。
* **持久化吞錯與職責解耦**：
  * 修復了 `HistoryManager` 中解碼損毀資料時的靜默吞錯與崩潰，提供安全 fallback 策略。
  * 將剪貼簿複製 `copyHistoryText` 自 `HistoryManager` 中剝離，移至 UI 層以實現職責分離。
* **Log 跳脫字元錯誤**：修正了 `logger.error` 語句中的雙反斜線跳脫字元 `\\(`，使其能正常印出錯誤描述。
* **Flaky 測試修正**：在 `viewModel_toggleRecording` 單元測試中，透過 TestClock Debounce Polling 替代固定時間 `sleep`，徹底根治測試隨機失敗的問題。
* **優雅退出 Flush 數據**：在 `applicationWillTerminate` 的 `_exit(0)` 強制退出前，加入 Keychain 寫入的同步 Flush 邏輯，保證用戶設定不遺失。
