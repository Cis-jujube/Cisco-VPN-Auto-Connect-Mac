import Foundation
import CiscoVPNCore

struct SelfTestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw SelfTestFailure(description: message)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw SelfTestFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

func expectThrows(_ message: String, _ body: () throws -> Void, matches: (Error) -> Bool) throws {
    do {
        try body()
    } catch {
        try expect(matches(error), message)
        return
    }
    throw SelfTestFailure(description: "\(message): expected throw")
}

func run(_ name: String, _ test: () throws -> Void) throws {
    do {
        try test()
        print("[PASS] \(name)")
    } catch {
        throw SelfTestFailure(description: "\(name): \(error)")
    }
}

final class RecordingOrder: @unchecked Sendable {
    var events: [String] = []
}

final class RecordingRunner: VPNCommandRunning, @unchecked Sendable {
    let order: RecordingOrder

    init(order: RecordingOrder) {
        self.order = order
    }

    func run(binary: URL, commands: [String], timeout: TimeInterval, redactedPreview: String) throws -> VPNCommandResult {
        order.events.append("run")
        return VPNCommandResult(exitCode: 0, output: "Connection State: Connected")
    }

    func runStaged(binary: URL, steps: [CiscoVPNConnectStep], timeout: TimeInterval, redactedPreview: String) throws -> VPNCommandResult {
        order.events.append("run")
        return VPNCommandResult(exitCode: 0, output: "Connection State: Connected")
    }
}

final class RecordingBlockerStopper: CiscoVPNClientBlockerStopping, @unchecked Sendable {
    let order: RecordingOrder

    init(order: RecordingOrder) {
        self.order = order
    }

    func stopBlockers() {
        order.events.append("stop")
    }
}

final class MemoryCredentialStore: VPNCredentialStore {
    var secrets: [String: SavedVPNSecret] = [:]

    func loadSecret(profileID: String) throws -> SavedVPNSecret? {
        secrets[profileID]
    }

    func saveSecret(_ secret: SavedVPNSecret, profileID: String) throws {
        secrets[profileID] = secret
    }

    func deleteSecret(profileID: String) throws {
        secrets.removeValue(forKey: profileID)
    }
}

try run("path resolver prefers existing environment override") {
    let existing = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-vpn-\(UUID().uuidString)")
    FileManager.default.createFile(atPath: existing.path, contents: Data())

    let resolver = CiscoVPNPathResolver(
        environment: ["CISCO_VPN_BIN": existing.path],
        isExecutable: { $0 == existing.path }
    )

    try expectEqual(resolver.resolve(), existing, "environment override should win")
}

try run("path resolver ignores non-executable files") {
    let resolver = CiscoVPNPathResolver(
        environment: ["CISCO_VPN_BIN": "/tmp/not-executable-vpn"],
        isExecutable: { _ in false }
    )

    try expectEqual(resolver.resolve(), nil, "non-executable override should be ignored")
}

try run("path resolver falls back to secureclient binary") {
    let resolver = CiscoVPNPathResolver(
        environment: [:],
        isExecutable: { $0 == "/opt/cisco/secureclient/bin/vpn" }
    )

    try expectEqual(resolver.resolve()?.path, "/opt/cisco/secureclient/bin/vpn", "secureclient fallback")
}

try run("old profile JSON decodes with auto MFA strategy") {
    let json = """
    {
      "id": "dku",
      "displayName": "DKU VPN",
      "server": "portal.dukekunshan.edu.cn",
      "group": "-Default-",
      "port": "443",
      "vpnProtocol": "ssl",
      "duoMethod": "push",
      "pushTarget": ""
    }
    """

    let profile = try JSONDecoder().decode(VPNProfile.self, from: Data(json.utf8))

    try expectEqual(profile.mfaStrategy, .auto, "legacy profiles should default to auto strategy")
}

try run("redactor removes saved credentials and generated MFA tokens") {
    let redactor = CiscoVPNRedactor(
        username: "netid",
        password: "secret-pw",
        mfaToken: "654321",
        totpSecret: "ABCDEFGHIJKLMNOP"
    )
    let output = redactor.redact("netid secret-pw 654321 ABCDEFGHIJKLMNOP")

    try expectEqual(output, "<username> <password> <mfa> <totp-secret>", "all known secrets should be redacted")
    try expect(!output.contains("secret-pw"), "password must not leak")
    try expect(!output.contains("654321"), "MFA token must not leak")
}

try run("stats parser reads mac Cisco stats output") {
    let output = """
    [ Connection Information ]

        Connection State:            Connected
        Duration:                    00:48:09

    [ Address Information ]

        Client Address (IPv4):       10.200.112.180
        Server Address:              portal.dukekunshan.edu.cn
    """

    let status = CiscoVPNStatsParser.parse(output)

    try expectEqual(status.state, .connected, "state")
    try expectEqual(status.server, "portal.dukekunshan.edu.cn", "server")
    try expectEqual(status.clientIPv4, "10.200.112.180", "client IPv4")
    try expectEqual(status.duration, "00:48:09", "duration")
}

try run("stats parser treats unavailable server as disconnected") {
    let output = """
    Connection State:            Disconnected
    Duration:                    00:00:00
    Client Address (IPv4):       Not Available
    Server Address:              Not Available
    """

    let status = CiscoVPNStatsParser.parse(output)

    try expectEqual(status.state, .disconnected, "state")
    try expect(status.server == nil, "server should be nil")
    try expect(status.clientIPv4 == nil, "client IP should be nil")
}

try run("preset group resolver matches Windows fallbacks") {
    try expectEqual(CiscoVPNGroupResolver.groupInput(for: "-Default-"), "", "default group")
    try expectEqual(CiscoVPNGroupResolver.groupInput(for: "Library Resources Only"), "1", "library group")
    try expectEqual(CiscoVPNGroupResolver.groupInput(for: "INTL-DUKE"), "2", "Duke INTL group")
    try expectEqual(CiscoVPNGroupResolver.groupInput(for: "0"), "0", "explicit default menu number")
    try expectEqual(CiscoVPNGroupResolver.groupInput(for: "3"), "3", "numeric group")
}

try run("group resolver parses live Cisco group menu like Windows script") {
    let menu = """
    Please enter your username and password.
        0) -Default-
        1) Library Resources Only
    Group: [-Default-]
    """

    try expectEqual(CiscoVPNGroupResolver.groupInput(for: "Library Resources Only", menuText: menu), "1", "live library group")
    try expectEqual(CiscoVPNGroupResolver.groupInput(for: "-Default-", menuText: menu), "", "live default group")
    try expectEqual(CiscoVPNGroupResolver.groupInput(for: "0", menuText: menu), "0", "live explicit default menu number")
}

