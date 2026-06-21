import Foundation

public enum CiscoVPNStatsParser {
    public static func parse(_ output: String) -> VPNStatus {
        let stateText = value(after: "Connection State", in: output)
            ?? value(after: "state", in: output)
            ?? ""
        let duration = available(value(after: "Duration", in: output))
        let remaining = available(value(after: "Remaining Session Time", in: output))
            ?? available(value(after: "Remaining Time", in: output))
        let server = available(value(after: "Server Address", in: output))
        let clientIP = available(value(after: "Client Address (IPv4)", in: output))

        return VPNStatus(
            state: state(from: stateText, server: server, clientIP: clientIP),
            server: server,
            clientIPv4: clientIP,
            duration: duration,
            remaining: remaining,
            rawOutput: output
        )
    }

    private static func value(after label: String, in output: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        let pattern = #"(?im)^\s*"# + escaped + #"\s*:\s*(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              let valueRange = Range(match.range(at: 1), in: output)
        else { return nil }
        return String(output[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func available(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.localizedCaseInsensitiveContains("not available") { return nil }
        if trimmed == "不可用" { return nil }
        if trimmed == "0.0.0.0" { return nil }
        return trimmed
    }

    private static func state(from stateText: String, server: String?, clientIP: String?) -> VPNConnectionState {
        let lower = stateText.lowercased()
        if lower.contains("disconnected") || lower.contains("not connected") {
            return .disconnected
        }
        if lower.contains("connected") || lower.contains("established") || stateText.contains("已连接") || stateText.contains("已連線") {
            return .connected
        }
        if server != nil || clientIP != nil {
            return .connected
        }
        if !stateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .unknown
        }
        return .disconnected
    }
}
