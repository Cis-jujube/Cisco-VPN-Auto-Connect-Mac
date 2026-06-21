import CiscoVPNCore
import Foundation

@MainActor
final class VPNAppStore: ObservableObject {
    @Published private(set) var profiles: [VPNProfile] = []
    @Published var selectedProfileID: String?
    @Published private(set) var status = VPNStatus(
        state: .unknown,
        server: nil,
        clientIPv4: nil,
        duration: nil,
        remaining: nil
    )
    @Published private(set) var logLines: [String] = []
    @Published private(set) var doctorReport: CiscoVPNDoctorReport?
    @Published private(set) var isBusy = false
    @Published var lastError: String?
    @Published var subscriptionImportStatus: String?
    @Published var appLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: Self.appLanguageKey)
        }
    }

    private let profileStore: FileProfileStore
    private let credentialStore: VPNCredentialStore
    private let client: CiscoVPNClient
    private let doctor: CiscoVPNDoctor
    private var awaitingPostConnectStatus = false
    private static let appLanguageKey = "CiscoVPNMac.appLanguage"

    init(
        profileStore: FileProfileStore = FileProfileStore(),
        credentialStore: VPNCredentialStore = KeychainCredentialStore(),
        client: CiscoVPNClient = CiscoVPNClient(),
        doctor: CiscoVPNDoctor? = nil
    ) {
        self.profileStore = profileStore
        self.credentialStore = credentialStore
        self.client = client
        self.doctor = doctor ?? CiscoVPNDoctor(credentialStore: credentialStore)
        let savedLanguage = UserDefaults.standard.string(forKey: Self.appLanguageKey)
            .flatMap(AppLanguage.init(rawValue:))
        self.appLanguage = savedLanguage ?? .simplifiedChinese
        load()
    }

    var selectedProfile: VPNProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first { $0.id == selectedProfileID }
    }

    var detectedBinaryPath: String {
        client.installedBinary()?.path ?? strings.notFound
    }

    var logText: String {
        logLines.joined(separator: "\n")
    }

    var diagnosticText: String {
        let doctorText = doctorReport?.diagnosticText ?? strings.doctorNotRunDiagnostic
        if logText.isEmpty {
            return doctorText
        }
        return "\(doctorText)\n\n\(strings.logsLabel):\n\(logText)"
    }

    var tutorialContent: TutorialContent {
        TutorialGuide.content(for: appLanguage)
    }

    var strings: AppStrings {
        AppStrings(language: appLanguage)
    }

    func load() {
        do {
            profiles = try profileStore.loadProfiles()
            if profiles.isEmpty {
                try profileStore.save(.dkuDefault)
                try profileStore.save(.dukeDefault)
                profiles = try profileStore.loadProfiles()
                appendLog("[init] Added DKU and Duke presets")
            }
            selectedProfileID = try profileStore.loadActiveProfileID() ?? profiles.first?.id
            if let selectedProfileID {
                try profileStore.setActiveProfileID(selectedProfileID)
            }
        } catch {
            lastError = error.localizedDescription
            appendLog("[error] \(error.localizedDescription)")
        }
    }

    func select(_ profileID: String?) {
        selectedProfileID = profileID
        if let profileID {
            try? profileStore.setActiveProfileID(profileID)
        }
    }

    func makeCustomProfile() {
        let base = VPNProfile(
            id: "custom",
            displayName: strings.customVPN,
            server: "",
            group: "-Default-",
            port: "443",
            vpnProtocol: "ssl",
            duoMethod: .push,
            pushTarget: ""
        )
        var candidate = base
        var suffix = 2
        while profiles.contains(where: { $0.id == candidate.id }) {
            candidate.id = "custom-\(suffix)"
            candidate.displayName = "\(strings.customVPN) \(suffix)"
            suffix += 1
        }
        saveProfile(candidate, secret: nil)
    }

    func saveProfile(_ profile: VPNProfile, secret: SavedVPNSecret?) {
        do {
            try profileStore.save(profile)
            if let secret {
                try credentialStore.saveSecret(secret, profileID: profile.id)
            }
            profiles = try profileStore.loadProfiles()
            select(profile.id)
            appendLog("[save] \(profile.displayName)")
        } catch {
            lastError = error.localizedDescription
            appendLog("[error] \(error.localizedDescription)")
        }
    }

    @discardableResult
    func saveTOTPAndEnablePasscode(
        profile: VPNProfile,
        savedSecret: SavedVPNSecret,
        input: String
    ) throws -> (profile: VPNProfile, secret: SavedVPNSecret) {
        do {
            let configured = try TOTPPasscodeSetup.apply(
                input: input,
                to: profile,
                savedSecret: savedSecret
            )
            try profileStore.save(configured.profile)
            try credentialStore.saveSecret(configured.secret, profileID: configured.profile.id)
            profiles = try profileStore.loadProfiles()
            select(configured.profile.id)
            lastError = nil
            appendLog("[totp] TOTP saved for \(configured.profile.displayName)")
            return configured
        } catch {
            lastError = friendlyMessage(for: error)
            appendLog("[error] \(friendlyMessage(for: error))")
            throw error
        }
    }

    func deleteSelectedProfile() {
        guard let profile = selectedProfile else { return }
        do {
            try profileStore.delete(profileID: profile.id)
            try credentialStore.deleteSecret(profileID: profile.id)
            profiles = try profileStore.loadProfiles()
            selectedProfileID = try profileStore.loadActiveProfileID() ?? profiles.first?.id
            appendLog("[delete] \(profile.displayName)")
        } catch {
            lastError = error.localizedDescription
            appendLog("[error] \(error.localizedDescription)")
        }
    }

    func loadSecret(profileID: String) -> SavedVPNSecret {
        do {
            return try credentialStore.loadSecret(profileID: profileID) ?? SavedVPNSecret()
        } catch {
            appendLog("[error] \(error.localizedDescription)")
            return SavedVPNSecret()
        }
    }

    func credentialSummary(for profile: VPNProfile?) -> String {
        guard let profile else { return strings.credentialNoProfile }
        let secret = (try? credentialStore.loadSecret(profileID: profile.id)) ?? SavedVPNSecret()
        let username = secret.username.isEmpty ? strings.credentialNoUsername : strings.credentialUsernameSaved
        let password = secret.password.isEmpty ? strings.credentialNoPassword : strings.credentialPasswordSaved
        let totp = secret.totpSecret.isEmpty ? strings.credentialNoTOTP : strings.credentialTOTPSaved
        return "\(username), \(password), \(totp)"
    }

    func runDoctor() {
        guard !isBusy else { return }
        let profile = selectedProfile
        let doctor = self.doctor
        isBusy = true
        appendLog("[doctor] Running local diagnostics")

        Task.detached {
            let report = doctor.run(profile: profile)
            await MainActor.run {
                self.doctorReport = report
                self.isBusy = false
                self.appendLog(report.diagnosticText, prefix: "[doctor]")
            }
        }
    }

    func resetSelectedCredentials() {
        guard let profile = selectedProfile else { return }
        do {
            try credentialStore.deleteSecret(profileID: profile.id)
            appendLog("[credentials] Reset saved credentials for \(profile.displayName)")
            lastError = strings.resetCredentialsMessage()
        } catch {
            lastError = error.localizedDescription
            appendLog("[error] \(error.localizedDescription)")
        }
    }

    func importSubscription(from rawURL: String) {
        guard !isBusy else { return }
        subscriptionImportStatus = nil
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), VPNProfileSubscriptionURLPolicy.isAllowed(url) else {
            lastError = strings.invalidSubscriptionURL
            appendLog("[subscription] invalid URL")
            return
        }

        isBusy = true
        lastError = nil
        appendLog("[subscription] Importing \(url.absoluteString)")

        Task.detached {
            let result = await Self.fetchSubscription(url: url)
            await MainActor.run {
                self.isBusy = false
                switch result {
                case .success(let imported):
                    do {
                        for profile in imported.profiles {
                            try self.profileStore.save(profile)
                        }
                        self.profiles = try self.profileStore.loadProfiles()
                        if let first = imported.profiles.first {
                            self.select(first.id)
                        }
                        let message = self.strings.subscriptionImportSuccess(
                            count: imported.profiles.count,
                            source: imported.sourceName
                        )
                        self.subscriptionImportStatus = message
                        self.lastError = nil
                        self.appendLog("[subscription] \(message)")
                    } catch {
                        self.lastError = self.friendlyMessage(for: error)
                        self.appendLog("[error] \(self.lastError ?? error.localizedDescription)")
                    }
                case .failure(let error):
                    self.lastError = self.friendlyMessage(for: error)
                    self.appendLog("[error] \(self.lastError ?? error.localizedDescription)")
                }
            }
        }
    }

    func refreshStatus() {
        guard !isBusy else { return }
        markStatusChecking()
        isBusy = true
        appendLog("[status] Refreshing Cisco VPN state")
        let client = self.client

        Task.detached {
            let result = Result { try client.stats() }
            await MainActor.run {
                self.isBusy = false
                switch result {
                case .success(let status):
                    self.status = status
                    if status.state == .connected {
                        self.awaitingPostConnectStatus = false
                        self.lastError = nil
                    } else if self.awaitingPostConnectStatus && status.state == .disconnected {
                        self.awaitingPostConnectStatus = false
                        self.lastError = self.userMessage(for: .stillDisconnected)
                    }
                    self.appendLog("[status] \(status.state.title)")
                case .failure(let error):
                    self.awaitingPostConnectStatus = false
                    self.lastError = error.localizedDescription
                    self.appendLog("[error] \(error.localizedDescription)")
                }
            }
        }
    }

    func connectSelected() {
        guard let profile = selectedProfile else { return }
        guard !isBusy else { return }
        let savedSecret = loadSecret(profileID: profile.id)

        if let preflightError = preflightMessage(profile: profile, secret: savedSecret) {
            lastError = preflightError
            appendLog("[preflight] \(preflightError)")
            return
        }

        markStatusChecking()
        isBusy = true
        lastError = nil
        appendLog("[connect] \(profile.displayName)")
        appendCredentialDiagnostics(savedSecret)
        let client = self.client

        Task.detached {
            let result = Result { try client.connect(profile: profile, savedSecret: savedSecret) }
            await MainActor.run {
                self.isBusy = false
                switch result {
                case .success(let commandResult):
                    self.appendLog(commandResult.redactedInputPreview, prefix: "[input]")
                    self.appendLog(self.redact(commandResult.output, secret: savedSecret), prefix: "[cisco]")
                    let outcome = CiscoVPNResultClassifier.classify(
                        output: commandResult.output,
                        status: nil,
                        strategy: profile.mfaStrategy
                    )
                    self.awaitingPostConnectStatus = outcome == .waitingForApproval
                        || outcome == .duoPushSentWaiting
                        || outcome == .unknown
                    let message = self.userMessage(for: outcome, profile: profile, secret: savedSecret)
                    self.lastError = message
                    if let message {
                        self.appendLog("[hint] \(message)")
                    }
                    self.refreshStatus()
                case .failure(let error):
                    self.awaitingPostConnectStatus = false
                    let outcome = CiscoVPNResultClassifier.classify(error: error)
                    let message = self.userMessage(for: outcome) ?? self.friendlyMessage(for: error)
                    self.lastError = message
                    self.appendLog("[error] \(message)")
                    self.refreshStatus()
                }
            }
        }
    }

    func disconnect() {
        guard !isBusy else { return }
        markStatusChecking()
        isBusy = true
        appendLog("[disconnect] Disconnecting")
        let client = self.client

        Task.detached {
            let result = Result { try client.disconnect() }
            await MainActor.run {
                self.isBusy = false
                switch result {
                case .success(let commandResult):
                    self.appendLog(commandResult.output, prefix: "[cisco]")
                    self.refreshStatus()
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.appendLog("[error] \(error.localizedDescription)")
                }
            }
        }
    }

    func clearLog() {
        logLines.removeAll()
    }

    private func appendLog(_ text: String, prefix: String? = nil) {
        let stamp = Self.timestamp()
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if lines.isEmpty {
            return
        }
        for line in lines {
            let body = prefix.map { "\($0) \(line)" } ?? line
            logLines.append("[\(stamp)] \(body)")
        }
        if logLines.count > 600 {
            logLines.removeFirst(logLines.count - 600)
        }
    }

    private func markStatusChecking() {
        status = VPNStatus(
            state: .unknown,
            server: selectedProfile?.server ?? status.server,
            clientIPv4: nil,
            duration: nil,
            remaining: nil,
            rawOutput: status.rawOutput
        )
    }

    private func redact(_ text: String, secret: SavedVPNSecret) -> String {
        CiscoVPNRedactor(secret: secret).redact(text)
    }

    private func appendCredentialDiagnostics(_ secret: SavedVPNSecret) {
        let diagnostics = secret.diagnostics
        appendLog("[credentials] \(diagnostics.summary)")
        if !diagnostics.passwordIsASCIIPrintable {
            appendLog("[warning] Password 含非 ASCII 字符。若不是有意使用中文/全角字符，请用英文输入法重新输入。")
        }
        if diagnostics.passwordHasLeadingOrTrailingWhitespace {
            appendLog("[warning] Password 首尾含空白字符。密码会原样提交，请确认这不是误输入。")
        }
        if diagnostics.passwordContainsNewline || diagnostics.passwordContainsControlCharacters {
            appendLog("[warning] Password 含换行或控制字符。请清空后重新输入。")
        }
    }

    private static func fetchSubscription(url: URL) async -> Result<VPNProfileSubscriptionImportResult, Error> {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw SubscriptionImportHTTPError(statusCode: httpResponse.statusCode)
            }
            return .success(try VPNProfileSubscriptionImporter.importProfiles(from: data))
        } catch {
            return .failure(error)
        }
    }

    private func userMessage(for outcome: VPNConnectOutcome, profile: VPNProfile, secret: SavedVPNSecret) -> String? {
        guard outcome == .authenticationFailed else {
            return userMessage(for: outcome)
        }

        let diagnostics = secret.diagnostics
        if !diagnostics.passwordIsASCIIPrintable {
            switch appLanguage {
            case .simplifiedChinese:
                return "登录失败发生在 DUO 前。当前保存的 Password 含非 ASCII 字符；如果不是有意使用中文/全角字符，请用英文输入法重新输入密码。当前 Group：\(profile.group)。"
            case .english:
                return "Login failed before DUO. The saved Password contains non-ASCII characters; if that was not intentional, re-enter it with the English input method. Current Group: \(profile.group)."
            }
        }

        return userMessage(for: outcome)
    }

    private func friendlyMessage(for error: Error) -> String {
        if let ciscoError = error as? CiscoVPNError {
            switch ciscoError {
            case .missingCredentials:
                return strings.missingConnectFields
            case .invalidBase32Secret:
                switch appLanguage {
                case .simplifiedChinese:
                    return "TOTP secret 不是有效的 Base32。DKU/Duke 日常建议使用 DUO Push。"
                case .english:
                    return "TOTP secret is not valid Base32. DKU/Duke daily use should prefer DUO Push."
                }
            case .groupNotFound(let group, let available):
                if available.isEmpty {
                    switch appLanguage {
                    case .simplifiedChinese:
                        return "Cisco 当前 Group 菜单里没有找到 \(group)。请展开高级设置，选择实际显示的 VPN Group。"
                    case .english:
                        return "Cisco did not show Group \(group). Open Advanced settings and choose the VPN Group shown by Cisco."
                    }
                }
                switch appLanguage {
                case .simplifiedChinese:
                    return "Cisco 当前 Group 菜单里没有找到 \(group)。可选 Group：\(available.joined(separator: ", "))。"
                case .english:
                    return "Cisco did not show Group \(group). Available Groups: \(available.joined(separator: ", "))."
                }
            case .keychain(let message):
                switch appLanguage {
                case .simplifiedChinese: return "Keychain 保存失败：\(message)"
                case .english: return "Keychain save failed: \(message)"
                }
            case .binaryNotFound, .missingTOTPSecret, .commandTimedOut:
                return userMessage(for: CiscoVPNResultClassifier.classify(error: ciscoError)) ?? ciscoError.localizedDescription
            }
        }
        if let subscriptionError = error as? VPNProfileSubscriptionError {
            return subscriptionMessage(for: subscriptionError)
        }
        if let httpError = error as? SubscriptionImportHTTPError {
            switch appLanguage {
            case .simplifiedChinese:
                return "订阅服务器返回 HTTP \(httpError.statusCode)。"
            case .english:
                return "Subscription server returned HTTP \(httpError.statusCode)."
            }
        }
        return error.localizedDescription
    }

    private func preflightMessage(profile: VPNProfile, secret: SavedVPNSecret) -> String? {
        if profile.server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch appLanguage {
            case .simplifiedChinese: return "请先填写 VPN Server。"
            case .english: return "Enter the VPN Server first."
            }
        }
        if secret.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || secret.password.isEmpty {
            return strings.missingConnectFields
        }
        if let guidance = secret.diagnostics.actionGuidance {
            switch appLanguage {
            case .simplifiedChinese:
                return "\(guidance) 请点击 Reset saved credentials for this profile 后，用英文输入法重新输入密码。"
            case .english:
                return "\(guidance) Click Reset saved credentials for this profile, then re-enter the password with the English input method."
            }
        }
        if profile.duoMethod == .passcode && secret.totpSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return userMessage(for: .missingTOTPSecret)
        }
        if client.installedBinary() == nil {
            return userMessage(for: .binaryMissing)
        }
        if !FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") {
            return userMessage(for: .terminalRunnerMissing)
        }
        return nil
    }

    private func userMessage(for outcome: VPNConnectOutcome) -> String? {
        switch appLanguage {
        case .simplifiedChinese:
            return outcome.userMessage
        case .english:
            switch outcome {
            case .connected:
                return nil
            case .authenticationFailed:
                return "Login failed. Check NetID, Password, and Group. DKU/Duke usually use DUO Push, not TOTP."
            case .authFailedBeforeMFA:
                return "The server rejected login before DUO. Check NetID, Password, Group, and hidden password characters."
            case .authFailedAfterMFA:
                return "Authentication failed after the DUO/MFA prompt. Check phone approval, MFA option, or passcode."
            case .possiblePasswordAppendRequired:
                return "Cisco's Password prompt appears to support an appended DUO factor. If the password is correct, try MFA Strategy passwordAppend in Advanced."
            case .missingTOTPSecret:
                return "This profile uses TOTP Passcode but no Base32 TOTP secret is saved. Switch back to DUO Push."
            case .binaryMissing:
                return "Cisco Secure Client CLI was not found. Confirm /opt/cisco/secureclient/bin/vpn exists."
            case .terminalRunnerMissing:
                return "/usr/bin/expect was not found, so the app cannot drive Cisco's terminal-style prompts."
            case .timedOut:
                return "Cisco VPN connection timed out. Approve DUO on your phone, then try again."
            case .duoTimeout:
                return "DUO did not complete before timeout. Check phone network, DUO Mobile, and school DUO policy."
            case .connectCapabilityUnavailable:
                return "Cisco Secure Client GUI or an old vpn process owns the connect capability. Quit Cisco Secure Client and retry."
            case .networkUnreachable:
                return "VPN server is unreachable. Check network, server, and port."
            case .ciscoServiceUnavailable:
                return "Cisco Secure Client service is unavailable. Confirm vpnagentd is running or restart Cisco Secure Client."
            case .groupNotFound(let saved, let available):
                if available.isEmpty {
                    return "Cisco did not show Group \(saved). Open Advanced settings and confirm the VPN Group."
                }
                return "Cisco did not show Group \(saved). Available Groups: \(available.joined(separator: ", "))."
            case .stillDisconnected:
                return "Cisco Secure Client still shows disconnected. Check DUO approval or confirm account and Group."
            case .waitingForApproval:
                return "Connection request was sent. If DUO appears on your phone, approve it, then click Refresh."
            case .duoPushSentWaiting:
                return "DUO Push was sent. Approve it on your phone."
            case .noMFAChallenge:
                return "Cisco did not expose a DUO challenge. The app waited as auto-push, but no explicit challenge appeared. Check Group or Duo policy."
            case .unknown:
                return "Connection did not finish. Copy diagnostics and inspect the last Cisco lines."
            }
        }
    }

    private func subscriptionMessage(for error: VPNProfileSubscriptionError) -> String {
        switch appLanguage {
        case .simplifiedChinese:
            switch error {
            case .invalidJSON:
                return "订阅必须是 JSON，并包含 profiles 数组。"
            case .containsCredentialFields:
                return "订阅包含账号、密码、TOTP secret 或 token 字段，已拒绝导入。订阅只能包含 VPN Profile 元数据。"
            case .emptyProfiles:
                return "订阅里没有 VPN Profile。"
            case .tooManyProfiles(let count):
                return "订阅包含 \(count) 个 Profile，超过 50 个上限。"
            case .missingServer(let profile):
                return "订阅 Profile \(profile) 缺少 VPN Server。"
            }
        case .english:
            return error.localizedDescription
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}

private struct SubscriptionImportHTTPError: Error {
    let statusCode: Int
}
