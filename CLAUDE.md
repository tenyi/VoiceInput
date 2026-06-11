# VoiceInput

macOS 上的全域語音輸入工具。按下快捷鍵即可對任意應用程式進行語音輸入，透過 Whisper 或 Apple 系統語音辨識將語音轉為文字，並自動插入到目標輸入框。

比對目標: VoiceInk App (<https://github.com/Beingpax/VoiceInk>)

## 開發規範

- Always reply in zh-TW.
- Thinking in zh-TW.
- Display thinking process in zh-TW.
- Display message in zh-TW.
- 嚴禁使用 zh-CN 簡體中文

## 核心功能（已完成）

- 全域快捷鍵觸發錄音（`CGEventTap`，支援任何應用程式）
- 支援兩種觸發模式：**按住說話（Press & Hold）** 與 **單鍵切換（Toggle）**
- 使用 **Whisper (whisper.xcframework)** 進行本地離線語音辨識
- 使用 **Apple SFSpeechRecognizer** 作為備用引擎
- 錄音時顯示膠囊狀浮動視窗，含即時辨識波形
- 轉錄完成後自動透過剪貼簿 Cmd+V 模擬插入文字
- 支援繁體中文 (zh-TW)、簡體中文 (zh-CN)、英文 (en-US)、日文 (ja-JP)
- 支援 LLM 修正（OpenAI、Anthropic、Ollama、Custom）
- 自訂快捷鍵（右 Command、左 Command、Fn、左/右 Option）
- 自訂詞典替換（字典管理功能）
- 轉錄歷史紀錄（最近 10 筆）
- 多麥克風裝置選擇（不修改系統全域設定）
- API Key 以 Keychain 安全儲存

## 詳細實作規格 (2026-02-25 更新)

### 1. 設定與 UI 介面

- **設定視窗**: 應用程式啟動時自動開啟，提供完整設定介面：
  - **辨識語言**: 繁體中文 (zh-TW)、簡體中文 (zh-CN)、英文 (en-US)、日文 (ja-JP)
  - **語音引擎選擇**: Apple SFSpeechRecognizer 或 Whisper（需指定 `.bin` 模型檔）
  - **快捷鍵選擇**: 右 Command（預設）、左 Command、Fn、左/右 Option
  - **觸發模式**: 按住說話（預設）/ 單鍵切換
  - **自動插入**: 轉錄完成後自動輸出至當前焦點應用程式
  - **LLM 修正**: 可啟用並設定 OpenAI / Anthropic / Ollama / Custom 提供者
  - **詞典管理**: 自訂文字替換規則
  - **麥克風選擇**: 選擇錄音裝置（系統預設或特定裝置）
- **浮動狀態面板**: 錄音時顯示，包含即時波形與辨識結果，錄音後自動隱藏

### 2. 快捷鍵邏輯

- **預設快捷鍵**: 右 Command 鍵
- **觸發模式**:
  - `pressAndHold`（按住說話）：按下開始錄音，放開觸發轉錄
  - `toggle`（單鍵切換）：第一次按下開始錄音，再次按下觸發轉錄
- **全域監聽**: 使用 `CGEventTap`（`.listenOnly` 模式）監聽 `flagsChanged` 與 `keyDown/keyUp`，需輔助功能權限
- **架構分層**:
  - `HotkeyManager`：原始按鍵事件擷取（CGEventTap + scancode + NX device flag mask）
  - `HotkeyInteractionController`：依觸發模式將原始事件轉換為語意事件
  - `VoiceInputViewModel`：接收語意事件執行實際業務邏輯

### 3. 文字轉錄與輸出

- **音訊擷取**: `AVCaptureSession` per-process（不修改系統全域預設音訊裝置）
- **音訊轉換**: `AudioConverterActor`（Swift Actor）隔離 `AVAudioConverter` 避免資料競爭
- **即時回饋**: 錄音期間以 Whisper chunk 模式更新部分辨識結果
- **安全插入**: 透過 `InputSimulator` 以剪貼簿 + Cmd+V 模擬插入，事後還原剪貼簿原始內容
- **LLM 修正流程**: 轉錄完成 → optionally LLM 修正 → 繁簡轉換 → 詞典替換 → 插入

### 4. SwiftUI 架構與持久化設定

#### VoiceInputViewModel（依賴注入架構）
`VoiceInputViewModel` 採用建構子依賴注入（DI）以支援單元測試，因此使用 `@Published + didSet { userDefaults.set(...) }` 模式取代 `@AppStorage`：

```swift
@Published var selectedLanguage: String {
    didSet { userDefaults.set(selectedLanguage, forKey: "selectedLanguage") }
}
```

- `userDefaults` 由建構子注入，測試時可傳入 `UserDefaults(suiteName: "test")`
- 這是**有意識的架構決策**，不是 `@AppStorage` 的退化

#### LLMSettingsViewModel（AppStorage 架構）
`LLMSettingsViewModel` **必須繼續使用 `@AppStorage`**，因為其設定欄位直接與 SwiftUI 設定介面雙向綁定，且不需要依賴注入替換：

```swift
@AppStorage("llmProvider") var llmProvider: String = LLMProvider.openAI.rawValue
@AppStorage("llmEnabled") var llmEnabled: Bool = false
```

#### 敏感資訊儲存規範
- **API Key 一律儲存於 Keychain**（`KeychainHelper`），不得存入 `UserDefaults` 或 `@AppStorage`
- Keychain 寫入採 **add-or-update** 模式（先 `SecItemUpdate`，不存在才 `SecItemAdd`）

#### 禁止事項
- **禁止**將 `LLMSettingsViewModel` 的 `@AppStorage` 拔除改為 `UserDefaults.set`
- **禁止**將 API Key 寫入 `UserDefaults` 或 `@AppStorage`
- **禁止**修改 `AudioEngine` 使用 `kAudioHardwarePropertyDefaultInputDevice`（會影響系統全域設定）

### 5. 已知注意事項

- `applicationWillTerminate` 使用 `_exit(0)` 強制退出：這是繞過 whisper.cpp / ggml-metal 全域 C++ 物件解構子崩潰的已知 workaround，**請勿移除**
- `nonisolated private let logger` 模式：Logger 本身是 Sendable，從 `nonisolated` context 使用安全

