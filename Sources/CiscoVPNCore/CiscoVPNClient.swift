import Darwin
import Foundation

public protocol VPNCommandRunning: Sendable {
    func run(binary: URL, commands: [String], timeout: TimeInterval, redactedPreview: String) throws -> VPNCommandResult
    func runStaged(binary: URL, steps: [CiscoVPNConnectStep], timeout: TimeInterval, redactedPreview: String) throws -> VPNCommandResult
}

public extension VPNCommandRunning {
    func runStaged(binary: URL, steps: [CiscoVPNConnectStep], timeout: TimeInterval, redactedPreview: String) throws -> VPNCommandResult {
        try run(
            binary: binary,
            commands: steps.map(\.input),
            timeout: timeout,
            redactedPreview: redactedPreview
        )
    }
}

public final class ProcessVPNCommandRunner: VPNCommandRunning, Sendable {
    public init() {}

    public func run(binary: URL, commands: [String], timeout: TimeInterval, redactedPreview: String = "") throws -> VPNCommandResult {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()

        process.executableURL = binary
        process.arguments = ["-s"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        try process.run()
        writeLines(commands, to: input.fileHandleForWriting)
        try? input.fileHandleForWriting.close()

        return try waitForResult(
            process: process,
            output: output,
            error: error,
            timeout: timeout,
            redactedPreview: redactedPreview
        )
    }

    public func runStaged(binary: URL, steps: [CiscoVPNConnectStep], timeout: TimeInterval, redactedPreview: String) throws -> VPNCommandResult {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        var capturedOutput = Data()

        process.executableURL = binary
        process.arguments = ["-s"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        try process.run()

        for step in steps {
            capturedOutput.append(readAvailableData(from: output))
            capturedOutput.append(readAvailableData(from: error))

            if !waitForPromptIfNeeded(
                before: step,
                process: process,
                output: output,
                error: error,
                capturedOutput: &capturedOutput
            ) {
                break
            }

            let inputLine: String
            if step.label == "group", let requestedGroup = step.requestedGroup {
                let menuText = String(data: capturedOutput, encoding: .utf8) ?? ""
                inputLine = try CiscoVPNGroupResolver.groupInput(for: requestedGroup, menuText: menuText)
            } else {
                inputLine = step.input
            }
            writeLines([inputLine], to: input.fileHandleForWriting)
            capturedOutput.append(readAvailableData(from: output))
            capturedOutput.append(readAvailableData(from: error))

            sleepAndCapture(
                step.delayAfter,
                process: process,
                output: output,
                error: error,
                capturedOutput: &capturedOutput
            )
            if !process.isRunning {
                break
            }
        }
        try? input.fileHandleForWriting.close()

        return try waitForResult(
            process: process,
            output: output,
            error: error,
            timeout: timeout,
            redactedPreview: redactedPreview,
            initialOutput: capturedOutput
        )
    }

    private func writeLines(_ lines: [String], to handle: FileHandle) {
        let payload = lines.joined(separator: "\n") + "\n"
        if let data = payload.data(using: .utf8) {
            handle.write(data)
        }
    }

    private func waitForResult(
        process: Process,
        output: Pipe,
        error: Pipe,
        timeout: TimeInterval,
        redactedPreview: String,
        initialOutput: Data = Data()
    ) throws -> VPNCommandResult {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.25)
            if process.isRunning {
                process.interrupt()
            }
            throw CiscoVPNError.commandTimedOut
        }

        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = error.fileHandleForReading.readDataToEndOfFile()
        let outputText = String(data: initialOutput + stdout + stderr, encoding: .utf8) ?? ""
        return VPNCommandResult(
            exitCode: process.terminationStatus,
            output: outputText,
            redactedInputPreview: redactedPreview
        )
    }

