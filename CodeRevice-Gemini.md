# VoiceInput 程式碼審查報告 (Code Review Report)

## 1. 執行摘要 (Executive Summary)

本報告針對 VoiceInput 專案進行全面的程式碼審查。目前專案架構清晰，採用 SwiftUI + MVVM 模式，且程式碼註解確實遵循繁體中文規範。然而，發現一項嚴重的功能缺失：**Whisper 語音辨識整合尚未實作**，目前僅支援 Apple 系統內建語音辨識。此外，全域快捷鍵管理 (HotkeyManager) 部分存在潛在的穩定性風險，可能導致快捷鍵失效。

## 2. 功能缺口分析 (Feature Gap Analysis)

| 功能需求 | 當前狀態 | 說明 |
| :--- | :--- | :--- |
| **語音轉文字** | ⚠️ 部分完成 | 僅支援 Apple SFSpeech。**Whisper 模型載入與推論尚未實作。** |
| **文字插入** | ✅ 已完成 | 透過 `InputSimulator` (Cmd+V / CGEvent) 實作，功能正常。 |
| **多語言支援** | ✅ 已完成 | 支援 zh-TW, zh-CN, en-US, ja-JP 選單，但目前僅對應 SFSpeech Locale。 |
| **全域快捷鍵** | ⚠️ 有風險 | 實作了 `CGEvent.tapCreate`，但在高負載或逾時情況下可能被系統停用而未自動重啟。 |
| **LLM 文字修正** | ✅ 已完成 | `LLMService` 支援 OpenAI, Anthropic, Ollama 及自訂 API，架構完整。 |
| **UI/UX** | ✅ 已完成 | 浮動視窗與設定頁面皆已實作，視覺效果良好。 |

## 3. 關鍵問題與建議 (Critical Issues & Recommendations)

### 3.1. 缺少 Whisper 整合 (Missing Whisper Integration)

- **問題**: `GEMINI.md` 明確要求支援 Whisper 模型 (`.bin`)，且 UI 有相關設定欄位。但在 `VoiceInputViewModel.swift` 中，`transcriptionService` 被寫死為 `SFSpeechTranscriptionService`。
- **影響**: 無法離線使用高品質模型，且與專案目標不符。
- **建議**:
    1. 引入 `whisper.cpp` 的 Swift 封裝 (如 `swift-whisper` 或直接整合 C++ code)。
    2. 建立 `WhisperTranscriptionService` 實作 `TranscriptionServiceProtocol`。
    3. 在 `VoiceInputViewModel` 中根據設定動態切換 Service。

### 3.2. 快捷鍵穩定性 (Hotkey Stability)

- **問題**: `HotkeyManager.swift` 使用 `CGEvent.tapCreate` 監聽鍵盤事件。系統可能會因為處理過慢或其他原因停用 Event Tap (Timeout)。目前程式碼沒有處理 `kCGEventTapDisabledByTimeout` 或 `kCGEventTapDisabledByUserInput` 的自動重啟機制。
- **影響**: 使用者可能會遇到「快捷鍵突然失效」的情況，必須重啟 App 才能恢復。
- **建議**:
  - 在 `CGEventTapCallBack` 中增加對 `.tapDisabledByTimeout` 與 `.tapDisabledByUserInput` 的處理，偵測到時自動呼叫 `CGEvent.tapEnable` 重新啟用。

### 3.3. 權限處理 (Permission Handling)

- **觀察**: `InputSimulator` 在執行貼上時，雖然會檢查輔助功能權限，但若無權限時的行為僅依賴 `hasRequested` 標記。
- **建議**: 確保在每次執行關鍵操作 (如 `post(tap: .cghidEventTap)`) 前，若失敗能有明確的 UI 提示引導使用者去設定。

## 4. 程式碼品質與架構 (Code Quality & Architecture)

- **優點**:
  - **MVVM 架構**: `VoiceInputViewModel` 職責清晰，與 View 分離良好。
  - **註解規範**: 符合使用者要求，詳細且使用繁體中文。
  - **UI 實作**: 浮動視窗使用 `NSPanel` + `SwiftUI` 是一個強大的組合，兼顧了靈活性與開發效率。

- **待改進**:
  - **InputSimulator**: 目前主要依賴 `Cmd+V` 貼上。建議增加「直接輸入 (Type writer)」模式作為備援，以應對某些禁止貼上的輸入框 (這點較次要，視需求而定)。

## 5. 下一步行動計畫 (Action Plan)

建議依照以下優先順序進行修正：

1. **修復快捷鍵穩定性**: 強化 `HotkeyManager`，確保長時間運行不中斷。
2. **實作 Whisper 服務**: 引入 whisper.cpp 相關依賴，並實作 `WhisperTranscriptionService`。
3. **整合服務切換**: 修改 ViewModel 邏輯，允許使用者在設定頁面切換引擎。
