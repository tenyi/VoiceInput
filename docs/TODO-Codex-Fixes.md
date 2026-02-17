# Codex 修復進度清單

更新時間: 2026-02-17

- [x] 修正 Custom Provider prompt 未套用
- [x] 修正啟動流程避免建立第二個 ViewModel
- [x] 修正 InputSimulator 剪貼簿還原邏輯（避免覆蓋非文字剪貼簿）
- [x] 修正 Whisper 轉錄併發競態
- [x] 修正 AudioEngine 以 uniqueID 比對裝置
- [x] 執行測試（單元測試）
- [x] 更新驗證結果與風險註記

## 備註
- 以高風險功能回歸為優先：錄音、轉錄、插入文字、設定持久化。
- 驗證結果：`xcodebuild -only-testing:VoiceInputTests test` 全數通過（3/3）。
- 既有風險：UI 測試 Runner 在整包測試時偶發啟動失敗（本次未在修復範圍內調整 UI 測試基礎設施）。