    private func sleepAndCapture(
        _ duration: TimeInterval,
        process: Process,
        output: Pipe,
        error: Pipe,
        capturedOutput: inout Data
    ) {
        guard duration > 0 else { return }
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            capturedOutput.append(readAvailableData(from: output))
            capturedOutput.append(readAvailableData(from: error))
            if !process.isRunning {
                return
            }
            Thread.sleep(forTimeInterval: min(0.1, max(0.01, deadline.timeIntervalSinceNow)))
        }
        capturedOutput.append(readAvailableData(from: output))
        capturedOutput.append(readAvailableData(from: error))
    }

    private func waitForPromptIfNeeded(
        before step: CiscoVPNConnectStep,
        process: Process,
        output: Pipe,
        error: Pipe,
        capturedOutput: inout Data
    ) -> Bool {
        let patterns: [String]
        let timeout: TimeInterval
        switch step.label {
        case "group":
            patterns = [#"(?i)group:"#]
            timeout = 8
        case "username":
            patterns = [#"(?i)username:"#]
            timeout = 8
        case "password":
            patterns = [#"(?i)password:"#]
            timeout = 8
        case "duo":
            patterns = [#"(?i)answer:"#, #"(?i)mfa option"#, #"(?i)push to"#, #"(?i)passcode"#, #"(?i)duo"#]
            timeout = 20
        default:
            return true
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            capturedOutput.append(readAvailableData(from: output))
            capturedOutput.append(readAvailableData(from: error))
            let text = String(data: capturedOutput, encoding: .utf8) ?? ""
            if isAuthenticationFailure(text) {
                return false
            }
            if patterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return true
    }

    private func isAuthenticationFailure(_ text: String) -> Bool {
        text.range(
            of: #"(?i)(login failed|authentication failed|login denied|access denied|invalid credentials|登录失败)"#,
            options: .regularExpression
        ) != nil
    }

    private func readAvailableData(from pipe: Pipe) -> Data {
        let handle = pipe.fileHandleForReading
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0 else { return Data() }
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        defer {
            _ = fcntl(descriptor, F_SETFL, flags)
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                continue
            }
            return data
        }
    }
}

public final class ExpectVPNCommandRunner: VPNCommandRunning, @unchecked Sendable {
    private let processRunner: ProcessVPNCommandRunner
    private let expectBinary: URL
    private let fileManager: FileManager

    public init(
        processRunner: ProcessVPNCommandRunner = ProcessVPNCommandRunner(),
        expectBinary: URL = URL(fileURLWithPath: "/usr/bin/expect"),
        fileManager: FileManager = .default
    ) {
        self.processRunner = processRunner
        self.expectBinary = expectBinary
        self.fileManager = fileManager
    }

    public func run(binary: URL, commands: [String], timeout: TimeInterval, redactedPreview: String = "") throws -> VPNCommandResult {
        try processRunner.run(
            binary: binary,
            commands: commands,
            timeout: timeout,
            redactedPreview: redactedPreview
        )
    }

    public func runStaged(binary: URL, steps: [CiscoVPNConnectStep], timeout: TimeInterval, redactedPreview: String) throws -> VPNCommandResult {
        guard fileManager.isExecutableFile(atPath: expectBinary.path) else {
            return try processRunner.runStaged(
                binary: binary,
                steps: steps,
                timeout: timeout,
                redactedPreview: redactedPreview
            )
        }

        let workDirectory = fileManager.temporaryDirectory
            .appending(path: "cisco-vpn-expect-\(UUID().uuidString)")
        let scriptURL = workDirectory.appending(path: "connect.exp")
        try fileManager.createDirectory(
            at: workDirectory,
            withIntermediateDirectories: false
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: workDirectory.path)
        defer {
            try? fileManager.removeItem(at: workDirectory)
        }

        try Self.expectScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        let output = Pipe()
        let error = Pipe()

        process.executableURL = expectBinary
        process.arguments = [scriptURL.path]
        process.standardOutput = output
        process.standardError = error
        process.environment = Self.environment(
            binary: binary,
            steps: steps,
            base: ProcessInfo.processInfo.environment
        )

        try process.run()
        let result = try waitForExpectResult(
            process: process,
            output: output,
            error: error,
            timeout: timeout,
            redactedPreview: redactedPreview
        )

        return VPNCommandResult(
            exitCode: result.exitCode,
            output: Self.redact(result.output, using: steps),
            redactedInputPreview: result.redactedInputPreview
        )
    }

    private func waitForExpectResult(
        process: Process,
        output: Pipe,
        error: Pipe,
        timeout: TimeInterval,
        redactedPreview: String
    ) throws -> VPNCommandResult {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.25)
            if process.isRunning {
                process.interrupt()
            }
            throw CiscoVPNError.commandTimedOut
        }

        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = error.fileHandleForReading.readDataToEndOfFile()
        let outputText = String(data: stdout + stderr, encoding: .utf8) ?? ""
        return VPNCommandResult(
            exitCode: process.terminationStatus,
            output: outputText,
            redactedInputPreview: redactedPreview
        )
    }

    private static func environment(
        binary: URL,
        steps: [CiscoVPNConnectStep],
        base: [String: String]
    ) -> [String: String] {
        var environment = base
        environment["CISCO_VPN_BINARY"] = binary.path
        environment["CISCO_VPN_CONNECT_INPUT"] = input(for: "connect", in: steps)
        environment["CISCO_VPN_GROUP_INPUT"] = input(for: "group", in: steps)
        environment["CISCO_VPN_GROUP_REQUESTED"] = steps.first { $0.label == "group" }?.requestedGroup ?? ""
        environment["CISCO_VPN_USERNAME_INPUT"] = input(for: "username", in: steps)
        environment["CISCO_VPN_PASSWORD_INPUT"] = input(for: "password", in: steps)
        environment["CISCO_VPN_DUO_INPUT"] = input(for: "duo", in: steps)
        environment["CISCO_VPN_MFA_STRATEGY"] = steps.first { $0.label == "duo" }?.mfaStrategy?.rawValue ?? MFAInjectionStrategy.auto.rawValue
        environment["CISCO_VPN_ACCEPT_INPUT"] = input(for: "accept", in: steps, default: "y")
        environment["CISCO_VPN_EXIT_INPUT"] = input(for: "exit", in: steps, default: "exit")
        return environment
    }

    private static func input(
        for label: String,
        in steps: [CiscoVPNConnectStep],
        default defaultValue: String = ""
    ) -> String {
        steps.first { $0.label == label }?.input ?? defaultValue
    }

    private static func redact(_ text: String, using steps: [CiscoVPNConnectStep]) -> String {
        CiscoVPNRedactor(
            username: input(for: "username", in: steps),
            password: input(for: "password", in: steps),
            mfaToken: input(for: "duo", in: steps)
        ).redact(text)
    }

    private static let expectScript = #"""
set timeout 10
log_user 1

proc env_value {key fallback} {
    global env
    if {[info exists env($key)]} {
        return $env($key)
    }
    return $fallback
}

proc send_line {value} {
    send -- "$value\r"
}

proc send_line_if_open {value} {
    if {[catch {send_line $value}]} {
        trace "Cisco CLI closed before the next input"
        return 0
    }
    return 1
}

proc trace {message} {
    puts "\n\[autoconnect\] $message"
}

proc normalize_group {value} {
    set lowered [string tolower [string trim $value]]
    regsub -all {[\t _-]+} $lowered "" compact
    return $compact
}

proc group_reply {fallback requested buffer} {
    set trimmed [string trim $requested]
    if {$trimmed eq "" || $trimmed eq "-Default-"} {
        return ""
    }
    if {[regexp {^[0-9]+$} $trimmed]} {
        return $trimmed
    }

    set requested_key [normalize_group $trimmed]
    foreach line [split $buffer "\n"] {
        set clean [string trim $line]
        if {[regexp {^([0-9]+)[ \t]*[).:-]?[ \t]*(.+)$} $clean -> number label]} {
            if {[normalize_group $label] eq $requested_key} {
                return $number
            }
        }
    }

    return $fallback
}

proc factor_is_passcode {value} {
    set trimmed [string trim $value]
    return [regexp {^[0-9]{6,8}$} $trimmed]
}

proc push_factor {duo_input} {
    set trimmed [string trim $duo_input]
    if {[factor_is_passcode $trimmed]} {
        return $trimmed
    }
    if {$trimmed eq "" || $trimmed eq "1"} {
        return "push"
    }
    if {[regexp {^[0-9]+$} $trimmed]} {
        return "push$trimmed"
    }
    return $trimmed
}

proc password_reply {password duo_input strategy} {
    if {$strategy eq "passwordAppend"} {
        return "$password,[push_factor $duo_input]"
    }
    return $password
}

proc prompt_summary {value} {
    regsub -all {[\r\n\t ]+} [string trim $value] " " compact
    if {[string length $compact] > 220} {
        return "[string range $compact 0 219]..."
    }
    return $compact
}

proc wait_for_initial_prompt {} {
    set timeout 8
    expect {
        -nocase -re {VPN>} {}
        timeout {}
        eof {}
    }
}

proc capture_group_menu {} {
    set timeout 2
    expect {
        -nocase -re {group:[^\r\n]*} { return $expect_out(buffer) }
        -nocase -re {login failed|authentication failed|access denied|invalid credentials} { return "" }
        timeout { return "" }
        eof { return "" }
    }
}

proc wait_for_username_prompt {} {
    set timeout 12
    expect {
        -nocase -re {(username|login)[^\r\n]*:} { return "username" }
        -nocase -re {password[^\r\n]*:} { return "password" }
        -nocase -re {login failed|authentication failed|access denied|invalid credentials} { return "auth-failed" }
        timeout { return "missing" }
        eof { return "eof" }
    }
}

proc wait_for_password_prompt {} {
    set timeout 12
    expect {
        -nocase -re {password[^\r\n]*:} { return "password" }
        -nocase -re {login failed|authentication failed|access denied|invalid credentials} { return "auth-failed" }
        timeout { return "missing" }
        eof { return "eof" }
    }
}

proc wait_for_mfa_or_result {} {
    set timeout 22
    expect {
        -nocase -re {login failed|authentication failed|access denied|invalid credentials|denied} {
            return [list auth-failed $expect_out(buffer)]
        }
        -nocase -re {connection state:[^\r\n]*connected|(^|[\r\n])[^\r\n]*connected[^\r\n]*} {
            return [list connected $expect_out(buffer)]
        }
        -nocase -re {mfa option field|answer:[^\r\n]*|push to|(^|[\r\n])[ \t]*[0-9]+[).:-]?[ \t]*(push|phone|call|sms|duo|passcode)[^\r\n]*} {
            after 300
            return [list numeric-menu $expect_out(buffer)]
        }
        -nocase -re {second password:[^\r\n]*|secondary password:[^\r\n]*|passcode:[^\r\n]*|token:[^\r\n]*} {
            return [list second-password $expect_out(buffer)]
        }
        -nocase -re {duo push sent|push sent|waiting for approval|approve[^\r\n]*(phone|duo|push)|sent a login request} {
            return [list auto-push $expect_out(buffer)]
        }
        timeout {
            return [list no-challenge ""]
        }
        eof {
            return [list eof ""]
        }
    }
}

