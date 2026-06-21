import AppKit
import CiscoVPNCore
import SwiftUI
import UniformTypeIdentifiers

struct TOTPAutoConnectSheet: View {
    @EnvironmentObject private var store: VPNAppStore
    @Environment(\.dismiss) private var dismiss

    let draft: ProfileDraft
    let onConfigured: (VPNProfile, SavedVPNSecret) -> Void

    @State private var manualInput = ""
    @State private var extractState = TOTPAutoConnectStepState.pending
    @State private var saveState = TOTPAutoConnectStepState.pending
    @State private var connectState = TOTPAutoConnectStepState.pending
    @State private var feedback: TOTPAutoConnectFeedback?
    @State private var isQRCodeImporterPresented = false
    @State private var isWorking = false

    private var hasCredentials: Bool {
        !draft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.password.isEmpty
    }

    private var credentialGuidance: String? {
        draft.credentialDiagnostics.actionGuidance
    }

    private var canRunTOTPFlow: Bool {
        hasCredentials && credentialGuidance == nil && !isWorking && !store.isBusy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            steps
            Divider()
            inputArea

            if let feedback {
                feedbackBanner(feedback)
            }

            footer
        }
        .padding(22)
        .frame(width: 560)
        .fileImporter(
            isPresented: $isQRCodeImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
            onCompletion: importTOTPFromQRCodeSelection
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("配置 TOTP 并连接", systemImage: "key.radiowaves.forward")
                .font(.title3.weight(.semibold))
            Text("自动扫描当前屏幕上的 TOTP 二维码，提取密钥、保存到 Keychain，然后开始连接。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            TOTPAutoConnectStepRow(
                number: 1,
                title: "提取密钥",
                detail: "优先从当前屏幕截图识别二维码，也支持剪贴板、图片文件或手动 Base32。",
                state: extractState
            )
            TOTPAutoConnectStepRow(
                number: 2,
                title: "保存密钥",
                detail: "保存到 macOS Keychain，并把当前 Profile 切到 TOTP Passcode。",
                state: saveState
            )
            TOTPAutoConnectStepRow(
                number: 3,
                title: "全自动连接",
                detail: "调用现有 Connect；App 会生成 6 位验证码并提交给 Cisco。",
                state: connectState
            )
        }
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !hasCredentials {
                Label("请先在主界面填写 NetID 和 Password；三位一体流程需要保存后立刻连接。", systemImage: "person.badge.key")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let credentialGuidance {
                Label("\(credentialGuidance) 请先在主界面重新输入 Password。", systemImage: "keyboard.badge.ellipsis")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                importFromCurrentScreen()
            } label: {
                Label("自动扫描当前屏幕并连接", systemImage: "viewfinder.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canRunTOTPFlow)

            HStack(spacing: 10) {
                Button {
                    importFromPasteboard()
                } label: {
                    Label("剪贴板备用", systemImage: "doc.on.clipboard")
                }
                .disabled(!canRunTOTPFlow)

                Button {
                    isQRCodeImporterPresented = true
                } label: {
                    Label("选择图片备用", systemImage: "qrcode.viewfinder")
                }
                .disabled(!canRunTOTPFlow)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("已有 Base32 或 otpauth 链接")
                    .font(.callout.weight(.medium))
                SecureField("粘贴 otpauth://totp/... 或 Base32 secret", text: $manualInput)
                    .textFieldStyle(.roundedBorder)

                Button {
                    saveAndConnect(input: manualInput)
                } label: {
                    Label("使用上方内容并连接", systemImage: "bolt.horizontal.circle.fill")
                }
                .disabled(!canRunTOTPFlow || manualInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("不会显示、复制或写入日志中的 TOTP secret；只能看到保存状态。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("关闭") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    private func feedbackBanner(_ feedback: TOTPAutoConnectFeedback) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: feedback.systemImage)
                .foregroundStyle(feedback.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(feedback.title)
                    .font(.callout.weight(.semibold))
                Text(feedback.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(feedback.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func importFromPasteboard() {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saveAndConnect(input: text)
            return
        }

        do {
            let payload = try TOTPQRCodeReader.firstPayload(in: pasteboard)
            saveAndConnect(input: payload)
        } catch {
            showFailure(
                title: "剪贴板不可用",
                message: "剪贴板里没有可用的 otpauth 链接、Base32 secret 或二维码图片。"
            )
        }
    }

    private func importFromCurrentScreen() {
        do {
            let payload = try TOTPScreenQRCodeReader.firstPayloadFromCurrentScreen()
            saveAndConnect(input: payload)
        } catch {
            showFailure(title: "屏幕扫描失败", message: userMessage(for: error))
        }
    }

    private func importTOTPFromQRCodeSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                showFailure(title: "二维码读取失败", message: "没有选择可读取的图片。")
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
                saveAndConnect(input: payload)
            } catch {
                showFailure(title: "二维码读取失败", message: userMessage(for: error))
            }
        case .failure(let error):
            showFailure(title: "二维码读取失败", message: userMessage(for: error))
        }
    }

    private func saveAndConnect(input: String) {
        guard !isWorking else { return }
        isWorking = true
        extractState = .working
        saveState = .pending
        connectState = .pending
        feedback = nil

        do {
            _ = try TOTPSecretImporter.secret(from: input)
            extractState = .done
            saveState = .working
            let configured = try store.saveTOTPAndEnablePasscode(
                profile: draft.profile,
                savedSecret: draft.secret,
                input: input
            )
            onConfigured(configured.profile, configured.secret)
            saveState = .done
            connectState = .working
            store.connectSelected()
            connectState = .done
            feedback = TOTPAutoConnectFeedback(
                systemImage: "checkmark.seal.fill",
                tint: .green,
                title: "TOTP 已保存，已开始连接",
                message: "当前 Profile 已切到 TOTP Passcode。连接日志会继续在主窗口更新。"
            )
        } catch {
            if extractState == .working {
                extractState = .failed
            } else if saveState == .working {
                saveState = .failed
            } else {
                connectState = .failed
            }
            showFailure(title: "TOTP 配置失败", message: userMessage(for: error))
        }

        isWorking = false
    }

    private func showFailure(title: String, message: String) {
        feedback = TOTPAutoConnectFeedback(
            systemImage: "exclamationmark.triangle.fill",
            tint: .yellow,
            title: title,
            message: message
        )
    }

    private func userMessage(for error: Error) -> String {
        if let importError = error as? TOTPSecretImportError {
            switch importError {
            case .unsupportedDuoActivationLink:
                return "这是 DUO 激活链接，不包含 TOTP Base32 secret。这个账号请使用 DUO Push，或获取标准 otpauth://totp/... 密钥。"
            case .emptyInput:
                return "没有可导入的 TOTP 内容。"
            case .missingSecret:
                return "这个 otpauth 链接缺少 secret 参数，不能生成验证码。"
            case .invalidBase32Secret:
                return "只支持标准 otpauth://totp/... 或 Base32 secret（A-Z、2-7）。"
            }
        }
        if let qrError = error as? TOTPQRCodeReaderError {
            switch qrError {
            case .imageNotReadable:
                return "无法读取截图或图片。请确认 macOS 已允许本 App 录屏，或改用选择二维码图片。"
            case .qrCodeNotFound:
                return "当前屏幕里没有识别到二维码。请先把标准 otpauth://totp/... 二维码显示在屏幕上，再点自动扫描。"
            }
        }
        if let screenError = error as? TOTPScreenQRCodeReaderError {
            return "\(screenError.localizedDescription) 请确认 macOS 已允许本 App 录屏，或改用二维码图片。"
        }
        return error.localizedDescription
    }
}

private enum TOTPAutoConnectStepState {
    case pending
    case working
    case done
    case failed

    var title: String {
        switch self {
        case .pending: "待执行"
        case .working: "进行中"
        case .done: "完成"
        case .failed: "失败"
        }
    }

    var systemImage: String {
        switch self {
        case .pending: "circle"
        case .working: "arrow.triangle.2.circlepath"
        case .done: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pending: .secondary
        case .working: .blue
        case .done: .green
        case .failed: .yellow
        }
    }

    var badgeFill: Color {
        switch self {
        case .pending: .gray
        case .working: .blue
        case .done: .green
        case .failed: .yellow
        }
    }
}

private struct TOTPAutoConnectStepRow: View {
    let number: Int
    let title: String
    let detail: String
    let state: TOTPAutoConnectStepState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(state.badgeFill))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Label(state.title, systemImage: state.systemImage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(state.tint)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct TOTPAutoConnectFeedback {
    let systemImage: String
    let tint: Color
    let title: String
    let message: String
}
