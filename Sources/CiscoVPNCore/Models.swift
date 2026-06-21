import Foundation

public enum DuoMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case push
    case passcode

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .push: "DUO Push"
        case .passcode: "TOTP Passcode"
        }
    }
}

public enum MFAInjectionStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case numericMenu
    case secondPassword
    case passwordAppend
    case waitOnly
    case passcode

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .numericMenu: "Numeric Menu"
        case .secondPassword: "Second Password"
        case .passwordAppend: "Password Append"
        case .waitOnly: "Wait Only"
        case .passcode: "Passcode"
        }
    }

    public var summary: String {
        switch self {
        case .auto:
            "Detect Cisco/Duo prompts and choose the safest response."
        case .numericMenu:
            "Send the saved numeric Duo menu option when Cisco shows a menu."
        case .secondPassword:
            "Send push/push2 or the TOTP code at a second-password prompt."
        case .passwordAppend:
            "Append ,push, ,push2, or ,code to the primary password field."
        case .waitOnly:
            "Send only the primary password and wait for server-triggered Duo Push."
        case .passcode:
            "Prefer a generated passcode at MFA prompts."
        }
    }
}

public struct VPNProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var server: String
    public var group: String
    public var port: String
    public var vpnProtocol: String
    public var duoMethod: DuoMethod
    public var mfaStrategy: MFAInjectionStrategy
    public var pushTarget: String

    public init(
        id: String,
        displayName: String,
        server: String,
        group: String,
        port: String,
        vpnProtocol: String,
        duoMethod: DuoMethod,
        mfaStrategy: MFAInjectionStrategy = .auto,
        pushTarget: String
    ) {
        self.id = VPNProfile.normalizedID(id)
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.server = server.trimmingCharacters(in: .whitespacesAndNewlines)
        self.group = group.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "443" : port.trimmingCharacters(in: .whitespacesAndNewlines)
        self.vpnProtocol = vpnProtocol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ssl" : vpnProtocol.trimmingCharacters(in: .whitespacesAndNewlines)
        self.duoMethod = duoMethod
        self.mfaStrategy = mfaStrategy
        self.pushTarget = CiscoVPNGroupResolver.normalizedNumericInput(pushTarget) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case server
        case group
        case port
        case vpnProtocol
        case duoMethod
        case mfaStrategy
        case pushTarget
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? "profile",
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName) ?? "VPN Profile",
            server: try container.decodeIfPresent(String.self, forKey: .server) ?? "",
            group: try container.decodeIfPresent(String.self, forKey: .group) ?? "-Default-",
            port: try container.decodeIfPresent(String.self, forKey: .port) ?? "443",
            vpnProtocol: try container.decodeIfPresent(String.self, forKey: .vpnProtocol) ?? "ssl",
            duoMethod: try container.decodeIfPresent(DuoMethod.self, forKey: .duoMethod) ?? .push,
            mfaStrategy: try container.decodeIfPresent(MFAInjectionStrategy.self, forKey: .mfaStrategy) ?? .auto,
            pushTarget: try container.decodeIfPresent(String.self, forKey: .pushTarget) ?? ""
        )
    }

    public static func normalizedID(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = value.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
        let filtered = String(String.UnicodeScalarView(scalars.filter { allowed.contains($0) }))
        return filtered.isEmpty ? "profile" : filtered
    }

    public static var dkuDefault: VPNProfile {
        VPNProfile(
            id: "dku",
            displayName: "DKU VPN",
            server: "portal.dukekunshan.edu.cn",
            group: "-Default-",
            port: "443",
            vpnProtocol: "ssl",
            duoMethod: .push,
            pushTarget: ""
        )
    }

    public static var dukeDefault: VPNProfile {
        VPNProfile(
            id: "duke",
            displayName: "Duke VPN",
            server: "vpn.duke.edu",
            group: "INTL-DUKE",
            port: "443",
            vpnProtocol: "ssl",
            duoMethod: .push,
            pushTarget: ""
        )
    }
}

public struct VPNSecret: Equatable, Sendable {
    public var username: String
    public var password: String
    public var totpCode: String?

    public init(username: String, password: String, totpCode: String?) {
        self.username = username
        self.password = password
        self.totpCode = totpCode
    }
}

public struct SavedVPNSecret: Codable, Equatable, Sendable {
    public var username: String
    public var password: String
    public var totpSecret: String

