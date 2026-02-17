import Foundation
import Combine
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import os

/// 負責管理 Whisper 模型導入、刪除、選擇的管理器
class ModelManager: ObservableObject {
    /// 日誌記錄器
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "ModelManager")

    /// 已導入的模型列表資料 (JSON 編碼格式)
    @AppStorage("importedModels") private var importedModelsData: Data = Data()

    /// 已導入的模型列表
    @Published var importedModels: [ImportedModel] = []

    /// 是否正在導入模型
    @Published var isImportingModel = false

    /// 模型導入進度 (0.0 - 1.0)
    @Published var modelImportProgress: Double = 0.0

    /// 模型導入錯誤訊息
    @Published var modelImportError: String?

    /// 模型導入速度文字
    @Published var modelImportSpeed: String = ""

    /// 模型導入剩餘時間文字
    @Published var modelImportRemainingTime: String = ""

    /// 模型儲存目錄
    let modelsDirectory: URL

    /// 公共模型目錄
    let publicModelsDirectory: URL

    /// 當前選擇的模型路徑
    @Published var selectedModelPath: String = ""

    init() {
        // 初始化目錄
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "VoiceInput"
        modelsDirectory = appSupport.appendingPathComponent(bundleID).appendingPathComponent("Models")

        // 公共模型目錄 (可選)
        publicModelsDirectory = URL(fileURLWithPath: "/usr/local/share/VoiceInput/Models")

        // 載入已導入的模型列表
        loadModels()
    }

    // MARK: - 模型列表管理

    /// 載入已導入的模型列表
    func loadModels() {
        guard !importedModelsData.isEmpty else { return }
        do {
            importedModels = try JSONDecoder().decode([ImportedModel].self, from: importedModelsData)
            logger.info("已載入 \(self.importedModels.count) 個已導入的模型")
        } catch {
            logger.error("無法載入已導入的模型列表: \(error.localizedDescription)")
        }
    }

    /// 保存已導入的模型列表
    private func saveModels() {
        do {
            importedModelsData = try JSONEncoder().encode(importedModels)
        } catch {
            logger.error("無法保存模型列表: \(error.localizedDescription)")
        }
    }

    // MARK: - 模型導入

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

            DispatchQueue.main.async {
                self.importModelFromURL(sourceURL)
            }
        }
    }

    /// 從指定 URL 導入模型
    func importModelFromURL(_ sourceURL: URL) {
        // 進入匯入狀態
        self.isImportingModel = true
        self.modelImportError = nil
        self.modelImportProgress = 0.0
        self.modelImportSpeed = "準備中..."
        self.modelImportRemainingTime = "計算中..."

        // 取得模型名稱（不含副檔名）
        let modelName = sourceURL.deletingPathExtension().lastPathComponent
        let destinationFileName = "\(modelName).bin"
        let destinationURL = modelsDirectory.appendingPathComponent(destinationFileName)

        // 檢查是否已存在
        if importedModels.contains(where: { $0.fileName == destinationFileName }) {
            self.modelImportError = "模型已存在: \(destinationFileName)"
            self.isImportingModel = false
            return
        }

        // 在背景執行複製操作
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                // 確保目錄存在
                try FileManager.default.createDirectory(at: self.modelsDirectory, withIntermediateDirectories: true, attributes: nil)

                // 取得檔案大小
                let fileSize = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

                // 開始複製
                DispatchQueue.main.async {
                    self.modelImportSpeed = "正在複製..."
                    self.modelImportProgress = 0.5
                }

                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }

                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

                // 建立新模型物件
                let newModel = ImportedModel(name: modelName, fileName: destinationFileName, fileSize: Int64(fileSize))

                DispatchQueue.main.async {
                    // 新增到列表
                    self.importedModels.append(newModel)
                    self.saveModels()

                    // 自動選擇新導入的模型
                    self.selectModel(newModel)

                    self.logger.info("模型導入成功: \(destinationFileName)，儲存於: \(destinationURL.path)")
                    self.isImportingModel = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.modelImportError = "導入失敗: \(error.localizedDescription)"
                    self.isImportingModel = false
                    self.logger.error("模型導入失敗: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - 模型刪除

    /// 刪除模型
    func deleteModel(_ model: ImportedModel) {
        let modelURL = modelsDirectory.appendingPathComponent(model.fileName)

        do {
            // 刪除檔案
            if FileManager.default.fileExists(atPath: modelURL.path) {
                try FileManager.default.removeItem(at: modelURL)
            }

            // 從列表移除
            importedModels.removeAll { $0.id == model.id }
            saveModels()

            // 如果當前選擇的模型被刪除，清除選擇
            if selectedModelPath == modelURL.path {
                selectedModelPath = ""
            }

            logger.info("模型已刪除: \(model.fileName)")
        } catch {
            logger.error("刪除模型失敗: \(error.localizedDescription)")
        }
    }

    // MARK: - 模型選擇

    /// 選擇已導入的模型
    func selectModel(_ model: ImportedModel) {
        let modelURL = modelsDirectory.appendingPathComponent(model.fileName)
        selectedModelPath = modelURL.path
        logger.info("已選擇模型: \(model.fileName)")
    }

    /// 取得目前選擇模型的 URL
    func getSelectedModelURL() -> URL? {
        if !selectedModelPath.isEmpty {
            return URL(fileURLWithPath: selectedModelPath)
        }
        return nil
    }

    /// 檢查模型檔案是否存在
    func modelExists(_ model: ImportedModel) -> Bool {
        let modelURL = modelsDirectory.appendingPathComponent(model.fileName)
        return FileManager.default.fileExists(atPath: modelURL.path)
    }

    /// 在 Finder 中顯示模型
    func showModelInFinder(_ model: ImportedModel) {
        let modelURL = modelsDirectory.appendingPathComponent(model.fileName)
        NSWorkspace.shared.selectFile(modelURL.path, inFileViewerRootedAtPath: modelsDirectory.path)
    }
}
