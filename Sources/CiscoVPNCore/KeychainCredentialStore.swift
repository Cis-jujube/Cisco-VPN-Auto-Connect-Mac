import Foundation
import Security

public protocol VPNCredentialStore {
    func loadSecret(profileID: String) throws -> SavedVPNSecret?
    func saveSecret(_ secret: SavedVPNSecret, profileID: String) throws
    func deleteSecret(profileID: String) throws
}

public final class KeychainCredentialStore: VPNCredentialStore {
    private let service: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(service: String = "CiscoVPNAutoConnect") {
        self.service = service
    }

    public func loadSecret(profileID: String) throws -> SavedVPNSecret? {
        var query = baseQuery(profileID: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CiscoVPNError.keychain(statusMessage(status))
        }
        guard let data = result as? Data else {
            return nil
        }
        return try decoder.decode(SavedVPNSecret.self, from: data)
    }

    public func saveSecret(_ secret: SavedVPNSecret, profileID: String) throws {
        let data = try encoder.encode(secret)
        var query = baseQuery(profileID: profileID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw CiscoVPNError.keychain(statusMessage(updateStatus))
        }

        query.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CiscoVPNError.keychain(statusMessage(addStatus))
        }
    }

    public func deleteSecret(profileID: String) throws {
        let status = SecItemDelete(baseQuery(profileID: profileID) as CFDictionary)
        if status == errSecItemNotFound || status == errSecSuccess {
            return
        }
        throw CiscoVPNError.keychain(statusMessage(status))
    }

    private func baseQuery(profileID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "profile:\(profileID)"
        ]
    }

    private func statusMessage(_ status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "OSStatus \(status)"
    }
}
