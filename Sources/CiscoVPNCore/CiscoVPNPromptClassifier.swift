import Foundation

public struct PromptTrace: Equatable, Sendable {
    public var sawMFAChallenge: Bool
    public var sentMFA: Bool
    public var waitingForDuo: Bool
    public var connected: Bool
    public var loginFailed: Bool
    public var noMFAChallenge: Bool
    public var serviceUnavailable: Bool
    public var networkUnreachable: Bool
    public var timedOut: Bool

    public init(
        sawMFAChallenge: Bool = false,
        sentMFA: Bool = false,
        waitingForDuo: Bool = false,
        connected: Bool = false,
        loginFailed: Bool = false,
        noMFAChallenge: Bool = false,
        serviceUnavailable: Bool = false,
        networkUnreachable: Bool = false,
        timedOut: Bool = false
    ) {
        self.sawMFAChallenge = sawMFAChallenge
        self.sentMFA = sentMFA
        self.waitingForDuo = waitingForDuo
        self.connected = connected
        self.loginFailed = loginFailed
        self.noMFAChallenge = noMFAChallenge
        self.serviceUnavailable = serviceUnavailable
        self.networkUnreachable = networkUnreachable
        self.timedOut = timedOut
    }
}

public enum CiscoVPNPromptClassifier {
    public static func trace(output: String, timedOut: Bool = false) -> PromptTrace {
        let normalized = output
            .replacingOccurrences(of: "\r", with: "\n")
            .lowercased()
        let ciscoOutputOnly = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("[autoconnect]") }
            .joined(separator: "\n")

        var trace = PromptTrace(timedOut: timedOut)
        trace.connected = contains(
            normalized,
            #"(?i)(connection state:\s*connected|state:\s*connected|client address \(ipv4\):\s*(?!not available)|connected to)"#
        )
        trace.loginFailed = contains(
            normalized,
            #"(?i)(login failed|authentication failed|failed login|invalid username|invalid password|access denied|invalid credentials|login denied)"#
        )
        trace.serviceUnavailable = contains(
            normalized,
            #"(?i)(vpn service is unavailable|vpnagentd.*not.*running|service unavailable|connect capability is unavailable|another cisco secure client application acquired it)"#
        )
        trace.networkUnreachable = contains(
            normalized,
            #"(?i)(could not connect|network is unreachable|no route to host|timed out connecting|connection refused|server unreachable)"#
        )
        trace.noMFAChallenge = normalized.contains("no duo challenge detected")

        trace.sawMFAChallenge = contains(
            ciscoOutputOnly,
            #"(?i)(duo push|push to|phone call|sms|second password|secondary password|duo passcode|passcode|mfa option|factor|answer:)"#
        ) || normalized.contains("detected mfa mode: numeric-menu")
            || normalized.contains("detected mfa mode: second-password")
            || normalized.contains("detected mfa mode: auto-push")

        trace.sentMFA = normalized.contains("selected factor:")
            || normalized.contains("second=<<mfa>>")
            || normalized.contains("second=<push")
            || normalized.contains("mfa=<")

        trace.waitingForDuo = contains(
            ciscoOutputOnly,
            #"(?i)(push.*sent|sent.*push|approve.*duo|waiting.*duo|waiting for approval|check.*phone|login request)"#
        ) || normalized.contains("detected mfa mode: auto-push")

        return trace
    }

    private static func contains(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
