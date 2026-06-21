import CiscoVPNCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct CiscoVPNMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = VPNAppStore()

    var body: some Scene {
        WindowGroup(store.strings.appName) {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 660)
        }
        .commands {
            CommandMenu(store.strings.vpnMenu) {
                Button(store.strings.connect) {
                    store.connectSelected()
                }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(store.selectedProfile == nil || store.isBusy)

                Button(store.strings.disconnect) {
                    store.disconnect()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(store.isBusy)

                Divider()

                Button(store.strings.refresh) {
                    store.refreshStatus()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(store.isBusy)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 520)
        }
    }
}
