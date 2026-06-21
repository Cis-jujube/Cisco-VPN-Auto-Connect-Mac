import CryptoKit
import Foundation

public struct TOTPGenerator: Sendable {
    public init() {}

    public func code(secret: String, unixTime: Int64 = Int64(Date().timeIntervalSince1970)) throws -> String {
        let keyData = try decodeBase32(secret)
        let counter = UInt64(unixTime / 30)
        let counterBytes = withUnsafeBytes(of: counter.bigEndian) { Data($0) }
        let key = SymmetricKey(data: keyData)
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: counterBytes, using: key)
        let hash = Array(hmac)

        guard let last = hash.last else { throw CiscoVPNError.invalidBase32Secret }
        let offset = Int(last & 0x0f)
        let binary = (Int(hash[offset] & 0x7f) << 24)
            | (Int(hash[offset + 1]) << 16)
            | (Int(hash[offset + 2]) << 8)
            | Int(hash[offset + 3])
        return String(format: "%06d", binary % 1_000_000)
    }

    private func decodeBase32(_ value: String) throws -> Data {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        let lookup = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($0.element, $0.offset) })
        let cleaned = value
            .uppercased()
            .filter { !$0.isWhitespace && $0 != "=" }

        var buffer = 0
        var bitsLeft = 0
        var bytes: [UInt8] = []

        for character in cleaned {
            guard let value = lookup[character] else {
                throw CiscoVPNError.invalidBase32Secret
            }
            buffer = (buffer << 5) | value
            bitsLeft += 5
            if bitsLeft >= 8 {
                let byte = UInt8((buffer >> (bitsLeft - 8)) & 0xff)
                bytes.append(byte)
                bitsLeft -= 8
            }
        }

        if bytes.isEmpty {
            throw CiscoVPNError.invalidBase32Secret
        }
        return Data(bytes)
    }
}
