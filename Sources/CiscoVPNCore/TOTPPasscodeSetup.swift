import Foundation

public enum TOTPPasscodeSetup {
    public static func apply(
        input: String,
        to profile: VPNProfile,
        savedSecret: SavedVPNSecret
    ) throws -> (profile: VPNProfile, secret: SavedVPNSecret) {
        let totpSecret = try TOTPSecretImporter.secret(from: input)
        let updatedProfile = VPNProfile(
            id: profile.id,
            displayName: profile.displayName,
            server: profile.server,
            group: profile.group,
            port: profile.port,
            vpnProtocol: profile.vpnProtocol,
            duoMethod: .passcode,
            mfaStrategy: .passcode,
            pushTarget: profile.pushTarget
        )
        let updatedSecret = SavedVPNSecret(
            username: savedSecret.username,
            password: savedSecret.password,
            totpSecret: totpSecret
        )
        return (updatedProfile, updatedSecret)
    }
}
