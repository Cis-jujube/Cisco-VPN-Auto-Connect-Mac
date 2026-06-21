import Foundation

public enum VPNConnectOutcome: Equatable, Sendable {
    case connected
    case authenticationFailed
    case authFailedBeforeMFA
    case authFailedAfterMFA
    case possiblePasswordAppendRequired
    case missingTOTPSecret
    case binaryMissing
    case terminalRunnerMissing
    case timedOut
    case duoTimeout
    case connectCapabilityUnavailable
    case networkUnreachable
    case ciscoServiceUnavailable
    case groupNotFound(saved: String, available: [String])
    case stillDisconnected
    case waitingForApproval
    case duoPushSentWaiting
    case noMFAChallenge
    case unknown

    public var userMessage: String? {
        switch self {
        case .connected:
            nil
        case .authenticationFailed:
            "登录失败。请检查 NetID、密码和 Group；DKU 通常用 DUO Push，不需要 TOTP。"
        case .authFailedBeforeMFA:
            "服务器在进入 DUO 前拒绝了登录。请优先检查 NetID、Password、Group，以及密码是否含全角字符、首尾空格或换行。"
        case .authFailedAfterMFA:
            "DUO/MFA 提示出现后认证失败。请确认手机审批、MFA 选项或 passcode 是否正确。"
        case .possiblePasswordAppendRequired:
            "Cisco 的 Password 提示看起来支持追加 DUO 因子。如果普通密码确认无误，可在 Advanced 中把 MFA Strategy 改为 passwordAppend 后再试。"
        case .missingTOTPSecret:
            "当前选择了 TOTP Passcode，但没有保存 Base32 TOTP secret。建议切回 DUO Push。"
        case .binaryMissing:
            "没有找到 Cisco Secure Client CLI。请确认 /opt/cisco/secureclient/bin/vpn 存在。"
        case .terminalRunnerMissing:
            "没有找到 /usr/bin/expect，无法驱动 Cisco 的终端式登录提示。"
        case .timedOut:
            "Cisco VPN 连接超时。请确认手机 DUO 已 Approve，然后再试一次。"
        case .duoTimeout:
            "DUO 请求没有在超时时间内完成。请确认手机网络、DUO Mobile 状态和学校 DUO 策略。"
        case .connectCapabilityUnavailable:
            "Cisco Secure Client 图形界面或旧的 vpn 进程占用了连接功能。请退出 Cisco Secure Client 后重试。"
        case .networkUnreachable:
            "VPN 服务器网络不可达。请检查网络、服务器地址和端口。"
        case .ciscoServiceUnavailable:
            "Cisco Secure Client 服务不可用。请确认 vpnagentd 正在运行，或重启 Cisco Secure Client。"
        case .groupNotFound(let saved, let available):
            if available.isEmpty {
                "Cisco 当前 Group 菜单里没有找到 \(saved)。请展开高级设置，确认 VPN Group。"
            } else {
                "Cisco 当前 Group 菜单里没有找到 \(saved)。可选 Group：\(available.joined(separator: ", "))。"
            }
        case .stillDisconnected:
            "Cisco Secure Client 仍显示未连接。请检查 DUO 是否已通过，或确认账号/Group 是否正确。"
        case .waitingForApproval:
            "已发送连接请求。如果手机弹出 DUO，请点 Approve，然后点 Refresh 查看状态。"
        case .duoPushSentWaiting:
            "已发起 DUO Push。请在手机上 approve。"
        case .noMFAChallenge:
            "Cisco 没有暴露 DUO 验证提示；App 已按自动 Push 模式等待，但没有看到明确的 Duo challenge。请检查 Group 或 Duo 策略。"
        case .unknown:
            "连接没有成功完成。请复制诊断日志查看 Cisco 返回的最后几行。"
        }
    }
}

public enum CiscoVPNResultClassifier {
    public static func classify(
        output: String,
        status: VPNStatus?,
        strategy: MFAInjectionStrategy = .auto,
        timedOut: Bool = false
    ) -> VPNConnectOutcome {
        if status?.state == .connected {
            return .connected
        }

        let normalized = output
            .replacingOccurrences(of: "\r", with: "\n")
            .lowercased()
        let ciscoOutputOnly = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("[autoconnect]") }
            .joined(separator: "\n")
        let trace = CiscoVPNPromptClassifier.trace(output: output, timedOut: timedOut)
        let appendPasswordEvidence = ciscoOutputOnly.range(
            of: #"(?i)(append[^\n]*(,\s*)?(push|duo|passcode)|single[- ]password|password\s*,\s*(push|push[0-9]+|[0-9]{6,8}))"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil

        if timedOut && trace.waitingForDuo {
            return .duoTimeout
        }

        if normalized.contains("login failed")
            || normalized.contains("authentication failed")
            || normalized.contains("failed login")
            || normalized.contains("invalid username")
            || normalized.contains("invalid password") {
            if trace.sawMFAChallenge || trace.sentMFA {
                return .authFailedAfterMFA
            }
            if strategy == .auto && appendPasswordEvidence {
                return .possiblePasswordAppendRequired
            }
            return .authFailedBeforeMFA
        }

        if normalized.contains("totp secret not found")
            || normalized.contains("no totp secret")
            || normalized.contains("missing totp") {
            return .missingTOTPSecret
        }

        if normalized.contains("connect capability is unavailable")
            || normalized.contains("another cisco secure client application acquired it") {
            return .connectCapabilityUnavailable
        }

        if trace.serviceUnavailable {
            return .ciscoServiceUnavailable
        }

        if trace.networkUnreachable {
            return .networkUnreachable
        }

        if normalized.contains("no duo challenge detected") {
            return .noMFAChallenge
        }

        if let statsState = lastStateMention(in: normalized, labels: ["connection state"]) {
            return statsState == .connected ? .connected : .stillDisconnected
        }

        if normalized.contains("client address (ipv4):") && !normalized.contains("not available") {
            return .connected
        }

        if ciscoOutputOnly.contains("duo")
            || ciscoOutputOnly.contains("push")
            || ciscoOutputOnly.contains("approve")
            || ciscoOutputOnly.contains("mfa") {
            return trace.waitingForDuo ? .duoPushSentWaiting : .waitingForApproval
        }

        if status?.state == .disconnected {
            return .stillDisconnected
        }

        if let promptState = lastStateMention(in: normalized, labels: ["state"]) {
            return promptState == .connected ? .connected : .stillDisconnected
        }

        return .unknown
    }

    public static func classify(error: Error) -> VPNConnectOutcome {
        guard let ciscoError = error as? CiscoVPNError else {
            return .unknown
        }

        switch ciscoError {
        case .binaryNotFound:
            return .binaryMissing
        case .missingTOTPSecret:
            return .missingTOTPSecret
        case .commandTimedOut:
            return .timedOut
        case .groupNotFound(let saved, let available):
            return .groupNotFound(saved: saved, available: available)
        case .missingCredentials, .invalidBase32Secret, .keychain:
            return .unknown
        }
    }

    private static func lastStateMention(in normalized: String, labels: [String]) -> VPNConnectionState? {
        let escapedLabels = labels
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let pattern = #"(?im)^\s*(?:vpn>\s*)?(?:>>\s*)?(?:"# + escapedLabels + #")\s*:\s*(connected|disconnected|not connected)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = regex.matches(in: normalized, range: range)
        guard let match = matches.last,
              let valueRange = Range(match.range(at: 1), in: normalized)
        else {
            return nil
        }

        let value = normalized[valueRange]
        return value.contains("disconnected") || value.contains("not connected") ? .disconnected : .connected
    }
}
