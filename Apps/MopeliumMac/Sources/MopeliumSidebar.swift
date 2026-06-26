#if canImport(SwiftUI)
import SwiftUI

struct MopeliumSidebar: View {
    @Binding var selection: MopeliumSection
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Mopelium")
                    .font(MopeliumType.brand(29))
                    .foregroundStyle(MopeliumTheme.primaryText(scheme))
                Text("Search Console")
                    .font(MopeliumType.caption(12, .semibold))
                    .foregroundStyle(MopeliumTheme.secondaryText(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 18)

            VStack(spacing: 6) {
                ForEach(MopeliumSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        MopeliumSidebarRow(section: section, selected: selection == section)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 6) {
                MopeliumStatusBadge(status: .local, label: "Local v0.2")
                Text("Static UI skeleton")
                    .font(MopeliumType.caption(11, .medium))
                    .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background {
            Rectangle()
                .fill(MopeliumTheme.surface(scheme).opacity(scheme == .dark ? 0.22 : 0.34))
                .background(.thinMaterial)
        }
    }
}
#endif
