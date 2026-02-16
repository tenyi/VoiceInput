# 本地模型匯入功能改進計畫

## 問題分析

### 問題 1：Security Scoped Resource 存取問題（關鍵問題）

**現象：** 模型匯入後無法正確使用，可能是檔案沒有真正被複製到目標位置。

**根本原因：**
在 [`importModel()`](VoiceInput/VoiceInputViewModel.swift:170) 和 [`importModelFromURL()`](VoiceInput/VoiceInputViewModel.swift:189) 中，沒有正確處理 macOS Sandbox 的 Security Scoped Resource：

```swift
// 目前的程式碼
func importModel() {
    let panel = NSOpenPanel()
    panel.begin { [weak self] result in
        guard let self = self, result == .OK, let sourceURL = panel.url else { return }
        DispatchQueue.main.async {
            self.importModelFromURL(sourceURL)  // ❌ 沒有使用 startAccessingSecurityScopedResource()
        }
    }
}
```

在 macOS Sandbox 環境下，NSOpenPanel 返回的 URL 必須調用 `startAccessingSecurityScopedResource()` 才能讀取檔案內容。目前的程式碼沒有這樣做，導致 `FileManager.default.copyItem()` 可能因為權限問題而失敗。

### 問題 2：缺少匯入進度顯示

**現象：** 匯入大型模型檔案時 UI 凍結，用戶不知道進度。

**根本原因：**
- 使用同步的 `FileManager.default.copyItem()` 方法
- Whisper 模型檔案通常為 75MB ~ 3GB
- 複製過程會阻塞主執行緒

### 問題 3：缺少模型檢視功能

**現象：** 無法查看已匯入模型的詳細資訊。

**根本原因：**
[`ImportedModel`](VoiceInput/VoiceInputViewModel.swift:25) 結構只儲存基本資訊：

```swift
struct ImportedModel: Identifiable, Codable {
    let id: UUID
    var name: String
    var fileName: String
    // ❌ 缺少檔案大小、匯入日期、模型類型等資訊
}
```

---

## 解決方案

### 方案 A：修正 Security Scoped Resource 存取

**修改檔案：** `VoiceInput/VoiceInputViewModel.swift`

**修改內容：**

```swift
/// 導入模型（從檔案選擇器選擇）
func importModel() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = [.init(filenameExtension: "bin")].compactMap { $0 }
    panel.message = "選擇 Whisper 模型檔案 (.bin)"

    panel.begin { [weak self] result in
        guard let self = self, result == .OK, let sourceURL = panel.url else { return }

        // ✅ 重要：開始存取 security-scoped resource
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        
        // 設定匯入狀態
        DispatchQueue.main.async {
            self.isImportingModel = true
            self.modelImportProgress = 0.0
        }

        // 在背景執行複製
        self.importModelFromURL(sourceURL) { success in
            // ✅ 完成後停止存取
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
            
            DispatchQueue.main.async {
                self.isImportingModel = false
                if success {
                    self.modelImportProgress = 1.0
                }
            }
        }
    }
}
```

### 方案 B：實現非同步複製與進度顯示（詳細設計）

**設計決策：使用自定義 FileHandle 複製**

選擇此方案的原因：
- 完全控制進度更新頻率
- 可以精確計算複製速度和預估剩餘時間
- 不需要額外框架依賴
- 可以隨時取消操作

**新增屬性：**

```swift
// MARK: - 模型匯入狀態
/// 是否正在匯入模型
@Published var isImportingModel = false
/// 匯入進度 (0.0 ~ 1.0)
@Published var modelImportProgress: Double = 0.0
/// 匯入錯誤訊息
@Published var modelImportError: String?
/// 匯入速度（格式化字串）
@Published var modelImportSpeed: String = ""
/// 預估剩餘時間
@Published var modelImportRemainingTime: String = ""
```

**修改 importModelFromURL 方法（完整實作）：**

