import AppKit
import CiscoVPNCore
import SwiftUI
import UniformTypeIdentifiers

struct ProfileEditor: View {
    @EnvironmentObject private var store: VPNAppStore
    let profile: VPNProfile

    @State private var draft: ProfileDraft?
    @State private var revealPassword = false
    @State private var isQRCodeImporterPresented = false
    @State private var totpImportFeedback: TOTPImportFeedback?
    @SceneStorage("CiscoVPNMac.profileEditor.advancedExpanded") private var advancedExpanded = false

    var body: some View {
        let strings = store.strings

        VStack(alignment: .leading, spacing: 18) {
            header

            if let draft {
                if let lastError = store.lastError {
                    NoticeBanner(
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .yellow,
                        title: strings.needsAttention,
                        message: lastError
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if draft.needsPushRecommendation {
                    pushRecommendation
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                quickConnectFields(draft: draft)
                actionRow(draft: draft)

                Divider()

                advancedSettings(draft: draft)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.snappy, value: store.lastError)
        .animation(.snappy, value: draft?.duoMethod)
        .animation(.snappy, value: advancedExpanded)
        .onAppear(perform: loadDraft)
        .onChange(of: profile.id) {
            loadDraft()
        }
        .fileImporter(
            isPresented: $isQRCodeImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
            onCompletion: importTOTPFromQRCodeSelection
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.strings.oneClickTitle)
                    .font(.title3.weight(.semibold))
                Text(profile.displayName)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(store.strings.duoPushRecommended, systemImage: "checkmark.shield")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
        }
    }

    private var pushRecommendation: some View {
        NoticeBanner(
            systemImage: "shield.lefthalf.filled",
            tint: .blue,
            title: store.strings.recommendDuoPushTitle,
            message: store.strings.recommendDuoPushMessage
        ) {
            Button {
                switchToPush()
            } label: {
                Label(store.strings.useDuoPush, systemImage: "arrow.uturn.backward.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func quickConnectFields(draft: ProfileDraft) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
            GridRow {
                Text(store.strings.netID)
                    .foregroundStyle(.secondary)
                    .frame(width: 82, alignment: .leading)
                TextField(store.strings.netIDPlaceholder, text: binding(\.username))
                    .textFieldStyle(.roundedBorder)
            }

            GridRow {
                Text(store.strings.password)
                    .foregroundStyle(.secondary)
                HStack {
                    if revealPassword {
                        TextField(store.strings.password, text: binding(\.password))
                    } else {
                        SecureField(store.strings.password, text: binding(\.password))
                    }
                    Button {
                        revealPassword.toggle()
                    } label: {
                        Image(systemName: revealPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(revealPassword ? store.strings.hidePassword : store.strings.showPassword)
                }
                .textFieldStyle(.roundedBorder)
            }

            if draft.hasPasswordHiddenCharacterWarning {
                GridRow {
                    Text("")
                    Label(store.strings.passwordHiddenWarning, systemImage: "keyboard.badge.ellipsis")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GridRow {
                Text(store.strings.duo)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Image(systemName: draft.duoMethod == .push ? "iphone.radiowaves.left.and.right" : "number.circle")
                        .foregroundStyle(draft.duoMethod == .push ? .green : .orange)
                    Text(draft.duoMethod == .push ? store.strings.duoPushSummary : store.strings.duoPasscodeSummary)
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button(store.strings.switchLabel) {
                        withAnimation(.snappy) {
                            advancedExpanded = true
                        }
                    }
                    .buttonStyle(.link)
                }
                .padding(.vertical, 8)
            }

            GridRow {
                Text(store.strings.connectionRule)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Menu {
                        Button(store.strings.ruleDKUDefault) {
                            applyRule(group: "-Default-", pushTarget: "")
                        }
                        Button(store.strings.ruleDKULibrary) {
                            applyRule(group: "Library Resources Only", pushTarget: "")
                        }
                        Button(store.strings.ruleDukeIntl) {
                            applyRule(group: "INTL-DUKE", pushTarget: "")
                        }
                        Button(store.strings.ruleDuoSecondPhone) {
                            applyRule(group: draft.group, pushTarget: "2")
                        }
                        Divider()
                        Button(store.strings.ruleAdvancedManual) {
                            withAnimation(.snappy) {
                                advancedExpanded = true
                            }
                        }
                    } label: {
                        Label(store.strings.applyRule, systemImage: "wand.and.stars")
                    }
                    .menuStyle(.button)

                    Text(store.strings.ruleHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func actionRow(draft: ProfileDraft) -> some View {
        HStack(spacing: 10) {
            Button {
                save()
                store.connectSelected()
            } label: {
                Label(store.isBusy ? store.strings.connecting : store.strings.connectAndWaitForDuo, systemImage: "bolt.horizontal.circle.fill")
                    .frame(minWidth: 148)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!draft.isConnectReady || store.isBusy)
            .keyboardShortcut(.return, modifiers: .command)

            Button {
                store.disconnect()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .help(store.strings.disconnectHelp)
            .disabled(store.isBusy)

            Button {
                store.refreshStatus()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(store.strings.refreshStatusHelp)
            .disabled(store.isBusy)

            Button {
                NSWorkspace.shared.open(URL(string: "https://ip.me/")!)
            } label: {
                Image(systemName: "safari")
            }
            .help(store.strings.openIPHelp)

            Spacer()

            if !draft.isConnectReady {
                Text(draft.isPasscodeMissingSecret ? store.strings.missingTOTPSecret : store.strings.missingConnectFields)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func advancedSettings(draft: ProfileDraft) -> some View {
        DisclosureGroup(isExpanded: $advancedExpanded) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text(store.strings.name).foregroundStyle(.secondary)
                    TextField("DKU VPN", text: binding(\.displayName))
                }
                GridRow {
                    Text(store.strings.profileID).foregroundStyle(.secondary)
                    TextField("dku", text: binding(\.id))
                        .disabled(true)
                }
                GridRow {
                    Text(store.strings.server).foregroundStyle(.secondary)
                    TextField("portal.dukekunshan.edu.cn", text: binding(\.server))
                }
                GridRow {
                    Text(store.strings.group).foregroundStyle(.secondary)
                    TextField("-Default-", text: binding(\.group))
                }
                GridRow {
                    Text(store.strings.port).foregroundStyle(.secondary)
                    TextField("443", text: binding(\.port))
                }
                GridRow {
                    Text(store.strings.vpnProtocol).foregroundStyle(.secondary)
                    TextField("ssl", text: binding(\.vpnProtocol))
                }
                GridRow {
                    Text(store.strings.duo).foregroundStyle(.secondary)
                    Picker("", selection: duoBinding) {
                        ForEach(DuoMethod.allCases) { method in
                            Text(store.strings.duoMethodTitle(method)).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                }

                GridRow {
                    Text(store.strings.mfaStrategy).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("", selection: mfaStrategyBinding) {
                            ForEach(MFAInjectionStrategy.allCases) { strategy in
                                Text(store.strings.mfaStrategyTitle(strategy)).tag(strategy)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 260, alignment: .leading)

                        Text(store.strings.mfaStrategySummary(draft.mfaStrategy))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if draft.duoMethod == .push {
                    GridRow {
                        Text(store.strings.mfaOption).foregroundStyle(.secondary)
                        TextField(store.strings.mfaOptionPlaceholder, text: binding(\.pushTarget))
                    }
                } else {
                    GridRow {
                        Text(store.strings.totp).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            SecureField(store.strings.base32Secret, text: binding(\.totpSecret))
                            totpImportMenu
                        }
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.top, 12)

            if let feedback = totpImportFeedback {
                NoticeBanner(
                    systemImage: feedback.systemImage,
                    tint: feedback.tint,
                    title: feedback.title,
                    message: feedback.message
                )
                .padding(.top, 10)
            }

            HStack {
                Button {
                    save()
                } label: {
                    Label(store.strings.saveAdvancedSettings, systemImage: "checkmark.circle")
                }
                .disabled(!draft.isProfileSaveReady)

                if draft.duoMethod == .passcode {
                    Button {
                        switchToPush()
                    } label: {
                        Label(store.strings.switchBackToDuoPush, systemImage: "shield")
                    }
                }

                Button(role: .destructive) {
                    store.resetSelectedCredentials()
                    loadDraft()
                } label: {
                    Label(store.strings.resetCurrentCredentials, systemImage: "key.slash")
                }
            }
            .padding(.top, 10)
        } label: {
            Label(store.strings.advancedProfileSettings, systemImage: "slider.horizontal.3")
                .font(.headline)
        }
    }

    private var totpImportMenu: some View {
        Menu {
            Button {
                importTOTPFromClipboard()
            } label: {
                Label(store.strings.importFromClipboard, systemImage: "doc.on.clipboard")
            }

            Button {
                isQRCodeImporterPresented = true
            } label: {
                Label(store.strings.importFromQRImage, systemImage: "qrcode.viewfinder")
            }
        } label: {
            Label(store.strings.importTOTP, systemImage: "square.and.arrow.down")
        }
        .menuStyle(.button)
    }

    private var duoBinding: Binding<DuoMethod> {
        Binding(
            get: { draft?.duoMethod ?? .push },
            set: { method in
                draft?.duoMethod = method
                draft?.mfaStrategy = method == .passcode ? .passcode : .auto
            }
        )
    }

    private var mfaStrategyBinding: Binding<MFAInjectionStrategy> {
        Binding(
            get: { draft?.mfaStrategy ?? .auto },
            set: { draft?.mfaStrategy = $0 }
        )
    }

    private func binding<T>(_ keyPath: WritableKeyPath<ProfileDraft, T>) -> Binding<T> {
        Binding(
            get: { draft![keyPath: keyPath] },
            set: { draft![keyPath: keyPath] = $0 }
        )
    }

    private func loadDraft() {
        let secret = store.loadSecret(profileID: profile.id)
        draft = ProfileDraft(profile: profile, secret: secret)
        totpImportFeedback = nil
    }

    private func save() {
        guard let draft else { return }
        store.saveProfile(draft.profile, secret: draft.secret)
    }

    private func switchToPush() {
        guard var current = draft else { return }
        current.duoMethod = .push
        current.mfaStrategy = .auto
        current.totpSecret = ""
        totpImportFeedback = nil
        withAnimation(.snappy) {
            draft = current
        }
        if current.isProfileSaveReady {
            store.saveProfile(current.profile, secret: current.secret)
        }
    }

    private func applyRule(group: String, pushTarget: String) {
        guard var current = draft else { return }
        current.group = group
        current.duoMethod = .push
        current.mfaStrategy = .auto
        current.pushTarget = pushTarget
        current.totpSecret = ""
        totpImportFeedback = nil
        withAnimation(.snappy) {
            draft = current
        }
        if current.isProfileSaveReady {
            store.saveProfile(current.profile, secret: current.secret)
        }
    }

    private func importTOTPFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            showTOTPImportFailure(TOTPSecretImportError.emptyInput)
            return
        }
        importTOTP(from: text)
    }

    private func importTOTPFromQRCodeSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                showTOTPImportFailure(TOTPQRCodeReaderError.imageNotReadable)
                return
            }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let payload = try TOTPQRCodeReader.firstPayload(in: url)
                importTOTP(from: payload)
            } catch {
                showTOTPImportFailure(error)
            }
        case .failure(let error):
            showTOTPImportFailure(error)
        }
    }

    private func importTOTP(from input: String) {
        do {
            guard var current = draft else { return }
            let configured = try TOTPPasscodeSetup.apply(
                input: input,
                to: current.profile,
                savedSecret: current.secret
            )
            current = ProfileDraft(profile: configured.profile, secret: configured.secret)
            withAnimation(.snappy) {
                advancedExpanded = true
                draft = current
                totpImportFeedback = TOTPImportFeedback(
                    systemImage: "checkmark.seal.fill",
                    tint: .green,
                    title: localized("TOTP 已导入", "TOTP Imported"),
                    message: localized(
                        "已保存 Base32 secret；之后点击 Connect 会自动生成并提交验证码。",
                        "The Base32 secret was saved. Connect will generate and submit the passcode."
                    )
                )
            }
            if current.isProfileSaveReady {
                store.saveProfile(current.profile, secret: current.secret)
            }
        } catch {
            showTOTPImportFailure(error)
        }
    }

    private func showTOTPImportFailure(_ error: Error, title: String? = nil) {
        let title = title ?? localized("TOTP 导入失败", "TOTP Import Failed")
        let message: String
        if let importError = error as? TOTPSecretImportError {
            switch importError {
            case .unsupportedDuoActivationLink:
                message = localized(
                    "这是 DUO 激活链接，不包含 TOTP Base32 secret。当前账号请使用 DUO Push，或在 DUO 设置里获取标准 Authenticator/TOTP 密钥。",
                    "This is a DUO activation link, not a TOTP Base32 secret. Use DUO Push or get a standard Authenticator/TOTP secret."
                )
            case .emptyInput:
                message = localized("剪贴板或图片里没有可导入的 TOTP 内容。", "Clipboard or image does not contain importable TOTP content.")
            case .missingSecret:
                message = localized("这个 otpauth 链接缺少 secret 参数，不能生成验证码。", "This otpauth link is missing the secret parameter.")
            case .invalidBase32Secret:
                message = localized("只支持标准 otpauth://totp/... 或 Base32 secret（A-Z、2-7）。", "Only standard otpauth://totp/... links or Base32 secrets (A-Z, 2-7) are supported.")
            }
        } else if let qrError = error as? TOTPQRCodeReaderError {
            switch qrError {
            case .imageNotReadable:
                message = localized("无法读取截图或图片。请确认 macOS 已允许本 App 录屏，或使用备用图片导入。", "Could not read the screenshot or image. Allow Screen Recording or import a QR image instead.")
            case .qrCodeNotFound:
                message = localized("当前屏幕里没有识别到二维码。请先把标准 otpauth://totp/... 二维码显示在屏幕上，再点自动提取。", "No QR code was found on screen. Show a standard otpauth://totp/... QR code before scanning.")
            }
        } else if let screenError = error as? TOTPScreenQRCodeReaderError {
            message = localized(
                "\(screenError.localizedDescription) 请确认 macOS 已允许本 App 录屏，或使用备用图片导入。",
                "\(screenError.localizedDescription) Allow Screen Recording or import a QR image instead."
            )
        } else {
            message = error.localizedDescription
        }

        showTOTPImportFailureMessage(title: title, message: message)
    }

    private func showTOTPImportFailureMessage(title: String, message: String) {
        withAnimation(.snappy) {
            advancedExpanded = true
            totpImportFeedback = TOTPImportFeedback(
                systemImage: "exclamationmark.triangle.fill",
                tint: .yellow,
                title: title,
                message: message
            )
        }
    }

    private func localized(_ zh: String, _ en: String) -> String {
        switch store.appLanguage {
        case .simplifiedChinese: zh
        case .english: en
        }
    }
}

private struct TOTPImportFeedback {
    let systemImage: String
    let tint: Color
    let title: String
    let message: String
}

private struct NoticeBanner<Action: View>: View {
    let systemImage: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder var action: Action

    init(
        systemImage: String,
        tint: Color,
        title: String,
        message: String,
        @ViewBuilder action: () -> Action
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.title = title
        self.message = message
        self.action = action()
    }

    init(systemImage: String, tint: Color, title: String, message: String) where Action == EmptyView {
        self.systemImage = systemImage
        self.tint = tint
        self.title = title
        self.message = message
        self.action = EmptyView()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
            action
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
