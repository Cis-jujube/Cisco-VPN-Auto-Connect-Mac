import Foundation

public enum CiscoVPNDoctorCheckStatus: String, Equatable, Sendable {
    case pass
    case warning
    case fail
    case skipped

    public var title: String {
        switch self {
        case .pass: "pass"
        case .warning: "warning"
        case .fail: "fail"
        case .skipped: "skipped"
        }
    }
}

public struct CiscoVPNDoctorCheck: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var status: CiscoVPNDoctorCheckStatus
    public var detail: String

    public init(id: String, title: String, status: CiscoVPNDoctorCheckStatus, detail: String) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
    }
}

public struct CiscoVPNDoctorReport: Equatable, Sendable {
    public var checks: [CiscoVPNDoctorCheck]

    public init(checks: [CiscoVPNDoctorCheck]) {
        self.checks = checks
    }

    public var diagnosticText: String {
        checks
            .map { "\($0.title): \($0.status.title) - \($0.detail)" }
            .joined(separator: "\n")
    }
}

public struct CiscoVPNDoctor: @unchecked Sendable {
    private let pathResolver: CiscoVPNPathResolver
    private let credentialStore: VPNCredentialStore
    private let isExecutable: @Sendable (String) -> Bool
    private let statsCheck: @Sendable (URL) -> Bool
    private let vpnAgentRunning: @Sendable () -> Bool
    private let networkCheck: @Sendable (String, Int) -> CiscoVPNDoctorCheckStatus
    private let proxyCheck: @Sendable () -> CiscoVPNDoctorCheck

    public init(
        pathResolver: CiscoVPNPathResolver = CiscoVPNPathResolver(),
        credentialStore: VPNCredentialStore = KeychainCredentialStore(),
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        statsCheck: @escaping @Sendable (URL) -> Bool = CiscoVPNDoctor.defaultStatsCheck,
        vpnAgentRunning: @escaping @Sendable () -> Bool = CiscoVPNDoctor.defaultVPNAgentRunning,
        networkCheck: @escaping @Sendable (String, Int) -> CiscoVPNDoctorCheckStatus = { _, _ in .skipped },
        proxyCheck: @escaping @Sendable () -> CiscoVPNDoctorCheck = CiscoVPNDoctor.defaultSystemProxyCheck
    ) {
        self.pathResolver = pathResolver
        self.credentialStore = credentialStore
        self.isExecutable = isExecutable
        self.statsCheck = statsCheck
        self.vpnAgentRunning = vpnAgentRunning
        self.networkCheck = networkCheck
        self.proxyCheck = proxyCheck
    }

    public func run(profile: VPNProfile?) -> CiscoVPNDoctorReport {
        var checks: [CiscoVPNDoctorCheck] = []
        let binary = pathResolver.resolve()

        if let binary {
            checks.append(check(id: "cisco-binary", title: "Cisco binary", status: .pass, detail: "found \(binary.path)"))
            let statsOK = statsCheck(binary)
            checks.append(check(
                id: "cisco-stats",
                title: "Cisco status",
                status: statsOK ? .pass : .warning,
                detail: statsOK ? "vpn stats can run" : "vpn stats did not complete"
            ))
        } else {
            checks.append(check(id: "cisco-binary", title: "Cisco binary", status: .fail, detail: "missing executable Cisco VPN CLI"))
            checks.append(check(id: "cisco-stats", title: "Cisco status", status: .skipped, detail: "skipped because Cisco binary is missing"))
        }

        let agentRunning = vpnAgentRunning()
        checks.append(check(
            id: "vpnagentd",
            title: "Cisco service",
            status: agentRunning ? .pass : .warning,
            detail: agentRunning ? "vpnagentd running" : "vpnagentd not running"
        ))

        let expectAvailable = isExecutable("/usr/bin/expect")
        checks.append(check(
            id: "terminal-runner",
            title: "Terminal runner",
            status: expectAvailable ? .pass : .fail,
            detail: expectAvailable ? "/usr/bin/expect found" : "/usr/bin/expect missing"
        ))
        checks.append(proxyCheck())

        if let profile {
            checks.append(check(
                id: "profile",
                title: "Profile",
                status: profile.server.isEmpty ? .fail : .pass,
                detail: "active=\(profile.displayName); server=\(profile.server.isEmpty ? "(missing)" : profile.server); group=\(profile.group.isEmpty ? "(default)" : profile.group); duo=\(profile.duoMethod.rawValue); strategy=\(profile.mfaStrategy.rawValue)"
            ))

            let secret = (try? credentialStore.loadSecret(profileID: profile.id)) ?? nil
            let usernameExists = !(secret?.username.isEmpty ?? true)
            let passwordExists = !(secret?.password.isEmpty ?? true)
            let totpExists = !(secret?.totpSecret.isEmpty ?? true)
            checks.append(check(
                id: "keychain",
                title: "Keychain",
                status: usernameExists && passwordExists ? .pass : .warning,
                detail: "username exists \(usernameExists ? "yes" : "no"); password exists \(passwordExists ? "yes" : "no"); totp exists \(totpExists ? "yes" : "no")"
            ))

            if let secret, !secret.password.isEmpty {
                let diagnostics = secret.diagnostics
                let detail = [diagnostics.summary, diagnostics.actionGuidance]
                    .compactMap { $0 }
                    .joined(separator: "; ")
                checks.append(check(
                    id: "password-diagnostics",
                    title: "Password diagnostics",
                    status: diagnostics.passwordIsASCIIPrintable
                        && !diagnostics.passwordHasLeadingOrTrailingWhitespace
                        && !diagnostics.passwordContainsNewline
                        && !diagnostics.passwordContainsControlCharacters ? .pass : .warning,
                    detail: detail
                ))
            } else {
                checks.append(check(
                    id: "password-diagnostics",
                    title: "Password diagnostics",
                    status: .skipped,
                    detail: "password missing"
                ))
            }

            let port = Int(profile.port) ?? 443
            let networkStatus = profile.server.isEmpty ? CiscoVPNDoctorCheckStatus.skipped : networkCheck(profile.server, port)
            checks.append(check(
                id: "network",
                title: "Network",
                status: networkStatus,
                detail: networkStatus == .skipped ? "server:\(port) reachability skipped" : "\(profile.server):\(port) \(networkStatus.title)"
            ))
        } else {
            checks.append(check(id: "profile", title: "Profile", status: .warning, detail: "no active profile"))
            checks.append(check(id: "keychain", title: "Keychain", status: .skipped, detail: "no active profile"))
            checks.append(check(id: "password-diagnostics", title: "Password diagnostics", status: .skipped, detail: "no active profile"))
            checks.append(check(id: "network", title: "Network", status: .skipped, detail: "no active profile"))
        }

        return CiscoVPNDoctorReport(checks: checks)
    }

