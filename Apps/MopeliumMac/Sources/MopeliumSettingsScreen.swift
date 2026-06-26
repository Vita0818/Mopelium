#if canImport(SwiftUI)
import SwiftUI

struct MopeliumSettingsScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MopeliumPageHeader(
                    title: "Settings",
                    subtitle: "Local UI only. No provider calls or config writes in v0.2."
                )

                SettingsSection(title: "Provider") {
                    MopeliumSettingRow(
                        title: "Base URL",
                        detail: "placeholder",
                        value: "https://api.openai.com/v1"
                    )
                    MopeliumSettingRow(
                        title: "Model",
                        detail: "placeholder",
                        value: "gpt-4o-mini"
                    )
                    MopeliumSettingRow(
                        title: "API Key Env",
                        detail: "not read",
                        value: "MOPELIUM_API_KEY"
                    )
                }

                SettingsSection(title: "Appearance") {
                    MopeliumSettingRow(
                        title: "Accent",
                        detail: "static",
                        value: "Mist"
                    )
                    MopeliumSettingRow(
                        title: "Material",
                        detail: "static",
                        value: "Glass"
                    )
                }

                SettingsSection(title: "About") {
                    MopeliumSettingRow(
                        title: "Version",
                        detail: "local",
                        value: "v0.2 UI skeleton"
                    )
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 30)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    private let content: Content
    @Environment(\.colorScheme) private var scheme

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        MopeliumGlassCard(cornerRadius: 24, contentPadding: 22) {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(MopeliumType.headline(16, .semibold))
                    .foregroundStyle(MopeliumTheme.primaryText(scheme))
                content
            }
        }
    }
}

#if DEBUG
struct MopeliumSettingsScreen_Previews: PreviewProvider {
    static var previews: some View {
        MopeliumSettingsScreen()
            .frame(width: 900, height: 700)
    }
}
#endif
#endif
