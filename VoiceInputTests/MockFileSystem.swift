import Foundation
@testable import VoiceInput

/// 用於測試的模擬檔案系統，使用全記憶體儲存 (In-Memory)
class MockFileSystem: FileSystemProtocol {
    var files: [URL: Data] = [:]
    var directories: Set<URL> = []
    
    // 模擬的 application Support 路徑
    var applicationSupportDirectory: URL? = URL(fileURLWithPath: "/mock/ApplicationSupport")
    
    func fileExists(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return files.keys.contains(url) || directories.contains(url)
    }
    
    func data(contentsOf url: URL) throws -> Data {
        if let data = files[url] {
            return data
        }
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: nil)
    }
    
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = nil) throws {
        directories.insert(url)
        // 簡單模擬，不深入處理 intermediate directories 的完整邏輯
    }
    
    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        files[url] = data
    }
    
    func removeItem(at url: URL) throws {
        if let _ = files.removeValue(forKey: url) {
            return
        }
        if directories.contains(url) {
            directories.remove(url)
            return
        }
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: nil)
    }
    
    func copyItem(at srcURL: URL, to dstURL: URL) throws {
        guard let data = files[srcURL] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: nil)
        }
        files[dstURL] = data
    }
    
    func getFileSize(at url: URL) throws -> Int64 {
        guard let data = files[url] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: nil)
        }
        return Int64(data.count)
    }
}