try run("group resolver rejects missing configured group when live menu is known") {
    let menu = """
    0) -Default-
    1) Library Resources Only
    """

    try expectThrows("missing live group should be rejected") {
        _ = try CiscoVPNGroupResolver.groupInput(for: "INTL-DUKE", menuText: menu)
    } matches: { error in
        guard case let CiscoVPNError.groupNotFound(saved, available) = error else {
            return false
        }
        return saved == "INTL-DUKE" && available == ["-Default-", "Library Resources Only"]
    }
}

try run("DKU and Duke presets default to DUO push") {
    try expectEqual(VPNProfile.dkuDefault.duoMethod, .push, "DKU should default to push")
    try expectEqual(VPNProfile.dukeDefault.duoMethod, .push, "Duke should default to push")
    try expectEqual(VPNProfile.dkuDefault.pushTarget, "", "DKU push target should be optional")
}

try run("saved secret trims username but preserves password") {
    let secret = SavedVPNSecret(username: "  netid\n", password: " secret-pw ", totpSecret: " ABCD ")

    try expectEqual(secret.username, "netid", "username should be normalized")
    try expectEqual(secret.password, " secret-pw ", "password must be preserved exactly")
    try expectEqual(secret.totpSecret, "ABCD", "TOTP secret should be normalized")
}

try run("saved secret diagnostics identify non-ASCII password without revealing it") {
    let secret = SavedVPNSecret(username: "netid", password: "abc123！", totpSecret: "")
    let diagnostics = secret.diagnostics

    try expectEqual(diagnostics.usernameCharacterCount, 5, "username length")
    try expectEqual(diagnostics.passwordCharacterCount, 7, "password length")
    try expect(!diagnostics.passwordIsASCIIPrintable, "non-ASCII punctuation should be detected")
    try expect(!diagnostics.passwordHasLeadingOrTrailingWhitespace, "no edge whitespace")
    try expect(!diagnostics.passwordContainsNewline, "no newline")
    try expect(!diagnostics.summary.contains("abc123"), "summary must not reveal password content")
}

try run("saved secret diagnostics preserve password whitespace signal") {
    let secret = SavedVPNSecret(username: "netid", password: " secret-pw ", totpSecret: "")
    let diagnostics = secret.diagnostics

    try expect(diagnostics.passwordIsASCIIPrintable, "ASCII password with spaces is still printable ASCII")
    try expect(diagnostics.passwordHasLeadingOrTrailingWhitespace, "edge whitespace should be visible as metadata")
    try expect(diagnostics.summary.contains("passwordEdgeWhitespace=yes"), "summary should include edge whitespace metadata")
}

try run("connect script uses resolved inputs and redacts secrets in preview") {
    let profile = VPNProfile(
        id: "dku",
        displayName: "DKU VPN",
        server: "portal.dukekunshan.edu.cn",
        group: "-Default-",
        port: "443",
        vpnProtocol: "ssl",
        duoMethod: .passcode,
        pushTarget: ""
    )
    let secret = VPNSecret(username: "netid", password: "correct-horse", totpCode: "123456")

    let script = CiscoVPNConnectScript(profile: profile, secret: secret)

    try expectEqual(script.commands, [
        "connect portal.dukekunshan.edu.cn",
        "",
        "netid",
        "correct-horse",
        "123456",
        "y",
        "exit"
    ], "command sequence")
    try expect(!script.redactedPreview.contains("netid"), "preview must hide username")
    try expect(!script.redactedPreview.contains("correct-horse"), "preview must hide password")
    try expect(!script.redactedPreview.contains("123456"), "preview must hide mfa")
    try expect(script.redactedPreview.contains("<username>"), "preview should show username placeholder")
    try expect(script.redactedPreview.contains("<password>"), "preview should show password placeholder")
    try expect(script.redactedPreview.contains("<mfa>"), "preview should show mfa placeholder")
    try expect(script.redactedPreview.contains("<default group: press Enter>"), "preview should show default group behavior")
}

try run("connect script exposes staged steps with delays and redaction") {
    let profile = VPNProfile(
        id: "dku",
        displayName: "DKU VPN",
        server: "portal.dukekunshan.edu.cn",
        group: "-Default-",
        port: "443",
        vpnProtocol: "ssl",
        duoMethod: .push,
        pushTarget: ""
    )
    let secret = VPNSecret(username: "netid", password: "correct-horse", totpCode: nil)

    let script = CiscoVPNConnectScript(profile: profile, secret: secret)

    try expectEqual(script.steps.map(\.label), ["connect", "group", "username", "password", "duo", "accept", "exit"], "step labels")
    try expectEqual(script.steps.map(\.input), [
        "connect portal.dukekunshan.edu.cn",
        "",
        "netid",
        "correct-horse",
        "1",
        "y",
        "exit"
    ], "step inputs")
    try expect((script.steps.first { $0.label == "group" }?.delayAfter ?? 0) >= 1.0, "group step should wait for Cisco prompt")
    try expect((script.steps.first { $0.label == "duo" }?.delayAfter ?? 0) >= 45.0, "push step should leave time for phone approval")
    try expect(!script.redactedPreview.contains("netid"), "preview must hide username")
    try expect(!script.redactedPreview.contains("correct-horse"), "preview must hide password")
    try expect(script.redactedPreview.contains("<username>"), "preview should show username placeholder")
    try expect(script.redactedPreview.contains("<password>"), "preview should show password placeholder")
}

try run("connect script includes non-default port for custom profiles") {
    let profile = VPNProfile(
        id: "company",
        displayName: "Company",
        server: "vpn.company.example",
        group: "2",
        port: "8443",
        vpnProtocol: "ssl",
        duoMethod: .push,
        pushTarget: "2"
    )
    let secret = VPNSecret(username: "jsmith", password: "pw", totpCode: nil)

    let script = CiscoVPNConnectScript(profile: profile, secret: secret)

    try expectEqual(script.commands[0], "connect vpn.company.example:8443", "connect address")
    try expectEqual(script.commands[4], "2", "push target")
}

try run("staged runner resolves group from live Cisco menu") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-menu-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fakeCLI = root.appending(path: "vpn")
    let script = """
    #!/bin/sh
    printf 'VPN> '
    IFS= read -r connect
    printf '\\nPlease enter your username and password.\\n'
    printf '    0) -Default-\\n'
    printf '    7) Library Resources Only\\n'
    printf 'Group: [-Default-] '
    IFS= read -r group
    printf '\\nselected group: %s\\n' "$group"
    exit 0
    """
    try script.write(to: fakeCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)
    let profile = VPNProfile(
        id: "dku",
        displayName: "DKU VPN",
        server: "portal.dukekunshan.edu.cn",
        group: "Library Resources Only",
        port: "443",
        vpnProtocol: "ssl",
        duoMethod: .push,
        pushTarget: ""
    )
    let connectScript = CiscoVPNConnectScript(
        profile: profile,
        secret: VPNSecret(username: "netid", password: "pw", totpCode: nil)
    )

    let result = try ProcessVPNCommandRunner().runStaged(
        binary: fakeCLI,
        steps: Array(connectScript.steps.prefix(2)),
        timeout: 5,
        redactedPreview: connectScript.redactedPreview
    )

    try expect(result.output.contains("selected group: 7"), "runner should send live group number")
}

