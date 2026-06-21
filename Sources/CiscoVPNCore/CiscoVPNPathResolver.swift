import Foundation

public struct CiscoVPNPathResolver: Sendable {
    private let environment: [String: String]
    private let isExecutable: @Sendable (String) -> Bool

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.environment = environment
        self.isExecutable = isExecutable
    }

    public func resolve() -> URL? {
        if let override = environment["CISCO_VPN_BIN"], isExecutable(override) {
            return URL(fileURLWithPath: override)
        }

        for candidate in Self.defaultCandidates where isExecutable(candidate) {
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    public static let defaultCandidates: [String] = [
        "/opt/cisco/secureclient/bin/vpn",
        "/opt/cisco/anyconnect/bin/vpn"
    ]
}