    private func check(id: String, title: String, status: CiscoVPNDoctorCheckStatus, detail: String) -> CiscoVPNDoctorCheck {
        CiscoVPNDoctorCheck(id: id, title: title, status: status, detail: detail)
    }

    public static func defaultStatsCheck(binary: URL) -> Bool {
        let runner = ProcessVPNCommandRunner()
        return (try? runner.run(
            binary: binary,
            commands: ["stats", "exit"],
            timeout: 8,
            redactedPreview: "stats\nexit"
        )) != nil
    }

    public static func defaultVPNAgentRunning() -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "vpnagentd"]
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public static func defaultSystemProxyCheck() -> CiscoVPNDoctorCheck {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        process.arguments = ["--proxy"]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return systemProxyCheck(from: text, exitCode: process.terminationStatus)
        } catch {
            return CiscoVPNDoctorCheck(
                id: "system-proxy",
                title: "System proxy",
                status: .skipped,
                detail: "scutil --proxy could not run"
            )
        }
    }

    public static func systemProxyCheck(from output: String, exitCode: Int32 = 0) -> CiscoVPNDoctorCheck {
        guard exitCode == 0 else {
            return CiscoVPNDoctorCheck(
                id: "system-proxy",
                title: "System proxy",
                status: .warning,
                detail: "scutil --proxy exited with code \(exitCode)"
            )
        }

        let hasDKUPAC = output.localizedCaseInsensitiveContains("proxy-dku.oit.duke.edu/wpad.dat")
        let fixedProxyPattern = #"(?im)^\s*HTTPS?Proxy\s*:\s*proxy-dku\.oit\.duke\.edu\s*$"#
        let hasFixedDKUProxy = output.range(of: fixedProxyPattern, options: [.regularExpression, .caseInsensitive]) != nil

        if hasFixedDKUProxy {
            return CiscoVPNDoctorCheck(
                id: "system-proxy",
                title: "System proxy",
                status: .warning,
                detail: hasDKUPAC
                    ? "fixed HTTP/HTTPS proxy is proxy-dku.oit.duke.edu:3128 while DKU PAC is active; this proxy can reject public HTTPS sites. Prefer PAC-only or a Cisco profile with ProxySettings=IgnoreProxy."
                    : "fixed HTTP/HTTPS proxy is proxy-dku.oit.duke.edu:3128; this proxy can reject public HTTPS sites."
            )
        }

        if hasDKUPAC {
            return CiscoVPNDoctorCheck(
                id: "system-proxy",
                title: "System proxy",
                status: .pass,
                detail: "DKU PAC is active without the blocked fixed proxy fallback"
            )
        }

        if output.localizedCaseInsensitiveContains("127.0.0.1") {
            return CiscoVPNDoctorCheck(
                id: "system-proxy",
                title: "System proxy",
                status: .pass,
                detail: "local proxy settings detected; no proxy-dku fixed proxy"
            )
        }

        return CiscoVPNDoctorCheck(
            id: "system-proxy",
            title: "System proxy",
            status: .skipped,
            detail: "no relevant system proxy issue detected"
        )
    }
}
