import Foundation

public struct VPNProfileSubscriptionImportResult: Equatable, Sendable {
    public let sourceName: String
    public let profiles: [VPNProfile]

    public init(sourceName: String, profiles: [VPNProfile]) {
        self.sourceName = sourceName
        self.profiles = profiles
    }
}

public enum VPNProfileSubscriptionError: Error, LocalizedError, Equatable {
    case invalidJSON
    case containsCredentialFields
    case emptyProfiles
    case tooManyProfiles(Int)
    case missingServer(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "Subscription must be JSON with a profiles array."
        case .containsCredentialFields:
            "Subscription rejected because it contains credential-like fields. Profile subscriptions may include VPN metadata only."
        case .emptyProfiles:
            "Subscription does not include any VPN profiles."
        case .tooManyProfiles(let count):
            "Subscription includes \(count) profiles. The limit is 50."
        case .missingServer(let profile):
            "Subscription profile '\(profile)' is missing a VPN server."
        }
    }
}

public enum VPNProfileSubscriptionURLPolicy {
    public static func isAllowed(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        if scheme == "https" {
            return !(url.host ?? "").isEmpty
        }
        if scheme == "http" {
            return isLocalhost(url.host)
        }
        return false
    }

    private static func isLocalhost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

public enum VPNProfileSubscriptionImporter {
    private static let maxProfiles = 50
    private static let credentialKeys: Set<String> = [
        "apikey",
        "api_key",
        "credential",
        "credentials",
        "pass",
        "password",
        "secret",
        "token",
        "totp_secret",
        "totpsecret",
        "user",
        "username"
    ]

    public static func importProfiles(from data: Data) throws -> VPNProfileSubscriptionImportResult {
        try rejectCredentialFields(in: data)

        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(SubscriptionEnvelope.self, from: data) {
            return try result(from: envelope)
        }
        if let profiles = try? decoder.decode([SubscriptionProfile].self, from: data) {
            return try result(from: SubscriptionEnvelope(name: nil, profiles: profiles))
        }
        throw VPNProfileSubscriptionError.invalidJSON
    }

    private static func result(from envelope: SubscriptionEnvelope) throws -> VPNProfileSubscriptionImportResult {
        guard !envelope.profiles.isEmpty else {
            throw VPNProfileSubscriptionError.emptyProfiles
        }
        guard envelope.profiles.count <= maxProfiles else {
            throw VPNProfileSubscriptionError.tooManyProfiles(envelope.profiles.count)
        }

        let profiles = try envelope.profiles.map { try $0.profile() }
        let sourceName = envelope.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return VPNProfileSubscriptionImportResult(
            sourceName: sourceName?.isEmpty == false ? sourceName! : "VPN Profile Subscription",
            profiles: profiles
        )
    }

    private static func rejectCredentialFields(in data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw VPNProfileSubscriptionError.invalidJSON
        }

        if containsCredentialField(object) {
            throw VPNProfileSubscriptionError.containsCredentialFields
        }
    }

    private static func containsCredentialField(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                let normalizedKey = key
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if credentialKeys.contains(normalizedKey) {
                    return true
                }
                if containsCredentialField(nestedValue) {
                    return true
                }
            }
            return false
        }
        if let array = value as? [Any] {
            return array.contains { containsCredentialField($0) }
        }
        return false
    }
}

private struct SubscriptionEnvelope: Decodable {
    let name: String?
    let profiles: [SubscriptionProfile]
}

private struct SubscriptionProfile: Decodable {
    let id: String?
    let displayName: String?
    let server: String?
    let group: String?
    let port: String?
    let vpnProtocol: String?
    let duoMethod: DuoMethod?
    let mfaStrategy: MFAInjectionStrategy?
    let pushTarget: String?

    func profile() throws -> VPNProfile {
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = name?.isEmpty == false ? name! : "VPN Profile"
        let serverValue = server?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !serverValue.isEmpty else {
            throw VPNProfileSubscriptionError.missingServer(fallbackName)
        }

        return VPNProfile(
            id: id?.isEmpty == false ? id! : fallbackName,
            displayName: fallbackName,
            server: serverValue,
            group: group ?? "-Default-",
            port: port ?? "443",
            vpnProtocol: vpnProtocol ?? "ssl",
            duoMethod: duoMethod ?? .push,
            mfaStrategy: mfaStrategy ?? .auto,
            pushTarget: pushTarget ?? ""
        )
    }
}
