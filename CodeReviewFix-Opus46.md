# Code Review 修正執行紀錄

> 修正日期：2026-02-27 | 執行者：Tech Lead (Gemini 3.1 Pro)

本次依據優先順序，完成了**三項高價值問題**的精確修復，這些問題涵蓋了系統底層競態、執行緒安全與功能性邊界條件防護。修改已全數通過 `xcodebuild` 測試。

---

## ✅ 1. 修復 InputSimulator 的剪貼簿還原競態 (H-4)

**問題描述**：原本的邏輯是將備份的內容 (`currentContent == text`) 重新進行比對，如果字串吻合就執行還原。這會導致一個極端邊界條件：**當使用者剛好也拷貝了一樣字串時，使用者的剪貼簿圖文快取會被無預警清空還原。**

**修復方式**：
全面棄用字串內容比對，改走 macOS AppKit 最原生的 `NSPasteboard.changeCount`。

- 在塞入轉錄文字前，紀錄下 `initialChangeCount = pasteboard.changeCount`
- 在丟到主執行緒 0.2 秒延遲後，檢查 `if pasteboard.changeCount == initialChangeCount`
- 如果計數器沒有變動，代表剪貼簿還在我們的控制內，此時才觸發完整的無損還原。

---

## ✅ 2. 修復 AudioEngine 的 bufferCallback 資料競爭 (C-1)

**問題描述**：`bufferCallback` 會在背景 `captureQueue` 中透過 `captureOutput` 代理頻繁被讀取，但在 `stopRecording` 方法中，它卻在主執行緒被直接宣告為 `nil`。雖然不一定會立刻崩潰，但違反了 Thread Sanitizer 的安全存取規定。

**修復方式**：
將清理邏輯排入專屬佇列清空：

```swift
captureQueue.async { [weak self] in
    self?.bufferCallback = nil
}
```

確保讀取與清除都在同一個 `captureQueue` 序列中執行，根絕競態條件。

---

## ✅ 3. 修復 LLMService 針對 Ollama API 的重複路徑拼接 (M-5)

**問題描述**：對於使用者自訂的 Ollama API，原有的判斷邏輯 `hasSuffix("/v1/chat/completions")` 太過單一。如果使用者輸入 `http://localhost:11434/v1` 做為 Base URL，結果會變成 `http://localhost:11434/v1/v1/chat/completions`。

**修復方式**：
採用三段式後綴檢驗：

- `hasSuffix("/v1/chat/completions")` ➔ 採納該 URL
- `hasSuffix("/v1")` ➔ 後綴補上 `/chat/completions`
- 其他情況 ➔ 後綴補上 `/v1/chat/completions`

有效防堵自訂網址的不當疊加。

---
*註：我們刻意保留了 `AppDelegate` 的 Singleton 模式與 `@AppStorage`，因這在當前專案的權衡下屬於合理的實踐，不應盲目為了理想架構（Dogmatism）而去破壞穩定的雙向資料綁定機制。*
