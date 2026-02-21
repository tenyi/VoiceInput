import Foundation
import Security

protocol KeychainProtocol {
    func save(_ value: String, service: String, account: String)
    func read(service: String, account: String) -> String?
    func delete(service: String, account: String)
}

/// 簡單的 Keychain 封裝工具
class KeychainHelper: KeychainProtocol {
    static let shared = KeychainHelper()
    
    private init() {}
    
    /// 儲存字串到 Keychain
    func save(_ value: String, service: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        // 建立查詢用字典 (不可包含 kSecValueData)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        // 先嘗試刪除舊的
        SecItemDelete(query as CFDictionary)
        
        // 建立新增用的字典（必須加上值）
        var addQuery = query
        addQuery[kSecValueData as String] = data
        
        // 新增
        SecItemAdd(addQuery as CFDictionary, nil)
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
