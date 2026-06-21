import SwiftUI

struct LogPanel: View {
    @EnvironmentObject private var store: VPNAppStore
    @SceneStorage("CiscoVPNMac.logPanel.expanded") private var isExpanded = false

    var body: some View {
        let strings = store.strings

        VStack(alignment: .leading, spacing: 12) {
            header

            if let lastError = store.lastError {
                Text(lastError)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(store.logText.isEmpty ? strings.noDiagnosticLog : strings.logRecorded)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView {
                        Text(store.logText.isEmpty ? strings.noLogEntries : store.logText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(store.logText.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(12)
                    }
                    .frame(minHeight: 180)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button {
                        store.clearLog()
                    } label: {
                        Label(strings.clearLog, systemImage: "trash")
                    }
                }
                .padding(.top, 8)
            } label: {
                Text(isExpanded ? strings.collapseFullLog : strings.expandFullLog)
                    .font(.callout.weight(.medium))
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.snappy, value: isExpanded)
    }

    private var header: some View {
        HStack {
            Label(store.strings.diagnostics, systemImage: "terminal")
                .font(.headline)

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(store.diagnosticText, forType: .string)
            } label: {
                Label(store.strings.copyDiagnostics, systemImage: "doc.on.doc")
            }
            .disabled(store.logText.isEmpty && store.doctorReport == nil)
            .help(store.strings.copyDiagnosticLogHelp)
        }
    }
}
