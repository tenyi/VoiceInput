# VoiceInput 程式碼審查報告

**審查日期**: 2026-02-15
**審查工具**: MiniMax-M2.5

---

## 總體評估

| 面向 | 評分 | 說明 |
|------|------|------|
| 程式碼結構 | ⭐⭐⭐⭐ | 結構清晰，單例模式使用恰當 |
| 錯誤處理 | ⭐⭐⭐ | 有基本錯誤處理，但部分區塊需加強 |
| 安全性 | ⭐⭐⭐⭐ | API Key 使用 AppStorage，但傳輸過程安全 |
| 記憶體管理 | ⭐⭐⭐⭐ | 善用 `[weak self]` 避免 retain cycle |
| API 相容性 | ⭐⭐ | 部分 API 使用已棄用方式 |

---

## 1. 安全性問題 (Security)

### 🔴 高風險

#### 1.1 API Key 明文儲存 (`VoiceInputViewModel.swift:37`)

```swift
@AppStorage("llmAPIKey") var llmAPIKey: String = ""
```

**問題**: API Key 以明文形式儲存在 UserDefaults 中，任何可存取該檔案的人都能看到。

**建議**: 雖然 AppStorage 方便，但建議在正式環境中使用 Keychain 儲存敏感的 API Key。

---

#### 1.2 硬編碼的按鍵虛擬碼 (`InputSimulator.swift:56-59`)

```swift
let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
```

**問題**: Command 鍵和 V 鍵的虛擬碼以魔術數字硬編碼。

**建議**: 使用 Carbon framework 定義的常數，如 `kVK_Command` (0x37) 和 `kVK_ANSI_V` (0x09)。

---

## 2. 錯誤處理問題 (Error Handling)

### 🟠 中風險

#### 2.1 錄音啟動失敗時無完善回饋 (`VoiceInputViewModel.swift:192-197`)

```swift
} catch {
    // 錄音啟動失敗
    WindowManager.shared.hideFloatingWindow()
    appState = .idle
}
```

**問題**: 僅有 `print` 輸出（若有），使用者不知道為何失敗。

**建議**: 應該顯示 Alert 告知使用者錯誤原因，可能是權限問題或其他硬體問題。

---

#### 2.2 LLM 網路請求缺乏 timeout (`LLMService.swift`)

```swift
URLSession.shared.dataTask(with: request) { ... }
```

**問題**: 網路請求沒有設定 timeout，可能導致使用者無限等待。

**建議**: 設定 URLRequest 的 timeoutInterval，例如 30 秒。

---

#### 2.3 剪貼簿操作失敗時無 fallback (`InputSimulator.swift:48-71`)

```swift
private func pasteText(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    // ... 模擬按鍵
}
```

**問題**: 若模擬按鍵失敗，沒有任何錯誤回饋或 fallback 機制。

---

## 3. API 相容性問題 (API Compatibility)

### 🔴 高風險

#### 3.1 System Preferences URL 即將棄用 (`PermissionManager.swift:343-395`)

```swift
// 使用 AppleScript 打開對應的隱私權設定
let script = """
tell application "System Preferences"
    activate
    reveal anchor "Microphone" of pane id "com.apple.preference.security"
end tell
"""
```

**問題**: Apple 已宣布 macOS Ventura (13+) 之後 `System Preferences` 將由 `System Settings` 取代，這段 AppleScript 即將失效。

**建議**: 改用直接開啟 URL 的方式：

```swift
if let url = type.systemPreferencesURL {
    NSWorkspace.shared.open(url)
}
```

---

#### 3.2 onChange API 差異 (`SettingsView.swift:104`)

```swift
.onChange(of: selectedHotkey) { _, newValue in
```

**問題**: 這是 iOS 17+ / macOS 14+ 的新語法。若要支援較舊版本，需要使用舊語法：

```swift
.onChange(of: selectedHotkey) { newValue in
```

**建議**: 確認最低支援版本，若要向下相容需修改。

---

### 🟠 中風險

#### 3.3 symbolEffect 需要較新版作業系統 (`WindowManager.swift:117, 124`)

```swift
.symbolEffect(.variableColor.iterative.reversing, isActive: true)
.symbolEffect(.rotate, isActive: true)
```

**問題**: `symbolEffect` 是 iOS 17 / macOS 14+ 的功能。

**建議**: 添加版本檢查或 graceful degradation。

