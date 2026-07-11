#if canImport(SwiftUI)
import Foundation
import SwiftUI
import MopeliumTools
#if canImport(AppKit)
import AppKit
#endif
#if canImport(PDFKit)
import PDFKit
#endif

struct MopeliumSourcesScreen: View {
    @Environment(\.colorScheme) private var scheme
    @StateObject private var model = MopeliumSourcesViewModel()

    private let columns = [
        GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 14, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            MopeliumPageHeader(
                title: "Sources",
                subtitle: "Read local documents, search the web, and fetch source pages for research context."
            ) {
                MopeliumStatusBadge(
                    status: model.isBusy ? .running : .enabled,
                    label: model.isBusy ? "Working" : "v0.4 Ready"
                )
                .padding(.top, 3)
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 14) {
                    DocumentReaderCard(model: model)
                    WebLookupCard(model: model)
                    SourceToolConsoleCard(model: model)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Connector Map")
                            .font(MopeliumType.headline(15, .semibold))
                            .foregroundStyle(MopeliumTheme.secondaryText(scheme))

                        LazyVGrid(columns: columns, alignment: .center, spacing: 14) {
                            ForEach(MopeliumMockData.connectors) { connector in
                                SourceConnectorCard(connector: connector)
                            }
                        }
                    }
                }
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity)
    }
}

@MainActor
private final class MopeliumSourcesViewModel: ObservableObject {
    @Published private(set) var document: MopeliumDocumentSnapshot?
    @Published private(set) var documentCandidates: [MopeliumDocumentCandidate] = []
    @Published private(set) var documentFolderTitle: String?
    @Published private(set) var documentError: String?
    @Published private(set) var isReadingDocument = false

    @Published var webQuery = ""
    @Published var webURL = ""
    @Published private(set) var webResults: [MopeliumWebResult] = []
    @Published private(set) var webPage: MopeliumWebPageSnapshot?
    @Published private(set) var webStatus = "Ready"
    @Published private(set) var webError: String?
    @Published private(set) var isWebRunning = false
    @Published private(set) var toolWorkspaceURL: URL?
    @Published var selectedToolName = "browser_search" {
        didSet {
            guard selectedToolName != oldValue else { return }
            toolArguments = Self.defaultArguments(for: selectedToolName)
            toolOutput = nil
            toolError = nil
        }
    }
    @Published var toolArguments = MopeliumSourcesViewModel.defaultArguments(for: "browser_search")
    @Published private(set) var toolOutput: String?
    @Published private(set) var toolChangedFiles: [String] = []
    @Published private(set) var toolError: String?
    @Published private(set) var isToolRunning = false

    let toolDescriptors = ToolRegistry.standard().descriptors()
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private var scopedURLs: [URL] = []
    private let toolRegistry = ToolRegistry.standard()

