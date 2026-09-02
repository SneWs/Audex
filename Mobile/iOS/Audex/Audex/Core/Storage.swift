import Foundation
import Security

enum KeychainStore {
    private static let service = "se.grenangen.Audex"
    private static let account = "jwt"

    static func save(_ token: String) {
        delete()
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@Observable
final class AppSettings {
    var serverURLString: String {
        didSet { UserDefaults.standard.set(serverURLString, forKey: Keys.serverURL) }
    }

    var prefersDarkMode: Bool {
        didSet { UserDefaults.standard.set(prefersDarkMode, forKey: Keys.darkMode) }
    }

    var playbackRate: Float {
        didSet { UserDefaults.standard.set(playbackRate, forKey: Keys.playbackRate) }
    }

    var serverURL: URL? {
        APIClient.normalize(serverURLString)
    }

    init() {
        serverURLString = UserDefaults.standard.string(forKey: Keys.serverURL) ?? ""
        prefersDarkMode = UserDefaults.standard.object(forKey: Keys.darkMode) as? Bool ?? true
        let storedRate = UserDefaults.standard.object(forKey: Keys.playbackRate) as? Float
        playbackRate = storedRate ?? 1.0
    }

    private enum Keys {
        static let serverURL = "server_uri"
        static let darkMode = "dark_mode"
        static let playbackRate = "playback_rate"
    }
}
