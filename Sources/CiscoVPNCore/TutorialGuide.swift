import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .simplifiedChinese: "中文"
        case .english: "English"
        }
    }
}

public struct TutorialSection: Equatable, Sendable {
    public let title: String
    public let systemImage: String
    public let items: [String]

    public init(title: String, systemImage: String, items: [String]) {
        self.title = title
        self.systemImage = systemImage
        self.items = items
    }
}

public struct TutorialContent: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let sections: [TutorialSection]

    public init(title: String, subtitle: String, sections: [TutorialSection]) {
        self.title = title
        self.subtitle = subtitle
        self.sections = sections
    }
}

public enum TutorialGuide {
    public static func content(for language: AppLanguage) -> TutorialContent {
        switch language {
        case .simplifiedChinese:
            TutorialContent(
                title: "使用教程",
                subtitle: "按顺序完成配置，默认用 DUO Push 连接 Cisco Secure Client；TOTP 仅作为高级备用。",
                sections: [
                    TutorialSection(
                        title: "1. 配置 Profile",
                        systemImage: "slider.horizontal.3",
                        items: [
                            "选择 DKU VPN、Duke VPN，或在左下角 Add 新建 Custom VPN。",
                            "确认 Server、Group、Port 和 Protocol。DKU 默认使用 portal.dukekunshan.edu.cn。",
                            "填写 NetID 和 Password，然后点 Save。密码会保存到 macOS Keychain。"
                        ]
                    ),
                    TutorialSection(
                        title: "2. 选择 DUO 方式",
                        systemImage: "checkmark.shield",
                        items: [
                            "DUO Push 是推荐路径：App 会自动识别 Cisco 的 MFA 提示，选择数字菜单、push/push2，或等待自动 Push。",
                            "TOTP Passcode 放在高级设置里，仅用于你已经有标准 Base32 TOTP secret 的情况。",
                            "MFA 选项可留空；只有多个 Duo 设备时，才填 2 或 3。它不是手机号尾号。"
                        ]
                    ),
                    TutorialSection(
                        title: "3. 连接与排错",
                        systemImage: "bolt.horizontal.circle",
                        items: [
                            "点 Connect 开始连接；点 Refresh 查看 Cisco Secure Client 当前状态。",
                            "连接失败时先检查 Cisco Secure Client 是否已安装，CLI 路径应为 /opt/cisco/secureclient/bin/vpn。",
                            "Log 面板会显示执行过程，但会遮蔽用户名、密码和 TOTP secret。"
                        ]
                    )
                ]
            )
        case .english:
            TutorialContent(
                title: "Quick Guide",
                subtitle: "Complete the profile, then connect with DUO Push by default. TOTP is kept as an advanced fallback.",
                sections: [
                    TutorialSection(
                        title: "1. Set Up A Profile",
                        systemImage: "slider.horizontal.3",
                        items: [
                            "Choose DKU VPN, Duke VPN, or use Add in the sidebar to create a Custom VPN.",
                            "Confirm Server, Group, Port, and Protocol. DKU defaults to portal.dukekunshan.edu.cn.",
                            "Enter NetID and Password, then click Save. The password is stored in macOS Keychain."
                        ]
                    ),
                    TutorialSection(
                        title: "2. Choose DUO Method",
                        systemImage: "checkmark.shield",
                        items: [
                            "DUO Push is recommended: the app detects Cisco's MFA style and uses numeric options, push/push2, or auto-push wait as needed.",
                            "TOTP Passcode lives in Advanced settings and is only for accounts that already have a standard Base32 TOTP secret.",
                            "Leave the MFA option blank by default. Only enter 2 or 3 when your Duo account has multiple devices."
                        ]
                    ),
                    TutorialSection(
                        title: "3. Connect And Troubleshoot",
                        systemImage: "bolt.horizontal.circle",
                        items: [
                            "Click Connect to start; click Refresh to read the current Cisco Secure Client status.",
                            "If connection fails, confirm Cisco Secure Client is installed and /opt/cisco/secureclient/bin/vpn exists.",
                            "The Log panel shows command progress while masking username, password, and TOTP secret values."
                        ]
                    )
                ]
            )
        }
    }
}
