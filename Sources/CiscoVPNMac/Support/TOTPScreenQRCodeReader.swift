import Foundation

enum TOTPScreenQRCodeReaderError: Error, LocalizedError {
    case captureFailed(String)
    case captureImageMissing

    var errorDescription: String? {
        switch self {
        case .captureFailed(let message):
            if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Screen capture failed."
            }
            return "Screen capture failed: \(message)"
        case .captureImageMissing:
            return "Screen capture did not produce an image."
        }
    }
}

enum TOTPScreenQRCodeReader {
    static func firstPayloadFromCurrentScreen() throws -> String {
        let screenshotURL = FileManager.default.temporaryDirectory
            .appending(path: "cisco-vpn-totp-screen-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: screenshotURL)
        }

        try captureScreen(to: screenshotURL)
        return try TOTPQRCodeReader.firstPayload(in: screenshotURL)
    }

    private static func captureScreen(to screenshotURL: URL) throws {
        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", screenshotURL.path]
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let errorText = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            throw TOTPScreenQRCodeReaderError.captureFailed(errorText)
        }
        guard FileManager.default.fileExists(atPath: screenshotURL.path) else {
            throw TOTPScreenQRCodeReaderError.captureImageMissing
        }
    }
}
