import Foundation

public struct CiscoVPNRedactor: Sendable {
    public var username: String?
    public var password: String?
    public var mfaToken: String?
    public var totpSecret: String?

    public init(
        username: String? = nil,
        password: String? = nil,
        mfaToken: String? = nil,
        totpSecret: String? = nil
    ) {
        self.username = username
        self.password = password
        self.mfaToken = mfaToken
        self.totpSecret = totpSecret
    }

    public init(secret: SavedVPNSecret, mfaToken: String? = nil) {
        self.init(
            username: secret.username,
            password: secret.password,
            mfaToken: mfaToken,
            totpSecret: secret.totpSecret
        )
    }

    public func redact(_ text: String) -> String {
        var result = text
        let replacements = [
            (value: username, placeholder: "<username>", minimumLength: 1),
            (value: password, placeholder: "<password>", minimumLength: 1),
            (value: mfaToken, placeholder: "<mfa>", minimumLength: 4),
            (value: totpSecret, placeholder: "<totp-secret>", minimumLength: 1)
        ]
            .compactMap { item -> (value: String, placeholder: String)? in
                guard let value = item.value, value.count >= item.minimumLength, !value.isEmpty else {
                    return nil
                }
                return (value, item.placeholder)
            }
            .sorted { $0.value.count > $1.value.count }

        for replacement in replacements {
            result = result.replacingOccurrences(of: replacement.value, with: replacement.placeholder)
        }
        return result
    }
}