    deinit {
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    var isBusy: Bool {
        isReadingDocument || isWebRunning || isToolRunning
    }

    var canSearch: Bool {
        !isWebRunning && !webQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canFetch: Bool {
        !isWebRunning && !webURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canCopyDocument: Bool {
        document != nil
    }

    var canCopyWebPage: Bool {
        webPage != nil
    }

    var selectedToolDescriptor: ToolDescriptor? {
        toolDescriptors.first { $0.name == selectedToolName }
    }

    var canRunTool: Bool {
        !isToolRunning && toolWorkspaceURL != nil && toolRegistry.tool(named: selectedToolName) != nil
    }

    func chooseDocument() {
        guard let url = MopeliumDocumentAccess.chooseFile() else { return }
        readDocument(at: url)
    }

    func browseFolder() {
        guard let folder = MopeliumDocumentAccess.chooseFolder() else { return }
        retainSecurityScope(for: folder)
        documentError = nil
        do {
            documentCandidates = try MopeliumDocumentReader.listDocuments(in: folder)
            documentFolderTitle = folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent
            if documentCandidates.isEmpty {
                documentError = "No readable text, Markdown, HTML, JSON, CSV, code, or PDF documents were found in the selected folder."
            }
        } catch {
            documentCandidates = []
            documentFolderTitle = nil
            documentError = error.localizedDescription
        }
    }

    func readCandidate(_ candidate: MopeliumDocumentCandidate) {
        readDocument(at: URL(fileURLWithPath: candidate.path))
    }

    func copyDocumentContext() {
        guard let document else { return }
        MopeliumClipboard.write("""
        Document: \(document.title)
        Path: \(document.path)
        Kind: \(document.kind)

        \(document.text)
        """)
    }

    func searchWeb() {
        let query = webQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isWebRunning else { return }
        isWebRunning = true
        webStatus = "Searching DuckDuckGo..."
        webError = nil

        Task {
            do {
                let results = try await MopeliumWebLookup.search(query: query)
                webResults = results
                webStatus = results.isEmpty ? "No results found." : "\(results.count) result\(results.count == 1 ? "" : "s") found."
                isWebRunning = false
            } catch {
                webError = error.localizedDescription
                webStatus = "Search failed."
                isWebRunning = false
            }
        }
    }

    func fetchEnteredURL() {
        fetchWebPage(webURL)
    }

    func fetchWebPage(_ urlString: String) {
        let target = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !isWebRunning else { return }
        isWebRunning = true
        webStatus = "Fetching page..."
        webError = nil

        Task {
            do {
                let page = try await MopeliumWebLookup.fetch(urlString: target)
                webPage = page
                webURL = page.urlString
                webStatus = "Fetched \(page.host) · HTTP \(page.statusCode)"
                isWebRunning = false
            } catch {
                webError = error.localizedDescription
                webStatus = "Fetch failed."
                isWebRunning = false
            }
        }
    }

    func copyWebContext() {
        guard let webPage else { return }
        MopeliumClipboard.write("""
        Web Page: \(webPage.title)
        URL: \(webPage.urlString)
        Status: HTTP \(webPage.statusCode)

        \(webPage.text)
        """)
    }

    func openInBrowser(_ urlString: String) {
        MopeliumWebLookup.openInBrowser(urlString)
    }

    func chooseToolWorkspace() {
        guard let folder = MopeliumDocumentAccess.chooseFolder(prompt: "Choose Tool Workspace") else { return }
        retainSecurityScope(for: folder)
        toolWorkspaceURL = folder
        toolError = nil
    }

    func useDocumentFolderAsToolWorkspace() {
        guard let path = documentCandidates.first?.path else { return }
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent()
        toolWorkspaceURL = folder
        toolError = nil
    }

    func resetToolArguments() {
        toolArguments = Self.defaultArguments(for: selectedToolName)
    }

    func runSelectedTool() {
        guard let workspace = toolWorkspaceURL else {
            toolError = "Choose a workspace before running a tool."
            return
        }
        guard let tool = toolRegistry.tool(named: selectedToolName) else {
            toolError = "Unknown tool: \(selectedToolName)"
            return
        }
        guard toolArguments.data(using: .utf8) != nil else {
            toolError = "Tool arguments must be UTF-8 JSON."
            return
        }

        isToolRunning = true
        toolError = nil
        toolOutput = nil
        toolChangedFiles = []

        let args = ToolArgs(raw: toolArguments)
        let context = ToolContext(workspaceRoot: workspace)
        Task {
            do {
                let observation = try await tool.execute(args, in: context)
                var output = observation.text
                if observation.truncated {
                    output += output.hasSuffix("\n") ? "[truncated]" : "\n[truncated]"
                }
                if let diff = observation.diff, !diff.isEmpty {
                    output += "\n\n[diff]\n\(diff)"
                }
                toolOutput = output
                toolChangedFiles = observation.changedFiles ?? []
                isToolRunning = false
            } catch {
                toolError = error.localizedDescription
                isToolRunning = false
            }
        }
    }

    private func readDocument(at url: URL) {
        isReadingDocument = true
        documentError = nil

        Task {
            do {
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    try MopeliumDocumentReader.read(url: url)
                }.value
                document = snapshot
                isReadingDocument = false
            } catch {
                documentError = error.localizedDescription
                isReadingDocument = false
            }
        }
    }

    private func retainSecurityScope(for url: URL) {
        if url.startAccessingSecurityScopedResource() {
            scopedURLs.append(url)
        }
    }

    private static func defaultArguments(for toolName: String) -> String {
        switch toolName {
        case "read_file":
            return #"{"path":"README.md","maxBytes":100000}"#
        case "list_files":
            return #"{"path":"."}"#
        case "search_text":
            return #"{"query":"Mopelium","path":"."}"#
        case "write_file":
            return #"{"path":"notes/example.txt","content":"Hello from MopeliumTools"}"#
        case "read_pdf":
            return #"{"path":"document.pdf","pages":"1","maxCharacters":200000}"#
        case "edit_pdf_pages":
            return #"{"mode":"extract","inputPath":"document.pdf","pages":"1","outputPath":"out/page-1.pdf"}"#
        case "reconstruct_document_image":
            return #"{"imagePath":"scan.png","outputPath":"out/reconstructed.md","format":"md","backend":"auto"}"#
        case "compile_latex":
            return #"{"inputPath":"paper.tex","outputDir":"out","engine":"auto"}"#
        case "generate_image":
            return #"{"prompt":"A concise research diagram","outputPath":"out/image.png","size":"1024x1024","count":1}"#
        case "web_fetch":
            return #"{"url":"https://example.com","maxCharacters":20000}"#
        case "browser_search":
            return #"{"query":"Mopelium research engine","engine":"duckduckgo","profile":"default","channel":"chromium","headless":true,"waitMillis":600,"maxCharacters":20000}"#
        case "browser_navigate":
            return #"{"url":"https://example.com","profile":"default","channel":"chromium","headless":true,"waitMillis":600,"maxCharacters":20000}"#
        case "browser_snapshot", "browser_reload", "browser_back", "browser_forward", "browser_history", "browser_profiles", "browser_downloads":
            return #"{"profile":"default","maxCharacters":20000}"#
        case "browser_handoff":
            return #"{"url":"https://example.com","profile":"default","channel":"chromium","handoffSeconds":20,"maxCharacters":20000}"#
        case "browser_click":
            return #"{"selector":"a","profile":"default","channel":"chromium","headless":true,"waitMillis":600,"maxCharacters":20000}"#
        case "browser_type":
            return #"{"selector":"input[name=q]","value":"Mopelium","profile":"default","channel":"chromium","headless":true,"waitMillis":600,"maxCharacters":20000}"#
        case "browser_submit":
            return #"{"selector":"form","profile":"default","channel":"chromium","headless":true,"timeoutMillis":10000,"waitMillis":600,"maxCharacters":20000}"#
        case "browser_select_option":
            return #"{"selector":"select","optionValue":"value","profile":"default","channel":"chromium","headless":true,"waitMillis":600,"maxCharacters":20000}"#
        case "browser_press_key":
            return #"{"key":"Enter","profile":"default","channel":"chromium","headless":true,"waitMillis":600,"maxCharacters":20000}"#
        case "browser_scroll":
            return #"{"direction":"down","amount":800,"profile":"default","channel":"chromium","headless":true,"waitMillis":600,"maxCharacters":20000}"#
        case "browser_wait":
            return #"{"text":"Example","profile":"default","channel":"chromium","headless":true,"timeoutMillis":10000,"waitMillis":100,"maxCharacters":20000}"#
        case "browser_screenshot":
            return #"{"outputPath":"screens/page.png","url":"https://example.com","profile":"default","channel":"chromium","headless":true,"fullPage":true,"waitMillis":600,"maxCharacters":20000}"#
        case "browser_upload_file":
            return #"{"filePath":"upload/report.txt","selector":"input[type=file]","profile":"default","channel":"chromium","headless":true,"waitMillis":600,"maxCharacters":20000}"#
        case "browser_download":
            return #"{"selector":"a","profile":"default","channel":"chromium","headless":true,"waitMillis":600,"downloadTimeoutMillis":15000,"maxCharacters":20000}"#
        case "browser_diagnostics":
            return #"{"profile":"default","channel":"chromium"}"#
        case "browser_profile_delete":
            return #"{"profile":"default","confirmProfile":"default"}"#
        case "run_shell":
            return #"{"command":"pwd"}"#
        case "git_status", "git_diff", "git_diff_staged", "git_info", "git_branch", "git_worktree_list":
            return #"{}"#
        case "git_recent_commits":
            return #"{"limit":10}"#
        case "git_diff_base":
            return #"{"base":"HEAD"}"#
        case "git_create_branch":
            return #"{"name":"mopelium-tools-check","startPoint":"HEAD"}"#
        case "git_stage", "git_unstage":
            return #"{"paths":["README.md"]}"#
        case "git_commit":
            return #"{"message":"Update Mopelium tools"}"#
        case "git_apply_patch_check", "git_apply_patch", "git_stage_patch", "git_unstage_patch", "git_revert_patch":
            return #"{"diff":"diff --git a/example.txt b/example.txt\n--- a/example.txt\n+++ b/example.txt\n@@ -1 +1 @@\n-old\n+new\n","confirmRevert":false}"#
        case "git_worktree_create":
            return #"{"name":"scratch","startPoint":"HEAD","branch":null}"#
        case "git_worktree_remove":
            return #"{"name":"scratch","confirmName":"scratch","force":false}"#
        default:
            return #"{}"#
        }
    }
}

private struct DocumentReaderCard: View {
    @ObservedObject var model: MopeliumSourcesViewModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MopeliumGlassCard(cornerRadius: 24, contentPadding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                SourceSectionHeader(
                    icon: "doc.text.magnifyingglass",
                    title: "Document Reader",
                    subtitle: "Choose a file or browse a folder. Text, Markdown, HTML, JSON, CSV, code, and PDF text are supported.",
                    status: model.document == nil ? .local : .enabled,
                    badge: model.document == nil ? "Local" : "Loaded"
                )

                HStack(spacing: 10) {
                    SourceActionButton(title: "Choose File", systemName: "doc.badge.plus", prominent: true, disabled: model.isReadingDocument) {
                        model.chooseDocument()
                    }
                    SourceActionButton(title: "Browse Folder", systemName: "folder.badge.plus", disabled: model.isReadingDocument) {
                        model.browseFolder()
                    }
                    SourceIconButton(systemName: "doc.on.doc", help: "Copy document context", disabled: !model.canCopyDocument) {
                        model.copyDocumentContext()
                    }
                    Spacer(minLength: 0)
                    if model.isReadingDocument {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let error = model.documentError {
                    SourceInlineNotice(text: error, status: .failed)
                }

                if let folder = model.documentFolderTitle, !model.documentCandidates.isEmpty {
                    SourceList(title: "Folder Documents", subtitle: folder) {
                        ForEach(model.documentCandidates) { candidate in
                            DocumentCandidateRow(candidate: candidate) {
                                model.readCandidate(candidate)
                            }
                            if candidate.id != model.documentCandidates.last?.id {
                                SourceDivider()
                            }
                        }
                    }
                }

                if let document = model.document {
                    SourcePreview(
                        title: document.title,
                        detail: "\(document.kind) · \(document.detail)\(document.truncated ? " · truncated" : "")",
                        text: document.text,
                        systemName: document.kind == "PDF" ? "doc.richtext" : "doc.plaintext",
                        status: document.truncated ? .queued : .enabled
                    )
                } else if model.documentCandidates.isEmpty {
                    SourceEmptyPrompt(
                        title: "No document loaded",
                        message: "Use a user-selected file or folder. Sensitive config-style files are rejected before reading.",
                        systemName: "text.page"
                    )
                }
            }
        }
    }
}

private struct WebLookupCard: View {
    @ObservedObject var model: MopeliumSourcesViewModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MopeliumGlassCard(cornerRadius: 24, contentPadding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                SourceSectionHeader(
                    icon: "globe.badge.chevron.backward",
                    title: "Web Lookup",
                    subtitle: "Search public pages, fetch HTTP(S) URLs, and extract readable page text without browser cookies or login state.",
                    status: model.isWebRunning ? .running : .enabled,
                    badge: model.webStatus
                )

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        SourceTextField(
                            placeholder: "Search the web...",
                            text: $model.webQuery,
                            systemName: "magnifyingglass"
                        )
                        .onSubmit {
                            if model.canSearch { model.searchWeb() }
                        }
                        SourceActionButton(title: "Search", systemName: "magnifyingglass", prominent: true, disabled: !model.canSearch) {
                            model.searchWeb()
                        }
                    }

                    HStack(spacing: 10) {
                        SourceTextField(
                            placeholder: "https://example.com/article",
                            text: $model.webURL,
                            systemName: "link"
                        )
                        .onSubmit {
                            if model.canFetch { model.fetchEnteredURL() }
                        }
                        SourceActionButton(title: "Fetch", systemName: "arrow.down.doc", disabled: !model.canFetch) {
                            model.fetchEnteredURL()
                        }
                        SourceIconButton(systemName: "doc.on.doc", help: "Copy web page context", disabled: !model.canCopyWebPage) {
                            model.copyWebContext()
                        }
                    }
                }

                if let error = model.webError {
                    SourceInlineNotice(text: error, status: .failed)
                }

                if !model.webResults.isEmpty {
                    SourceList(title: "Search Results", subtitle: "DuckDuckGo HTML") {
                        ForEach(model.webResults) { result in
                            WebResultRow(result: result, onFetch: {
                                model.fetchWebPage(result.urlString)
                            }, onOpen: {
                                model.openInBrowser(result.urlString)
                            })
                            if result.id != model.webResults.last?.id {
                                SourceDivider()
                            }
                        }
                    }
                }

                if let page = model.webPage {
                    SourcePreview(
                        title: page.title,
                        detail: "\(page.host) · HTTP \(page.statusCode) · \(page.contentType)\(page.truncated ? " · truncated" : "")",
                        text: page.text,
                        systemName: "safari",
                        status: page.statusCode >= 200 && page.statusCode < 300 ? .enabled : .queued
                    )

                    if !page.links.isEmpty {
                        SourceList(title: "Page Links", subtitle: "\(min(page.links.count, 8)) shown") {
                            ForEach(page.links.prefix(8)) { link in
                                WebResultRow(result: link, onFetch: {
                                    model.fetchWebPage(link.urlString)
                                }, onOpen: {
                                    model.openInBrowser(link.urlString)
                                })
                                if link.id != page.links.prefix(8).last?.id {
                                    SourceDivider()
                                }
                            }
                        }
                    }
                } else if model.webResults.isEmpty {
                    SourceEmptyPrompt(
                        title: "No web page loaded",
                        message: "Search for a topic or fetch a direct URL. Dynamic, login-only, and JavaScript-heavy pages can use the browser-profile tools below.",
                        systemName: "network"
                    )
                }
            }
        }
    }
}

