import CiscoVPNCore
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: VPNAppStore
    @State private var isSubscriptionImporterPresented = false

    var body: some View {
        let strings = store.strings

        VStack(spacing: 0) {
            List(selection: Binding(
                get: { store.selectedProfileID },
                set: { store.select($0) }
            )) {
                Section(strings.profiles) {
                    ForEach(store.profiles) { profile in
                        ProfileRow(
                            profile: profile,
                            isActive: profile.id == store.selectedProfileID,
                            strings: strings
                        )
                            .tag(Optional(profile.id))
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Menu {
                    Button {
                        store.saveProfile(.dkuDefault, secret: nil)
                    } label: {
                        Label("DKU VPN", systemImage: "building.columns")
                    }

                    Button {
                        store.saveProfile(.dukeDefault, secret: nil)
                    } label: {
                        Label("Duke VPN", systemImage: "graduationcap")
                    }

                    Divider()

                    Button {
                        store.makeCustomProfile()
                    } label: {
                        Label(strings.customVPN, systemImage: "plus")
                    }

                    Divider()

                    Button {
                        isSubscriptionImporterPresented = true
                    } label: {
                        Label(strings.importURLSubscription, systemImage: "link.badge.plus")
                    }
                } label: {
                    Label(strings.add, systemImage: "plus")
                }
                .menuStyle(.borderlessButton)

                Spacer()

                Button {
                    store.deleteSelectedProfile()
                } label: {
                    Label(strings.delete, systemImage: "trash")
                }
                .disabled(store.selectedProfile == nil)
            }
            .padding(12)
        }
        .sheet(isPresented: $isSubscriptionImporterPresented) {
            SubscriptionImportSheet()
                .environmentObject(store)
        }
    }
}

private struct ProfileRow: View {
    let profile: VPNProfile
    let isActive: Bool
    let strings: AppStrings

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(isActive ? .blue : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .lineLimit(1)
                Text(profile.server.isEmpty ? strings.noServer : profile.server)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var icon: String {
        switch profile.id {
        case "dku": "building.columns.fill"
        case "duke": "graduationcap.fill"
        default: "network"
        }
    }
}
