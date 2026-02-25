import Foundation
import Security
import os

protocol KeychainProtocol {
    func save(_ value: String, service: String, account: String)
    func read(service: String, account: String) -> String?
    func delete(service: String, account: String)
}

/// 簡單的 Keychain 封裝工具
class KeychainHelper: KeychainProtocol {
    static let shared = KeychainHelper()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceInput", category: "KeychainHelper")
    
    private init() {}
    
    /// 儲存字串到 Keychain（add-or-update 模式，避免 errSecDuplicateItem 靜默失敗）
    func save(_ value: String, service: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        
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
            if addStatus != errSecSuccess {
                logger.error("Keychain add 失敗，service=\(service), account=\(account), status=\(addStatus)")
            }
        } else {
            logger.error("Keychain update 失敗，service=\(service), account=\(account), status=\(updateStatus)")
        }
    }
    
    /// 從 Keychain 讀取字串
    func read(service: String, account: String) -> String? {
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
        }
        
        return nil
    }
    
    /// 從 Keychain 刪除資料
    func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
