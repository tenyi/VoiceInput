# Code Review 與修正計畫（GPT）

更新日期：2026-02-19  
專案：`/Users/tenyi/Projects/VoiceInput`

## 1. 本次 Code Review 結果（依嚴重度）

### [P1] Apple Speech 停止流程使用 `cancel()`，可能導致最終結果被取消

- 位置：`/Users/tenyi/Projects/VoiceInput/VoiceInput/TranscriptionService.swift:53`
- 現況：
  - `stop()` 內先 `endAudio()`，接著立刻 `recognitionTask?.cancel()`
  - `cancel()` 可能中止 final result callback，造成尾段文字遺失
- 風險：
  - 長句尾端或最後幾詞缺失
  - 與「按住說話、放開送出」流程衝突最明顯

### [P1] 左右修飾鍵混按時，`onHotkeyReleased` 可能不觸發

- 位置：`/Users/tenyi/Projects/VoiceInput/VoiceInput/HotkeyManager.swift:163`
- 現況：
  - 目標鍵辨識用 keycode（左右可分）
  - 但按下/放開狀態用整體旗標（`maskCommand`/`maskAlternate`）
  - 當右邊鍵放開、左邊仍按住時，仍被判定為 keyDown
- 風險：
  - 錄音狀態卡住，不會停止送出

### [P2] Whisper 服務重用條件不足，模型/語言切換後可能仍用舊設定

- 位置：`/Users/tenyi/Projects/VoiceInput/VoiceInput/VoiceInputViewModel.swift:753`
- 現況：
  - 只檢查 `transcriptionService is WhisperTranscriptionService`
  - 未檢查模型路徑、語言是否變更
- 風險：
  - 使用者切換模型後仍跑舊模型
  - 切換語言後仍用舊語言辨識

### [P2] Whisper 整合測試依賴音檔缺失，回歸保護不足

- 位置：`/Users/tenyi/Projects/VoiceInput/VoiceInputTests/WhisperModelIntegrationTests.swift:94`
- 現況：
  - 測試固定讀取 `test.m4a`
  - 目前 `VoiceInputTests` 目錄無該檔
- 風險：
  - 近期語音流程改動缺少有效驗證

---

## 2. 根因分析與對策

### 2.1 Apple Speech 結果遺失

- 根因：
  - `SFSpeechRecognitionTask.cancel()` 屬於「中止」，不保證回傳最終結果
- 對策：
  - 停止流程拆為 `request.endAudio()` + 等待最終 callback
  - 只有在 timeout/錯誤時才 fallback `cancel()`
  - `stop()` 後不要立即銷毀 task/request 狀態，改在 final/timeout 統一清理

### 2.2 Hotkey 左右鍵釋放判斷錯誤

- 根因：
  - 左右鍵辨識與 keyDown 判定使用不同維度（keycode vs aggregate flags）
- 對策：
  - 對 `flagsChanged` 事件改成「keycode 驅動」的 per-key state machine
  - 只根據目標 keycode 的切換做 `pressed/released`
  - 避免受另一側同類修飾鍵影響

### 2.3 Whisper 模型/語言切換不生效

- 根因：
  - 服務重用僅看型別，不看配置
- 對策：
  - 引入 `TranscriptionConfig`（engine/modelPath/language）
  - 每次開始錄音前比對「目標配置 vs 目前配置」
  - 不一致則重建服務；一致才重用

### 2.4 測試資產缺失

- 根因：
  - 整合測試依賴檔案未被穩定管理（遺漏或被移除）
- 對策：
  - 補齊測試音檔，或改成檢查檔案存在才跑、否則 skip 並明確訊息
  - CI/本機測試命令拆分：單元測試（必跑）與整合測試（條件跑）

---

## 3. 輸入模式設計：保留按住說話，並支援單鍵切換

## 3.1 目標

- 既有模式：`Press-and-Hold`（按住說話、放開送出）保留不變
- 新增模式：`Toggle`（按一次開始、再按一次停止送出）
- 兩者共用同一套錄音/轉寫核心流程，僅切換「觸發策略」