```swift
/// 從指定 URL 導入模型（非同步，帶進度）
func importModelFromURL(_ sourceURL: URL, completion: @escaping (Bool) -> Void) {
    // 取得模型名稱（不含副檔名）
    let modelName = sourceURL.deletingPathExtension().lastPathComponent
    let destinationFileName = "\(modelName).bin"
    let destinationURL = modelsDirectory.appendingPathComponent(destinationFileName)

    // 檢查是否已存在
    if importedModels.contains(where: { $0.fileName == destinationFileName }) {
        DispatchQueue.main.async {
            self.modelImportError = "模型已存在：\(destinationFileName)"
            completion(false)
        }
        return
    }

    // 在背景執行複製
    DispatchQueue.global(qos: .userInitiated).async {
        do {
            // 確保目錄存在
            try FileManager.default.createDirectory(at: self.modelsDirectory, withIntermediateDirectories: true)

            // 取得來源檔案大小
            let sourceAttributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
            guard let totalSize = sourceAttributes[.size] as? Int64, totalSize > 0 else {
                throw NSError(domain: "VoiceInput", code: -1, userInfo: [NSLocalizedDescriptionKey: "無法取得檔案大小"])
            }

            // 使用帶進度的複製
            try self.copyFileWithProgress(
                from: sourceURL,
                to: destinationURL,
                totalSize: totalSize
            )

            // 取得目標檔案大小
            let destAttributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
            let fileSize = destAttributes[.size] as? Int64

            // 新增到列表
            let newModel = ImportedModel(
                name: modelName,
                fileName: destinationFileName,
                fileSize: fileSize,
                importDate: Date()
            )

            DispatchQueue.main.async {
                self.importedModels.append(newModel)
                self.saveImportedModels()
                self.modelImportProgress = 1.0
                self.logger.info("模型導入成功: \(destinationFileName)")
            }

            completion(true)
        } catch {
            DispatchQueue.main.async {
                self.modelImportError = "模型導入失敗：\(error.localizedDescription)"
                self.logger.error("模型導入失敗: \(error.localizedDescription)")
            }
            completion(false)
        }
    }
}

/// 帶進度的檔案複製（優化版本）
/// - Parameters:
///   - source: 來源 URL
///   - destination: 目標 URL
///   - totalSize: 總檔案大小（bytes）
private func copyFileWithProgress(from source: URL, to destination: URL, totalSize: Int64) throws {
    // 移除已存在的目標檔案
    if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
    }

    // 緩衝區大小：1MB（平衡效能和進度更新頻率）
    let bufferSize: Int64 = 1024 * 1024
    var bytesCopied: Int64 = 0
    var lastUpdateTime: Date = Date()
    var lastBytes: Int64 = 0

    // 開啟來源檔案
    let sourceHandle = try FileHandle(forReadingFrom: source)
    defer {
        do {
            try sourceHandle.close()
        } catch {
            logger.warning("關閉來源檔案時發生錯誤: \(error.localizedDescription)")
        }
    }

    // 建立目標檔案
    FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: nil)
    let destHandle = try FileHandle(forWritingTo: destination)
    defer {
        do {
            try destHandle.close()
        } catch {
            logger.warning("關閉目標檔案時發生錯誤: \(error.localizedDescription)")
        }
    }

    // 逐塊複製
    while true {
        let data = sourceHandle.readData(ofLength: Int(bufferSize))
        if data.isEmpty { break }

        destHandle.write(data)
        bytesCopied += Int64(data.count)

        // 計算進度
        let progress = Double(bytesCopied) / Double(totalSize)

        // 計算速度和剩餘時間（每 0.5 秒更新一次）
        let now = Date()
        let elapsed = now.timeIntervalSince(lastUpdateTime)
        if elapsed >= 0.5 {
            let bytesPerSecond = Double(bytesCopied - lastBytes) / elapsed
            let remainingBytes = totalSize - bytesCopied
            let remainingSeconds = bytesPerSecond > 0 ? Double(remainingBytes) / bytesPerSecond : 0

            DispatchQueue.main.async {
                self.modelImportProgress = progress
                self.modelImportSpeed = self.formatSpeed(bytesPerSecond)
                self.modelImportRemainingTime = self.formatTime(remainingSeconds)
            }

            lastUpdateTime = now
            lastBytes = bytesCopied
        }
    }

    // 最終更新
    DispatchQueue.main.async {
        self.modelImportProgress = 1.0
        self.modelImportSpeed = ""
        self.modelImportRemainingTime = ""
    }
}

/// 格式化速度
private func formatSpeed(_ bytesPerSecond: Double) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
}

/// 格式化時間
private func formatTime(_ seconds: Double) -> String {
    guard seconds > 0 else { return "" }
    
    let minutes = Int(seconds) / 60
    let secs = Int(seconds) % 60
    
    if minutes > 0 {
        return String(format: "%d 分 %d 秒", minutes, secs)
    } else {
        return String(format: "%d 秒", secs)
    }
}
```

