import CiscoVPNCore
import Foundation

struct AppStrings {
    let appLanguage: AppLanguage

    init(language: AppLanguage) {
        self.appLanguage = language
    }

    private func text(_ zh: String, _ en: String) -> String {
        switch appLanguage {
        case .simplifiedChinese: zh
        case .english: en
        }
    }

    var appName: String { "Cisco VPN AutoConnect" }
    var vpnMenu: String { text("VPN", "VPN") }
    var refresh: String { text("刷新", "Refresh") }
    var doctor: String { text("诊断", "Doctor") }
    var runDoctor: String { text("运行诊断", "Run Doctor") }
    var connect: String { text("连接", "Connect") }
    var connecting: String { text("正在连接...", "Connecting...") }
    var disconnect: String { text("断开", "Disconnect") }
    var settings: String { text("设置", "Settings") }
    var language: String { text("语言", "Language") }
    var chooseLanguage: String { text("切换整个 App 的语言", "Change the language for the whole app") }
    var profiles: String { text("配置", "Profiles") }
    var add: String { text("添加", "Add") }
    var delete: String { text("删除", "Delete") }
    var customVPN: String { text("自定义 VPN", "Custom VPN") }
    var importURLSubscription: String { text("导入 URL 订阅", "Import URL Subscription") }
    var importSubscriptionTitle: String { text("导入 VPN Profile 订阅", "Import VPN Profile Subscription") }
    var subscriptionURL: String { text("订阅 URL", "Subscription URL") }
    var subscriptionURLPlaceholder: String { "https://example.edu/vpn-profiles.json" }
    var subscriptionHelp: String {
        text(
            "只导入 VPN Profile 元数据，例如名称、服务器、Group、端口和 DUO 设置。不会导入平台账号、密码、TOTP secret 或 token。",
            "Imports VPN profile metadata only: name, server, group, port, and DUO settings. It never imports usernames, passwords, TOTP secrets, or tokens."
        )
    }
    var subscriptionSecurityNote: String {
        text(
            "远程订阅必须使用 HTTPS；本机调试允许 localhost HTTP。",
            "Remote subscriptions must use HTTPS; localhost HTTP is allowed for local testing."
        )
    }
    var importNow: String { text("导入", "Import") }
    var cancel: String { text("取消", "Cancel") }
    var noProfileTitle: String { text("未选择配置", "No Profile Selected") }
    var noServer: String { text("未填写服务器", "No server") }
    var notFound: String { text("未找到", "Not found") }
    var doctorNotRunDiagnostic: String { text("Doctor: 未运行", "Doctor: not run") }
    var logsLabel: String { text("日志", "Logs") }

    var statusConnected: String { text("已连接", "Connected") }
    var statusDisconnected: String { text("未连接", "Disconnected") }
    var statusChecking: String { text("正在检查", "Checking") }
    var metricProfile: String { text("配置", "Profile") }
    var metricIPv4: String { "IPv4" }
    var metricDuration: String { text("时长", "Duration") }
    var metricRemaining: String { text("剩余", "Remaining") }
    var metricCisco: String { "Cisco" }
    var metricMFA: String { "MFA" }
    var metricCredentials: String { text("凭据", "Credentials") }
    var credentialNoProfile: String { text("未选择配置", "No profile") }
    var credentialUsernameSaved: String { text("NetID 已保存", "username saved") }
    var credentialNoUsername: String { text("未保存 NetID", "no username") }
    var credentialPasswordSaved: String { text("密码已保存", "password saved") }
    var credentialNoPassword: String { text("未保存密码", "no password") }
    var credentialTOTPSaved: String { text("TOTP 已保存", "TOTP saved") }
    var credentialNoTOTP: String { text("未保存 TOTP", "no TOTP") }

