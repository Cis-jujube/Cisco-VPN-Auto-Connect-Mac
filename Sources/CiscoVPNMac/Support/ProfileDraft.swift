import CiscoVPNCore
import Foundation

struct ProfileDraft: Equatable {
    var id: String
    var displayName: String
    var server: String
    var group: String
    var port: String
    var vpnProtocol: String
    var duoMethod: DuoMethod
    var mfaStrategy: MFAInjectionStrategy
    var pushTarget: String
    var username: String
    var password: String
    var totpSecret: String

    init(profile: VPNProfile, secret: SavedVPNSecret) {
        self.id = profile.id
        self.displayName = profile.displayName
        self.server = profile.server
        self.group = profile.group
        self.port = profile.port
        self.vpnProtocol = profile.vpnProtocol
        self.duoMethod = profile.duoMethod
        self.mfaStrategy = profile.mfaStrategy
        self.pushTarget = profile.pushTarget
        self.username = secret.username
        self.password = secret.password
        self.totpSecret = secret.totpSecret
    }

    var profile: VPNProfile {
        VPNProfile(
            id: id,
            displayName: displayName,
            server: server,
            group: group,
            port: port,
            vpnProtocol: vpnProtocol,
            duoMethod: duoMethod,
            mfaStrategy: mfaStrategy,
            pushTarget: pushTarget
        )
    }

    var secret: SavedVPNSecret {
        SavedVPNSecret(username: username, password: password, totpSecret: totpSecret)
    }

    var credentialDiagnostics: SavedVPNSecretDiagnostics {
        secret.diagnostics
    }

    var isPasscodeMissingSecret: Bool {
        duoMethod == .passcode && totpSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasPasswordHiddenCharacterWarning: Bool {
        !password.isEmpty
            && (!credentialDiagnostics.passwordIsASCIIPrintable
                || credentialDiagnostics.passwordHasLeadingOrTrailingWhitespace
                || credentialDiagnostics.passwordContainsNewline
                || credentialDiagnostics.passwordContainsControlCharacters)
    }

    var needsPushRecommendation: Bool {
        isPasscodeMissingSecret
    }

    var isProfileSaveReady: Bool {
        !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isPasscodeMissingSecret
    }

    var isConnectReady: Bool {
        !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && !isPasscodeMissingSecret
    }
}
