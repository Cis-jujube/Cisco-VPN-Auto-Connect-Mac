import Foundation

public enum TOTPSecretImportError: Error, LocalizedError, Equatable {
    case emptyInput
    case unsupportedDuoActivationLink
    case missingSecret
    case invalidBase32Secret

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            "No TOTP text was provided."
        case .unsupportedDuoActivationLink:
            "Duo activation links cannot be converted into a TOTP secret."
        case .missingSecret:
            "The authenticator URL does not contain a TOTP secret."
        case .invalidBase32Secret:
            "The imported TOTP secret is not valid Base32."
        }
    }
}

public enum TOTPSecretImporter {
    public static func secret(from input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TOTPSecretImportError.emptyInput
        }

        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("duo://") {
            throw TOTPSecretImportError.unsupportedDuoActivationLink
        }

        if lowercased.hasPrefix("otpauth://") {
            guard let value = secretQueryValue(from: trimmed) else {
                throw TOTPSecretImportError.missingSecret
            }
            return try normalizedBase32Secret(value)
        }

        return try normalizedBase32Secret(trimmed)
    }

    private static func secretQueryValue(from urlString: String) -> String? {
        if let components = URLComponents(string: urlString),
           let item = components.queryItems?.first(where: { $0.name.caseInsensitiveCompare("secret") == .orderedSame }),
           let value = item.value {
            return value
        }

        guard let queryStart = urlString.firstIndex(of: "?") else {
            return nil
        }
        let query = urlString[urlString.index(after: queryStart)...]
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first ?? ""

        for field in query.split(separator: "&", omittingEmptySubsequences: false) {
            let pair = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            let name = percentDecoded(String(pair[0]))
            guard name.caseInsensitiveCompare("secret") == .orderedSame else { continue }
            return percentDecoded(String(pair[1]))
        }

        return nil
    }

    private static func normalizedBase32Secret(_ value: String) throws -> String {
        let cleaned = value
            .uppercased()
            .filter { !$0.isWhitespace && $0 != "=" }
        let alphabet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

        guard !cleaned.isEmpty else {
            throw TOTPSecretImportError.emptyInput
        }

        guard cleaned.unicodeScalars.allSatisfy({ alphabet.contains($0) }) else {
            throw TOTPSecretImportError.invalidBase32Secret
        }

        do {
            _ = try TOTPGenerator().code(secret: cleaned)
        } catch {
            throw TOTPSecretImportError.invalidBase32Secret
        }

        return cleaned
    }

    private static func percentDecoded(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }
}