set binary [env_value CISCO_VPN_BINARY ""]
set mfa_strategy [env_value CISCO_VPN_MFA_STRATEGY "auto"]
spawn $binary -s

wait_for_initial_prompt
after 500
trace "sending connect command"
if {![send_line_if_open [env_value CISCO_VPN_CONNECT_INPUT ""]]} {
    exit 1
}

after 1500
set group_buffer [capture_group_menu]
trace "sending group response"
if {![send_line_if_open [group_reply \
    [env_value CISCO_VPN_GROUP_INPUT ""] \
    [env_value CISCO_VPN_GROUP_REQUESTED ""] \
    $group_buffer]]} {
    exit 1
}

after 500
trace "waiting for username prompt"
set username_prompt [wait_for_username_prompt]
set password_prompt_seen 0
set can_send_password 1
if {$username_prompt eq "password"} {
    set password_prompt_seen 1
    trace "password prompt appeared before username input; using Cisco's saved username"
} elseif {$username_prompt eq "auth-failed"} {
    trace "Cisco reported authentication failure before username input"
    set can_send_password 0
} elseif {$username_prompt eq "eof"} {
    trace "Cisco CLI ended before username input"
    set can_send_password 0
} else {
    if {$username_prompt eq "missing"} {
        trace "username prompt not observed; continuing with saved username"
    }
    trace "sending saved username"
    if {![send_line_if_open [env_value CISCO_VPN_USERNAME_INPUT ""]]} {
        exit 1
    }
}

