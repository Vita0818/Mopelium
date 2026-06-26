#if canImport(SwiftUI)
import SwiftUI

struct MopeliumResearchScreen: View {
    @Environment(\.colorScheme) private var scheme
    @State private var prompt = ""

    var body: some View {
        VStack(spacing: 0) {
            MopeliumPageHeader(
                title: "Research",
                subtitle: "Search, filter, and summarize across user-defined directions."
            ) {
                MopeliumStatusBadge(status: .local, label: "Local v0.2")
                    .padding(.top, 3)
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 14)

            ScrollView {
                LazyVStack(spacing: 14) {
                    ActiveQueryCard(query: MopeliumMockData.activeQuery)
                    ResultSummaryCard(summary: MopeliumMockData.summary)
                    ForEach(MopeliumMockData.sourceSnippets) { snippet in
                        SourceSnippetCard(snippet: snippet)
                    }
                }
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
            }
            .scrollContentBackground(.hidden)

            MopeliumComposer(
                text: $prompt,
                placeholder: "Ask Mopelium to explore a direction..."
            )
            .frame(maxWidth: 900)
            .padding(.horizontal, 30)
            .padding(.top, 10)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ActiveQueryCard: View {
    let query: MopeliumResearchQuery
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MopeliumGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    MopeliumIconBadge(systemName: "magnifyingglass", status: .running)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(query.title)
                            .font(MopeliumType.headline(16, .semibold))
                            .foregroundStyle(MopeliumTheme.primaryText(scheme))
                        Text("\(query.sourceCount) sources")
                            .font(MopeliumType.caption(12, .medium))
                            .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                    }
                    Spacer(minLength: 0)
                    MopeliumStatusBadge(status: query.status, label: "Running")
                }

                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: query.progress)
                        .tint(MopeliumTheme.accent)
                    Text(query.progressText)
                        .font(MopeliumType.caption(12, .medium))
                        .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                }
            }
        }
    }
}

private struct ResultSummaryCard: View {
    let summary: MopeliumResultSummary
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MopeliumGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    MopeliumIconBadge(systemName: "sparkle.magnifyingglass", status: .done)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(summary.title)
                            .font(MopeliumType.headline(16, .semibold))
                            .foregroundStyle(MopeliumTheme.primaryText(scheme))
                        Text(summary.summary)
                            .font(MopeliumType.body(14))
                            .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    MopeliumStatusBadge(status: .done, label: summary.confidence)
                }

                HStack(spacing: 8) {
                    ForEach(summary.chips, id: \.self) { chip in
                        MopeliumStatusBadge(status: .local, label: chip)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct SourceSnippetCard: View {
    let snippet: MopeliumSourceSnippet
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MopeliumGlassCard(cornerRadius: 20, contentPadding: 18) {
            HStack(alignment: .top, spacing: 12) {
                MopeliumIconBadge(systemName: "safari", status: snippet.status)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(snippet.title)
                            .font(MopeliumType.headline(15, .semibold))
                            .foregroundStyle(MopeliumTheme.primaryText(scheme))
                        Spacer(minLength: 0)
                        MopeliumStatusBadge(status: snippet.status, label: snippet.status == .queued ? "Queued" : "Indexed")
                    }
                    Text(snippet.domain)
                        .font(MopeliumType.mono(12))
                        .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
                    Text(snippet.excerpt)
                        .font(MopeliumType.body(13))
                        .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#if DEBUG
struct MopeliumResearchScreen_Previews: PreviewProvider {
    static var previews: some View {
        MopeliumResearchScreen()
            .frame(width: 900, height: 700)
    }
}
#endif
#endif