    var oneClickTitle: String { text("一键连接", "One-Click Connect") }
    var duoPushRecommended: String { text("推荐 DUO Push", "DUO Push Recommended") }
    var needsAttention: String { text("需要处理", "Needs Attention") }
    var recommendDuoPushTitle: String { text("建议切回 DUO Push", "Switch Back To DUO Push") }
    var recommendDuoPushMessage: String {
        text(
            "TOTP 获取不稳定。DKU/Duke 日常推荐直接用手机 DUO Push 审批。",
            "TOTP setup is unreliable. DKU/Duke daily use should prefer DUO Push approval on your phone."
        )
    }
    var useDuoPush: String { text("使用 DUO Push", "Use DUO Push") }
    var netID: String { "NetID" }
    var netIDPlaceholder: String { text("你的 NetID", "your NetID") }
    var password: String { "Password" }
    var showPassword: String { text("显示密码", "Show password") }
    var hidePassword: String { text("隐藏密码", "Hide password") }
    var passwordHiddenWarning: String {
        text(
            "Password 会原样提交；请确认没有中文输入法、全角标点、首尾空格、换行或隐藏控制字符。",
            "Password is submitted exactly as typed. Check for non-English input, full-width punctuation, leading/trailing spaces, newlines, or hidden control characters."
        )
    }
    var duo: String { "DUO" }
    var duoPushSummary: String {
        text(
            "DUO Push：自动识别 MFA，手机 Approve",
            "DUO Push: auto-detect MFA, approve on phone"
        )
    }
    var duoPasscodeSummary: String {
        text(
            "TOTP Passcode：高级备用",
            "TOTP Passcode: advanced fallback"
        )
    }
    var switchLabel: String { text("切换", "Change") }
    var connectionRule: String { text("连接规则", "Connection Rule") }
    var applyRule: String { text("应用规则", "Apply Rule") }
    var ruleDKUDefault: String { text("DKU 默认", "DKU Default") }
    var ruleDKULibrary: String { text("DKU 图书馆资源", "DKU Library Resources") }
    var ruleDukeIntl: String { text("Duke INTL", "Duke INTL") }
    var ruleDuoSecondPhone: String { text("DUO 第二台设备", "DUO Second Device") }
    var ruleAdvancedManual: String { text("高级自定义", "Advanced Manual") }
    var ruleHelp: String {
        text(
            "用预设规则写入 Group、DUO 和 MFA 策略；不需要手写 Cisco 菜单序号。",
            "Use presets to write Group, DUO, and MFA strategy. No Cisco menu-number editing required."
        )
    }
    var connectAndWaitForDuo: String { text("连接并等待 DUO", "Connect And Wait For DUO") }
    var totpAdvancedOnly: String { text("TOTP 备用导入", "TOTP Backup Import") }
    var totpAdvancedHelp: String { text("TOTP 高级备用方式", "TOTP advanced fallback") }
    var disconnectHelp: String { text("断开 VPN", "Disconnect VPN") }
    var refreshStatusHelp: String { text("刷新状态", "Refresh status") }
    var openIPHelp: String { text("打开 ip.me", "Open ip.me") }
    var missingConnectFields: String { text("请填写 NetID 和 Password", "Enter NetID and Password") }
    var missingTOTPSecret: String { text("TOTP secret 缺失", "TOTP secret missing") }
    var advancedProfileSettings: String { text("高级 Profile 设置", "Advanced Profile Settings") }
    var name: String { text("名称", "Name") }
    var profileID: String { "Profile ID" }
    var server: String { "Server" }
    var group: String { "Group" }
    var port: String { "Port" }
    var vpnProtocol: String { "Protocol" }
    var mfaStrategy: String { text("MFA 策略", "MFA Strategy") }
    var mfaOption: String { text("MFA 选项", "MFA Option") }
    var mfaOptionPlaceholder: String { text("留空=第一台设备；多设备才填 2/3", "Blank=first device; use 2/3 only for multiple devices") }
    var totp: String { "TOTP" }
    var base32Secret: String { "Base32 secret" }
    var saveAdvancedSettings: String { text("保存高级设置", "Save Advanced Settings") }
    var switchBackToDuoPush: String { text("切回 DUO Push", "Switch Back To DUO Push") }
    var resetCurrentCredentials: String { text("重置当前凭据", "Reset Current Credentials") }
    var importFromClipboard: String { text("从剪贴板导入", "Import From Clipboard") }
    var importFromQRImage: String { text("从二维码图片导入", "Import From QR Image") }
    var importTOTP: String { text("导入 TOTP", "Import TOTP") }

