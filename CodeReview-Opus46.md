# VoiceInput 全專案 Code Review 報告

> 審查日期：2026-02-27 | 審查範圍：12 個核心 Swift 原始碼檔案 + 測試

---

## 📊 總覽評分

| 面向 | 分數 | 說明 |
|------|------|------|
| **架構設計** | ⭐⭐⭐⭐ | MVVM + 服務層分明，DI 支援良好 |
| **程式碼品質** | ⭐⭐⭐⭐ | 註解完整，命名一致，職責清晰 |
| **並行安全性** | ⭐⭐⭐ | 有意識處理 MainActor，但有數處資料競爭風險 |
| **錯誤處理** | ⭐⭐⭐ | KeychainHelper 已重構為 throwing，部分地方仍吞掉錯誤 |
| **安全性** | ⭐⭐⭐⭐ | API Key 走 Keychain，敏感資料未外洩 |
| **測試覆蓋率** | ⭐⭐ | 核心流程有測，但多數服務類無對應測試 |
| **效能** | ⭐⭐⭐⭐ | 音訊處理在背景執行緒，UI 不卡頓 |

---

## 🔴 嚴重問題 (Critical)

### C-1. `AudioEngine` 缺少 `@MainActor` 標記，多處存在資料競爭

**檔案**: [AudioEngine.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/AudioEngine.swift)

`AudioEngine` 使用 `@Published` 屬性（`isRecording`, `availableInputDevices`, `selectedDeviceID`），這些會觸發 SwiftUI View 更新，但 `captureOutput` 在 `captureQueue`（背景執行緒）上執行，而 `refreshAvailableDevices()` 手動 `DispatchQueue.main.async` 來更新 `@Published` 屬性。

```swift
// ⚠️ captureQueue 背景執行緒回呼 bufferCallback
func captureOutput(_ output: ..., didOutput sampleBuffer: ...) {
    guard let callback = bufferCallback else { return } // bufferCallback 可能在主執行緒被清空
    // ...
    callback(pcmBuffer) // 回呼在背景執行緒
}
```

**風險**: `bufferCallback` 在 `stopRecording()` 中被設為 `nil`（主執行緒），但 `captureOutput` 在 `captureQueue` 讀取它—這是經典的 **讀寫競爭**。

**建議**: 將 `bufferCallback` 的存取限制在 `captureQueue` 或使用 `os_unfair_lock`/`actor`。

---

### C-2. `LLMService` HTTP 回應未檢查 StatusCode