try run("default client uses terminal-style interaction for Cisco prompts") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-terminal-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fakeCLI = root.appending(path: "vpn")
    let script = """
    #!/bin/sh
    printf 'VPN> '
    IFS= read -r connect
    printf '\\nPlease enter your username and password.\\n'
    printf 'Group: [-Default-] '
    IFS= read -r group
    printf '\\nselected group: <%s>\\n' "$group"
    printf 'Username: '
    IFS= read -r username
    printf '\\nusername=<%s>\\n' "$username"
    printf '\\nPassword: '
    IFS= read -r password
    printf '\\nAnswer: '
    IFS= read -r mfa
    printf '\\nMFA=<%s>\\n' "$mfa"
    printf 'Connection State: Connected\\n'
    exit 0
    """
    try script.write(to: fakeCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)
    let client = CiscoVPNClient(
        pathResolver: CiscoVPNPathResolver(
            environment: ["CISCO_VPN_BIN": fakeCLI.path],
            isExecutable: { $0 == fakeCLI.path }
        ),
        blockerStopper: RecordingBlockerStopper(order: RecordingOrder())
    )

    let result = try client.connect(
        profile: .dkuDefault,
        savedSecret: SavedVPNSecret(username: "netid", password: "secret-pw", totpSecret: "")
    )

    try expect(
        result.output.contains("selected group: <>"),
        "default group should submit an empty reply to accept Cisco's default. Output: \(result.output)"
    )
    try expect(
        result.output.contains("username=<<username>>"),
        "username without Cisco prompt default should be sent explicitly. Output: \(result.output)"
    )
    try expect(result.output.contains("<password>"), "terminal transcript should label redacted password")
    try expect(result.output.contains("MFA=<1>"), "DUO Push should send option 1")
    try expect(!result.output.contains("netid"), "terminal transcript must redact echoed username")
    try expect(!result.output.contains("secret-pw"), "terminal transcript must redact echoed password")
}

try run("terminal interaction sends explicit username even when Cisco shows a default") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-terminal-username-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fakeCLI = root.appending(path: "vpn")
    let script = """
    #!/bin/sh
    printf 'VPN> '
    IFS= read -r connect
    printf '\\nPlease enter your username and password.\\n'
    printf 'Group: [-Default-] '
    IFS= read -r group
    printf '\\nUsername: [netid] '
    IFS= read -r username
    printf '\\nusername=<%s>\\n' "$username"
    printf 'Password: '
    IFS= read -r password
    printf '\\nAnswer: '
    IFS= read -r mfa
    printf '\\nMFA=<%s>\\n' "$mfa"
    printf 'Connection State: Connected\\n'
    exit 0
    """
    try script.write(to: fakeCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)
    let client = CiscoVPNClient(
        pathResolver: CiscoVPNPathResolver(
            environment: ["CISCO_VPN_BIN": fakeCLI.path],
            isExecutable: { $0 == fakeCLI.path }
        ),
        blockerStopper: RecordingBlockerStopper(order: RecordingOrder())
    )

    let result = try client.connect(
        profile: .dkuDefault,
        savedSecret: SavedVPNSecret(username: "netid", password: "secret-pw", totpSecret: "")
    )

    try expect(
        result.output.contains("username=<<username>>"),
        "Cisco username default should be overridden with the saved username. Output: \(result.output)"
    )
    try expect(result.output.contains("<password>"), "terminal transcript should label redacted password")
    try expect(result.output.contains("MFA=<1>"), "DUO Push should still send option 1")
}

try run("terminal interaction redacts echoed non-ASCII passwords") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-terminal-nonascii-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fakeCLI = root.appending(path: "vpn")
    let script = """
    #!/bin/sh
    printf 'VPN> '
    IFS= read -r connect
    printf '\\nGroup: [-Default-] '
    IFS= read -r group
    printf '\\nselected group: <%s>\\n' "$group"
    printf 'Username: '
    IFS= read -r username
    printf '\\nPassword: '
    IFS= read -r password
    printf '\\npassword=<%s>\\n' "$password"
    printf 'Connection State: Connected\\n'
    exit 0
    """
    try script.write(to: fakeCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)
    let client = CiscoVPNClient(
        pathResolver: CiscoVPNPathResolver(
            environment: ["CISCO_VPN_BIN": fakeCLI.path],
            isExecutable: { $0 == fakeCLI.path }
        ),
        blockerStopper: RecordingBlockerStopper(order: RecordingOrder())
    )

    let result = try client.connect(
        profile: .dkuDefault,
        savedSecret: SavedVPNSecret(username: "netid", password: "abc123！", totpSecret: "")
    )

    try expect(
        result.output.contains("selected group: <>"),
        "default group should still accept Cisco's default. Output: \(result.output)"
    )
    try expect(result.output.contains("password=<<password>>"), "echoed non-ASCII password should be redacted")
    try expect(!result.output.contains("abc123！"), "non-ASCII password must not leak in transcript")
}

try run("terminal interaction does not report expect stack when Cisco exits early") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-terminal-early-exit-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fakeCLI = root.appending(path: "vpn")
    let script = """
    #!/bin/sh
    printf 'VPN> '
    IFS= read -r connect
    printf '\\nGroup: [-Default-] '
    IFS= read -r group
    printf '\\nUsername: [netid] '
    IFS= read -r username
    printf '\\nPassword: '
    IFS= read -r password
    printf '\\n  >> Login failed.\\n'
    exit 1
    """
    try script.write(to: fakeCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)
    let client = CiscoVPNClient(
        pathResolver: CiscoVPNPathResolver(
            environment: ["CISCO_VPN_BIN": fakeCLI.path],
            isExecutable: { $0 == fakeCLI.path }
        ),
        blockerStopper: RecordingBlockerStopper(order: RecordingOrder())
    )

    let result = try client.connect(
        profile: .dkuDefault,
        savedSecret: SavedVPNSecret(username: "netid", password: "secret-pw", totpSecret: "")
    )

    try expect(result.output.contains("Login failed"), "early Cisco failure should still be captured")
    try expect(!result.output.contains("spawn id"), "closed spawn should not leak expect stack")
    try expect(!result.output.contains("while executing"), "closed spawn should not leak Tcl stack")
}

