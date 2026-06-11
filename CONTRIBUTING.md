# VoiceInput 專案貢獻指南 (Contributing Guidelines)

感謝您有興趣貢獻 VoiceInput 專案！為了維護程式碼品質與專案的長期健康，請在提交任何修改前閱讀本指南。

---

## 📌 開發與分支規範

1. **分支命名**：
   - 功能開發：`feature/功能名稱`
   - 問題修復：`bugfix/修復名稱`
   - 架構重構：`refactor/重構名稱`
2. **提交流程**：
   - 在本地執行完整測試，確保所有單元測試皆為綠色。
   - 確保程式碼通過 SwiftLint 靜態檢查，不含有嚴重的編譯警告。
   - 提交 Pull Request (PR) 至 `main` 分支。

---

## 🔍 Code Review (程式碼審查) 制度

本專案實施嚴格的程式碼審查制度以確保設計品質與穩定性。

### 1. 強制審查門檻 (200 行規則)
* **規則**：任何**變更行數大於 200 行**（包含新增、刪除、修改的程式碼，不含第三方依賴庫與外部 binary 檔案如 `whisper.xcframework`）的 Pull Request，**必須在 Merge 前強制通過程式碼審查 (Code Review)**。
* **原因**：大範圍的變更對系統核心邏輯（如 `AudioEngine`、`HotkeyManager`、`VoiceInputViewModel`）影響較大，需要至少一位資深開發者或代碼負責人進行詳細審查以防 flaky 測試或回歸問題。

### 2. 審查報告範本
審查時需填寫 Code Review 報告，報告應記錄變更的優先順序、架構影響、已發現的 Bug 以及驗證測試結果。您可以參考 [code-review-template.md](file:///Users/tenyi/Projects/VoiceInput/docs/code-review-template.md) 進行撰寫。

---

## 🛠 本地開發環境準備

### 1. 下載必要的相依項目
由於 `whisper.xcframework` 二進位框架較大，未包含於 Git 儲存庫中。在本地編譯前，請執行以下腳本自動下載：
```bash
./scripts/download-whisper.sh
```

### 2. 安裝 Git Pre-commit Hooks
為了防止敏感資訊（例如 API 密鑰、密碼）與超大檔案意外被提交到 Git 倉庫中，請在開始開發前安裝預防性鉤子：
```bash
./scripts/setup-pre-commit.sh
```

### 3. 執行測試
在提交程式碼前，請務必在終端機中執行以下指令驗證程式碼正確性：
```bash
./run-test.sh
```
或執行穩定性驗證腳本：
```bash
./run-tests-10x.sh
```
若有任何一個測試失敗，請勿提交 PR。
