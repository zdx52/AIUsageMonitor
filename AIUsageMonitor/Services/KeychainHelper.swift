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
        
        // 先删除所有旧条目（兼容多个 service name）
        for name in [Self.serviceName, Bundle.main.bundleIdentifier ?? Self.serviceName] {
            let delQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: name,
                kSecAttrAccount as String: key
            ]
            SecItemDelete(delQuery as CFDictionary)
        }
        
        // 使用固定 service name 保存，并允许当前 App 无提示访问
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // 添加访问控制：允许当前 App 无提示访问
        var trustedApp: SecTrustedApplication?
        if SecTrustedApplicationCreateFromPath(nil, &trustedApp) == errSecSuccess,
           let app = trustedApp {
            let accessList = [app] as CFArray
            var access: SecAccess?
            if SecAccessCreate(Self.serviceName as CFString, accessList, &access) == errSecSuccess,
               let secAccess = access {
                query[kSecAttrAccess as String] = secAccess
            }
        }
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("⚠️ Keychain save 失败 (key: \(key), status: \(status))")
        }
    }
    
    static func get(key: String) -> String? {
        // 优先使用固定 service name
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        
        // 兼容旧版：尝试用 Bundle ID 查找
        if let bundleID = Bundle.main.bundleIdentifier {
            let fallbackQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: bundleID,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var fallbackResult: AnyObject?
            if SecItemCopyMatching(fallbackQuery as CFDictionary, &fallbackResult) == errSecSuccess,
               let data = fallbackResult as? Data {
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
