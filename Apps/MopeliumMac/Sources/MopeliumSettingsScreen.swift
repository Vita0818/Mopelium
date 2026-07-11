#if canImport(SwiftUI)
import SwiftUI
import MopeliumCore

struct MopeliumSettingsScreen: View {
    @Environment(\.colorScheme) private var scheme
    @State private var config = MopeliumConfigSnapshot.unavailable
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MopeliumPageHeader(
                    title: "Settings",
                    subtitle: "Provider configuration is read from Mopelium CLI config and environment."
                ) {
                    Button(action: reload) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(MopeliumTheme.accentDeep)
                            .frame(width: 32, height: 32)
                            .background {
                                Circle()
                                    .fill(MopeliumTheme.surface(scheme).opacity(scheme == .dark ? 0.30 : 0.72))
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Reload config")
                }

                if let loadError {
                    SettingsSection(title: "Status") {
                        Text(loadError)
                            .font(MopeliumType.body(13))
                            .foregroundStyle(MopeliumTheme.statusFailed)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsSection(title: "Provider") {
                    MopeliumSettingRow(
                        title: "Base URL",
                        detail: config.providerHost,
                        value: config.baseURLString
                    )
                    MopeliumSettingRow(
                        title: "Model",
                        detail: "active",
                        value: config.model
                    )
                    MopeliumSettingRow(
                        title: "Response Mode",
                        detail: "config",
                        value: config.responseModeLabel
                    )
                }

                SettingsSection(title: "Credentials") {
                    MopeliumSettingRow(
                        title: "API Key Env",
                        detail: "environment",
                        value: config.apiKeyEnv
                    )
                    MopeliumSettingRow(
                        title: "API Key Status",
                        detail: config.apiKeyLoaded ? "loaded" : "missing",
                        value: config.apiKeyLoaded ? "Available from \(config.apiKeyEnv)" : "Not loaded"
                    )
                }

                SettingsSection(title: "Config File") {
                    MopeliumSettingRow(
                        title: "Path",
                        detail: "read/write",
                        value: CLIConfigStore.defaultURL().path
                    )
                    MopeliumSettingRow(
                        title: "API Key Storage",
                        detail: "blocked",
                        value: "API keys are never written to config.json"
                    )
                }

                SettingsSection(title: "About") {
                    MopeliumSettingRow(
                        title: "Version",
                        detail: "local",
                        value: "v0.4 document and web sources"
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
        .task {
            reload()
        }
    }

    private func reload() {
        do {
            config = try MopeliumConfigSnapshot.load()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
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