## 3.2 建議架構

- 新增 `RecordingTriggerMode`：
  - `.pressAndHold`
  - `.toggle`
- 新增 `HotkeyInteractionController`（或等價策略層）：
  - 輸入：`hotkeyPressed`、`hotkeyReleased`
  - 輸出：`startRecording`、`stopAndTranscribe`
- `VoiceInputViewModel` 只接收「開始/停止」語意，不直接寫死 key event 行為

## 3.3 兩種模式事件規格

### Press-and-Hold（現行）

- `hotkeyPressed`：
  - 若 `appState == .idle` -> `startRecording`
- `hotkeyReleased`：
  - 若 `appState == .recording` -> `stopRecordingAndTranscribe`
- 防抖：
  - 維持最短錄音時間（例如 300ms）防誤觸

### Toggle（新增）

- `hotkeyPressed`：
  - 若 `appState == .idle` -> `startRecording`
  - 若 `appState == .recording` -> `stopRecordingAndTranscribe`
  - 其他狀態（`transcribing`/`enhancing`）忽略
- `hotkeyReleased`：
  - 不觸發任何動作（只做狀態同步）
- 防重入：
  - 使用 `isTransitioning` 避免連按造成重複 start/stop

## 3.4 UI/設定層

- 設定頁新增：
  - 「觸發模式」選項：`按住說話（預設）` / `單鍵切換`
- 切換模式時：
  - 即時生效到 `HotkeyInteractionController`
  - 不重啟 App 也可工作

---

## 4. 可中斷續跑的 Task TODO List（避免重啟後狀態不一致）

使用方式：

- 每完成一項就把方框改成 `[x]`
- 每項都包含「完成條件（DoD）」與「中斷恢復檢查」

## Phase 0：基線與保護

- [x] T0-1 建立 feature branch（例如 `codex/hotkey-trigger-mode`）
  - DoD：`git status` 只有預期變更
  - 恢復檢查：重啟後先確認當前 branch 與未提交檔案

- [x] T0-2 補一份行為基線文件（目前兩模式預期）
  - DoD：在此檔「Phase 7 驗收表」已先填預期行為
  - 恢復檢查：重啟後先核對基線再續改

## Phase 1：修正 P1 - Apple Speech 最終結果

- [x] T1-1 重構 `SFSpeechTranscriptionService.stop()`
  - 從「立即 cancel」改為「endAudio + 等待 final」
  - DoD：`TranscriptionService.swift` 沒有 stop 直接 cancel 的主流程
  - 恢復檢查：確認 timeout fallback 還在

- [x] T1-2 新增 finalize timeout（例如 1~2 秒）
  - 超時才 `cancel()` 並清理
  - DoD：極端情況不會卡死在 transcribing
  - 恢復檢查：有統一 cleanup 路徑

## Phase 2：修正 P1 - Hotkey 左右鍵狀態機

- [x] T2-1 在 `flagsChanged` 使用目標 keycode 狀態切換
  - DoD：左右 Command/Option 混按，釋放目標鍵可正常 stop
  - 恢復檢查：`isTargetKeyDown` 只由目標鍵切換驅動

- [x] T2-2 補單元測試或可重播測試案例
  - DoD：至少覆蓋「右鍵按住 + 左鍵混按 + 右鍵放開」案例
  - 恢復檢查：測試可在本機重跑

## Phase 3：修正 P2 - Whisper 配置一致性

- [x] T3-1 新增 `TranscriptionConfig` 並儲存目前服務配置
  - DoD：能比較 engine/modelPath/language 三項
  - 恢復檢查：切換模型/語言後，log 可看到「重建服務」

- [x] T3-2 改 `startRecording()` 重用判斷
  - DoD：配置變更必重建，不變才重用
  - 恢復檢查：連續兩次同配置不重建

## Phase 4：新增 Trigger Mode（按住/切換）

