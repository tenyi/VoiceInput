import Foundation
import Security
import os

protocol KeychainProtocol {
    func save(_ value: String, service: String, account: String) throws
    func read(service: String, account: String) throws -> String?
    func delete(service: String, account: String) throws
}

enum KeychainError: LocalizedError {
    case encodingFailed
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case duplicateItem

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "資料編碼失敗"
        case .itemNotFound: return "找不到 Keychain 項目"
        case .unexpectedStatus(let status): return "Keychain 發生非預期的錯誤 (狀態碼: \(status))"
        case .duplicateItem: return "Keychain 項目已存在"
        }
    }
}

/// 簡單的 Keychain 封裝工具
final class KeychainHelper: KeychainProtocol {
    static let shared = KeychainHelper()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "KeychainHelper")

    // C-5 修復:序列化 save 流程,避免 SecItemUpdate → SecItemAdd 之間的 TOCTOU 競態。
    // 多執行緒同時 save 同一組 service+account 時,可能 Add 階段另一端先建立,
    // 導致 errSecDuplicateItem 被誤判為 unexpectedStatus。
    private let saveLock = NSLock()

    private init() {}

    /// 儲存字串到 Keychain（add-or-update 模式 + 序列化保護）
    func save(_ value: String, service: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        saveLock.lock()
        defer { saveLock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // 先嘗試更新已存在的項目
        let updateAttribs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttribs as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            // 項目不存在，新增
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecSuccess {
                return
            }
            // C-5 修復:處理 Add 階段被另一執行緒搶先新增的 errSecDuplicateItem
            // 改回 SecItemUpdate 重試一次,確保最終狀態一致
            if addStatus == errSecDuplicateItem {
                let retryStatus = SecItemUpdate(query as CFDictionary, updateAttribs as CFDictionary)
                if retryStatus == errSecSuccess {
                    return
                }
                logger.error("Keychain update 重試失敗，service=\(service), account=\(account), status=\(retryStatus)")
                throw KeychainError.unexpectedStatus(retryStatus)
            }
            logger.error("Keychain add 失敗，service=\(service), account=\(account), status=\(addStatus)")
            throw KeychainError.unexpectedStatus(addStatus)
        }

        logger.error("Keychain update 失敗，service=\(service), account=\(account), status=\(updateStatus)")
        throw KeychainError.unexpectedStatus(updateStatus)
    }
    
    /// 從 Keychain 讀取字串
    func read(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        } else if status == errSecItemNotFound {
            return nil
        } else {
            logger.error("Keychain read 失敗，service=\(service), account=\(account), status=\(status)")
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    /// 從 Keychain 刪除資料
    func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Keychain delete 失敗，service=\(service), account=\(account), status=\(status)")
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
