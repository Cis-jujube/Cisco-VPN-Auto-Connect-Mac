import CiscoVPNCore
import SwiftUI

struct TutorialCard: View {
    @EnvironmentObject private var store: VPNAppStore

    var body: some View {
        let content = store.tutorialContent
        let strings = store.strings

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(content.title, systemImage: "questionmark.circle")
                        .font(.headline)

                    Text(content.subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                Picker(strings.language, selection: $store.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .labelsHidden()
                .help(strings.chooseLanguage)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(content.sections.enumerated()), id: \.offset) { _, section in
                    TutorialSectionView(section: section)
                    if section != content.sections.last {
                        Divider()
                    }
                }
            }
            .id(store.appLanguage)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.snappy, value: store.appLanguage)
    }
}

private struct TutorialSectionView: View {
    let section: TutorialSection

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Image(systemName: section.systemImage)
                    .foregroundStyle(.blue)
                    .frame(width: 20)

                Text(section.title)
                    .font(.callout.weight(.semibold))
            }

            ForEach(section.items, id: \.self) { item in
                GridRow {
                    Text("")
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 4, height: 4)
                        Text(item)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
