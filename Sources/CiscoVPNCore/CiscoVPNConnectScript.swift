import Foundation

public enum CiscoVPNGroupResolver {
    public static func groupInput(for group: String) -> String {
        let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
        if let numeric = normalizedGroupNumberInput(trimmed) {
            return numeric
        }
        if trimmed.isEmpty || trimmed == "-Default-" {
            return ""
        }
        if trimmed == "Library Resources Only" {
            return "1"
        }
        if trimmed == "INTL-DUKE" {
            return "2"
        }
        return trimmed
    }

    public static func groupInput(for group: String, menuText: String) throws -> String {
        let requestedGroup = group.trimmingCharacters(in: .whitespacesAndNewlines)
        if let numeric = normalizedGroupNumberInput(requestedGroup) {
            return numeric
        }

        let options = groupMenuOptions(in: menuText)
        guard !options.isEmpty else {
            return groupInput(for: group)
        }

        if requestedGroup.isEmpty || requestedGroup == "-Default-" {
            return ""
        }

        let requestedKey = comparisonKey(for: requestedGroup)
        if let matched = options.first(where: { $0.comparisonKey == requestedKey }) {
            return matched.number
        }

        throw CiscoVPNError.groupNotFound(requestedGroup, available: options.map(\.label))
    }

    public static func normalizedNumericInput(_ value: String) -> String? {
        let digits = value.filter(\.isNumber)
        guard let number = Int(digits), number > 0 else { return nil }
        return String(number)
    }

    private static func normalizedGroupNumberInput(_ value: String) -> String? {
        let digits = value.filter(\.isNumber)
        guard let number = Int(digits), number >= 0 else { return nil }
        return String(number)
    }

    public static func groupMenuOptions(in text: String) -> [CiscoVPNGroupMenuOption] {
        let normalized = text.replacingOccurrences(of: "\r", with: "")
        let patterns = [
            #"(?m)^\s*([0-9]+)\s*[-.):]\s*([^\n]+?)\s*$"#,
            #"(?m)^\s*([0-9]+)\s+([^\n]+?)\s*$"#
        ]
        var seenNumbers: Set<String> = []
        var options: [CiscoVPNGroupMenuOption] = []

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            for match in regex.matches(in: normalized, range: range) {
                guard match.numberOfRanges >= 3,
                      let numberRange = Range(match.range(at: 1), in: normalized),
                      let labelRange = Range(match.range(at: 2), in: normalized) else {
                    continue
                }
                let number = String(normalized[numberRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let label = String(normalized[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !number.isEmpty, !label.isEmpty, !seenNumbers.contains(number) else {
                    continue
                }
                if label.range(
                    of: #"push|sms passcode|passcode|password|username|answer|approve|token"#,
                    options: [.regularExpression, .caseInsensitive]
                ) != nil {
                    continue
                }
                options.append(CiscoVPNGroupMenuOption(number: number, label: label, comparisonKey: comparisonKey(for: label)))
                seenNumbers.insert(number)
            }
        }

        return options
    }

    private static func comparisonKey(for name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"[\s_-]+"#, with: "", options: .regularExpression)
    }
}

public struct CiscoVPNGroupMenuOption: Equatable, Sendable {
    public let number: String
    public let label: String
    public let comparisonKey: String
}

public struct CiscoVPNConnectScript: Equatable, Sendable {
    public let steps: [CiscoVPNConnectStep]
    public let redactedPreview: String
    public let mfaStrategy: MFAInjectionStrategy

    public var commands: [String] {
        steps.map(\.input)
    }

    public init(profile: VPNProfile, secret: VPNSecret) {
        let duoInput: String
        switch profile.duoMethod {
        case .push:
            duoInput = CiscoVPNGroupResolver.normalizedNumericInput(profile.pushTarget) ?? "1"
        case .passcode:
            duoInput = secret.totpCode ?? ""
        }

        mfaStrategy = profile.mfaStrategy
        steps = [
            CiscoVPNConnectStep(label: "connect", input: "connect \(Self.connectAddress(for: profile))", delayAfter: 1.5),
            CiscoVPNConnectStep(
                label: "group",
                input: CiscoVPNGroupResolver.groupInput(for: profile.group),
                delayAfter: 1.0,
                requestedGroup: profile.group
            ),
            CiscoVPNConnectStep(label: "username", input: secret.username, delayAfter: 0.6),
            CiscoVPNConnectStep(label: "password", input: secret.password, delayAfter: 0.8),
            CiscoVPNConnectStep(
                label: "duo",
                input: duoInput,
                delayAfter: profile.duoMethod == .push ? 50.0 : 1.0,
                mfaStrategy: profile.mfaStrategy
            ),
            CiscoVPNConnectStep(label: "accept", input: "y", delayAfter: 0.6),
            CiscoVPNConnectStep(label: "exit", input: "exit", delayAfter: 0.0)
        ]

        redactedPreview = [
            steps[0].input,
            Self.redactedGroupPreview(for: profile.group, fallbackInput: steps[1].input),
            "<username>",
            "<password>",
            "<mfa>",
            "y",
            "exit"
        ].joined(separator: "\n")
    }

    private static func connectAddress(for profile: VPNProfile) -> String {
        let port = profile.port.trimmingCharacters(in: .whitespacesAndNewlines)
        if port.isEmpty || port == "443" {
            return profile.server
        }
        return "\(profile.server):\(port)"
    }

    private static func redactedGroupPreview(for group: String, fallbackInput: String) -> String {
        let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "-Default-" {
            return "<default group: press Enter>"
        }
        return fallbackInput
    }
}

public struct CiscoVPNConnectStep: Equatable, Sendable {
    public let label: String
    public let input: String
    public let delayAfter: TimeInterval
    public let requestedGroup: String?
    public let mfaStrategy: MFAInjectionStrategy?

    public init(
        label: String,
        input: String,
        delayAfter: TimeInterval,
        requestedGroup: String? = nil,
        mfaStrategy: MFAInjectionStrategy? = nil
    ) {
        self.label = label
        self.input = input
        self.delayAfter = delayAfter
        self.requestedGroup = requestedGroup
        self.mfaStrategy = mfaStrategy
    }
}
