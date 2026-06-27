import Foundation
import Security

class KeychainHelper {
    
    // 固定 service name，避免 .app bundle 与 debug 二进制之间 bundle identifier 不一致
    private static let serviceName = "com.aiusagemonitor"
    
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else {
            print("⚠️ Keychain save: 字符串转 Data 失败 (key: \(key))")
            return
        }
        
        // 先删除旧的
        delete(key: key)
        
        // 使用固定 service name，避免 Bundle ID 变化导致 Keychain 读取失败
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
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
        // 依次尝试多个 service name，兼容不同构建方式存的 Key
        let namesToTry = [
            Self.serviceName,                                                // 固定名
            Bundle.main.bundleIdentifier ?? Self.serviceName                 // 当前 Bundle ID
        ]
        
        for name in namesToTry {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: name,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            
            if status == errSecSuccess, let data = result as? Data {
                return String(data: data, encoding: .utf8)
            }
        }
        
        return nil
    }
    
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("⚠️ Keychain delete 失败 (key: \(key), status: \(status))")
        }
    }
}