private struct SourceToolConsoleCard: View {
    @ObservedObject var model: MopeliumSourcesViewModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MopeliumGlassCard(cornerRadius: 24, contentPadding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                SourceSectionHeader(
                    icon: "wrench.and.screwdriver",
                    title: "Full Intatis Tool Surface",
                    subtitle: "Run the migrated file, PDF, web_fetch, browser profile, browser interaction, download, upload, screenshot, shell, git, and patch tools inside a selected workspace.",
                    status: model.isToolRunning ? .running : .enabled,
                    badge: "\(model.toolDescriptors.count) tools"
                )

                HStack(spacing: 10) {
                    SourceActionButton(title: "Choose Workspace", systemName: "folder", prominent: model.toolWorkspaceURL == nil, disabled: model.isToolRunning) {
                        model.chooseToolWorkspace()
                    }
                    if !model.documentCandidates.isEmpty {
                        SourceActionButton(title: "Use Document Folder", systemName: "folder.badge.gearshape", disabled: model.isToolRunning) {
                            model.useDocumentFolderAsToolWorkspace()
                        }
                    }
                    Text(model.toolWorkspaceURL?.path ?? "No workspace selected")
                        .font(MopeliumType.mono(12))
                        .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tool")
                        .font(MopeliumType.caption(12, .semibold))
                        .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                    Picker("Tool", selection: $model.selectedToolName) {
                        ForEach(model.toolDescriptors, id: \.name) { descriptor in
                            Text("\(descriptor.name) · \(descriptor.sideEffect.rawValue)")
                                .tag(descriptor.name)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    if let descriptor = model.selectedToolDescriptor {
                        Text(descriptor.description)
                            .font(MopeliumType.caption(12, .medium))
                            .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                            .fixedSize(horizontal: false, vertical: true)

                        SourceSchemaView(schema: descriptor.parameters)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Arguments JSON")
                            .font(MopeliumType.caption(12, .semibold))
                            .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                        Spacer(minLength: 0)
                        SourceActionButton(title: "Reset", systemName: "arrow.counterclockwise", disabled: model.isToolRunning) {
                            model.resetToolArguments()
                        }
                    }
                    TextEditor(text: $model.toolArguments)
                        .font(MopeliumType.mono(12))
                        .foregroundStyle(MopeliumTheme.primaryText(scheme))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 92, maxHeight: 140)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(MopeliumTheme.surface(scheme).opacity(scheme == .dark ? 0.30 : 0.70))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(MopeliumTheme.stroke(scheme).opacity(0.78), lineWidth: 1)
                        }
                }

                HStack(spacing: 10) {
                    SourceActionButton(title: "Run Tool", systemName: "play.fill", prominent: true, disabled: !model.canRunTool) {
                        model.runSelectedTool()
                    }
                    if model.isToolRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer(minLength: 0)
                }

                if let error = model.toolError {
                    SourceInlineNotice(text: error, status: .failed)
                }

                if !model.toolChangedFiles.isEmpty {
                    SourceList(title: "Changed Files", subtitle: "\(model.toolChangedFiles.count)") {
                        ForEach(model.toolChangedFiles, id: \.self) { path in
                            Text(path)
                                .font(MopeliumType.mono(12))
                                .foregroundStyle(MopeliumTheme.primaryText(scheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                    }
                }

                if let output = model.toolOutput {
                    SourcePreview(
                        title: model.selectedToolName,
                        detail: model.toolWorkspaceURL?.lastPathComponent ?? "workspace",
                        text: output,
                        systemName: "terminal",
                        status: .enabled
                    )
                } else {
                    SourceEmptyPrompt(
                        title: "Tool console",
                        message: "Choose a workspace, select any migrated tool, edit JSON arguments, and run it. Browser profile data stays under .mopelium/browser inside the workspace.",
                        systemName: "curlybraces"
                    )
                }
            }
        }
    }
}

private struct SourceSchemaView: View {
    let schema: JSONValue
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        DisclosureGroup {
            Text(renderedSchema)
                .font(MopeliumType.mono(11))
                .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } label: {
            Text("Parameter schema")
                .font(MopeliumType.caption(11, .semibold))
                .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
        }
    }