---

## 4. 記憶體管理與效能問題

### 🟠 中風險

#### 4.1 AudioEngine 重複建立 (`VoiceInputViewModel.swift:58`)

```swift
private var audioEngine = AudioEngine.shared
```

**問題**: 這裡使用 `AudioEngine.shared` 但 AudioEngine 本身已是單例，不需再在 ViewModel 中持有參考。

---

#### 4.2 TranscriptionService 每次建立新實體 (`VoiceInputViewModel.swift:60`)

```swift
private var transcriptionService: TranscriptionServiceProtocol = SFSpeechTranscriptionService()
```

**問題**: 每次初始化 ViewModel 都會建立新的 TranscriptionService。建議改為單例或延遲初始化。

---

#### 4.3 Potential retain cycle (`HotkeyManager.swift:153-155`)

```swift
DispatchQueue.main.async { [weak self] in
    self?.onHotkeyPressed?()
}
```

**問題**: 這裡正確使用了 `[weak self]`，但 callback 本身被 ViewModel 持有，可能形成 strong reference cycle。建議確認 callback 鏈沒有 retain cycle。

---

## 5. 程式碼品質問題

### 🟡 低風險

#### 5.1 未使用的屬性 (`AudioEngine.swift:15`)

```swift
private var inputNode: AVAudioInputNode?
```

**問題**: 這個屬性在 `startRecording()` 中被重新賦值，但在 `stopRecording()` 中沒有設為 nil。

---

#### 5.2 重複的程式碼 (`SettingsView.swift:181-189` vs `ContentView.swift:176-186`)

選擇 Whisper 模型檔案的程式碼在兩處重複。

**建議**: 提取為共用函數。

---

#### 5.3 不一致的錯誤處理 (`TranscriptionService.swift:68`)

```swift
if let error = error {
    print("識別錯誤 (Recognition error): \(error)")
    self.stop()
}
```

**問題**: 發生錯誤時只 print，沒有通知使用者或 ViewModel。

---

## 6. 功能性問題

### 🟠 中風險

#### 6.1 Whisper 模型路徑設定未實際使用

在 `SettingsView.swift` 和 `ContentView.swift` 中有 Whisper 模型路徑設定，但 `SFSpeechTranscriptionService` 只使用 Apple 內建的語音辨識，並未實際載入 Whisper 模型。

**建議**: 這可能是預留功能，但應該在 UI 上標註為「尚未實作」或實作完整功能。

---

#### 6.2 浮動視窗位置固定 (`WindowManager.swift:70-75`)

```swift
if let screen = NSScreen.main {
    let screenRect = screen.visibleFrame
    let x = screenRect.midX - 150
    let y = screenRect.midY - 100
    window.setFrameOrigin(NSPoint(x: x, y: y))
}
```

**問題**: 浮動視窗總是顯示在主螢幕中央，若使用者使用多螢幕，可能不在預期位置。

---

#### 6.3 快捷鍵設定 UI 顯示不正確 (`SettingsView.swift:98-106`)

Picker 選擇的項目可能與實際儲存的 `selectedHotkey` 不一致，特別是當使用者直接修改 AppStorage 時。

---

## 7. 建議改進項目優先順序

| 優先順序 | 項目 | 檔案 |
|----------|------|------|
| **高** | 修復 System Preferences AppleScript 兼容性 | PermissionManager.swift |
| **高** | 新增 LLM 請求 timeout | LLMService.swift |
| **中** | 新增錄音失敗的 UI 回饋 | VoiceInputViewModel.swift |
| **中** | 修正 onChange API 兼容性 | SettingsView.swift |
| **中** | 使用 Keychain 儲存 API Key | VoiceInputViewModel.swift |
| **低** | 提取共用函數減少重複碼 | SettingsView/ContentView |
| **低** | symbolEffect 版本相容處理 | WindowManager.swift |

---

## 總結

整體而言，VoiceInput 專案架構清晰，程式碼品質不錯。主要問題在於：

1. **API 兼容性** - AppleScript 即將失效，需要儘早修正
2. **錯誤處理** - 部分區塊缺少完善的錯誤回饋
3. **安全性** - API Key 儲存方式可進一步加強

建議優先處理高風險項目，確保應用程式在未來 macOS 版本仍能正常運作。

---

*此報告由 AI 程式碼審查工具生成*
