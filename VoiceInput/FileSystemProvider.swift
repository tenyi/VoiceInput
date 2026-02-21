import Foundation

/// 檔案系統操作協定，用於依賴注入與測試隔離
protocol FileSystemProtocol: Sendable {
    /// 檢查指定路徑的檔案是否存在
    func fileExists(atPath path: String) -> Bool
    
    /// 從指定的 URL 讀取資料
    func data(contentsOf url: URL) throws -> Data
    
    /// 取得使用者的 Application Support 目錄
    var applicationSupportDirectory: URL? { get }
    
    /// 建立目錄
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]?) throws
    
    /// 寫入資料到指定的 URL
    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws
    
    /// 刪除指定路徑的項目
    func removeItem(at url: URL) throws
    
    /// 複製項目
    func copyItem(at srcURL: URL, to dstURL: URL) throws
    
    /// 取得檔案大小
    func getFileSize(at url: URL) throws -> Int64
}

/// 實際的檔案系統實作，封裝 FileManager
final class DefaultFileSystem: FileSystemProtocol, Sendable {
    static let shared = DefaultFileSystem()
    private let manager = FileManager.default
    
    private init() {}
    
    func fileExists(atPath path: String) -> Bool {
        return manager.fileExists(atPath: path)
    }
    
    func data(contentsOf url: URL) throws -> Data {
        return try Data(contentsOf: url)
    }
    
    var applicationSupportDirectory: URL? {
        return manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }
    
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = nil) throws {
        try manager.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
    
    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        try data.write(to: url, options: options)
    }
    
    func removeItem(at url: URL) throws {
        try manager.removeItem(at: url)
    }
    
    func copyItem(at srcURL: URL, to dstURL: URL) throws {
        try manager.copyItem(at: srcURL, to: dstURL)
    }
    
    func getFileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }
}
