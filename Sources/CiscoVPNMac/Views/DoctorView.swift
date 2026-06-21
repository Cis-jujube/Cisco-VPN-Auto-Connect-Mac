import CiscoVPNCore
import SwiftUI

struct DoctorView: View {
    @EnvironmentObject private var store: VPNAppStore

    var body: some View {
        let strings = store.strings

        VStack(alignment: .leading, spacing: 12) {
            header

            if let report = store.doctorReport {
                VStack(spacing: 8) {
                    ForEach(report.checks) { check in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: icon(for: check.status))
                                .foregroundStyle(color(for: check.status))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(check.title)
                                    .font(.callout.weight(.semibold))
                                Text(check.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                if check.id == "password-diagnostics", check.status == .warning {
                                    Button(role: .destructive) {
                                        store.resetSelectedCredentials()
                                    } label: {
                                        Label(strings.resetProfileCredentials, systemImage: "key.slash")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .padding(.top, 4)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                }
            } else {
                Text(strings.doctorNotRun)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var header: some View {
        HStack {
            Label(store.strings.doctor, systemImage: "stethoscope")
                .font(.headline)
            Spacer()
            Button {
                store.runDoctor()
            } label: {
                Label(store.strings.runDoctor, systemImage: "play.circle")
            }
            .disabled(store.isBusy)
        }
    }

    private func icon(for status: CiscoVPNDoctorCheckStatus) -> String {
        switch status {
        case .pass: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .fail: "xmark.octagon.fill"
        case .skipped: "minus.circle.fill"
        }
    }

    private func color(for status: CiscoVPNDoctorCheckStatus) -> Color {
        switch status {
        case .pass: .green
        case .warning: .orange
        case .fail: .red
        case .skipped: .secondary
        }
    }
}