    private var renderedSchema: String {
        guard let data = try? JSONEncoder.prettySorted.encode(schema) else {
            return "\(schema)"
        }
        return String(decoding: data, as: UTF8.self)
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

private struct SourceSectionHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: MopeliumStatus
    let badge: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MopeliumIconBadge(systemName: icon, status: status)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .font(MopeliumType.headline(17, .semibold))
                        .foregroundStyle(MopeliumTheme.primaryText(scheme))
                    MopeliumStatusBadge(status: status, label: badge)
                }
                Text(subtitle)
                    .font(MopeliumType.body(13))
                    .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SourceActionButton: View {
    let title: String
    let systemName: String
    var prominent = false
    var disabled = false
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(MopeliumType.button(13))
            }
            .foregroundStyle(prominent ? MopeliumTheme.textOnAccent : MopeliumTheme.primaryText(scheme))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(background)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(prominent ? Color.clear : MopeliumTheme.stroke(scheme).opacity(0.82), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private var background: AnyShapeStyle {
        if prominent {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [MopeliumTheme.accentDeep, MopeliumTheme.accent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(MopeliumTheme.surface(scheme).opacity(scheme == .dark ? 0.30 : 0.72))
    }
}

private struct SourceIconButton: View {
    let systemName: String
    let help: String
    var disabled = false
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(MopeliumTheme.surface(scheme).opacity(scheme == .dark ? 0.30 : 0.72))
                }
                .overlay {
                    Circle()
                        .stroke(MopeliumTheme.stroke(scheme).opacity(0.78), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .help(help)
    }
}

private struct SourceTextField: View {
    let placeholder: String
    @Binding var text: String
    let systemName: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
                .frame(width: 18)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(MopeliumType.body(14))
                .foregroundStyle(MopeliumTheme.primaryText(scheme))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MopeliumTheme.surface(scheme).opacity(scheme == .dark ? 0.30 : 0.70))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MopeliumTheme.stroke(scheme).opacity(0.78), lineWidth: 1)
        }
    }
}