    public init(username: String = "", password: String = "", totpSecret: String = "") {
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
        self.totpSecret = totpSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case username
        case password
        case totpSecret
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            username: try container.decodeIfPresent(String.self, forKey: .username) ?? "",
            password: try container.decodeIfPresent(String.self, forKey: .password) ?? "",
            totpSecret: try container.decodeIfPresent(String.self, forKey: .totpSecret) ?? ""
        )
    }

    public var diagnostics: SavedVPNSecretDiagnostics {
        SavedVPNSecretDiagnostics(secret: self)
    }
}

public struct SavedVPNSecretDiagnostics: Equatable, Sendable {
    public let usernameCharacterCount: Int
    public let passwordCharacterCount: Int
    public let passwordIsASCIIPrintable: Bool
    public let passwordHasLeadingOrTrailingWhitespace: Bool
    public let passwordContainsNewline: Bool
    public let passwordContainsControlCharacters: Bool

    public init(secret: SavedVPNSecret) {
        usernameCharacterCount = secret.username.count
        passwordCharacterCount = secret.password.count
        passwordIsASCIIPrintable = secret.password.unicodeScalars.allSatisfy {
            $0.value >= 0x20 && $0.value <= 0x7e
        }
        passwordHasLeadingOrTrailingWhitespace = (secret.password.first?.isWhitespace ?? false)
            || (secret.password.last?.isWhitespace ?? false)
        passwordContainsNewline = secret.password.contains { $0 == "\n" || $0 == "\r" }
        passwordContainsControlCharacters = secret.password.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
    }

    public var summary: String {
        [
            "NetID chars=\(usernameCharacterCount)",
            "password chars=\(passwordCharacterCount)",
            "passwordASCII=\(passwordIsASCIIPrintable ? "yes" : "no")",
            "passwordEdgeWhitespace=\(passwordHasLeadingOrTrailingWhitespace ? "yes" : "no")",
            "passwordNewline=\(passwordContainsNewline ? "yes" : "no")",
            "passwordControl=\(passwordContainsControlCharacters ? "yes" : "no")"
        ].joined(separator: "; ")
    }

    public var actionGuidance: String? {
        if passwordContainsNewline || passwordContainsControlCharacters {
            return "Reset saved credentials and re-enter the password; newline or hidden control characters were detected."
        }
        if passwordHasLeadingOrTrailingWhitespace {
            return "Reset saved credentials if the leading/trailing whitespace was not intentional."
        }
        if !passwordIsASCIIPrintable {
            return "Reset saved credentials and re-enter the password with the English input method if Chinese/full-width characters were not intentional."
        }
        return nil
    }
}

public enum VPNConnectionState: String, Codable, Equatable, Sendable {
    case connected
    case disconnected
    case unknown

    public var title: String {
        switch self {
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .unknown: "Unknown"
        }
    }
}

public struct VPNStatus: Equatable, Sendable {
    public var state: VPNConnectionState
    public var server: String?
    public var clientIPv4: String?
    public var duration: String?
    public var remaining: String?
    public var rawOutput: String

    public init(
        state: VPNConnectionState,
        server: String?,
        clientIPv4: String?,
        duration: String?,
        remaining: String?,
        rawOutput: String = ""
    ) {
        self.state = state
        self.server = server
        self.clientIPv4 = clientIPv4
        self.duration = duration
        self.remaining = remaining
        self.rawOutput = rawOutput
    }
}

public struct VPNCommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var output: String
    public var redactedInputPreview: String

    public init(exitCode: Int32, output: String, redactedInputPreview: String = "") {
        self.exitCode = exitCode
        self.output = output
        self.redactedInputPreview = redactedInputPreview
    }
}

public enum CiscoVPNError: Error, LocalizedError, Equatable {
    case binaryNotFound
    case missingCredentials
    case missingTOTPSecret
    case commandTimedOut
    case invalidBase32Secret
    case groupNotFound(String, available: [String])
    case keychain(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            "Cisco VPN CLI was not found. Install Cisco Secure Client or set CISCO_VPN_BIN."
        case .missingCredentials:
            "Username and password are required before connecting."
        case .missingTOTPSecret:
            "This profile uses passcode mode, but no TOTP secret is saved."
        case .commandTimedOut:
            "Cisco VPN command timed out."
        case .invalidBase32Secret:
            "The TOTP secret is not valid Base32."
        case .groupNotFound(let group, let available):
            if available.isEmpty {
                "Configured VPN group '\(group)' was not found in the Cisco group menu."
            } else {
                "Configured VPN group '\(group)' was not found. Available groups: \(available.joined(separator: ", "))."
            }
        case .keychain(let message):
            "Keychain error: \(message)"
        }
    }
}