after 500
if {!$password_prompt_seen} {
    trace "waiting for password prompt"
    set password_prompt [wait_for_password_prompt]
    if {$password_prompt eq "auth-failed"} {
        trace "Cisco reported authentication failure before password input"
        set can_send_password 0
    } elseif {$password_prompt eq "eof"} {
        trace "Cisco CLI ended before password input"
        set can_send_password 0
    } elseif {$password_prompt eq "missing"} {
        trace "password prompt not observed; continuing with saved password"
    }
}

if {!$can_send_password} {
    exit 0
}

set password_input [password_reply \
    [env_value CISCO_VPN_PASSWORD_INPUT ""] \
    [env_value CISCO_VPN_DUO_INPUT ""] \
    $mfa_strategy]
trace "sending saved password"
if {![send_line_if_open $password_input]} {
    exit 1
}

after 500
set mfa_result [wait_for_mfa_or_result]
set mfa_mode [lindex $mfa_result 0]
set mfa_buffer [lindex $mfa_result 1]
if {$mfa_buffer ne ""} {
    trace "MFA prompt summary: [prompt_summary $mfa_buffer]"
}

if {$mfa_mode eq "numeric-menu"} {
    if {$mfa_strategy eq "waitOnly" || $mfa_strategy eq "secondPassword" || $mfa_strategy eq "passwordAppend"} {
        trace "detected MFA mode: numeric-menu; no factor sent for strategy $mfa_strategy"
    } else {
        set factor [env_value CISCO_VPN_DUO_INPUT "1"]
        trace "detected MFA mode: numeric-menu; selected factor: $factor"
        if {![send_line_if_open $factor]} {
            exit 1
        }
    }
} elseif {$mfa_mode eq "second-password"} {
    if {$mfa_strategy eq "waitOnly" || $mfa_strategy eq "numericMenu" || $mfa_strategy eq "passwordAppend"} {
        trace "detected MFA mode: second-password; no factor sent for strategy $mfa_strategy"
    } else {
        set factor [push_factor [env_value CISCO_VPN_DUO_INPUT ""]]
        trace "detected MFA mode: second-password; selected factor: $factor"
        if {![send_line_if_open $factor]} {
            exit 1
        }
    }
} elseif {$mfa_mode eq "auto-push"} {
    trace "detected MFA mode: auto-push; no additional factor input sent"
} elseif {$mfa_mode eq "no-challenge"} {
    trace "no Duo challenge detected; waiting for auto-push or connection"
} elseif {$mfa_mode eq "connected"} {
    trace "detected connected state before explicit MFA input"
} elseif {$mfa_mode eq "auth-failed"} {
    trace "Cisco reported authentication failure before MFA input"
} else {
    trace "Cisco CLI ended before explicit MFA input"
}

