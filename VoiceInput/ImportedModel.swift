import Foundation

/// 已導入的 Whisper 模型結構
struct ImportedModel: Identifiable, Codable {
    let id: UUID
    var name: String
    var fileName: String
    /// 檔案大小（bytes）
    var fileSize: Int64?
    /// 匯入日期
    var importDate: Date

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

    /// 推斷的模型類型（根據檔案大小）
    var inferredModelType: String {
        guard let size = fileSize else { return "未知" }
        // 根據檔案大小推斷模型類型（近似值）
        if size < 75_000_000 {
            return "Tiny"
        } else if size < 150_000_000 {
            return "Base"
        } else if size < 500_000_000 {
            return "Small"
        } else if size < 1_500_000_000 {
            return "Medium"
        } else {
            return "Large"
        }
    }

    /// 檢查檔案是否存在
    func fileExists(in directory: URL) -> Bool {
        let url = directory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path)
    }
}