    var doctorNotRun: String {
        text(
            "Doctor 尚未运行。运行后会检查 Cisco CLI、expect、Keychain、Profile 和基础诊断。",
            "Doctor has not run yet. It checks Cisco CLI, expect, Keychain, Profile, and basic diagnostics."
        )
    }
    var resetProfileCredentials: String { text("重置当前 Profile 凭据", "Reset Current Profile Credentials") }
    var diagnostics: String { text("诊断", "Diagnostics") }
    var noDiagnosticLog: String { text("暂无诊断日志", "No diagnostic log yet") }
    var logRecorded: String { text("日志已记录，需要时可展开查看。", "Logs are recorded. Expand when needed.") }
    var noLogEntries: String { text("No log entries", "No log entries") }
    var clearLog: String { text("清空日志", "Clear Log") }
    var collapseFullLog: String { text("收起完整日志", "Collapse Full Log") }
    var expandFullLog: String { text("展开完整日志", "Expand Full Log") }
    var copyDiagnostics: String { text("复制诊断日志", "Copy Diagnostics") }
    var copyDiagnosticLogHelp: String { text("复制诊断日志", "Copy diagnostic log") }
    var ciscoCLI: String { "Cisco CLI" }
    var override: String { text("覆盖路径", "Override") }

    var invalidSubscriptionURL: String {
        text(
            "请输入有效的 HTTPS 订阅 URL。本机调试可使用 http://localhost。",
            "Enter a valid HTTPS subscription URL. http://localhost is allowed for local testing."
        )
    }
    var importingSubscription: String { text("正在导入订阅", "Importing subscription") }
    func subscriptionImportSuccess(count: Int, source: String) -> String {
        text(
            "已从 \(source) 导入 \(count) 个 VPN Profile。",
            "Imported \(count) VPN profile(s) from \(source)."
        )
    }

    func duoMethodTitle(_ method: DuoMethod) -> String {
        switch method {
        case .push: "DUO Push"
        case .passcode: "TOTP Passcode"
        }
    }

    func mfaStrategyTitle(_ strategy: MFAInjectionStrategy) -> String {
        switch strategy {
        case .auto: text("自动", "Auto")
        case .numericMenu: text("数字菜单", "Numeric Menu")
        case .secondPassword: text("第二密码", "Second Password")
        case .passwordAppend: "Password Append"
        case .waitOnly: text("只等待", "Wait Only")
        case .passcode: "Passcode"
        }
    }

    func mfaStrategySummary(_ strategy: MFAInjectionStrategy) -> String {
        switch strategy {
        case .auto:
            text("自动识别 Cisco/Duo 提示，并选择最安全的响应。", "Detect Cisco/Duo prompts and choose the safest response.")
        case .numericMenu:
            text("Cisco 显示数字菜单时发送保存的 Duo 菜单选项。", "Send the saved Duo menu option when Cisco shows a numeric menu.")
        case .secondPassword:
            text("在 Second Password 提示处发送 push/push2 或 TOTP code。", "Send push/push2 or the TOTP code at a second-password prompt.")
        case .passwordAppend:
            text("把 ,push、,push2 或 ,code 拼到主密码字段后面。", "Append ,push, ,push2, or ,code to the primary password field.")
        case .waitOnly:
            text("只发送主密码，等待服务器自动触发 DUO Push。", "Send only the primary password and wait for server-triggered DUO Push.")
        case .passcode:
            text("优先在 MFA 提示处发送自动生成的 passcode。", "Prefer a generated passcode at MFA prompts.")
        }
    }

    func resetCredentialsMessage() -> String {
        text(
            "已删除当前 Profile 的 Keychain 凭据；Profile metadata 已保留。",
            "Deleted the current profile's Keychain credentials; profile metadata was kept."
        )
    }
}
