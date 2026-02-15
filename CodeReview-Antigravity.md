# VoiceInput 程式碼審查報告

**審查者**: Antigravity (Google DeepMind)
**審查日期**: 2026-02-15
**審查範圍**: 全部 14 個原始碼檔案

---

## 1. 執行摘要

VoiceInput 專案架構清晰，採用 SwiftUI + MVVM 模式，程式碼可讀性高且註解完善（繁體中文）。專案以 macOS Menu Bar App 形態運作，功能流程完整涵蓋「按下快捷鍵 → 錄音 → 轉錄 → 插入文字」的主要路徑。

**主要發現**：

| 嚴重度 | 數量 | 摘要 |
|--------|------|------|
| 🔴 高風險 | 3 | Whisper 未實作、Event Tap 無自動恢復、剪貼簿內容被覆蓋 |
| 🟠 中風險 | 5 | API Key 明文存放、LLM 無 timeout、錯誤回饋不足、AppleScript 相容性、inputNode 未清理 |
| 🟡 低風險 | 5 | 重複程式碼、魔術數字、多螢幕定位、背景色無差異、Item.swift 殘留 |

---

## 2. 與 Gemini / MiniMax 報告的比較

### 2.1 三方共識（確認正確的發現）

以下問題三方報告均有提及，代表高度可信：

| 問題 | Gemini | MiniMax | Antigravity |
|------|--------|---------|-------------|
| Whisper 模型未實作，僅支援 SFSpeech | ✅ | ✅ | ✅ |
| Event Tap 缺少 timeout 自動恢復 | ✅ | ❌ | ✅ |
| API Key 以 AppStorage 明文儲存 | ❌ | ✅ | ✅ |
| LLM 網路請求缺少 timeout | ❌ | ✅ | ✅ |
| 錄音失敗時無 UI 錯誤回饋 | ❌ | ✅ | ✅ |
| AppleScript 使用已棄用的 System Preferences | ❌ | ✅ | ✅ |
| selectModelFile() 重複程式碼 | ❌ | ✅ | ✅ |

### 2.2 Gemini 報告評價

**優點**：

- 精準指出 Whisper 功能缺口並給出具體實作建議（引入 whisper.cpp）
- 正確識別了 Event Tap 穩定性問題（`kCGEventTapDisabledByTimeout`）

**缺點**：

- 範圍過窄，僅關注 3 個關鍵問題，遺漏較多中低風險項目
- 未提及 API Key 安全性問題
- 未提及 LLM 的 timeout 問題
- 未提及 AppleScript 相容性問題

**結論**：Gemini 的報告**品質高但覆蓋不足**，更像是「重點摘要」而非全面審查。

### 2.3 MiniMax 報告評價

**優點**：

- 覆蓋面廣，從安全性、錯誤處理、API 相容性到記憶體管理各面向都有涉獵
- 列出具體的程式碼行號與片段，便於追蹤
- 提供了優先順序排列的改進表格

**缺點/不正確之處**：

1. **§1.2 「硬編碼虛擬碼」歸為高風險安全問題 ❌** — 魔術數字是程式碼品質問題，但絕非「安全性問題」。`0x37` 和 `0x09` 是 macOS 固定的 virtual key code，不存在被竄改的風險。應歸類為低風險的程式碼品質問題。

2. **§4.1 「AudioEngine 重複建立」的描述有誤 ❌** — MiniMax 說「不需再在 ViewModel 中持有參考」，但 `private var audioEngine = AudioEngine.shared` 只是**持有一個對單例的引用**，並非「重複建立」。這是正常的存取模式，問題不大。

3. **§4.3 「Potential retain cycle」的分析過度臆測 ⚠️** — 它指出 `onHotkeyPressed` 的 callback 鏈可能形成 retain cycle，但實際上 ViewModel 透過 `[weak self]` 捕獲自身，而 `HotkeyManager` 本身是單例不會被釋放，所以這裡不構成 retain cycle。

