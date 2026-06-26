import Foundation
import Security

class KeychainHelper {
    
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else {
            print("⚠️ Keychain save: 字符串转 Data 失败 (key: \(key))")
            return
        }
        
        // 先删除旧的
        delete(key: key)
        
        // 使用 App Bundle ID 作为 service name，避免权限冲突
        let serviceName = Bundle.main.bundleIdentifier ?? "com.aiusagemonitor"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("⚠️ Keychain save 失败 (key: \(key), status: \(status))")
        }
    }
    
    static func get(key: String) -> String? {
        let serviceName = Bundle.main.bundleIdentifier ?? "com.aiusagemonitor"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    static func delete(key: String) {
        let serviceName = Bundle.main.bundleIdentifier ?? "com.aiusagemonitor"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("⚠️ Keychain delete 失败 (key: \(key), status: \(status))")
        }
    }
}