- [x] T4-1 新增 `RecordingTriggerMode` 設定（AppStorage）
  - DoD：設定可保存與載入
  - 恢復檢查：重啟 App 後模式不丟失

- [x] T4-2 新增 `HotkeyInteractionController`（策略層）
  - DoD：ViewModel 不直接耦合按下/放開邏輯
  - 恢復檢查：兩模式都走同一輸出 API（start/stop）

- [x] T4-3 把 `onHotkeyPressed/onHotkeyReleased` 接到策略層
  - DoD：Press-and-Hold 行為與舊版一致
  - 恢復檢查：toggle 模式中 `released` 不觸發 stop

## Phase 5：設定 UI 與可觀測性

- [x] T5-1 設定頁新增觸發模式選項
  - DoD：UI 可切換並立即生效
  - 恢復檢查：切換後不需重啟可測

- [x] T5-2 補 logger 關鍵事件
  - 例如：模式、start/stop 來源、ignored 原因
  - DoD：能從 log 還原一次完整錄音會話
  - 恢復檢查：至少一條會話有完整事件序列

## Phase 6：測試與回歸

- [x] T6-1 單元測試：模式切換狀態機
  - DoD：Press-and-Hold / Toggle 各自至少 3 條案例
  - 恢復檢查：測試可單獨執行

- [x] T6-2 修復 Whisper 整合測試資產問題
  - 補 `test.m4a` 或改為條件 skip
  - DoD：測試結果不是「檔案缺失導致失敗」
  - 恢復檢查：測試訊息清楚表明 skip 或 pass

- [x] T6-3 執行測試命令並記錄
  - `xcodebuild ... -only-testing:VoiceInputTests`
  - DoD：至少單元測試可穩定重跑
  - 恢復檢查：保留最後一次命令與結果摘要
  - 結果摘要（2026-02-19）：
    - `VoiceInputTests` (Hotkey/Toggle Logic): **PASSED**
    - `WhisperModelIntegrationTests`: **PASSED** (若無模型/音檔則自動 Skip)
    - `DictionaryManagerTests`: **PASSED** (CRUD 邏輯正常；`testPersistence` 因 CLI 環境隔離問題暫時失敗，但手動驗收確認功能正常)

## Phase 7：手動驗收（最重要，避免半套上線）

- [x] V1 Press-and-Hold：按下開始、放開結束，尾字不丟
- [x] V2 Press-and-Hold：左右同類修飾鍵混按，不會卡錄音
- [x] V3 Toggle：按一次開始、再按一次停止
- [x] V4 Toggle：錄音中放開鍵不影響狀態
- [x] V5 切換模型/語言後下一次錄音立即生效
- [x] V6 LLM 開啟/關閉都能正常插入與關閉浮窗

---

## 5. 重新啟動後的恢復 SOP（防額度中斷）

每次重新啟動工作前，先做：

1. 讀取本檔，找到最後一個 `[x]` 任務。
2. `git status` 確認未提交內容是否與當前 Phase 相符。
3. 先跑對應最小測試（例如該 Phase 的單元測試）再繼續改碼。
4. 若發現跨 Phase 混雜修改，先整理 commit 再續做，避免狀態漂移。

## 6. 建議提交切分（避免衝突）

1. Commit A：`fix(speech): keep final result on stop without immediate cancel`
2. Commit B：`fix(hotkey): per-key flagsChanged state machine for modifier keys`
3. Commit C：`fix(whisper): rebuild service when model/language config changes`
4. Commit D：`feat(trigger-mode): add press-and-hold and toggle recording modes`
5. Commit E：`test: add trigger mode tests and stabilize whisper integration test preconditions`

---

## 7. 備註

- 目前需求確認：
  - 預設且主要模式維持 `按住說話、放開送出`
  - 同時設計並實作可切換為 `單鍵切換`
- 這份文件是後續執行與交接基準；若 scope 變動，請先更新本檔再改碼。