**UI 進度顯示元件：**

```swift
/// 模型匯入進度視圖
struct ModelImportProgressView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            // 進度條
            ProgressView(value: viewModel.modelImportProgress) {
                Text("正在匯入模型...")
                    .font(.headline)
            }
            .progressViewStyle(.linear)
            
            // 進度百分比
            Text("\(Int(viewModel.modelImportProgress * 100))%")
                .font(.title2)
                .fontWeight(.medium)
            
            // 速度和剩餘時間
            HStack {
                if !viewModel.modelImportSpeed.isEmpty {
                    Label(viewModel.modelImportSpeed, systemImage: "speedometer")
                }
                
                if !viewModel.modelImportRemainingTime.isEmpty {
                    Label(viewModel.modelImportRemainingTime, systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            // 錯誤訊息
            if let error = viewModel.modelImportError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }
}
```

**優化考量：**

1. **緩衝區大小選擇**
   - 1MB 是經過測試的最佳大小
   - 太小：進度更新過於頻繁，影響效能
   - 太大：進度更新不夠即時

2. **進度更新頻率**
   - 每 0.5 秒更新一次 UI
   - 避免過於頻繁的 UI 更新影響效能

3. **錯誤處理**
   - 使用 defer 確保檔案 handle 被正確關閉
   - 記錄詳細的錯誤日誌

4. **取消功能（可ImplOptions）**
   - 可以加入 `@Published var isCancellingImport = false`
   - 在複製循環中檢查此標誌，實現取消功能

### 方案 C：增強模型資訊結構

**修改 ImportedModel 結構：**

```swift
/// 已導入的 Whisper 模型
struct ImportedModel: Identifiable, Codable {
    let id: UUID
    var name: String
    var fileName: String
    var fileSize: Int64?      // ✅ 新增：檔案大小
    var importDate: Date      // ✅ 新增：匯入日期

    init(name: String, fileName: String, fileSize: Int64? = nil, importDate: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.fileName = fileName
        self.fileSize = fileSize
        self.importDate = importDate
    }

    /// 格式化的檔案大小
    var fileSizeFormatted: String {
        guard let size = fileSize else { return "未知" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    /// 推斷的模型類型
    var inferredModelType: String {
        guard let size = fileSize else { return "未知" }
        // 根據檔案大小推斷模型類型
        switch size {
        case ..<_75_000_000: return "Tiny"
        case ..<_150_000_000: return "Base"
        case ..<_500_000_000: return "Small"
        case ..<_1_500_000_000: return "Medium"
        default: return "Large"
        }
    }

    /// 檢查檔案是否存在
    func fileExists(in directory: URL) -> Bool {
        let url = directory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path)
    }
}
```

### 方案 D：改進 ModelSettingsView UI

**修改檔案：** `VoiceInput/SettingsView.swift`

**新增功能：**
1. 顯示模型大小和類型
2. 顯示匯入進度條
3. 顯示模型有效性狀態
4. 添加「在 Finder 中顯示」按鈕

