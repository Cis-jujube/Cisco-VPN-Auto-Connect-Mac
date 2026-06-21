import CiscoVPNCore
import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var store: VPNAppStore

    var body: some View {
        let strings = store.strings

        VStack(spacing: 0) {
            StatusCard()
                .padding([.top, .horizontal], 22)
                .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let profile = store.selectedProfile {
                        ProfileEditor(profile: profile)
                    } else {
                        ContentUnavailableView(
                            strings.noProfileTitle,
                            systemImage: "network.slash"
                        )
                        .frame(maxWidth: .infinity, minHeight: 260)
                    }

                    DoctorView()
                    TutorialCard()
                    LogPanel()
                }
                .padding(22)
            }
        }
        .background(.background)
    }
}
