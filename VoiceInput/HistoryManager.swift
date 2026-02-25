import Foundation
import Combine
import os
import AppKit

/// 轉錄歷史紀錄單元
struct TranscriptionHistoryItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let text: String
    let createdAt: Date
}

/// 負責轉錄歷史紀錄的管理與持久化
@MainActor
class HistoryManager: ObservableObject {
    @Published var transcriptionHistory: [TranscriptionHistoryItem] = []
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "HistoryManager")
    
    /// 檔案系統提供者，用於依賴注入
    nonisolated private let fileSystem: FileSystemProtocol
    
    /// 轉錄歷史紀錄檔案儲存路徑 (Application Support/VoiceInput/transcription_history.json)
    private var transcriptionHistoryFileURL: URL {
        let appSupport = fileSystem.applicationSupportDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("VoiceInput", isDirectory: true)
        return dir.appendingPathComponent("transcription_history.json")
    }
    
    init(fileSystem: FileSystemProtocol) {
        self.fileSystem = fileSystem
        Task { @MainActor in
            loadTranscriptionHistory()
        }
    }

    convenience init() {
        self.init(fileSystem: DefaultFileSystem.shared)
    }
    
    /// 載入轉錄歷史（最多保留 10 筆）
    private func loadTranscriptionHistory() {
        let fileURL = transcriptionHistoryFileURL
        guard fileSystem.fileExists(atPath: fileURL.path) else {
            transcriptionHistory = []
            return
        }

        do {
            let data = try fileSystem.data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([TranscriptionHistoryItem].self, from: data)
            transcriptionHistory = Array(decoded.sorted(by: { $0.createdAt > $1.createdAt }).prefix(10))
        } catch {
            logger.error("無法載入轉錄歷史: \(error.localizedDescription)")
            transcriptionHistory = []
        }
    }

    /// 保存轉錄歷史（最多保留 10 筆）
    private func saveTranscriptionHistory() {
        do {
            let historyToSave = Array(transcriptionHistory.prefix(10))
            let data = try JSONEncoder().encode(historyToSave)
            let fileURL = transcriptionHistoryFileURL
            let directory = fileURL.deletingLastPathComponent()
            // 確保資料夾存在
            try fileSystem.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            try fileSystem.write(data, to: fileURL, options: .atomic)
        } catch {
            logger.error("無法保存轉錄歷史: \(error.localizedDescription)")
        }
    }
    
    /// 添加轉錄歷史（僅保留最近 10 筆）
    func addHistoryIfNeeded(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "等待輸入...", !trimmed.hasPrefix("識別錯誤：") else {
            return
        }

        let item = TranscriptionHistoryItem(text: trimmed, createdAt: Date())
        transcriptionHistory.insert(item, at: 0)
        if transcriptionHistory.count > 10 {
            transcriptionHistory = Array(transcriptionHistory.prefix(10))
        }
        saveTranscriptionHistory()
    }

    /// 刪除指定歷史紀錄
    func deleteHistoryItem(_ item: TranscriptionHistoryItem) {
        transcriptionHistory.removeAll { $0.id == item.id }
        saveTranscriptionHistory()
    }

    /// 複製歷史文字到剪貼簿
    func copyHistoryText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
