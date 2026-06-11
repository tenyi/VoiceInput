# Singleton 依賴注入 (DI) 重構評估報告

## 📌 背景
本專案目前有多個核心服務使用 Singleton (`static let shared`) 模式進行全域存取。雖然 Singleton 能簡化呼叫，但會對單元測試 (Unit Test) 造成高度耦合，使我們無法輕易 mock 系統硬體或外部服務。為了提升可測試性 (Testability) 與代碼健壯性，本報告針對專案中現存的 Singleton 進行盤點，並評估將其改為建構子依賴注入 (DI) 的影響與後續計畫。

---

## 🔍 Singleton 盤點與評估

目前專案中共有 9 個主要的 Singleton 實例，以及 4 個 App 級別的生命週期單例：

| 服務名稱 / 實例 | 目前 DI 解耦狀態 | 重構可行性評估與改動影響 | 建議決策 |
| :--- | :--- | :--- | :--- |
| **`AudioEngine.shared`** | **已完成** | 目前已定義 `AudioEngineProtocol`，且在 `VoiceInputViewModel.init` 中以建構子注入。測試中已能 100% 使用 `MockAudioEngine` 替換。 | ✅ 無需變動 (維持現狀) |
| **`InputSimulator.shared`** | **已完成** | 目前已定義 `InputSimulatorProtocol`，且在 `VoiceInputViewModel.init` 中以建構子注入。測試中已使用 `MockInputSimulator`。 | ✅ 無需變動 (維持現狀) |
| **`PermissionManager.shared`** | **已完成** | 目前已抽取出 `PermissionManagerProtocol`。在 `AudioEngine` 與 `VoiceInputViewModel` 均已支援建構子注入，且 `AudioEngineTests` 與 `PermissionManagerTests` 已成功解耦。 | ✅ 無需變動 (維持現狀) |
| **`HotkeyManager.shared`** | **未完成** | `HotkeyManager` 負責 CGEventTap 的熱鍵監聽。目前在 `VoiceInputViewModel` 中直接存取。需定義 `HotkeyManagerProtocol` 並在 ViewModel 中進行注入。 | ⏳ 建議未來 Sprint 重構 |
| **`LLMService.shared`** | **未完成** | 提供大語言模型修正文字。目前 ViewModel 雖然注入了 `LLMSettingsViewModel`，但轉譯後的修正邏輯仍直接呼叫 `LLMService.shared`。需定義 `LLMServiceProtocol` 並在 ViewModel 中注入。 | ⏳ 建議未來 Sprint 重構 |
| **`DefaultFileSystem.shared`** | **未完成** | 用於存取 `FileManager`，在 `ModelManager` 中被直接使用。可以抽取 `FileSystemProtocol`，在 `ModelManager` 中注入，以便於測試模型檔案導入與刪除之邊界條件。 | ⏳ 建議未來 Sprint 重構 |
| **`KeychainHelper.shared`** | **未完成** | 用於安全存取 API Key。在 `LLMSettingsViewModel` 中被直接呼叫。可以定義 `KeychainHelperProtocol`，在 `LLMSettingsViewModel` 的建構子中注入，以解耦 Keychain 依賴。 | ⏳ 建議未來 Sprint 重構 |
| **`DictionaryManager.shared`** | **未完成** | 用於詞典替換。目前 ViewModel 在轉譯流程中直接存取 `DictionaryManager.shared`。需定義 `DictionaryManagerProtocol` 並注入至 ViewModel 中。 | ⏳ 建議未來 Sprint 重構 |
| **`WindowManager.shared`** | **未完成** | 負責浮動視窗與設定視窗的顯示。目前 ViewModel 部分邏輯與 App 層有間接調用。需定義 `WindowManagerProtocol` 並注入。 | ⏳ 建議未來 Sprint 重構 |

### ⚠️ App 級別單例 (AppDelegate 生命週期)
在 `VoiceInputApp.swift` / `AppDelegate` 下的四個實例：
- `AppDelegate.sharedViewModel`
- `AppDelegate.sharedLLMSettingsViewModel`
- `AppDelegate.sharedModelManager`
- `AppDelegate.sharedHistoryManager`

**評估**：
- 在 `VoiceInputViewModel` 中，我們在 **A2 任務**中已經成功將 `LLMSettingsViewModel` 與 `ModelManager` 改為建構子注入（預設值為 `AppDelegate.sharedXXX`）。這代表 ViewModel 的測試已能完全 mock 這些單例。
- 為了進一步最佳化，未來可將 `sharedHistoryManager` 也改為建構子注入 ViewModel，使 ViewModel 達到 100% 的依賴解耦。

---

## 🛠 未來重構計畫 (Roadmap)

我們建議在下一個 Sprint 依序執行以下 Singleton 的 DI 重構：

### 第一階段：解耦核心業務邏輯 (高優先級)
1. **`LLMService` 重構**：
   - 建立 `LLMServiceProtocol`
   - 在 `VoiceInputViewModel` 的 `init` 中注入該 Protocol。
2. **`DictionaryManager` 重構**：
   - 建立 `DictionaryManagerProtocol`
   - 注入至 `VoiceInputViewModel`，以便在測試中驗證詞典替換邏輯，而不需要讀取實際的 UserDefaults 磁碟配置。

### 第二階段：解耦硬體與系統依賴 (中優先級)
1. **`HotkeyManager` 重構**：
   - 建立 `HotkeyManagerProtocol`
   - 注入至 `VoiceInputViewModel`，測試中可完全 Mock 快速鍵的啟動與關閉狀態，避開 `CGEventTap` 的權限阻礙。
2. **`KeychainHelper` 重構**：
   - 建立 `KeychainHelperProtocol`
   - 注入至 `LLMSettingsViewModel`，使 API Key 測試不需真的寫入 macOS 的系統 Keychain，大幅加快測試運行速度。

### 第三階段：文件與輔助服務 (低優先級)
1. **`DefaultFileSystem` 重構**：
   - 建立 `FileSystemProtocol` 並注入至 `ModelManager`。
2. **`HistoryManager` 注入優化**：
   - 將 `HistoryManager` 剩餘的直接調用改為 ViewModel 建構子注入。

---

## 📝 結論與決策記錄
- **決策**：現階段 **`AudioEngine`**、**`InputSimulator`** 與 **`PermissionManager`** 已成功解耦，提供單元測試足夠的保護。
- 餘下的 **`LLMService`**、**`HotkeyManager`**、**`KeychainHelper`** 等 Singleton 重構將作為技術債，記錄於本報告與 `TODO.md` 中，並排入後續的 Sprint 開發規劃，不在此次 TODO 提交中強行重構，以保持當前 Sprint 的改動範疇聚焦。
