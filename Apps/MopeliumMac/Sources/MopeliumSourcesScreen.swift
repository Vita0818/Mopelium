#if canImport(SwiftUI)
import SwiftUI

struct MopeliumSourcesScreen: View {
    private let columns = [
        GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 14, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            MopeliumPageHeader(
                title: "Sources",
                subtitle: "Static preview of future source connectors."
            )
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 14)

            ScrollView {
                LazyVGrid(columns: columns, alignment: .center, spacing: 14) {
                    ForEach(MopeliumMockData.connectors) { connector in
                        SourceConnectorCard(connector: connector)
                    }
                }
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SourceConnectorCard: View {
    let connector: MopeliumSourceConnector
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MopeliumGlassCard(cornerRadius: 20, contentPadding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    MopeliumIconBadge(
                        systemName: connector.icon,
                        status: connector.enabled ? .enabled : .disabled
                    )
                    VStack(alignment: .leading, spacing: 5) {
                        Text(connector.title)
                            .font(MopeliumType.headline(15, .semibold))
                            .foregroundStyle(MopeliumTheme.primaryText(scheme))
                        Text(connector.statusText)
                            .font(MopeliumType.caption(12, .medium))
                            .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                    }
                    Spacer(minLength: 0)
                    MopeliumStatusBadge(
                        status: connector.enabled ? .enabled : .disabled,
                        label: connector.enabled ? "Enabled" : "Disabled"
                    )
                }

                Text(connector.description)
                    .font(MopeliumType.body(13))
                    .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 48, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
struct MopeliumSourcesScreen_Previews: PreviewProvider {
    static var previews: some View {
        MopeliumSourcesScreen()
            .frame(width: 900, height: 700)
    }
}
#endif
#endif
