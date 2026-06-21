import SwiftUI

struct StatusCard: View {
    @EnvironmentObject private var store: VPNAppStore

    var body: some View {
        let strings = store.strings

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 14, height: 14)
                    .shadow(color: statusColor.opacity(0.35), radius: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.title2.weight(.semibold))
                    Text(store.status.server ?? store.selectedProfile?.server ?? store.detectedBinaryPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if store.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    MetricPill(title: strings.metricProfile, value: store.selectedProfile?.displayName ?? "-")
                    MetricPill(title: strings.metricIPv4, value: store.status.clientIPv4 ?? "-")
                    MetricPill(title: strings.metricDuration, value: store.status.duration ?? "00:00:00")
                    MetricPill(title: strings.metricRemaining, value: store.status.remaining ?? "-")
                }

                HStack(spacing: 12) {
                    MetricPill(title: strings.metricCisco, value: store.detectedBinaryPath)
                    MetricPill(
                        title: strings.metricMFA,
                        value: store.selectedProfile.map { strings.mfaStrategyTitle($0.mfaStrategy) } ?? "-"
                    )
                    MetricPill(title: strings.metricCredentials, value: store.credentialSummary(for: store.selectedProfile))
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusTitle: String {
        switch store.status.state {
        case .connected: store.strings.statusConnected
        case .disconnected: store.strings.statusDisconnected
        case .unknown: store.strings.statusChecking
        }
    }

    private var statusColor: Color {
        switch store.status.state {
        case .connected: .green
        case .disconnected: .red
        case .unknown: .yellow
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