try run("terminal interaction resolves non-default group from live Cisco menu") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-terminal-menu-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fakeCLI = root.appending(path: "vpn")
    let script = """
    #!/bin/sh
    printf 'VPN> '
    IFS= read -r connect
    printf '\\nPlease enter your username and password.\\n'
    printf '    0) -Default-\\n'
    printf '    7) Library Resources Only\\n'
    printf 'Group: [-Default-] '
    IFS= read -r group
    printf '\\nselected group: <%s>\\n' "$group"
    printf 'Username: '
    IFS= read -r username
    printf '\\nPassword: '
    IFS= read -r password
    printf '\\nAnswer: '
    IFS= read -r mfa
    printf '\\nMFA=<%s>\\n' "$mfa"
    printf 'Connection State: Connected\\n'
    exit 0
    """
    try script.write(to: fakeCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)
    let profile = VPNProfile(
        id: "dku",
        displayName: "DKU VPN",
        server: "portal.dukekunshan.edu.cn",
        group: "Library Resources Only",
        port: "443",
        vpnProtocol: "ssl",
        duoMethod: .push,
        pushTarget: ""
    )
    let client = CiscoVPNClient(
        pathResolver: CiscoVPNPathResolver(
            environment: ["CISCO_VPN_BIN": fakeCLI.path],
            isExecutable: { $0 == fakeCLI.path }
        ),
        blockerStopper: RecordingBlockerStopper(order: RecordingOrder())
    )

    let result = try client.connect(
        profile: profile,
        savedSecret: SavedVPNSecret(username: "netid", password: "secret-pw", totpSecret: "")
    )

    try expect(
        result.output.contains("selected group: <7>"),
        "terminal runner should send the live group number. Output: \(result.output)"
    )
}

try run("terminal interaction keeps sending credentials when MFA prompt is not observable") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-terminal-timed-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fakeCLI = root.appending(path: "vpn")
    let script = """
    #!/bin/sh
    printf 'VPN> '
    IFS= read -r connect
    printf '\\nPlease enter your username and password.\\n'
    printf '    0) -Default-\\n'
    printf 'Group: [-Default-] '
    IFS= read -r group
    printf '\\nUsername: '
    IFS= read -r username
    printf '\\nPassword: '
    IFS= read -r password
    printf '\\nselected group: <%s>\\n' "$group"
    printf 'username=<%s>\\n' "$username"
    printf 'password=<%s>\\n' "$password"
    printf 'Connection State: Connected\\n'
    exit 0
    """
    try script.write(to: fakeCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)
    let connectScript = CiscoVPNConnectScript(
        profile: .dkuDefault,
        secret: VPNSecret(username: "netid", password: "secret-pw", totpCode: nil)
    )

    let result = try ExpectVPNCommandRunner().runStaged(
        binary: fakeCLI,
        steps: connectScript.steps,
        timeout: 6,
        redactedPreview: connectScript.redactedPreview
    )

    try expect(
        result.output.contains("selected group: <>"),
        "default group should submit an empty reply to accept Cisco's default. Output: \(result.output)"
    )
    try expect(
        result.output.contains("username=<<username>>"),
        "username should be sent even when later prompts are not visible. Output: \(result.output)"
    )
    try expect(result.output.contains("password=<<password>>"), "password should be sent and redacted")
    try expect(
        result.output.contains("[autoconnect] waiting for username prompt"),
        "runner should wait for the username prompt before sending credentials. Output: \(result.output)"
    )
    try expect(
        result.output.contains("[autoconnect] waiting for password prompt"),
        "runner should wait for the password prompt before sending credentials. Output: \(result.output)"
    )
    try expect(!result.output.contains("MFA=<1>"), "DUO Push should not blindly send option 1 without a challenge")
}

try run("terminal interaction exits promptly after connected prompt") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-terminal-connected-prompt-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fakeCLI = root.appending(path: "vpn")
    let script = """
    #!/bin/sh
    printf 'VPN> '
    IFS= read -r connect
    printf '\\nGroup: [-Default-] '
    IFS= read -r group
    printf '\\nUsername: '
    IFS= read -r username
    printf '\\nPassword: '
    IFS= read -r password
    printf '\\nAnswer: '
    IFS= read -r mfa
    printf '\\nConnection State: Connected\\n'
    printf 'VPN> '
    IFS= read -r exit_command
    printf '\\nexit=<%s>\\n' "$exit_command"
    exit 0
    """
    try script.write(to: fakeCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)
    let connectScript = CiscoVPNConnectScript(
        profile: .dkuDefault,
        secret: VPNSecret(username: "netid", password: "secret-pw", totpCode: nil)
    )

    let result = try ExpectVPNCommandRunner().runStaged(
        binary: fakeCLI,
        steps: connectScript.steps,
        timeout: 6,
        redactedPreview: connectScript.redactedPreview
    )

    try expect(
        result.output.contains("exit=<exit>"),
        "runner should close the Cisco CLI promptly once connected. Output: \(result.output)"
    )
}

try run("adaptive MFA sends numeric menu option for Duo challenge menus") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-mfa-numeric-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fakeCLI = root.appending(path: "vpn")
    let script = """
    #!/bin/sh
    printf 'VPN> '
    IFS= read -r connect
    printf '\\nGroup: [-Default-] '
    IFS= read -r group
    printf '\\nUsername: '
    IFS= read -r username
    printf '\\nPassword: '
    IFS= read -r password
    printf '\\nIn the MFA option field, enter a passcode or the number of an option below:\\n'
    printf '1-Push to X-5434\\n'
    printf '2-Push to X-1111\\n'
    printf 'Answer: '
    IFS= read -r mfa
    printf '\\nMFA=<%s>\\n' "$mfa"
    printf 'Connection State: Connected\\n'
    exit 0
    """
    try script.write(to: fakeCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)
    let profile = VPNProfile(
        id: "dku",
        displayName: "DKU VPN",
        server: "portal.dukekunshan.edu.cn",
        group: "-Default-",
        port: "443",
        vpnProtocol: "ssl",
        duoMethod: .push,
        pushTarget: "2"
    )
    let connectScript = CiscoVPNConnectScript(
        profile: profile,
        secret: VPNSecret(username: "netid", password: "secret-pw", totpCode: nil)
    )

    let result = try ExpectVPNCommandRunner().runStaged(
        binary: fakeCLI,
        steps: connectScript.steps,
        timeout: 8,
        redactedPreview: connectScript.redactedPreview
    )

    try expect(result.output.contains("detected MFA mode: numeric-menu"), "numeric menu mode should be logged")
    try expect(result.output.contains("selected factor: 2"), "numeric factor should be logged")
    try expect(result.output.contains("MFA=<2>"), "numeric menu should receive configured option 2")
}

