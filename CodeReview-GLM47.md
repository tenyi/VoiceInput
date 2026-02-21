# VoiceInput 專案程式碼審查報告

**審查日期**: 2026-02-21
**審查工具**: GLM-4.7 (Code Reviewer Agent)
**專案類型**: macOS 語音輸入應用程式

---

## 📊 審查概要

| 優先級 | 數量 | 主要類別 |
|--------|------|----------|
| P1 - 嚴重 | 4 | 記憶體管理、並發安全、輸入驗證、安全性 |
| P2 - 警告 | 4 | 錯誤處理、本地化、效能、資源管理 |
| P3 - 建議 | 4 | 測試、文件、程式碼品質 |

**建議修復順序**: P1-1 → P1-2 → P1-3 → P1-4 → P2 項目 → P3 改進

---

## ✅ 正向觀察

1. **優秀的架構重構**: 從 `LLMManager` 重構為 `LLMProcessingService` 和 `LLMSettingsViewModel`，遵循單一職責原則 (SRP)

2. **依賴注入實作**: 在 `VoiceInputViewModel` 中使用 DI pattern，提高了可測試性

3. **SwiftUI 最佳實踐**: 正確使用 `@StateObject`、`@ObservedObject`、`@Published` 等屬性包裝器

4. **型別安全**: 善用 Swift 的 enum 和 struct 來定義清晰的型別系統

5. **錯誤處理**: 定義了自定義錯誤型別 (`WhisperError`、`LLMError`)

---

## 🚨 Priority 1 - 嚴重問題 (必須修復)

### 1.1 記憶體管理問題 - AudioEngine.swift

**位置**: `VoiceInput/AudioEngine.swift`

**問題描述**:
CoreAudio 物件可能存在記憶體洩漏風險，`AudioUnit` 和其他 CoreAudio 資源未在 `deinit` 中正確釋放。

**當前實作**:

```swift
private var audioUnit: AudioUnit?
private var audioFormat: AudioStreamBasicDescription?
```

**建議修正**:

```swift
deinit {
    stopRecording()
    cleanupAudio()
}

private func cleanupAudio() {
    if let audioUnit = audioUnit {
        AudioComponentInstanceDispose(audioUnit)
        self.audioUnit = nil
    }
    // 清理其他 CoreAudio 資源
}
```

**影響**: 可能導致長期使用後記憶體耗盡，應用程式崩潰

---

### 1.2 並發安全問題 - VoiceInputViewModel.swift

**位置**: `VoiceInput/VoiceInputViewModel.swift`

**問題描述**:
`@Published` 屬性在多線程環境下可能產生競態條件。音訊處理和轉錄可能在背景線程執行，而 UI 更新需要在主線程。

**當前實作**:

```swift
@Published private(set) var isRecording = false
@Published private(set) var transcribedText = ""

func startRecording() {
    isRecording = true  // 可能在非主線程呼叫
    // ...
}
```

**建議修正**:

```swift
@MainActor
final class VoiceInputViewModel: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcribedText = ""

    nonisolated func startRecording() async {
        await MainActor.run {
            isRecording = true
        }
        // 背景處理...
    }
}
```

**影響**: 可能導致資料損壞、UI 更新異常、崩潰

---

### 1.3 未驗證的使用者輸入 - SettingsView.swift

**位置**: `VoiceInput/SettingsView.swift`

**問題描述**:
自訂模型路徑和 API 金鑰未經充分驗證，可能導致應用程式載入無效檔案或連接到不安全的端點。

**當前實作**:

```swift
TextField("模型路徑", text: $viewModel.customModelPath)
```

**建議修正**:

```swift
TextField("模型路徑", text: $viewModel.customModelPath)
    .onChange(of: viewModel.customModelPath) { newPath in
        guard !newPath.isEmpty else { return }
        validateModelPath(newPath)
    }

private func validateModelPath(_ path: String) {
    let url = URL(fileURLWithPath: path)
    // 驗證檔案存在性、權限和格式
    guard FileManager.default.fileExists(atPath: path) else {
        // 顯示錯誤提示
        return
    }
    guard path.hasSuffix(".bin") || path.hasSuffix(".model") else {
        // 驗證副檔名
        return
    }
}
```

**影響**: 可能載入惡意檔案、導致崩潰或安全漏洞

---

### 1.4 敏感資訊暴露風險

**位置**: 多個檔案 (LLM 相關模組)

**問題描述**:
LLM API 金鑰可能被意外記錄到 log 或錯誤報告中，造成安全風險。

**建議修正**:

```swift
// 在 log 中遮蔽敏感資訊
extension Logger {
    static func maskSensitive(_ text: String) -> String {
        if text.count > 8 {
            return String(text.prefix(4)) +
                   String(repeating: "*", count: text.count - 8) +
                   String(text.suffix(4))
        }
        return String(repeating: "*", count: text.count)
    }

    static func logAPIKey(_ key: String, context: String) {
        let masked = maskSensitive(key)
        print("[\(context)] API Key: \(masked)")
    }
}
```

**影響**: API 金鑰洩漏，可能被濫用產生費用

---

## ⚠️ Priority 2 - 警告問題 (應該修復)

### 2.1 錯誤處理不一致

**位置**: 多個檔案

**問題描述**:
某些函數使用 `throws`，某些使用 `Result` 型別，有些直接忽略錯誤，導致錯誤處理策略不統一。

**建議修正**:

```swift
// 定義統一的錯誤型別
enum AppError: LocalizedError {
    case audioRecording(Error)
    case transcription(WhisperError)
    case llmProcessing(LLMError)
    case fileIO(Error)
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .audioRecording(let error):
            return "錄音錯誤: \(error.localizedDescription)"
        case .transcription(let error):
            return "轉錄錯誤: \(error.localizedDescription)"
        case .llmProcessing(let error):
            return "LLM 處理錯誤: \(error.localizedDescription)"
        case .fileIO(let error):
            return "檔案操作錯誤: \(error.localizedDescription)"
        case .invalidInput(let message):
            return "輸入無效: \(message)"
        }
    }
}
```

---

### 2.2 硬編碼字串未本地化

**位置**: `SettingsView.swift`、`ContentView.swift`

**問題描述**:
UI 字串未本地化且散落在程式碼中，不支援國際化。

**當前實作**:

```swift
Text("設定")
Text("開始錄音")
```

**建議修正**:

```swift
// 建立 Localizable.strings
enum L10n {
    static let settings = "設定"
    static let startRecording = "開始錄音"
    static let stopRecording = "停止錄音"
    static let language = "語言"
    // ...
}

Text(L10n.settings)
```

---

### 2.3 Whisper 資源清理不完整

**位置**: `VoiceInput/WhisperTranscriptionService.swift`

**問題描述**:
Whisper 模型資源可能未在 `deinit` 中正確釋放。

**建議修正**:

```swift
deinit {
    // 確保正確釋放 Whisper 模型資源
    whisperContext?.release()
    whisperContext = nil
}
```

---

### 2.4 頻繁的磁碟 I/O

**位置**: `SettingsView.swift`

**問題描述**:
每次設定變更都可能觸發磁碟寫入，影響效能。

**建議修正**:

```swift
// 使用防抖機制
@State private var debounceTask: Task<Void, Never>?

private func saveSettingsDebounced() {
    debounceTask?.cancel()
    debounceTask = Task {
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 秒
        await saveSettings()
    }
}
```

---

## 💡 Priority 3 - 建議改進 (考慮改進)

### 3.1 測試覆蓋率不足

**建議**: 增加以下測試案例

```swift
// 記憶體洩漏測試
func testAudioEngineMemoryCleanup() {
    let engine = AudioEngine()
    // 執行錄音循環
    for _ in 0..<100 {
        engine.startRecording()
        engine.stopRecording()
    }
    // 驗證記憶體沒有異常增長
}

// 並發操作測試
func testConcurrentRecordingOperations() async {
    let viewModel = VoiceInputViewModel()
    await withTaskGroup(of: Void.self) { group in
        group.addTask { await viewModel.startRecording() }
        group.addTask { await viewModel.stopRecording() }
    }
}

// 錯誤路徑測試
func testInvalidModelPathHandling() {
    let viewModel = VoiceInputViewModel()
    viewModel.customModelPath = "/invalid/path"
    XCTAssertThrowsError(try viewModel.validateSettings())
}
```

---

### 3.2 程式碼文件不足

**建議**: 為公開 API 添加詳細文檔註解

```swift
/// 處理語音轉錄的服務
///
/// 此服務負責協調音訊捕獲和 Whisper 模型推理，
/// 支援即時和批次轉錄模式。
///
/// - Note: 此類別為執行緒安全
/// - Important: 必須在主線程初始化
public final class WhisperTranscriptionService {
    /// 開始轉錄音訊資料
    /// - Parameter audioData: PCM 格式的音訊資料
    /// - Returns: 轉錄後的文字結果
    /// - Throws: `WhisperError.transcriptionFailed`
    public func transcribe(_ audioData: Data) async throws -> String
}
```

---

### 3.3 Magic Numbers

**位置**: 多個檔案

**當前實作**:

```swift
let sampleRate = 16000
let bufferDuration = 0.03
```

**建議修正**:

```swift
enum AudioConstants {
    static let sampleRate: Double = 16000
    static let bufferDuration: TimeInterval = 0.03
    static let maxRecordingDuration: TimeInterval = 300
    static let channels: UInt32 = 1
}
```

---

### 3.4 型別推斷優化

**當前實作**:

```swift
let languages = ["zh-TW", "en-US", "ja-JP"]
```

**建議修正**:

```swift
let languages: [SupportedLanguage] = [
    .traditionalChinese,
    .englishUS,
    .japanese
]

enum SupportedLanguage: String, CaseIterable, Identifiable {
    case traditionalChinese = "zh-TW"
    case englishUS = "en-US"
    case japanese = "ja-JP"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .traditionalChinese: return "繁體中文"
        case .englishUS: return "英文"
        case .japanese: return "日文"
        }
    }
}
```

---

## 📋 修復優先順序

| 優先順序 | 項目 | 預估工時 | 風險等級 |
|---------|------|----------|----------|
| 1 | P1-1: AudioEngine 記憶體管理 | 1-2 小時 | 高 |
| 2 | P1-2: 並發安全問題 | 2-4 小時 | 高 |
| 3 | P1-3: 輸入驗證 | 2-3 小時 | 中 |
| 4 | P1-4: 敏感資訊保護 | 1 小時 | 中 |
| 5 | P2-1: 錯誤處理統一 | 3-4 小時 | 中 |
| 6 | P2-2: 本地化支援 | 4-6 小時 | 低 |
| 7 | P2-3: 資源清理 | 1 小時 | 低 |
| 8 | P2-4: 防抖機制 | 1 小時 | 低 |
| 9 | P3 項目 | 按需安排 | 低 |

---

## 🎯 建議行動

1. **立即修復** (本週內): P1-1, P1-2
2. **短期修復** (本月內): P1-3, P1-4, P2-1
3. **中期改進** (下個版本): P2-2, P2-3, P2-4
4. **長期改進** (持續進行): P3 項目

---

*報告由 GLM-4.7 Code Reviewer Agent 生成*
