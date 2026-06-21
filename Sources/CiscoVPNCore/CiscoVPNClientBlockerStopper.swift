import Foundation

public protocol CiscoVPNClientBlockerStopping: Sendable {
    func stopBlockers()
}

public final class ProcessCiscoVPNClientBlockerStopper: CiscoVPNClientBlockerStopping, Sendable {
    public init() {}

    public func stopBlockers() {
        terminateExactProcess(named: "Cisco Secure Client")
        terminateExactProcess(named: "vpnui")
        terminateExactProcess(named: "csc_ui")
        terminateCommandLineMatches([
            "/opt/cisco/secureclient/bin/vpn -s",
            "/opt/cisco/anyconnect/bin/vpn -s"
        ])
        Thread.sleep(forTimeInterval: 0.4)
    }

    private func terminateExactProcess(named name: String) {
        run("/usr/bin/pkill", arguments: ["-x", name])
    }

    private func terminateCommandLineMatches(_ patterns: [String]) {
        for pattern in patterns {
            run("/usr/bin/pkill", arguments: ["-f", pattern])
        }
    }

    private func run(_ executable: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return
        }
    }
}