try run("adaptive MFA sends push token for second password prompts") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-mfa-second-password-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fakeCLI = root.appending(path: "vpn")
    let script = """
    #!/bin/sh
    printf 'VPN> '
    IFS= read -r connect
    printf '\\nGroup: [-Default-] '
    IFS= read -r group
    printf '\\nUsername: '
    IFS= read -r username
    printf '\\nPassword: '
    IFS= read -r password
    printf '\\nSecond Password: '
    IFS= read -r second
    printf '\\nsecond=<%s>\\n' "$second"
    printf 'Connection State: Connected\\n'
    exit 0
    """
    try script.write(to: fakeCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)
    let profile = VPNProfile(
        id: "dku",
        displayName: "DKU VPN",
        server: "portal.dukekunshan.edu.cn",
        group: "-Default-",
        port: "443",
        vpnProtocol: "ssl",
        duoMethod: .push,
        pushTarget: "2"
    )
    let connectScript = CiscoVPNConnectScript(
        profile: profile,
        secret: VPNSecret(username: "netid", password: "secret-pw", totpCode: nil)
    )

    let result = try ExpectVPNCommandRunner().runStaged(
        binary: fakeCLI,
        steps: connectScript.steps,
        timeout: 8,
        redactedPreview: connectScript.redactedPreview
    )

    try expect(result.output.contains("detected MFA mode: second-password"), "second password mode should be logged")
    try expect(result.output.contains("selected factor: push2"), "second phone should map to push2")
    try expect(result.output.contains("second=<push2>"), "second password prompt should receive push2")
}

try run("auto MFA does not append push token in the primary password field") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-mfa-auto-no-append-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fakeCLI = root.appending(path: "vpn")
    let script = """
    #!/bin/sh
    printf 'VPN> '
    IFS= read -r connect
    printf '\\nGroup: [-Default-] '
    IFS= read -r group
    printf '\\nUsername: '
    IFS= read -r username
    printf '\\nPassword (append ,push or ,push2 for Duo): '
    IFS= read -r password
    printf '\\npassword=<%s>\\n' "$password"
    printf 'Duo Push sent automatically. Waiting for approval...\\n'
    printf 'Connection State: Connected\\n'
    exit 0
    """
    try script.write(to: fakeCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)
    let profile = VPNProfile(
        id: "dku",
        displayName: "DKU VPN",
        server: "portal.dukekunshan.edu.cn",
        group: "-Default-",
        port: "443",
        vpnProtocol: "ssl",
        duoMethod: .push,
        mfaStrategy: .auto,
        pushTarget: "2"
    )
    let connectScript = CiscoVPNConnectScript(
        profile: profile,
        secret: VPNSecret(username: "netid", password: "secret-pw", totpCode: nil)
    )

    let result = try ExpectVPNCommandRunner().runStaged(
        binary: fakeCLI,
        steps: connectScript.steps,
        timeout: 8,
        redactedPreview: connectScript.redactedPreview
    )

    try expect(result.output.contains("password=<<password>>"), "auto strategy should send the real password only")
    try expect(!result.output.contains("password=<<password>,push2>"), "auto strategy must not append Duo factor into the primary password field")
}

try run("passwordAppend strategy appends push token in the primary password field") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-mfa-append-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fakeCLI = root.appending(path: "vpn")
    let script = """
    #!/bin/sh
    printf 'VPN> '
    IFS= read -r connect
    printf '\\nGroup: [-Default-] '
    IFS= read -r group
    printf '\\nUsername: '
    IFS= read -r username
    printf '\\nPassword: '
    IFS= read -r password
    printf '\\npassword=<%s>\\n' "$password"
    printf 'Connection State: Connected\\n'
    exit 0
    """
    try script.write(to: fakeCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)
    let profile = VPNProfile(
        id: "dku",
        displayName: "DKU VPN",
        server: "portal.dukekunshan.edu.cn",
        group: "-Default-",
        port: "443",
        vpnProtocol: "ssl",
        duoMethod: .push,
        mfaStrategy: .passwordAppend,
        pushTarget: "2"
    )
    let connectScript = CiscoVPNConnectScript(
        profile: profile,
        secret: VPNSecret(username: "netid", password: "secret-pw", totpCode: nil)
    )

    let result = try ExpectVPNCommandRunner().runStaged(
        binary: fakeCLI,
        steps: connectScript.steps,
        timeout: 8,
        redactedPreview: connectScript.redactedPreview
    )

    try expect(result.output.contains("password=<<password>,push2>"), "passwordAppend should receive password,push2")
    try expect(!result.output.contains("secret-pw"), "appended password must still be redacted")
}

try run("adaptive MFA does not send numeric option when Cisco starts auto push") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-mfa-auto-push-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fakeCLI = root.appending(path: "vpn")
    let script = """
    #!/bin/sh
    printf 'VPN> '
    IFS= read -r connect
    printf '\\nGroup: [-Default-] '
    IFS= read -r group
    printf '\\nUsername: '
    IFS= read -r username
    printf '\\nPassword: '
    IFS= read -r password
    printf '\\nDuo Push sent automatically. Waiting for approval...\\n'
    sleep 1
    printf 'Connection State: Connected\\n'
    printf 'VPN> '
    IFS= read -r next
    printf '\\nnext=<%s>\\n' "$next"
    exit 0
    """
    try script.write(to: fakeCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)
    let connectScript = CiscoVPNConnectScript(
        profile: .dkuDefault,
        secret: VPNSecret(username: "netid", password: "secret-pw", totpCode: nil)
    )

    let result = try ExpectVPNCommandRunner().runStaged(
        binary: fakeCLI,
        steps: connectScript.steps,
        timeout: 8,
        redactedPreview: connectScript.redactedPreview
    )

    try expect(result.output.contains("detected MFA mode: auto-push"), "auto push mode should be logged")
    try expect(result.output.contains("next=<exit>"), "runner should send exit next, not stray option 1. Output: \(result.output)")
    try expect(!result.output.contains("next=<1>"), "auto push must not receive a stray numeric option")
}

