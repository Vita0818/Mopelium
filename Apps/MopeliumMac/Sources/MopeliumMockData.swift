#if canImport(SwiftUI)
import Foundation

struct MopeliumResearchQuery: Identifiable {
    let id = UUID()
    let title: String
    let status: MopeliumStatus
    let sourceCount: Int
    let progress: Double
    let progressText: String
}

struct MopeliumResultSummary: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let chips: [String]
    let confidence: String
}

struct MopeliumSourceSnippet: Identifiable {
    let id = UUID()
    let title: String
    let domain: String
    let excerpt: String
    let status: MopeliumStatus
}

struct MopeliumTaskItem: Identifiable {
    let id = UUID()
    let title: String
    let trigger: String
    let status: MopeliumStatus
    let lastRun: String
    let metadata: String
}

struct MopeliumSourceConnector: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
    let enabled: Bool
    let statusText: String
}

enum MopeliumMockData {
    static let activeQuery = MopeliumResearchQuery(
        title: "What changed in local-first AI tools this week?",
        status: .running,
        sourceCount: 12,
        progress: 0.62,
        progressText: "Filtering release notes, repos, and short-form posts"
    )

    static let summary = MopeliumResultSummary(
        title: "Local-first tooling is converging on private indexes",
        summary: "Recent updates emphasize file-aware retrieval, smaller on-device models, and cleaner handoff between local context and hosted reasoning. The most useful products are narrowing scope before summarization.",
        chips: ["release notes", "developer blogs", "GitHub"],
        confidence: "Medium confidence"
    )

    static let sourceSnippets: [MopeliumSourceSnippet] = [
        MopeliumSourceSnippet(
            title: "Private workspace indexing patterns",
            domain: "engineering.example.dev",
            excerpt: "Teams are moving indexing closer to the filesystem while keeping ranking policies explicit and auditable.",
            status: .done
        ),
        MopeliumSourceSnippet(
            title: "Small model search rerankers",
            domain: "papers.example.org",
            excerpt: "A compact reranker can remove most low-value documents before a summary model sees the prompt.",
            status: .queued
        ),
        MopeliumSourceSnippet(
            title: "Mac app local context notes",
            domain: "github.com/example/local-ai-notes",
            excerpt: "Native shells increasingly separate source collection, evaluation, and synthesis into visible stages.",
            status: .done
        ),
    ]

    static let tasks: [MopeliumTaskItem] = [
        MopeliumTaskItem(
            title: "AI coding tools weekly scan",
            trigger: "scheduled",
            status: .running,
            lastRun: "Today 09:20",
            metadata: "8 directions · 24 source candidates"
        ),
        MopeliumTaskItem(
            title: "New papers in retrieval-augmented generation",
            trigger: "source update",
            status: .queued,
            lastRun: "Yesterday 18:05",
            metadata: "arXiv + RSS · title and abstract filter"
        ),
        MopeliumTaskItem(
            title: "Mac local model ecosystem",
            trigger: "manual",
            status: .done,
            lastRun: "Jun 24 21:10",
            metadata: "GitHub releases · vendor posts"
        ),
        MopeliumTaskItem(
            title: "ZJU course material watcher",
            trigger: "scheduled",
            status: .failed,
            lastRun: "Jun 23 07:30",
            metadata: "PDF folder · manual notes pending"
        ),
    ]

    static let connectors: [MopeliumSourceConnector] = [
        MopeliumSourceConnector(
            icon: "globe",
            title: "Web",
            description: "Search DuckDuckGo HTML results and fetch HTTP(S) pages into readable research context.",
            enabled: true,
            statusText: "Live in v0.4"
        ),
        MopeliumSourceConnector(
            icon: "dot.radiowaves.left.and.right",
            title: "RSS",
            description: "Follow feeds for product updates, blogs, and journals.",
            enabled: true,
            statusText: "Static preview"
        ),
        MopeliumSourceConnector(
            icon: "doc.text.magnifyingglass",
            title: "arXiv",
            description: "Track papers by topic, author, and keyword direction.",
            enabled: false,
            statusText: "Future source"
        ),
        MopeliumSourceConnector(
            icon: "chevron.left.forwardslash.chevron.right",
            title: "GitHub",
            description: "Watch releases, discussions, issues, and repository trends.",
            enabled: false,
            statusText: "Future source"
        ),
        MopeliumSourceConnector(
            icon: "folder",
            title: "PDF folder",
            description: "Browse selected folders and read local text, Markdown, code, HTML, JSON, CSV, and PDF text.",
            enabled: true,
            statusText: "Local reader"
        ),
        MopeliumSourceConnector(
            icon: "note.text",
            title: "Manual notes",
            description: "Keep hand-entered research notes beside collected sources.",
            enabled: true,
            statusText: "Static preview"
        ),
    ]
}
#endif
