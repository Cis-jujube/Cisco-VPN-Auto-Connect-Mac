import CiscoVPNCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: VPNAppStore

    var body: some View {
        let strings = store.strings

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            DetailView()
        }
        .toolbar {
            ToolbarItemGroup {
                Picker(strings.language, selection: $store.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .help(strings.chooseLanguage)

                Button {
                    store.refreshStatus()
                } label: {
                    Label(strings.refresh, systemImage: "arrow.clockwise")
                }
                .disabled(store.isBusy)

                Button {
                    store.runDoctor()
                } label: {
                    Label(strings.doctor, systemImage: "stethoscope")
                }
                .disabled(store.isBusy)

                Button {
                    store.connectSelected()
                } label: {
                    Label(strings.connect, systemImage: "bolt.horizontal.circle.fill")
                }
                .disabled(store.selectedProfile == nil || store.isBusy)

                Button {
                    store.disconnect()
                } label: {
                    Label(strings.disconnect, systemImage: "xmark.circle")
                }
                .disabled(store.isBusy)
            }
        }
        .onAppear {
            store.refreshStatus()
        }
        .alert(strings.appName, isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK") {
                store.lastError = nil
            }
        } message: {
            Text(store.lastError ?? "")
        }
    }
}
