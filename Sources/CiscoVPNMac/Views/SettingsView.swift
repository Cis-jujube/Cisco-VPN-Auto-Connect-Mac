import CiscoVPNCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: VPNAppStore

    var body: some View {
        let strings = store.strings

        Form {
            Picker(strings.language, selection: $store.appLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }

            LabeledContent(strings.ciscoCLI) {
                Text(store.detectedBinaryPath)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            LabeledContent(strings.override) {
                Text("CISCO_VPN_BIN")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
