import Foundation

public final class FileProfileStore {
    public let rootDirectory: URL
    public let profilesFile: URL
    public let activeProfileFile: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootDirectory: URL = FileProfileStore.defaultRootDirectory()) {
        self.rootDirectory = rootDirectory
        self.profilesFile = rootDirectory.appending(path: "profiles.json")
        self.activeProfileFile = rootDirectory.appending(path: "active_profile")
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public static func defaultRootDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["CISCO_VPN_PROFILE_ROOT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return base.appending(path: "Cisco VPN AutoConnect", directoryHint: .isDirectory)
    }

    public func loadProfiles() throws -> [VPNProfile] {
        guard FileManager.default.fileExists(atPath: profilesFile.path) else { return [] }
        let data = try Data(contentsOf: profilesFile)
        return try decoder.decode([VPNProfile].self, from: data)
    }

    public func save(_ profile: VPNProfile) throws {
        try ensureRootDirectory()
        var profiles = try loadProfiles()
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profiles.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        let data = try encoder.encode(profiles)
        try data.write(to: profilesFile, options: .atomic)
    }

    public func delete(profileID: String) throws {
        var profiles = try loadProfiles()
        profiles.removeAll { $0.id == profileID }
        try ensureRootDirectory()
        try encoder.encode(profiles).write(to: profilesFile, options: .atomic)
        if try loadActiveProfileID() == profileID {
            try setActiveProfileID(profiles.first?.id ?? "")
        }
    }

    public func loadActiveProfileID() throws -> String? {
        guard FileManager.default.fileExists(atPath: activeProfileFile.path) else { return nil }
        let raw = try String(contentsOf: activeProfileFile, encoding: .utf8)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func setActiveProfileID(_ id: String) throws {
        try ensureRootDirectory()
        try id.write(to: activeProfileFile, atomically: true, encoding: .utf8)
    }

    private func ensureRootDirectory() throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