try run("waitOnly strategy never sends an explicit Duo factor after password") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-mfa-wait-only-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fakeCLI = root.appending(path: "vpn")
    let script = """
    #!/bin/sh
    printf 'VPN> '
    IFS= read -r connect
    printf '\\nGroup: [-Default-] '
    IFS= read -r group
    printf '\\nUsername: '
    IFS= read -r username
    printf '\\nPassword: '
    IFS= read -r password
    printf '\\nDuo Push sent automatically. Waiting for approval...\\n'
    sleep 1
    printf 'Connection State: Connected\\n'
    printf 'VPN> '
    IFS= read -r next
    printf '\\nnext=<%s>\\n' "$next"
    exit 0
    """
    try script.write(to: fakeCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)
    let profile = VPNProfile(
        id: "dku",
        displayName: "DKU VPN",
        server: "portal.dukekunshan.edu.cn",
        group: "-Default-",
        port: "443",
        vpnProtocol: "ssl",
        duoMethod: .push,
        mfaStrategy: .waitOnly,
        pushTarget: "2"
    )
    let connectScript = CiscoVPNConnectScript(
        profile: profile,
        secret: VPNSecret(username: "netid", password: "secret-pw", totpCode: nil)
    )

    let result = try ExpectVPNCommandRunner().runStaged(
        binary: fakeCLI,
        steps: connectScript.steps,
        timeout: 8,
        redactedPreview: connectScript.redactedPreview
    )

    try expect(result.output.contains("detected MFA mode: auto-push"), "waitOnly should still observe auto-push")
    try expect(result.output.contains("next=<exit>"), "waitOnly should send exit after connected state")
    try expect(!result.output.contains("next=<2>"), "waitOnly must not send numeric factor")
    try expect(!result.output.contains("push2"), "waitOnly must not send push factor")
}

try run("adaptive MFA sends TOTP code to second password prompt") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-mfa-totp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fakeCLI = root.appending(path: "vpn")
    let script = """
    #!/bin/sh
    printf 'VPN> '
    IFS= read -r connect
    printf '\\nGroup: [-Default-] '
    IFS= read -r group
    printf '\\nUsername: '
    IFS= read -r username
    printf '\\nPassword: '
    IFS= read -r password
    printf '\\nSecond Password: '
    IFS= read -r second
    printf '\\nsecond=<%s>\\n' "$second"
    printf 'Connection State: Connected\\n'
    exit 0
    """
    try script.write(to: fakeCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)
    let profile = VPNProfile(
        id: "dku",
        displayName: "DKU VPN",
        server: "portal.dukekunshan.edu.cn",
        group: "-Default-",
        port: "443",
        vpnProtocol: "ssl",
        duoMethod: .passcode,
        pushTarget: ""
    )
    let connectScript = CiscoVPNConnectScript(
        profile: profile,
        secret: VPNSecret(username: "netid", password: "secret-pw", totpCode: "654321")
    )

    let result = try ExpectVPNCommandRunner().runStaged(
        binary: fakeCLI,
        steps: connectScript.steps,
        timeout: 8,
        redactedPreview: connectScript.redactedPreview
    )

    try expect(result.output.contains("selected factor: <mfa>"), "TOTP factor should be redacted in diagnostics")
    try expect(result.output.contains("second=<<mfa>>"), "second password prompt should receive the TOTP code redacted")
    try expect(!result.output.contains("654321"), "TOTP code must be redacted from transcript")
}

try run("passcode mode without TOTP secret fails before running Cisco CLI") {
    let existing = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-vpn-\(UUID().uuidString)")
    FileManager.default.createFile(atPath: existing.path, contents: Data())
    let client = CiscoVPNClient(
        pathResolver: CiscoVPNPathResolver(
            environment: ["CISCO_VPN_BIN": existing.path],
            isExecutable: { $0 == existing.path }
        )
    )
    let profile = VPNProfile(
        id: "dku",
        displayName: "DKU VPN",
        server: "portal.dukekunshan.edu.cn",
        group: "-Default-",
        port: "443",
        vpnProtocol: "ssl",
        duoMethod: .passcode,
        pushTarget: ""
    )

    try expectThrows("missing TOTP should be rejected") {
        _ = try client.connect(
            profile: profile,
            savedSecret: SavedVPNSecret(username: "netid", password: "pw", totpSecret: "")
        )
    } matches: { error in
        error as? CiscoVPNError == .missingTOTPSecret
    }
}

try run("connect stops local Cisco blockers before running CLI") {
    let existing = FileManager.default.temporaryDirectory
        .appending(path: "fake-cisco-vpn-\(UUID().uuidString)")
    FileManager.default.createFile(atPath: existing.path, contents: Data())
    let order = RecordingOrder()
    let client = CiscoVPNClient(
        pathResolver: CiscoVPNPathResolver(
            environment: ["CISCO_VPN_BIN": existing.path],
            isExecutable: { $0 == existing.path }
        ),
        runner: RecordingRunner(order: order),
        blockerStopper: RecordingBlockerStopper(order: order)
    )
    let profile = VPNProfile(
        id: "dku",
        displayName: "DKU VPN",
        server: "portal.dukekunshan.edu.cn",
        group: "-Default-",
        port: "443",
        vpnProtocol: "ssl",
        duoMethod: .push,
        pushTarget: ""
    )

    _ = try client.connect(
        profile: profile,
        savedSecret: SavedVPNSecret(username: "netid", password: "pw", totpSecret: "")
    )

    try expectEqual(order.events, ["stop", "run"], "blocker cleanup order")
}

try run("result classifier separates pre-MFA login failure from connected state") {
    let failed = CiscoVPNResultClassifier.classify(
        output: """
        Please enter your username and password.
        Username: <masked>
        >> Login failed.
        Password:
        """,
        status: nil
    )
    try expectEqual(failed, .authFailedBeforeMFA, "login failed before MFA output")

    let connected = CiscoVPNResultClassifier.classify(
        output: "Connection State: Connected\nClient Address (IPv4): 10.0.0.2",
        status: nil
    )
    try expectEqual(connected, .connected, "connected output")

    let disconnected = CiscoVPNResultClassifier.classify(
        output: "VPN> state: Disconnected",
        status: VPNStatus(state: .disconnected, server: nil, clientIPv4: nil, duration: nil, remaining: nil)
    )
    try expectEqual(disconnected, .stillDisconnected, "post-connect disconnected status")
}

try run("result classifier does not treat stale connected prompt as final state") {
    let waiting = CiscoVPNResultClassifier.classify(
        output: """
        VPN> state: Connected
        [autoconnect] sending connect command
        Duo Push sent automatically. Waiting for approval...
        [autoconnect] detected MFA mode: auto-push; no additional factor input sent
        """,
        status: nil
    )
    try expectEqual(waiting, .duoPushSentWaiting, "stale connected prompt before Duo should not finish connection")

    let disconnected = CiscoVPNResultClassifier.classify(
        output: """
        VPN> state: Connected
        [autoconnect] sending connect command
        VPN> state: Disconnected
        """,
        status: nil
    )
    try expectEqual(disconnected, .stillDisconnected, "latest prompt state should win")
}