private struct SourceList<Content: View>: View {
    let title: String
    let subtitle: String
    private let content: Content
    @Environment(\.colorScheme) private var scheme

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(MopeliumType.caption(12, .semibold))
                    .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                Text(subtitle)
                    .font(MopeliumType.caption(11, .medium))
                    .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                content
            }
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MopeliumTheme.surface(scheme).opacity(scheme == .dark ? 0.24 : 0.54))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MopeliumTheme.stroke(scheme).opacity(0.72), lineWidth: 1)
            }
        }
    }
}

private struct DocumentCandidateRow: View {
    let candidate: MopeliumDocumentCandidate
    let onRead: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: candidate.kind == "PDF" ? "doc.richtext" : "doc.plaintext")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MopeliumTheme.accentDeep)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                    .font(MopeliumType.body(13, .semibold))
                    .foregroundStyle(MopeliumTheme.primaryText(scheme))
                    .lineLimit(1)
                Text(candidate.detail)
                    .font(MopeliumType.caption(11, .medium))
                    .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            SourceActionButton(title: "Read", systemName: "text.magnifyingglass", disabled: false) {
                onRead()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct WebResultRow: View {
    let result: MopeliumWebResult
    let onFetch: () -> Void
    let onOpen: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "link.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MopeliumTheme.accentDeep)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(MopeliumType.body(13, .semibold))
                    .foregroundStyle(MopeliumTheme.primaryText(scheme))
                    .lineLimit(2)
                Text(result.urlString)
                    .font(MopeliumType.caption(11, .medium))
                    .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
                    .lineLimit(1)
                if !result.snippet.isEmpty {
                    Text(result.snippet)
                        .font(MopeliumType.caption(12, .regular))
                        .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                SourceIconButton(systemName: "arrow.down.doc", help: "Fetch page") {
                    onFetch()
                }
                SourceIconButton(systemName: "safari", help: "Open in browser") {
                    onOpen()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct SourcePreview: View {
    let title: String
    let detail: String
    let text: String
    let systemName: String
    let status: MopeliumStatus
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MopeliumTheme.statusColor(status))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(MopeliumType.body(13, .semibold))
                        .foregroundStyle(MopeliumTheme.primaryText(scheme))
                        .lineLimit(1)
                    Text(detail)
                        .font(MopeliumType.caption(11, .medium))
                        .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)

            SourceDivider()

            ScrollView {
                Text(text.isEmpty ? "(no readable text)" : text)
                    .font(MopeliumType.mono(12))
                    .foregroundStyle(MopeliumTheme.primaryText(scheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
            }
            .frame(maxHeight: 260)
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MopeliumTheme.surface(scheme).opacity(scheme == .dark ? 0.24 : 0.54))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MopeliumTheme.stroke(scheme).opacity(0.72), lineWidth: 1)
        }
    }
}

