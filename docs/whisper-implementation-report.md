# Whisper 實作比較研究報告

## 摘要

本報告說明 Codex 如何成功將 VoiceInput 從 **SwiftWhisper**（3年前的舊庫）升級到最新的 **whisper.xcframework**，以及之前嘗試從 VoiceInk 移植失敗的原因分析。

---

## 一、背景：為什麼需要更換 Whisper 技術棧

### SwiftWhisper 的問題

| 項目 | SwiftWhisper | whisper.xcframework |
|------|---------------|---------------------|
| **最後更新** | 3年前（2022-2023） | 持續更新（最新） |
| **底層 whisper.cpp** | 舊版本 | 最新版本 |
| **模型支援** | 有限 | 完整支援新模型 |
| **維護狀態** | 廢棄 | 活躍開發 |

**SwiftWhisper** 是一個 Swift 封裝庫，基於 3 年前的 whisper.cpp 版本，已經停止維護。這意味著：

- 無法使用新的 Whisper 模型（如 large-v3）
- 可能存在與最新 macOS 版本的兼容性問題
- 缺少新功能和性能優化

---

## 二、Codex 的解決方案：技術棧替換

Codex 做了**技術棧替換**，而非從 VoiceInk 複製代碼。這是一個關鍵的理解：

- **移植**：從 A 專案複製完整功能到 B 專案
- **替換**：用新技術棧替換舊技術棧，保持現有功能

### 1. 新增 `LibWhisper.swift`（102行）

**檔案位置**：`VoiceInput/LibWhisper.swift`

```swift
actor WhisperContext {
    private var context: OpaquePointer?

    init(modelPath: String) throws {
        var params = whisper_context_default_params()
        params.flash_attn = true  // 啟用 Metal 加速
        // 直接調用 C API
    }

    func transcribe(samples: [Float], language: String?) throws -> String {
        // 直接調用 whisper_full()
    }
}
```

**特點**：
- 直接使用 `whisper.xcframework` 的 C API
- 自己編寫輕量級 Swift 封裝
- 啟用 Flash Attention（Metal 加速）
- 只有 102 行代碼

### 2. 簡化 `WhisperTranscriptionService.swift`

| 變更 | 舊版（SwiftWhisper） | 新版（whisper.xcframework） |
|------|---------------------|----------------------------|
| **Delegate** | 需要 `WhisperDelegate` 協議 | 不需要 |
| **異步處理** | 依賴 Delegate 回調 | 使用 Swift async/await |
| **代碼行數** | ~320 行 | ~180 行 |
| **依賴** | 外部 SwiftWhisper 庫 | 只依賴 whisper.xcframework |

### 3. 技術實現差異

**SwiftWhisper（舊版）**：
```swift
import SwiftWhisper
let whisper = Whisper(fromFileURL: modelURL)
whisper.delegate = self
try await whisper.transcribe(audioFrames: frames)
```

**whisper.xcframework（新版）**：
```swift
import whisper  // 直接調用 C API
let context = try WhisperContext(modelPath: path)
try await context.transcribe(samples: frames, language: "zh")
```

兩者 API 完全不同，無法直接替換。

---

## 三、之前移植失敗的原因分析

### 1. 對任務的理解錯誤

- **以為要「移植 VoiceInk 的 Whisper」**
- **實際任務應該是「將 SwiftWhisper 替換為 whisper.xcframework」**

這導致了：
- 試圖複製整個 VoiceInk 的狀態管理系統
- 過度複雜化實現
- 忽略了 Codex 已經做過的輕量級封裝

### 2. 過度複雜化

VoiceInk 有完整的功能集，但 VoiceInput 需要的是簡單的技術棧替換：

| 方案 | Codex（成功） | 失敗的嘗試 |
|------|--------------|------------|
| **代碼量** | 102 行 | 可能 300+ 行 |
| **依賴** | whisper.xcframework | 引入過多依賴 |
| **複雜度** | 輕量封裝 | 完整移植 |
| **狀態管理** | 保持現有架構 | 引入新狀態機 |

### 3. 沒有理解核心差異

VoiceInk 和 VoiceInput 的 Whisper 實現本質上使用相同的技術棧（whisper.cpp xcframework），差異只在於：

- 狀態管理複雜度
- 額外功能（VAD、prompt、模型下載）
- 與其他模組的整合方式

---

## 四、 Codex 成功的關鍵

1. **理解任務本質**：不是「移植」，而是「技術棧替換」
2. **最小化改動**：只新增必要的封裝代碼
3. **直接使用新技術**：跳過 SwiftWhisper，直接用 whisper.xcframework
4. **保持簡潔**：102 行代碼完成核心功能
5. **保持相容性**：確保新舊程式碼可以共存

---

## 五、對 VoiceInput 的意義

這次升級讓 VoiceInput：

- ✅ 使用最新 Whisper 模型
- ✅ 獲得 Metal 加速支持（Flash Attention）
- ✅ 減少外部依賴
- ✅ 代碼更簡潔易維護

---

## 六、未來改進方向

如果未來要進一步提升 Whisper 功能，應該基於 Codex 的實現進行**增量開發**，而非引入整個 VoiceInk 的架構：

### 建議的增量改進

1. **VAD 支持** - 在 LibWhisper.swift 中增加語音活動檢測
2. **Prompt 支持** - 增加 initial_prompt 參數，提升辨識準確度
3. **模型預熱** - 在應用啟動時預先載入模型
4. **模型下載** - 從 HuggingFace 自動下載模型

---

## 附錄：相關檔案

- `VoiceInput/LibWhisper.swift` - WhisperContext Actor 封裝
- `VoiceInput/WhisperTranscriptionService.swift` - 轉錄服務實現
- `VoiceInput/VoiceInputViewModel.swift` - 整合 Whisper 的 ViewModel
- `VoiceInput.xcodeproj/project.pbxproj` - whisper.xcframework 連結配置