set timeout 65
expect {
    -nocase -re {accept|banner|continue|y/n|yes/no} {
        send_line_if_open [env_value CISCO_VPN_ACCEPT_INPUT "y"]
        exp_continue
    }
    -nocase -re {connected|connection state:[^\r\n]*connected} {}
    -nocase -re {login failed|authentication failed|access denied|invalid credentials|denied} {}
    timeout {}
    eof {}
}

set exit_input [env_value CISCO_VPN_EXIT_INPUT ""]
if {$exit_input ne ""} {
    catch { send_line_if_open $exit_input }
    set timeout 3
    catch { expect {
        eof {}
        timeout {}
    } }
}
"""#
}

public final class CiscoVPNClient: @unchecked Sendable {
    private let pathResolver: CiscoVPNPathResolver
    private let runner: VPNCommandRunning
    private let totpGenerator: TOTPGenerator
    private let blockerStopper: CiscoVPNClientBlockerStopping

    public init(
        pathResolver: CiscoVPNPathResolver = CiscoVPNPathResolver(),
        runner: VPNCommandRunning = ExpectVPNCommandRunner(),
        totpGenerator: TOTPGenerator = TOTPGenerator(),
        blockerStopper: CiscoVPNClientBlockerStopping = ProcessCiscoVPNClientBlockerStopper()
    ) {
        self.pathResolver = pathResolver
        self.runner = runner
        self.totpGenerator = totpGenerator
        self.blockerStopper = blockerStopper
    }

    public func installedBinary() -> URL? {
        pathResolver.resolve()
    }

    public func stats() throws -> VPNStatus {
        guard let binary = pathResolver.resolve() else {
            throw CiscoVPNError.binaryNotFound
        }
        let result = try runner.run(
            binary: binary,
            commands: ["stats", "exit"],
            timeout: 10,
            redactedPreview: "stats\nexit"
        )
        return CiscoVPNStatsParser.parse(result.output)
    }

    public func disconnect() throws -> VPNCommandResult {
        guard let binary = pathResolver.resolve() else {
            throw CiscoVPNError.binaryNotFound
        }
        return try runner.run(
            binary: binary,
            commands: ["disconnect", "exit"],
            timeout: 30,
            redactedPreview: "disconnect\nexit"
        )
    }

    public func connect(profile: VPNProfile, savedSecret: SavedVPNSecret) throws -> VPNCommandResult {
        guard let binary = pathResolver.resolve() else {
            throw CiscoVPNError.binaryNotFound
        }
        guard !savedSecret.username.isEmpty, !savedSecret.password.isEmpty else {
            throw CiscoVPNError.missingCredentials
        }

        let totpCode: String?
        if profile.duoMethod == .passcode {
            guard !savedSecret.totpSecret.isEmpty else {
                throw CiscoVPNError.missingTOTPSecret
            }
            totpCode = try totpGenerator.code(secret: savedSecret.totpSecret)
        } else {
            totpCode = nil
        }

        blockerStopper.stopBlockers()

        let script = CiscoVPNConnectScript(
            profile: profile,
            secret: VPNSecret(username: savedSecret.username, password: savedSecret.password, totpCode: totpCode)
        )

        return try runner.runStaged(
            binary: binary,
            steps: script.steps,
            timeout: 240,
            redactedPreview: script.redactedPreview
        )
    }
}