private struct SourceEmptyPrompt: View {
    let title: String
    let message: String
    let systemName: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(MopeliumType.body(13, .semibold))
                    .foregroundStyle(MopeliumTheme.primaryText(scheme))
                Text(message)
                    .font(MopeliumType.caption(12, .medium))
                    .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MopeliumTheme.surface(scheme).opacity(scheme == .dark ? 0.20 : 0.46))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MopeliumTheme.stroke(scheme).opacity(0.58), lineWidth: 1)
        }
    }
}

private struct SourceInlineNotice: View {
    let text: String
    let status: MopeliumStatus
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: status == .failed ? "exclamationmark.triangle" : "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MopeliumTheme.statusColor(status))
                .frame(width: 18)
            Text(text)
                .font(MopeliumType.caption(12, .medium))
                .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MopeliumTheme.statusFill(status, scheme))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MopeliumTheme.statusStroke(status, scheme), lineWidth: 1)
                }
        }
    }
}

private struct SourceDivider: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(MopeliumTheme.stroke(scheme).opacity(0.62))
            .frame(height: 1)
            .padding(.leading, 44)
    }
}

private struct MopeliumDocumentSnapshot: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let path: String
    let kind: String
    let detail: String
    let text: String
    let truncated: Bool
}

private struct MopeliumDocumentCandidate: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let path: String
    let kind: String
    let detail: String
}

private struct MopeliumWebResult: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let urlString: String
    let snippet: String
}

private struct MopeliumWebPageSnapshot: Equatable, Sendable {
    let title: String
    let urlString: String
    let host: String
    let statusCode: Int
    let contentType: String
    let text: String
    let links: [MopeliumWebResult]
    let truncated: Bool
}

private enum MopeliumSourceError: LocalizedError {
    case unsupported(String)
    case sensitivePath(String)
    case invalidURL(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let message), .sensitivePath(let message), .invalidURL(let message), .network(let message):
            return message
        }
    }
}

private enum MopeliumDocumentAccess {
    @MainActor
    static func chooseFile(prompt: String = "Read") -> URL? {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
        #else
        return nil
        #endif
    }

    @MainActor
    static func chooseFolder(prompt: String = "Browse") -> URL? {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
        #else
        return nil
        #endif
    }
}