try run("result classifier detects post-MFA failures and Duo timeout") {
    let afterMFA = CiscoVPNResultClassifier.classify(
        output: """
        [autoconnect] detected MFA mode: second-password; selected factor: push
        Authentication failed
        """,
        status: nil
    )
    try expectEqual(afterMFA, .authFailedAfterMFA, "MFA prompt followed by auth failure")

    let appendCandidate = CiscoVPNResultClassifier.classify(
        output: """
        [autoconnect] sending saved password
        Login failed
        """,
        status: nil,
        strategy: .auto
    )
    try expectEqual(appendCandidate, .authFailedBeforeMFA, "plain pre-MFA login failure should not guess passwordAppend")

    let appendPrompt = CiscoVPNResultClassifier.classify(
        output: """
        Password (append ,push or ,push2 for Duo):
        [autoconnect] sending saved password
        Login failed
        """,
        status: nil,
        strategy: .auto
    )
    try expectEqual(appendPrompt, .possiblePasswordAppendRequired, "Cisco append-password prompt can suggest passwordAppend")

    let timeout = CiscoVPNResultClassifier.classify(
        output: """
        Duo Push sent automatically. Waiting for approval...
        [autoconnect] detected MFA mode: auto-push; no additional factor input sent
        """,
        status: nil,
        timedOut: true
    )
    try expectEqual(timeout, .duoTimeout, "Duo waiting followed by timeout")
}

try run("result classifier detects Cisco connect capability lock") {
    let locked = CiscoVPNResultClassifier.classify(
        output: """
        error: Connect capability is unavailable. Another Cisco Secure Client application acquired it.
        """,
        status: nil
    )

    try expectEqual(locked, .connectCapabilityUnavailable, "Cisco client lock output")
}

try run("result classifier ignores internal MFA trace without real Duo challenge") {
    let tracedOnly = CiscoVPNResultClassifier.classify(
        output: """
        [autoconnect] sending MFA response
        [autoconnect] no Duo challenge detected; waiting for auto-push or connection
        VPN> state: Disconnected
        """,
        status: nil
    )

    try expectEqual(tracedOnly, .noMFAChallenge, "internal trace should not be treated as Duo approval wait")
}

try run("doctor report contains only redacted credential diagnostics") {
    let credentialStore = MemoryCredentialStore()
    try credentialStore.saveSecret(
        SavedVPNSecret(username: "netid", password: "secret-pw！", totpSecret: "ABCDEFGHIJKLMNOP"),
        profileID: "dku"
    )
    let profile = VPNProfile(
        id: "dku",
        displayName: "DKU VPN",
        server: "portal.dukekunshan.edu.cn",
        group: "-Default-",
        port: "443",
        vpnProtocol: "ssl",
        duoMethod: .push,
        mfaStrategy: .auto,
        pushTarget: ""
    )
    let doctor = CiscoVPNDoctor(
        pathResolver: CiscoVPNPathResolver(environment: [:], isExecutable: { $0 == "/opt/cisco/secureclient/bin/vpn" }),
        credentialStore: credentialStore,
        isExecutable: { $0 == "/usr/bin/expect" || $0 == "/opt/cisco/secureclient/bin/vpn" },
        statsCheck: { _ in true },
        vpnAgentRunning: { true },
        networkCheck: { _, _ in .skipped },
        proxyCheck: {
            CiscoVPNDoctorCheck(
                id: "system-proxy",
                title: "System proxy",
                status: .skipped,
                detail: "test proxy skipped"
            )
        }
    )

    let report = doctor.run(profile: profile)
    let text = report.diagnosticText

    try expect(text.contains("Cisco binary"), "doctor should include Cisco binary status")
    try expect(text.contains("password chars=10"), "doctor should include password length only")
    try expect(text.contains("passwordASCII=no"), "doctor should include character diagnostics")
    try expect(text.contains("Reset saved credentials"), "doctor should include actionable reset guidance")
    try expect(text.contains("totp exists yes"), "doctor should include TOTP existence")
    try expect(!text.contains("netid"), "doctor must not reveal username")
    try expect(!text.contains("secret-pw"), "doctor must not reveal password")
    try expect(!text.contains("ABCDEFGHIJKLMNOP"), "doctor must not reveal TOTP secret")
}

try run("doctor detects DKU fixed proxy fallback") {
    let report = CiscoVPNDoctor.systemProxyCheck(from: """
    <dictionary> {
      HTTPEnable : 1
      HTTPPort : 3128
      HTTPProxy : proxy-dku.oit.duke.edu
      HTTPSEnable : 1
      HTTPSPort : 3128
      HTTPSProxy : proxy-dku.oit.duke.edu
      ProxyAutoConfigEnable : 1
      ProxyAutoConfigURLString : http://proxy-dku.oit.duke.edu/wpad.dat
    }
    """)

    try expectEqual(report.status, .warning, "fixed proxy-dku should warn")
    try expect(report.detail.contains("ProxySettings=IgnoreProxy"), "warning should include durable fix direction")
}

try run("reset credentials deletes secret while preserving profile metadata") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "vpn-profile-reset-\(UUID().uuidString)")
    let profileStore = FileProfileStore(rootDirectory: root)
    let credentialStore = MemoryCredentialStore()
    let profile = VPNProfile(
        id: "dku",
        displayName: "DKU VPN",
        server: "portal.dukekunshan.edu.cn",
        group: "-Default-",
        port: "443",
        vpnProtocol: "ssl",
        duoMethod: .push,
        mfaStrategy: .auto,
        pushTarget: ""
    )

    try profileStore.save(profile)
    try credentialStore.saveSecret(SavedVPNSecret(username: "netid", password: "secret-pw", totpSecret: "ABCDEFGHIJKLMNOP"), profileID: profile.id)
    try credentialStore.deleteSecret(profileID: profile.id)

    try expectEqual(try profileStore.loadProfiles(), [profile], "profile metadata should remain")
    try expectEqual(try credentialStore.loadSecret(profileID: profile.id), nil, "credential secret should be deleted")
}

try run("TOTP matches RFC 6238 vector") {
    let generator = TOTPGenerator()
    let secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    let code = try generator.code(secret: secret, unixTime: 59)

    try expectEqual(code, "287082", "TOTP code")
}

try run("TOTP importer extracts secret from otpauth URL") {
    let imported = try TOTPSecretImporter.secret(
        from: "otpauth://totp/DKU:netid?secret=abcd efgh ijkl mnop&issuer=DKU"
    )

    try expectEqual(imported, "ABCDEFGHIJKLMNOP", "imported secret")
}

try run("TOTP importer accepts raw Base32 secret") {
    let imported = try TOTPSecretImporter.secret(from: "abcd efgh ijkl mnop")

    try expectEqual(imported, "ABCDEFGHIJKLMNOP", "normalized raw secret")
}