4. **§3.2 onChange API 問題** — 說法正確但實務影響有限。本專案的 deployment target 若已設定為 macOS 14+，則新語法完全合法。應先確認 deployment target。

5. **未發現 Event Tap 自動恢復問題** — 這是 Gemini 正確指出但 MiniMax 遺漏的重要問題。

**結論**：MiniMax 報告**覆蓋度佳但有部分錯誤歸類與誤判**，整體有參考價值但需要審慎篩選。

---

## 3. 獨立審查：高風險問題

### 🔴 3.1 Whisper 整合未實作

**檔案**: [VoiceInputViewModel.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/VoiceInputViewModel.swift#L60)

```swift
private var transcriptionService: TranscriptionServiceProtocol = SFSpeechTranscriptionService()
```

**問題**: UI 有 Whisper 模型路徑設定、`GEMINI.md` 明確要求支援 Whisper，但 `transcriptionService` 被寫死為 `SFSpeechTranscriptionService`。`whisperModelPath` 屬性始終未被使用。

**建議**:

1. 引入 `whisper.cpp` Swift binding
2. 新增 `WhisperTranscriptionService` 實作 `TranscriptionServiceProtocol`
3. 在 ViewModel 中根據 `whisperModelPath` 是否為空動態切換

### 🔴 3.2 Event Tap 無自動恢復機制

**檔案**: [HotkeyManager.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/HotkeyManager.swift#L76-L80)

```swift
let callback: CGEventTapCallBack = { proxy, type, event, refcon in
    guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    manager.handleEvent(proxy: proxy, type: type, event: event)
    return Unmanaged.passUnretained(event)
}
```

**問題**: 當系統因處理過慢而停用 Event Tap（觸發 `kCGEventTapDisabledByTimeout`），程式碼完全沒有檢測與恢復邏輯。使用者將會遇到「快捷鍵突然失效」而不知原因。

**建議**: 在 callback 中增加檢測：

```swift
let callback: CGEventTapCallBack = { proxy, type, event, refcon in
    // 若 Event Tap 被系統停用，自動重新啟用
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let refcon = refcon {
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }
    // ... 正常處理邏輯
}
```

### 🔴 3.3 剪貼簿內容被覆蓋且無備份

**檔案**: [InputSimulator.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/InputSimulator.swift#L48-L71)

```swift
private func pasteText(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    // ... 模擬 Cmd+V
}
```

**問題**: 此處直接清除使用者剪貼簿並寫入轉錄文字。如果使用者剪貼簿中有重要內容（如密碼、程式碼片段），會被靜默覆蓋。**兩份報告均未提及此問題。**

**建議**:

1. 在覆寫前備份剪貼簿內容
2. 模擬貼上完成後，延遲恢復剪貼簿
3. 或改用 `CGEventKeyboardSetUnicodeString` 直接輸入文字，完全避免操作剪貼簿

```swift
private func pasteText(_ text: String) {
    let pasteboard = NSPasteboard.general
    // 備份現有剪貼簿
    let backup = pasteboard.string(forType: .string)

    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    // ... 模擬 Cmd+V

    // 延遲恢復剪貼簿
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        pasteboard.clearContents()
        if let backup = backup {
            pasteboard.setString(backup, forType: .string)
        }
    }
}
```

---

## 4. 獨立審查：中風險問題

### 🟠 4.1 API Key 明文儲存於 UserDefaults

**檔案**: [VoiceInputViewModel.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/VoiceInputViewModel.swift#L37)

```swift
@AppStorage("llmAPIKey") var llmAPIKey: String = ""
```

`@AppStorage` 底層為 `UserDefaults`，資料以 plist 明文存放在磁碟上。雖然 macOS 有沙箱保護，但仍建議使用 **Keychain** 儲存 API Key。

### 🟠 4.2 LLM 網路請求缺少 timeout

**檔案**: [LLMService.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/LLMService.swift#L113)

所有四個 provider (OpenAI, Anthropic, Ollama, Custom) 的 `URLRequest` 都未設定 `timeoutInterval`，預設為 60 秒。對於文字修正場景，30 秒已綽綽有餘。

```swift
// 建議加入
request.timeoutInterval = 30
```

### 🟠 4.3 錄音失敗時無使用者回饋

**檔案**: [VoiceInputViewModel.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/VoiceInputViewModel.swift#L193-L197)

```swift
} catch {
    // 錄音啟動失敗
    WindowManager.shared.hideFloatingWindow()
    appState = .idle
}
```

catch 區塊空白處理，使用者完全不知道為何錄音沒有開始。應至少顯示一個通知或在浮動視窗中短暫顯示錯誤訊息。

### 🟠 4.4 AppleScript 使用 "System Preferences" 已過時

**檔案**: [PermissionManager.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/PermissionManager.swift#L352-L381)

macOS Ventura (13+) 將 "System Preferences" 重新命名為 "System Settings"，AppleScript 呼叫會失敗。目前程式碼有 fallback 機制（失敗時改用 URL），但應直接使用 URL 方式，省去 AppleScript 依賴：

```swift
func openSystemPreferences(for type: PermissionType) {
    if let url = type.systemPreferencesURL {
        NSWorkspace.shared.open(url)
    }
}
```

### 🟠 4.5 inputNode 未在 stopRecording 中清理

**檔案**: [AudioEngine.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/AudioEngine.swift#L81-L85)

```swift
func stopRecording() {
    inputNode?.removeTap(onBus: 0)
    audioEngine.stop()
    isRecording = false
    // inputNode 仍持有引用，應設為 nil
}
```

---

## 5. 獨立審查：低風險問題

### 🟡 5.1 selectModelFile() 重複定義

`ContentView.swift:176-186` 和 `SettingsView.swift:180-190` 有完全相同的 `selectModelFile()` 函數。建議提取為共用工具函數或放在 ViewModel 中。

### 🟡 5.2 虛擬碼使用魔術數字

**檔案**: `InputSimulator.swift:56-59`

`0x37`（Command）和 `0x09`（V）應使用 Carbon 的 `kVK_Command` 和 `kVK_ANSI_V` 常數。

### 🟡 5.3 浮動視窗固定在主螢幕中央

**檔案**: `WindowManager.swift:70-75`

多螢幕環境下，使用者可能在非主螢幕工作，浮動視窗卻顯示在主螢幕。應使用 `NSScreen.screens.first(where:)` 或 `NSScreen.main` 配合游標位置判斷。

### 🟡 5.4 FloatingPanelView 的 backgroundColor 無差異

**檔案**: `WindowManager.swift:152-160`

三個狀態回傳完全相同的顏色 `Color.black.opacity(0.75)`。若無差異化需求，可簡化為單一回傳值；若有計畫差異化（如錄音用紅色底色），應在此實作。

### 🟡 5.5 Item.swift 為專案範本殘留

`Item.swift` 是 Xcode SwiftData 範本自動產生的檔案，專案中未使用。建議移除以保持專案整潔。

---

## 6. 架構與設計觀察

### ✅ 做得好的部分

| 面向 | 評價 |
|------|------|
| **MVVM 分層** | `VoiceInputViewModel` 職責清晰，View 不直接處理邏輯 |
| **Protocol 導向** | `TranscriptionServiceProtocol` 為未來擴充（Whisper）奠定基礎 |
| **單例使用** | `AudioEngine`, `HotkeyManager`, `InputSimulator`, `PermissionManager` 等核心服務合理使用單例 |
| **記憶體管理** | 全域一致使用 `[weak self]` 避免 retain cycle |
| **Menu Bar App** | 以 `MenuBarExtra` 實作，搭配 `NSPanel` 浮動視窗，架構正確 |
| **權限管理** | `PermissionManager` 統一處理三種權限，串連式請求邏輯完整 |
| **LLM 整合** | 支援 4 種 provider，錯誤類型完善 |
| **繁體中文註解** | 全面且規範，符合使用者要求 |

### ⚠️ 架構建議

1. **ViewModel 中 `@ObservedObject var permissionManager`** — 在非 View 層級使用 `@ObservedObject` 不會自動觸發 UI 更新，應使用 `Combine` 的 `sink` 或直接透過 View 訂閱。
2. **TranscriptionService 的錯誤傳播** — `TranscriptionService.swift:68` 的識別錯誤僅 `print` 輸出，未透過 callback 通知 ViewModel，使用者無法得知辨識失敗。
3. **LLM 回應解析重複** — `callOpenAI`、`callAnthropic`、`callOllama`、`callCustomAPI` 的 JSON 解析邏輯高度相似，建議抽取共用的 response parsing 方法。
4. **App 缺少正式的 logging** — 所有錯誤處理都用 `print()`，正式版應改用 `os.Logger` 或 `OSLog`。

---

## 7. 綜合優先順序建議

| 優先順序 | 項目 | 檔案 | 難度 |
|----------|------|------|------|
| **P0** | 新增 Event Tap 自動恢復機制 | `HotkeyManager.swift` | 低 |
| **P0** | 備份/復原剪貼簿內容 | `InputSimulator.swift` | 低 |
| **P1** | 實作 Whisper 轉錄服務 | 新增 `WhisperTranscriptionService.swift` | 高 |
| **P1** | 新增 LLM 請求 timeout | `LLMService.swift` | 低 |
| **P1** | 新增錄音失敗的 UI 回饋 | `VoiceInputViewModel.swift` | 低 |
| **P2** | 改用 Keychain 儲存 API Key | `VoiceInputViewModel.swift` | 中 |
| **P2** | 移除 AppleScript，改用 URL 開啟設定 | `PermissionManager.swift` | 低 |
| **P2** | 轉錄錯誤傳播到 ViewModel | `TranscriptionService.swift` | 低 |
| **P3** | 提取 selectModelFile() 共用函數 | `ContentView` / `SettingsView` | 低 |
| **P3** | 使用具名常數取代虛擬碼魔術數字 | `InputSimulator.swift` | 低 |
| **P3** | 移除 Item.swift 範本殘留 | `Item.swift` | 低 |
| **P3** | 改用 os.Logger 取代 print | 全域 | 中 |

---

## 8. 總結

| 評比面向 | 評分 | 說明 |
|----------|------|------|
| 程式碼結構 | ⭐⭐⭐⭐ | MVVM 分層得宜，Protocol 運用良好 |
| 功能完整度 | ⭐⭐⭐ | 核心流程可運作，但 Whisper 是最大缺口 |
| 錯誤處理 | ⭐⭐⭐ | 有基本架構但多處缺乏使用者回饋 |
| 安全性 | ⭐⭐⭐ | API Key 儲存、剪貼簿操作需改進 |
| 穩定性 | ⭐⭐⭐ | Event Tap 是重大隱患 |
| 程式碼品質 | ⭐⭐⭐⭐ | 註解完善、命名一致、記憶體管理正確 |
| 可擴充性 | ⭐⭐⭐⭐ | Protocol 與服務架構為擴充留下良好基礎 |

### 與其他報告的對比結論

- **Gemini** 的報告更精簡、重點突出，但覆蓋度不足，適合作為快速摘要
- **MiniMax** 的報告更全面、格式完整，但有部分分類錯誤（虛擬碼歸入安全性）和事實錯誤（AudioEngine「重複建立」的說法不正確）
- 本報告新增發現了**剪貼簿覆蓋問題**（🔴 高風險）、**ViewModel 中 @ObservedObject 使用不當**、**TranscriptionService 錯誤未傳播**、**Item.swift 殘留**等，均為前兩份報告所遺漏

---

*此報告由 Antigravity AI 程式碼審查工具獨立生成*