private enum MopeliumDocumentReader {
    private static let maxTextCharacters = 60_000
    private static let maxCandidates = 80
    private static let supportedExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "rst", "json", "csv", "tsv", "xml",
        "html", "htm", "log", "swift", "py", "js", "ts", "tsx", "jsx", "java",
        "c", "cc", "cpp", "h", "hpp", "m", "mm", "yml", "yaml", "toml", "pdf",
    ]

    static func listDocuments(in folder: URL) throws -> [MopeliumDocumentCandidate] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw MopeliumSourceError.unsupported("Selected item is not a folder.")
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var candidates: [MopeliumDocumentCandidate] = []
        for case let url as URL in enumerator {
            if candidates.count >= maxCandidates { break }
            guard isSupportedDocument(url), !isSensitive(url) else { continue }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            let relative = relativePath(of: url, root: folder)
            let bytes = values?.fileSize ?? 0
            candidates.append(MopeliumDocumentCandidate(
                id: url.standardizedFileURL.path,
                title: url.lastPathComponent,
                path: url.path,
                kind: kind(for: url),
                detail: "\(relative) · \(formatBytes(bytes))"
            ))
        }
        return candidates.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func read(url: URL) throws -> MopeliumDocumentSnapshot {
        guard isSupportedDocument(url) else {
            throw MopeliumSourceError.unsupported("Unsupported document type: .\(url.pathExtension.lowercased()).")
        }
        guard !isSensitive(url) else {
            throw MopeliumSourceError.sensitivePath("Mopelium refuses to read env, key, token, certificate, and secret-looking files.")
        }

        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        if url.pathExtension.lowercased() == "pdf" {
            return try readPDF(url: url)
        }

        let data = try Data(contentsOf: url)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw MopeliumSourceError.unsupported("Only UTF-8 text documents are supported for this file type.")
        }
        let readable = ["html", "htm"].contains(url.pathExtension.lowercased())
            ? MopeliumHTML.text(fromHTML: raw)
            : MopeliumHTML.normalizedText(raw)
        let (limited, truncated) = limitText(readable)
        return MopeliumDocumentSnapshot(
            title: url.lastPathComponent,
            path: url.path,
            kind: kind(for: url),
            detail: "\(formatBytes(data.count))",
            text: limited,
            truncated: truncated
        )
    }

    private static func readPDF(url: URL) throws -> MopeliumDocumentSnapshot {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else {
            throw MopeliumSourceError.unsupported("Could not open PDF document.")
        }

        var parts: [String] = []
        var characterCount = 0
        var truncated = false
        for index in 0..<document.pageCount {
            let pageText = document.page(at: index)?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let block = "--- page \(index + 1) ---\n\(pageText.isEmpty ? "(no extractable text on this page)" : pageText)"
            characterCount += block.count
            if characterCount > maxTextCharacters {
                truncated = true
                break
            }
            parts.append(block)
        }

        let body = parts.joined(separator: "\n\n")
        let (limited, limitTruncated) = limitText(body)
        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return MopeliumDocumentSnapshot(
            title: title?.isEmpty == false ? title! : url.lastPathComponent,
            path: url.path,
            kind: "PDF",
            detail: "\(document.pageCount) page\(document.pageCount == 1 ? "" : "s")",
            text: limited,
            truncated: truncated || limitTruncated
        )
        #else
        throw MopeliumSourceError.unsupported("PDF reading requires PDFKit on macOS.")
        #endif
    }

    private static func isSupportedDocument(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isSensitive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        if name == ".env" || name.hasPrefix(".env.") || name == "secrets.json" {
            return true
        }
        if ["pem", "key", "p12", "p8", "mobileprovision"].contains(ext) {
            return true
        }
        return name.contains("private_key")
            || name.contains("api_key")
            || name.contains("access_token")
            || name.contains("password")
    }

    private static func kind(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "PDF"
        case "md", "markdown": return "Markdown"
        case "html", "htm": return "HTML"
        case "json": return "JSON"
        case "csv", "tsv": return "Table"
        case "swift", "py", "js", "ts", "tsx", "jsx", "java", "c", "cc", "cpp", "h", "hpp", "m", "mm": return "Code"
        default: return "Text"
        }
    }

    private static func limitText(_ text: String) -> (String, Bool) {
        guard text.count > maxTextCharacters else { return (text, false) }
        return (String(text.prefix(maxTextCharacters)) + "\n[truncated]", true)
    }

    private static func relativePath(of url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }
        let start = filePath.index(filePath.startIndex, offsetBy: rootPath.count)
        return String(filePath[start...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

private enum MopeliumWebLookup {
    private static let maxBytes = 3_000_000
    private static let maxTextCharacters = 60_000

    static func search(query: String) async throws -> [MopeliumWebResult] {
        var components = URLComponents(string: "https://duckduckgo.com/html/")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else {
            throw MopeliumSourceError.invalidURL("Could not build search URL.")
        }

        let raw = try await fetchRaw(url: url)
        let parsed = parseDuckDuckGoResults(html: raw.text, baseURL: raw.url)
        if !parsed.isEmpty { return Array(parsed.prefix(8)) }
        return Array(extractLinks(html: raw.text, baseURL: raw.url).prefix(8))
    }

    static func fetch(urlString: String) async throws -> MopeliumWebPageSnapshot {
        let url = try validatedHTTPURL(urlString)
        let raw = try await fetchRaw(url: url)
        let contentType = raw.contentType.lowercased()
        let readable = contentType.contains("html")
            ? MopeliumHTML.text(fromHTML: raw.text)
            : MopeliumHTML.normalizedText(raw.text)
        let (limited, truncated) = limitText(readable)
        let title = MopeliumHTML.title(fromHTML: raw.text) ?? raw.url.host ?? raw.url.absoluteString
        return MopeliumWebPageSnapshot(
            title: title,
            urlString: raw.url.absoluteString,
            host: raw.url.host ?? raw.url.absoluteString,
            statusCode: raw.statusCode,
            contentType: raw.contentType,
            text: limited,
            links: Array(extractLinks(html: raw.text, baseURL: raw.url).prefix(12)),
            truncated: truncated || raw.truncatedBytes
        )
    }

    static func openInBrowser(_ urlString: String) {
        #if canImport(AppKit)
        guard let url = try? validatedHTTPURL(urlString) else { return }
        NSWorkspace.shared.open(url)
        #endif
    }

    private static func fetchRaw(url: URL) async throws -> (url: URL, statusCode: Int, contentType: String, text: String, truncatedBytes: Bool) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("Mopelium/0.4", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml,text/plain;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw MopeliumSourceError.network("Response was not HTTP.")
            }
            let limitedData: Data
            let truncated = data.count > maxBytes
            if truncated {
                limitedData = Data(data.prefix(maxBytes))
            } else {
                limitedData = data
            }
            let text = String(data: limitedData, encoding: .utf8)
                ?? String(decoding: limitedData, as: UTF8.self)
            return (
                http.url ?? url,
                http.statusCode,
                http.value(forHTTPHeaderField: "Content-Type") ?? "unknown",
                text,
                truncated
            )
        } catch let error as MopeliumSourceError {
            throw error
        } catch {
            throw MopeliumSourceError.network(error.localizedDescription)
        }
    }

    private static func validatedHTTPURL(_ raw: String) throws -> URL {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") {
            value = "https://\(value)"
        }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host?.isEmpty == false else {
            throw MopeliumSourceError.invalidURL("URL must be HTTP(S) with a host.")
        }
        return url
    }

    private static func parseDuckDuckGoResults(html: String, baseURL: URL) -> [MopeliumWebResult] {
        let anchors = MopeliumHTML.matches(
            in: html,
            pattern: #"<a[^>]+class=["'][^"']*result__a[^"']*["'][^>]+href=["']([^"']+)["'][^>]*>(.*?)</a>"#
        )
        let snippets = MopeliumHTML.matches(
            in: html,
            pattern: #"<a[^>]+class=["'][^"']*result__snippet[^"']*["'][^>]*>(.*?)</a>|<div[^>]+class=["'][^"']*result__snippet[^"']*["'][^>]*>(.*?)</div>"#
        )

        var results: [MopeliumWebResult] = []
        var seen = Set<String>()
        for (index, match) in anchors.enumerated() {
            let rawHref = MopeliumHTML.substring(html, match: match, at: 1)
            let href = normalizedSearchURL(rawHref, baseURL: baseURL)
            guard href.hasPrefix("http"), seen.insert(href).inserted else { continue }
            let title = MopeliumHTML.text(fromHTML: MopeliumHTML.substring(html, match: match, at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let snippetMatch = snippets.indices.contains(index) ? snippets[index] : nil
            let snippet = snippetMatch.map { item -> String in
                let first = MopeliumHTML.substring(html, match: item, at: 1)
                let second = MopeliumHTML.substring(html, match: item, at: 2)
                return MopeliumHTML.text(fromHTML: first.isEmpty ? second : first)
            } ?? ""
            results.append(MopeliumWebResult(
                id: href,
                title: title.isEmpty ? href : title,
                urlString: href,
                snippet: snippet
            ))
        }
        return results
    }

    private static func extractLinks(html: String, baseURL: URL) -> [MopeliumWebResult] {
        let matches = MopeliumHTML.matches(
            in: html,
            pattern: #"<a[^>]+href=["']([^"']+)["'][^>]*>(.*?)</a>"#
        )
        var links: [MopeliumWebResult] = []
        var seen = Set<String>()
        for match in matches {
            let href = normalizedSearchURL(MopeliumHTML.substring(html, match: match, at: 1), baseURL: baseURL)
            guard href.hasPrefix("http"), seen.insert(href).inserted else { continue }
            guard let host = URL(string: href)?.host, !host.contains("duckduckgo.com") else { continue }
            let title = MopeliumHTML.text(fromHTML: MopeliumHTML.substring(html, match: match, at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            links.append(MopeliumWebResult(
                id: href,
                title: title.isEmpty ? host : title,
                urlString: href,
                snippet: ""
            ))
            if links.count >= 30 { break }
        }
        return links
    }

    private static func normalizedSearchURL(_ raw: String, baseURL: URL) -> String {
        let decoded = MopeliumHTML.decodedEntities(raw)
        if let components = URLComponents(string: decoded),
           components.host?.contains("duckduckgo.com") == true,
           let target = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
           !target.isEmpty {
            return target
        }
        return URL(string: decoded, relativeTo: baseURL)?.absoluteURL.absoluteString ?? decoded
    }

    private static func limitText(_ text: String) -> (String, Bool) {
        guard text.count > maxTextCharacters else { return (text, false) }
        return (String(text.prefix(maxTextCharacters)) + "\n[truncated]", true)
    }
}

private enum MopeliumHTML {
    static func text(fromHTML html: String) -> String {
        var text = html
        text = replacing(pattern: #"(?is)<script\b[^>]*>.*?</script>"#, in: text, with: " ")
        text = replacing(pattern: #"(?is)<style\b[^>]*>.*?</style>"#, in: text, with: " ")
        text = replacing(pattern: #"(?is)<!--.*?-->"#, in: text, with: " ")
        text = replacing(pattern: #"(?i)<br\s*/?>"#, in: text, with: "\n")
        text = replacing(pattern: #"(?i)</(p|div|section|article|li|h[1-6]|tr|blockquote)>"#, in: text, with: "\n")
        text = replacing(pattern: #"(?s)<[^>]+>"#, in: text, with: " ")
        return normalizedText(decodedEntities(text))
    }

    static func title(fromHTML html: String) -> String? {
        guard let match = matches(in: html, pattern: #"(?is)<title[^>]*>(.*?)</title>"#).first else {
            return nil
        }
        let title = text(fromHTML: substring(html, match: match, at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    static func normalizedText(_ raw: String) -> String {
        let collapsedSpaces = replacing(pattern: #"[ \t]{2,}"#, in: raw, with: " ")
        let lines = collapsedSpaces
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    static func decodedEntities(_ raw: String) -> String {
        var text = raw
        let named = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " ",
        ]
        for (entity, value) in named {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return decodeNumericEntities(text)
    }

    static func matches(in text: String, pattern: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func substring(_ text: String, match: NSTextCheckingResult, at index: Int) -> String {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: text) else {
            return ""
        }
        return String(text[range])
    }

    private static func replacing(pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: replacement
        )
    }

    private static func decodeNumericEntities(_ raw: String) -> String {
        let pattern = #"&#(x?[0-9A-Fa-f]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return raw }
        var text = raw
        for match in regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).reversed() {
            guard let fullRange = Range(match.range(at: 0), in: text),
                  let valueRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let token = String(text[valueRange])
            let scalarValue: UInt32?
            if token.lowercased().hasPrefix("x") {
                scalarValue = UInt32(token.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(token, radix: 10)
            }
            if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                text.replaceSubrange(fullRange, with: String(Character(scalar)))
            }
        }
        return text
    }
}

private enum MopeliumClipboard {
    static func write(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
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