try run("TOTP importer rejects Duo activation links") {
    try expectThrows("Duo activation link should not be treated as TOTP") {
        _ = try TOTPSecretImporter.secret(from: "duo://1234567890abcdef")
    } matches: { error in
        error as? TOTPSecretImportError == .unsupportedDuoActivationLink
    }
}

try run("TOTP setup enables passcode profile and preserves credentials") {
    let profile = VPNProfile.dkuDefault
    let savedSecret = SavedVPNSecret(username: "netid", password: "secret-pw", totpSecret: "")

    let configured = try TOTPPasscodeSetup.apply(
        input: "otpauth://totp/DKU:netid?secret=abcd efgh ijkl mnop&issuer=DKU",
        to: profile,
        savedSecret: savedSecret
    )

    try expectEqual(configured.profile.duoMethod, .passcode, "DUO method")
    try expectEqual(configured.profile.mfaStrategy, .passcode, "MFA strategy")
    try expectEqual(configured.secret.username, "netid", "username should be preserved")
    try expectEqual(configured.secret.password, "secret-pw", "password should be preserved")
    try expectEqual(configured.secret.totpSecret, "ABCDEFGHIJKLMNOP", "TOTP secret should be normalized")
}

try run("profile store persists profiles without secrets") {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "vpn-profile-store-\(UUID().uuidString)")
    let store = FileProfileStore(rootDirectory: root)
    let profile = VPNProfile(
        id: "dku",
        displayName: "DKU VPN",
        server: "portal.dukekunshan.edu.cn",
        group: "-Default-",
        port: "443",
        vpnProtocol: "ssl",
        duoMethod: .push,
        pushTarget: "1"
    )

    try store.save(profile)
    try store.setActiveProfileID(profile.id)

    let loaded = try store.loadProfiles()
    let raw = try String(contentsOf: store.profilesFile, encoding: .utf8)

    try expectEqual(loaded, [profile], "loaded profiles")
    try expectEqual(try store.loadActiveProfileID(), "dku", "active profile")
    try expect(!raw.localizedCaseInsensitiveContains("password"), "profiles JSON must not contain password")
    try expect(!raw.localizedCaseInsensitiveContains("totp"), "profiles JSON must not contain TOTP")
}

try run("profile store supports environment root override for isolated demos") {
    let key = "CISCO_VPN_PROFILE_ROOT"
    let previous = getenv(key).map { String(cString: $0) }
    let root = FileManager.default.temporaryDirectory
        .appending(path: "vpn-profile-env-\(UUID().uuidString)")
        .standardizedFileURL
    setenv(key, root.path, 1)
    defer {
        if let previous {
            setenv(key, previous, 1)
        } else {
            unsetenv(key)
        }
    }

    try expectEqual(
        FileProfileStore.defaultRootDirectory().path,
        root.path,
        "profile root should honor environment override"
    )
}

try run("profile subscription importer accepts metadata-only VPN profiles") {
    let payload = """
    {
      "name": "Campus VPNs",
      "profiles": [
        {
          "id": "dku-main",
          "displayName": "DKU Main",
          "server": "portal.dukekunshan.edu.cn",
          "group": "-Default-",
          "port": "443",
          "vpnProtocol": "ssl",
          "duoMethod": "push",
          "mfaStrategy": "auto",
          "pushTarget": ""
        },
        {
          "id": "duke-intl",
          "displayName": "Duke INTL",
          "server": "vpn.duke.edu",
          "group": "INTL-DUKE"
        }
      ]
    }
    """

    let imported = try VPNProfileSubscriptionImporter.importProfiles(from: Data(payload.utf8))

    try expectEqual(imported.sourceName, "Campus VPNs", "subscription name")
    try expectEqual(imported.profiles.count, 2, "profile count")
    try expectEqual(imported.profiles[0].id, "dku-main", "first profile ID")
    try expectEqual(imported.profiles[0].duoMethod, .push, "DUO Push should be supported")
    try expectEqual(imported.profiles[1].port, "443", "missing port should default")
    try expectEqual(imported.profiles[1].vpnProtocol, "ssl", "missing protocol should default")
    try expectEqual(imported.profiles[1].mfaStrategy, .auto, "missing strategy should default")
}

try run("profile subscription importer rejects secrets and credential-like keys") {
    let payload = """
    {
      "profiles": [
        {
          "id": "unsafe",
          "displayName": "Unsafe",
          "server": "vpn.example.edu",
          "password": "do-not-import"
        }
      ]
    }
    """

    try expectThrows("subscription must not carry credentials") {
        _ = try VPNProfileSubscriptionImporter.importProfiles(from: Data(payload.utf8))
    } matches: { error in
        guard case VPNProfileSubscriptionError.containsCredentialFields = error else {
            return false
        }
        return true
    }
}

try run("profile subscription importer validates safe subscription URLs") {
    try expect(
        VPNProfileSubscriptionURLPolicy.isAllowed(URL(string: "https://example.edu/vpn-profiles.json")!),
        "HTTPS subscription URL should be allowed"
    )
    try expect(
        VPNProfileSubscriptionURLPolicy.isAllowed(URL(string: "http://localhost:8080/vpn-profiles.json")!),
        "localhost HTTP should be allowed for development"
    )
    try expect(
        !VPNProfileSubscriptionURLPolicy.isAllowed(URL(string: "http://example.edu/vpn-profiles.json")!),
        "public HTTP subscription URL should be rejected"
    )
    try expect(
        !VPNProfileSubscriptionURLPolicy.isAllowed(URL(string: "file:///Users/me/profile.json")!),
        "file URL should be rejected by URL subscription import"
    )
}

try run("tutorial guide provides Chinese and English onboarding copy") {
    try expectEqual(AppLanguage.allCases.map(\.rawValue), ["zh-Hans", "en"], "language options")
    try expectEqual(AppLanguage.simplifiedChinese.displayName, "中文", "Chinese display name")
    try expectEqual(AppLanguage.english.displayName, "English", "English display name")

    let chinese = TutorialGuide.content(for: .simplifiedChinese)
    let english = TutorialGuide.content(for: .english)

    try expect(chinese.title.contains("教程"), "Chinese guide should have Chinese title")
    try expect(english.title.localizedCaseInsensitiveContains("guide"), "English guide should have English title")
    try expect(chinese.sections.count >= 3, "Chinese guide should include setup, connect, and safety sections")
    try expect(english.sections.count == chinese.sections.count, "Both languages should have matching section counts")
    try expect(chinese.sections.flatMap(\.items).contains { $0.contains("Keychain") }, "Chinese guide should mention Keychain")
    try expect(english.sections.flatMap(\.items).contains { $0.localizedCaseInsensitiveContains("Cisco Secure Client") }, "English guide should mention Cisco Secure Client")
}

print("[OK] CiscoVPNCoreSelfTests completed")