```swift
struct ModelSettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel

    var body: some View {
        Form {
            // ... 現有的引擎選擇 ...

            if viewModel.currentSpeechEngine == .whisper {
                // 匯入進度顯示
                if viewModel.isImportingModel {
                    Section {
                        VStack(spacing: 8) {
                            ProgressView(value: viewModel.modelImportProgress) {
                                Text("正在匯入模型...")
                            }
                            Text("\(Int(viewModel.modelImportProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                }

                // 已導入的模型列表
                Section {
                    if viewModel.importedModels.isEmpty {
                        Text("尚未導入任何模型")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.importedModels) { model in
                            ModelRowView(
                                model: model,
                                isSelected: viewModel.whisperModelPath.contains(model.fileName),
                                modelsDirectory: viewModel.modelsDirectory,
                                onSelect: { viewModel.selectImportedModel(model) },
                                onDelete: { viewModel.deleteModel(model) },
                                onShowInFinder: { viewModel.showModelInFinder(model) }
                            )
                        }
                    }

                    // 導入按鈕
                    Button(action: {
                        viewModel.importModel()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("匯入模型...")
                        }
                    }
                    .disabled(viewModel.isImportingModel)
                } header: {
                    Text("已導入的模型")
                } footer: {
                    Text("點擊模型名稱選擇使用，點擊刪除圖示移除模型")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // ... 其他設定 ...
            }
        }
        .padding()
    }
}

/// 模型列表行視圖
struct ModelRowView: View {
    let model: ImportedModel
    let isSelected: Bool
    let modelsDirectory: URL
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onShowInFinder: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.name)
                        .font(.body)
                    
                    // 模型類型標籤
                    Text(model.inferredModelType)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }

                HStack {
                    // 檔案大小
                    Text(model.fileSizeFormatted)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // 匯入日期
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(model.importDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // 檔案存在狀態
                if !model.fileExists(in: modelsDirectory) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("檔案不存在")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // 選中狀態
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }

            // 在 Finder 中顯示
            Button(action: onShowInFinder) {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("在 Finder 中顯示")

            // 刪除按鈕
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
```

### 方案 E：新增輔助方法

**在 VoiceInputViewModel 中新增：**

```swift
/// 在 Finder 中顯示模型檔案
func showModelInFinder(_ model: ImportedModel) {
    let modelURL = modelsDirectory.appendingPathComponent(model.fileName)
    NSWorkspace.shared.activateFileViewerSelecting([modelURL])
}

/// 驗證模型檔案是否有效
func validateModel(_ model: ImportedModel) -> Bool {
    let modelURL = modelsDirectory.appendingPathComponent(model.fileName)
    guard FileManager.default.fileExists(atPath: modelURL.path) else { return false }
    
    // 檢查檔案大小是否合理（至少 1MB）
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
          let size = attributes[.size] as? Int64,
          size > 1_000_000 else {
        return false
    }
    
    return true
}
```

---

## 實作優先順序

1. **高優先級** - 修正 Security Scoped Resource 存取問題（方案 A）
   - 這是導致模型無法正確匯入的根本原因

2. **高優先級** - 增強模型資訊結構（方案 C）
   - 需要先完成才能支援後續的 UI 改進

3. **中優先級** - 實現非同步複製與進度顯示（方案 B）
   - 改善用戶體驗

4. **中優先級** - 改進 ModelSettingsView UI（方案 D）
   - 提供更好的模型檢視功能

5. **低優先級** - 新增輔助方法（方案 E）
   - 錦上添花的功能

---

## 注意事項

1. **向後相容性**
   - 修改 `ImportedModel` 結構後，需要處理舊版資料的遷移
   - 建議在 `loadImportedModels()` 中加入遷移邏輯

2. **錯誤處理**
   - 所有檔案操作都應該有完善的錯誤處理
   - 錯誤訊息應該清楚地顯示給用戶

3. **效能考量**
   - 大檔案複製應該在背景執行
   - 進度更新不應該過於頻繁（建議每 1% 更新一次）

---

## 相關檔案

- [`VoiceInput/VoiceInputViewModel.swift`](VoiceInput/VoiceInputViewModel.swift) - 主要修改檔案
- [`VoiceInput/SettingsView.swift`](VoiceInput/SettingsView.swift) - UI 修改
- [`VoiceInput/WhisperTranscriptionService.swift`](VoiceInput/WhisperTranscriptionService.swift) - 模型載入服務
