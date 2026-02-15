# VoiceInput Code Review 修正任務

> 來源：`CodeReview-Antigravity.md` (2026-02-15)
> 執行者：Gemini 3 Pro
> 規則：所有註解、commit message 使用繁體中文台灣用語

---

## P0 — 必須立即修復

### [ ] 1. HotkeyManager：Event Tap 自動恢復機制

**檔案**: `VoiceInput/HotkeyManager.swift`

在 `CGEventTapCallBack` 中新增對 `tapDisabledByTimeout` 與 `tapDisabledByUserInput` 的處理。當系統停用 Event Tap 時，自動呼叫 `CGEvent.tapEnable(tap:enable:)` 重新啟用。

- 需要將 `eventTap` 改為可在 callback 中存取（透過 `refcon` 取得 manager 實例）
- 加入 `print` 或 `os.Logger` 記錄恢復事件

### [ ] 2. InputSimulator：剪貼簿備份與復原

**檔案**: `VoiceInput/InputSimulator.swift`

修改 `pasteText(_:)` 方法：

1. 在 `clearContents()` 前備份現有剪貼簿內容（`pasteboard.string(forType: .string)`）
2. 模擬 Cmd+V 完成後，延遲約 0.5 秒恢復原本的剪貼簿內容
3. 注意：備份需涵蓋純文字即可，不需處理圖片等類型

---

## P1 — 高優先順序

### [ ] 3. LLMService：新增網路請求 timeout

**檔案**: `VoiceInput/LLMService.swift`

在 `callOpenAI`、`callAnthropic`、`callOllama`、`callCustomAPI` 四個方法中，對 `URLRequest` 加入：

```swift
request.timeoutInterval = 30
```

### [ ] 4. VoiceInputViewModel：錄音失敗時顯示錯誤回饋

**檔案**: `VoiceInput/VoiceInputViewModel.swift`

修改 `startRecording()` 的 `catch` 區塊：

- 將錯誤訊息設定到 `transcribedText`（例如：`"錄音啟動失敗：\(error.localizedDescription)"`）
- 在浮動視窗中短暫顯示錯誤後再隱藏（延遲 2 秒）
- 不要直接隱藏視窗

### [ ] 5. TranscriptionService：錯誤傳播到 ViewModel

**檔案**: `VoiceInput/TranscriptionService.swift`

修改 `process(buffer:completion:)` 中的錯誤處理：

- 當 `error` 不為 nil 時，除了 `self.stop()` 外，也應透過 completion 回傳錯誤資訊
- 可考慮將 `completion` 改為 `(Result<String, Error>) -> Void`，或新增一個 `onError` callback
- 如改動 protocol，需同步修改 `VoiceInputViewModel` 中的呼叫端

---

## P2 — 中優先順序

### [ ] 6. API Key 改用 Keychain 儲存

**檔案**: `VoiceInput/VoiceInputViewModel.swift`

- 將 `@AppStorage("llmAPIKey")` 替換為 Keychain 存取
- 可使用 `Security` framework 的 `SecItemAdd` / `SecItemCopyMatching`，或引入輕量 Keychain 封裝
- `SettingsView.swift` 中的 `SecureField` 綁定需同步修改

### [ ] 7. PermissionManager：移除 AppleScript，改用 URL

**檔案**: `VoiceInput/PermissionManager.swift`

簡化 `openSystemPreferences(for:)` 方法：

- 移除整段 AppleScript 邏輯
- 直接使用 `NSWorkspace.shared.open(type.systemPreferencesURL!)` 開啟對應的系統設定頁面
- `systemPreferencesURL` 已定義在 `PermissionType` 中，可直接使用

### [ ] 8. PermissionManager：修正 UI 文案

**檔案**: `VoiceInput/PermissionManager.swift`

將 `deniedMessage` 中的「系統偏好設定」改為「系統設定」（macOS Ventura+ 用語）。

---

## P3 — 低優先順序

### [ ] 9. 提取 selectModelFile() 共用函數

**檔案**: `VoiceInput/ContentView.swift`、`VoiceInput/SettingsView.swift`

將重複的 `selectModelFile()` 提取到 `VoiceInputViewModel` 或新建工具類別中。

### [ ] 10. InputSimulator：魔術數字改用具名常數

**檔案**: `VoiceInput/InputSimulator.swift`

將 `0x37` 改為 `kVK_Command`、`0x09` 改為 `kVK_ANSI_V`（需 `import Carbon.HIToolbox`）。

### [ ] 11. 移除 Item.swift 範本殘留

**檔案**: `VoiceInput/Item.swift`

此檔案為 Xcode SwiftData 範本自動生成，專案中未使用。直接刪除。同時檢查 `VoiceInputApp.swift` 中是否有 SwiftData 相關的 `import` 可一併移除。

### [ ] 12. WindowManager：浮動視窗多螢幕定位

**檔案**: `VoiceInput/WindowManager.swift`

修改 `createFloatingWindow()` 中的視窗定位邏輯，使其顯示在目前使用中的螢幕（而非固定在主螢幕）。可嘗試使用 `NSEvent.mouseLocation` 判斷游標所在螢幕。

### [ ] 13. 全域：將 print() 改為 os.Logger

全部程式碼中的 `print()` 替換為 `os.Logger`：

```swift
import os
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "模組名稱")
logger.info("訊息")
logger.error("錯誤")
```

---

## 驗證清單

完成修改後，請確認以下事項：

- [ ] 專案可以成功 Build（無編譯錯誤）
- [ ] 快捷鍵長時間使用後仍然可用（Event Tap 恢復）
- [ ] 貼上文字後，剪貼簿恢復原本內容
- [ ] LLM 請求超時後不會卡死 UI
- [ ] 錄音失敗時浮動視窗顯示錯誤訊息
- [ ] 「打開系統設定」按鈕可正常開啟對應頁面（macOS Ventura+）
