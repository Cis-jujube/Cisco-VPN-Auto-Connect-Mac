import SwiftUI

struct SubscriptionImportSheet: View {
    @EnvironmentObject private var store: VPNAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""

    var body: some View {
        let strings = store.strings

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "link.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.importSubscriptionTitle)
                        .font(.title3.weight(.semibold))
                    Text(strings.subscriptionHelp)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(strings.subscriptionURL)
                    .font(.callout.weight(.medium))
                TextField(strings.subscriptionURLPlaceholder, text: $urlString)
                    .textFieldStyle(.roundedBorder)
            }

            Label(strings.subscriptionSecurityNote, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let status = store.subscriptionImportStatus {
                Label(status, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let error = store.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(strings.cancel) {
                    dismiss()
                }
                Button {
                    store.importSubscription(from: urlString)
                } label: {
                    if store.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(strings.importNow)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isBusy)
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}