**檔案**: [LLMService.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/LLMService.swift#L101-L108)

```swift
private func performRequest(_ request: URLRequest, parser: (Data) throws -> String) async throws -> String {
    let (data, _) = try await networkProvider.data(for: request) // ← response 被丟棄
    return try parser(data)
}
```

`URLResponse` 直接被忽略。當 API 回傳 `401 Unauthorized` 或 `429 Rate Limited` 時，`parser` 可能無法解析 body 而拋出誤導性的 `invalidResponse` 錯誤，對使用者毫無幫助。

**建議**:

```swift
let (data, response) = try await networkProvider.data(for: request)
if let httpResponse = response as? HTTPURLResponse,
   !(200...299).contains(httpResponse.statusCode) {
    // 嘗試從 body 解析 error message，否則用 statusCode 回報
    throw LLMServiceError.httpError(statusCode: httpResponse.statusCode, ...)
}
```

---

### C-3. `AppDelegate` 的 `static let` 全域狀態在測試環境中無法替換

**檔案**: [VoiceInputApp.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/VoiceInputApp.swift#L34-L37)

```swift
static let sharedViewModel = VoiceInputViewModel()           // ← 不可替換
static let sharedLLMSettingsViewModel = LLMSettingsViewModel() // ← 不可替換
static let sharedModelManager = ModelManager()
static let sharedHistoryManager = HistoryManager()
```

這些 `static let` 在 process 第一次存取時就被初始化（`lazy static`），在單元測試中無法注入 mock。且多個測試 suite 共享同一份實例。

**影響**: `VoiceInputViewModel.performLLMCorrection()` 直接呼叫 `AppDelegate.sharedLLMSettingsViewModel`，使得 ViewModel 的 LLM 邏輯無法單元測試。

---

## 🟠 高優先度問題 (High)

### H-1. `VoiceInputViewModel` 大量使用 `DispatchQueue.main.asyncAfter` 產生不可控的時序

**檔案**: [VoiceInputViewModel.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/VoiceInputViewModel.swift)

至少有 **6 處** 使用固定延遲（`0.1s`, `0.5s`, `1.0s`, `2.0s`），這些都：

- 在單元測試中不可控（測試必須等真實時間）
- 在慢速機器上可能延遲不夠

| 位置 | 延遲 | 用途 |
|------|------|------|
| `startRecording()` 錯誤處理 | 2.0s | 顯示錯誤訊息後隱藏 |
| `stopRecordingAndTranscribe()` | 0.5s | 讓使用者看到轉寫動畫 |
| `insertText()` | 0.1s | 等焦點切換 |
| `hideWindow()` | 1.0s | 顯示結果後隱藏 |
| `proceedToInsertAndHide()` LLM 錯誤 | 2.0s | 顯示錯誤訊息 |
| `startRecording()` 缺模型 | 2.0s | 顯示錯誤後重置 |

**建議**: 抽出一個 `@MainActor func delay(_ seconds: TimeInterval)` 或使用 `Task.sleep`（在測試中可注入 `Clock`）。

---

### H-2. `PermissionManager` 的 `requestAllPermissionsForcibly` 方法永遠不會被呼叫

**檔案**: [PermissionManager.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/PermissionManager.swift)

`requestAllPermissionsForcibly` 標記為 `private`，且在類別內部**沒有任何呼叫方**。這是一段死碼（dead code）。

---

### H-3. `LLMSettingsViewModel` 混用 `@AppStorage` 與手動 `UserDefaults` 讀取

**檔案**: [LLMSettingsViewModel.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/LLMSettingsViewModel.swift)

`init()` 中的註解說明了問題：

```swift
// 為了避免 AppStorage 尚未掛載完成導致的競態條件，手動讀取 UserDefaults.standard 取得真正的值
let realProviderString = userDefaults.string(forKey: "llmProvider") ?? LLMProvider.openAI.rawValue
```

這暗示 `@AppStorage` 在 init 時可能尚未與 `UserDefaults` 同步。若 init 時序改變（例如 SwiftUI 生命週期調整），可能再次出現同步問題。

此外，`resolveEffectiveConfiguration()` 也繞過 `@AppStorage` 直接讀 `UserDefaults`：

```swift
let providerString = userDefaults.string(forKey: "llmProvider") ?? ...
```

**建議**: 統一走 `UserDefaults` + `@Published`（像 `VoiceInputViewModel` 一樣），既然你已經做了 DI 支援，拔掉 `@AppStorage` 可以消除這個競態。但這與 GEMINI.md 中的架構決策衝突 — **需確認是否接受此 trade-off**。

---

### H-4. `InputSimulator.pasteText()` 剪貼簿還原邏輯存在競態

**檔案**: [InputSimulator.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/InputSimulator.swift)

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
    let currentContent = pasteboard.string(forType: .string)
    if currentContent == text { // ← 如果使用者貼的文字碰巧與原文相同呢？
        pasteboard.clearContents()
        // 還原舊剪貼簿...
    }
}
```

此比較 `currentContent == text` 只比較了 `.string` 型別，但原始剪貼簿可能包含圖片、RTF 等。當使用者複製的新內容恰好也是同樣文字時，會被錯誤還原。

**建議**: 使用 `NSPasteboard.changeCount` 來判斷是否有新的複製操作，而非比較內容。

---

## 🟡 中優先度問題 (Medium)

### M-1. `HotkeyManager` 的 `Unmanaged.passUnretained(self)` 潛在懸空指標

**檔案**: [HotkeyManager.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/HotkeyManager.swift)

```swift
let refcon = Unmanaged.passUnretained(self).toOpaque()
```

雖然 `HotkeyManager` 是 singleton（`static let shared`），理論上不會被 dealloc，但如果未來架構改變，這裡會變成 **use-after-free**。

---

### M-2. `WindowManager` 使用 `AnyView` 型別擦除

**檔案**: [WindowManager.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/WindowManager.swift#L74)

```swift
let hostingController = NSHostingController(rootView: AnyView(contentView))
```

`AnyView` 會阻止 SwiftUI 的 diff 最佳化。雖然對只有一個浮動視窗的場景影響不大，但這是不良實踐。

**建議**: 使用泛型 `NSHostingController<FloatingPanelView>` 直接承載。

---

### M-3. `DictionaryManager` 儲存 `saveItems()` / `loadItems()` 吞掉解碼錯誤

**檔案**: [DictionaryManager.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/DictionaryManager.swift)

```swift
private func saveItems() {
    if let encoded = try? JSONEncoder().encode(items) { // ← 靜默吞掉錯誤
        userDefaults.set(encoded, forKey: storageKey)
    }
}
```

如果 `DictionaryItem` 的 schema 變更導致 encode/decode 失敗，使用者會看到空白詞典但完全不知道原因。

---

### M-4. `TranscriptionManager` 未標記 `@MainActor`，但 `@Published` 需要主執行緒更新

**檔案**: [TranscriptionManager.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/TranscriptionManager.swift)

`setupTranscriptionCallback()` 中手動 `DispatchQueue.main.async`，但 `startTranscription()` 和 `stopTranscription()` 直接修改 `isTranscribing`（`@Published`），沒有做主執行緒保護。

---

### M-5. `LLMService.callOllama` 拼接 URL 可能產生重複路徑

**檔案**: [LLMService.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/LLMService.swift)

```swift
let endpoint = baseURL.hasSuffix("/v1/chat/completions") 
    ? baseURL 
    : "\(baseURL)/v1/chat/completions"
```

如果使用者輸入 `http://localhost:11434/v1`，結果會是 `http://localhost:11434/v1/v1/chat/completions`。只檢查完整後綴不夠。

---

### M-6. 硬編碼字串散落各處，缺乏常數管理

多處重複的魔術字串：

- `"等待輸入..."` 出現在 `VoiceInputViewModel`、`HistoryManager`、`ContentView`
- `"識別錯誤："` 出現在 `VoiceInputViewModel`、`TranscriptionManager`、`HistoryManager`
- `"com.tenyi.voiceinput"` Keychain service 名稱分散在 `LLMSettingsViewModel` 中

**建議**: 抽出為常數或 `AppStatusMessage` enum（已部分做，但不完整）。

---

## 🔵 低優先度 / 改進建議 (Low)

### L-1. 測試覆蓋不足

目前測試僅覆蓋：

- ✅ `LLMSettingsViewModel.resolveEffectiveConfiguration`
- ✅ `HotkeyInteractionController` 狀態機
- ✅ `VoiceInputViewModel.toggleRecording`（基本流程）
- ✅ `DictionaryManager` 基本操作

**缺少測試**：

- ❌ `LLMService` 各 provider 的 request/response 處理
- ❌ `AudioEngine` 錄音啟停邏輯
- ❌ `PermissionManager` 權限流程
- ❌ `InputSimulator` 剪貼簿操作
- ❌ `HistoryManager` 持久化操作
- ❌ `TranscriptionManager` 引擎切換邏輯
- ❌ `KeychainHelper` 各種 OSStatus 場景

### L-2. `HistoryManager.copyHistoryText` 職責不屬於此類

剪貼簿操作應屬於 UI 層或 `InputSimulator`，不應放在資料管理層。

### L-3. `Anthropic-Version` 使用寫死的 `2023-06-01`

[LLMService.swift](file:///Users/tenyi/Projects/VoiceInput/VoiceInput/LLMService.swift) 中：

```swift
request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
```

這是一個過時的 API 版本，建議至少改為可設定的參數或更新至最新版。

### L-4. `VoiceInputApp.body` 中使用 `@StateObject` 包裝 `static let`

```swift
@StateObject private var viewModel = AppDelegate.sharedViewModel
```

`@StateObject` 的設計是為了在 View 層管理物件生命週期。但 `AppDelegate.sharedViewModel` 是 app-level singleton，用 `@ObservedObject` 或直接 `.environmentObject()` 更語義正確。

---

## ✅ 做得好的地方

1. **KeychainHelper 重構完善** — add-or-update 模式，throwing API，錯誤類型清晰
2. **HotkeyManager 狀態機設計** — `processFlagsChangedEvent` 可重播、可測試
3. **VoiceInputViewModel 的 DI 架構** — 建構子注入 `AudioEngineProtocol`、`HotkeyManagerProtocol`、`InputSimulatorProtocol`、`UserDefaults`
4. **剪貼簿備份還原** — `InputSimulator` 對所有型別做快照，而非只處理 `.string`
5. **裝置熱插拔感知** — `AudioEngine.setupDeviceNotificationObserver()` 自動重新整理
6. **Whisper 配置重用** — `TranscriptionManager` 偵測配置是否變更，避免不必要的模型重建

---

## 📋 建議修復優先順序

| # | 問題 | 嚴重度 | 預估工時 |
|---|------|--------|----------|
| 1 | C-2: LLMService 檢查 HTTP StatusCode | 🔴 Critical | 0.5h |
| 2 | C-1: AudioEngine `bufferCallback` 資料競爭 | 🔴 Critical | 1h |
| 3 | H-4: InputSimulator 用 `changeCount` 替代內容比較 | 🟠 High | 0.5h |
| 4 | M-5: Ollama URL 拼接修正 | 🟡 Medium | 0.5h |
| 5 | M-6: 硬編碼字串抽出為常數 | 🟡 Medium | 1h |
| 6 | H-1: 重構 `asyncAfter` 為可測試的延遲機制 | 🟠 High | 2h |
| 7 | M-4: TranscriptionManager 加 `@MainActor` | 🟡 Medium | 0.5h |
| 8 | L-1: 補齊 LLMService 單元測試 | 🔵 Low | 2h |
| 9 | C-3: AppDelegate static 依賴可替換性 | 🔴 Critical | 3h |
| 10 | H-2: 清理 PermissionManager 死碼 | 🟠 High | 0.25h |
