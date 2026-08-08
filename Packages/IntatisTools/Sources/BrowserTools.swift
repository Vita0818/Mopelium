import Foundation
import IntatisCore
import IntatisProtocol

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Shared browser helpers

private enum BrowserToolConfig {
    static let defaultProfile = "default"
    static let defaultChannel = "chromium"
    static let maxSnapshotCharacters = 100_000

    static func normalizedProfile(_ raw: String?) throws -> String {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let profile = value.isEmpty ? defaultProfile : value
        guard profile.count <= 64,
              profile != ".",
              profile != "..",
              profile.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }) else {
            throw IntatisError.decoding("browser profile must use only letters, numbers, '.', '-' or '_'")
        }
        return profile
    }

    static func normalizedChannel(_ raw: String?) -> String {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch value {
        case "chrome", "chrome-beta", "chrome-dev", "chrome-canary",
             "msedge", "msedge-beta", "msedge-dev", "msedge-canary",
             "chromium":
            return value
        default:
            return defaultChannel
        }
    }

    static func browserRoot(in workspace: URL) throws -> URL {
        try PathConfinement.resolve(".intatis/browser", within: workspace)
    }

    static func profileURL(profile: String, workspace: URL) throws -> URL {
        try PathConfinement.resolve(".intatis/browser/profiles/\(profile)", within: workspace)
    }

    static func downloadsURL(profile: String, workspace: URL) throws -> URL {
        try PathConfinement.resolve(".intatis/browser/downloads/\(profile)", within: workspace)
    }

    static func stateURL(profile: String, workspace: URL) throws -> URL {
        try PathConfinement.resolve(".intatis/browser/state/\(profile).json", within: workspace)
    }

    static func historyURL(workspace: URL) throws -> URL {
        try PathConfinement.resolve(".intatis/browser/history.jsonl", within: workspace)
    }

    static func executionTouchedPaths(profile: String) -> [String] {
        [
            ".intatis/browser/profiles/\(profile)",
            ".intatis/browser/downloads/\(profile)",
            ".intatis/browser/state/\(profile).json",
            ".intatis/browser/history.jsonl",
        ]
    }

    static func prepare(profile: String,
                        workspace: URL,
                        workspaceLease: WorkspaceLease) throws -> BrowserPaths {
        let paths = try paths(profile: profile, workspace: workspace)
        _ = try validateBrowserWorkspaceAccess(
            readablePaths: [],
            writablePaths: [
                paths.profileDir.path,
                paths.downloadsDir.path,
                paths.stateFile.path,
                paths.historyFile.path,
            ],
            cwd: workspace,
            workspaceLease: workspaceLease)
        try FileManager.default.createDirectory(at: paths.profileDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.downloadsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.historyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        return paths
    }

    static func paths(profile: String, workspace: URL) throws -> BrowserPaths {
        let profileURL = try profileURL(profile: profile, workspace: workspace)
        let downloadsURL = try downloadsURL(profile: profile, workspace: workspace)
        let stateURL = try stateURL(profile: profile, workspace: workspace)
        let historyURL = try historyURL(workspace: workspace)
        return BrowserPaths(profile: profile,
                            profileDir: profileURL,
                            downloadsDir: downloadsURL,
                            stateFile: stateURL,
                            historyFile: historyURL)
    }

    static func validatedHTTPURL(_ raw: String) throws -> URL {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host?.isEmpty == false else {
            throw IntatisError.config("URL must be http(s) with a host")
        }
        return url
    }

    static func validatedHTTPURLString(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try validatedHTTPURL(trimmed)
        return trimmed
    }

    static func httpURLStringIfValid(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return try? validatedHTTPURLString(raw)
    }
}

/// Browser permissions need more semantic detail than an argument digest, but
/// raw browser arguments are not an appropriate reviewer surface. In
/// particular, `browser_type.value` may contain private text. Every browser
/// tool uses this host-generated, bounded preview so the reviewer can verify
/// the exact profile, target, and effect without receiving typed values,
/// cookies, local storage, or profile contents.
private enum BrowserPermissionPreview {
    private struct Arguments {
        let values: [String: JSONValue]

        init?(_ args: ToolArgs) {
            guard let data = args.raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(JSONValue.self, from: data),
                  case .object(let values) = decoded else {
                return nil
            }
            self.values = values
        }

        func string(_ key: String) -> String? {
            guard case .string(let value)? = values[key] else { return nil }
            return value
        }

        func bool(_ key: String) -> Bool? {
            guard case .bool(let value)? = values[key] else { return nil }
            return value
        }

        func integer(_ key: String) -> Int? {
            guard case .number(let value)? = values[key],
                  value.isFinite,
                  value.rounded() == value,
                  value >= Double(Int.min),
                  value <= Double(Int.max) else {
                return nil
            }
            return Int(value)
        }
    }

    static func make(toolName: String, args: ToolArgs) -> PermissionActionPreview? {
        guard let arguments = Arguments(args) else { return nil }
        var fields: [String: String] = [:]

        func set(_ key: String, _ value: String?) {
            guard let value, value.isEmpty == false else { return }
            fields[key] = value
        }

        func set(_ key: String, _ value: Bool) {
            fields[key] = String(value)
        }

        func set(_ key: String, _ value: Int) {
            fields[key] = String(value)
        }

        func profile() -> String {
            let raw = arguments.string("profile")
            return (try? BrowserToolConfig.normalizedProfile(raw))
                ?? raw
                ?? BrowserToolConfig.defaultProfile
        }

        func channel() -> String {
            BrowserToolConfig.normalizedChannel(arguments.string("channel"))
        }

        func browserMode(defaultHeadless: Bool = true) -> String {
            (arguments.bool("headless") ?? defaultHeadless) ? "headless" : "headed"
        }

        func addTarget(defaultKind: String = "current_page") {
            if let selector = arguments.string("selector"), selector.isEmpty == false {
                set("target_kind", "selector")
                set("target", selector)
            } else if let role = arguments.string("role"), role.isEmpty == false,
                      let name = arguments.string("name"), name.isEmpty == false {
                set("target_kind", "role")
                set("target", "\(role):\(name)")
            } else if let text = arguments.string("text"), text.isEmpty == false {
                set("target_kind", "text")
                set("target", text)
            } else {
                set("target_kind", defaultKind)
            }
        }

        func addTargetPosition() {
            set("exact", arguments.bool("exact") ?? false)
            set("nth", arguments.integer("nth") ?? 0)
        }

        switch toolName {
        case "browser_diagnostics":
            set("profile", profile())
            set("channel", channel())
            set("scope", "runtime_and_workspace_browser_metadata")

        case "browser_profiles":
            set("profile_filter", arguments.string("profile") ?? "all")
            set("limit", arguments.integer("limit") ?? 20)
            set("include_profile_size", arguments.bool("includeProfileSize") ?? false)
            set("scope", "profile_metadata_only")

        case "browser_profile_delete":
            let selectedProfile = profile()
            let confirmedProfile = arguments.string("confirmProfile").flatMap {
                try? BrowserToolConfig.normalizedProfile($0)
            }
            set("profile", selectedProfile)
            set("confirmation_matches", confirmedProfile == selectedProfile)
            set("scope", "profile_state_downloads_and_history_metadata")

        case "browser_history":
            set("profile_filter", arguments.string("profile") ?? "all")
            set("limit", arguments.integer("limit") ?? 20)
            set("scope", "history_metadata_only")

        case "browser_navigate":
            set("profile", profile())
            set("browser_mode", browserMode())
            set("channel", channel())
            set("url", arguments.string("url"))

        case "browser_snapshot":
            set("profile", profile())
            set("browser_mode", browserMode())
            set("channel", channel())
            set("scope", "current_live_page")
            set("max_characters", arguments.integer("maxCharacters")
                ?? BrowserToolConfig.maxSnapshotCharacters)

        case "browser_handoff":
            set("profile", profile())
            set("browser_mode", "headed")
            set("channel", channel())
            set("url", arguments.string("url") ?? "current_live_page")
            set("handoff_seconds", arguments.integer("handoffSeconds") ?? 60)

        case "browser_reload", "browser_back", "browser_forward":
            set("profile", profile())
            set("browser_mode", browserMode())
            set("channel", channel())
            set("scope", "current_live_page")

        case "browser_click":
            set("profile", profile())
            set("browser_mode", browserMode())
            set("channel", channel())
            addTarget()
            addTargetPosition()

        case "browser_type":
            set("profile", profile())
            set("browser_mode", browserMode())
            addTarget()
            set("nth", arguments.integer("nth") ?? 0)
            set("clear", arguments.bool("clear") ?? true)
            set("submit", arguments.bool("submit") ?? false)
            set("input_characters", arguments.string("value")?.count ?? 0)

        case "browser_submit":
            set("profile", profile())
            set("browser_mode", browserMode())
            addTarget(defaultKind: "current_form")
            addTargetPosition()
            set("timeout_millis", arguments.integer("timeoutMillis") ?? 5_000)

        case "browser_select_option":
            set("profile", profile())
            set("browser_mode", browserMode())
            addTarget()
            addTargetPosition()
            if let value = arguments.string("optionValue"), value.isEmpty == false {
                set("option_kind", "value")
                set("option", value)
            } else if let label = arguments.string("optionLabel"), label.isEmpty == false {
                set("option_kind", "label")
                set("option", label)
            } else if let index = arguments.integer("optionIndex") {
                set("option_kind", "index")
                set("option", index)
            }

        case "browser_press_key":
            set("profile", profile())
            set("browser_mode", browserMode())
            addTarget(defaultKind: "current_focus")
            addTargetPosition()
            set("key", (try? normalizedBrowserKey(arguments.string("key") ?? ""))
                ?? arguments.string("key"))

        case "browser_scroll":
            set("profile", profile())
            set("browser_mode", browserMode())
            addTarget()
            addTargetPosition()
            if let delta = try? browserScrollDelta(
                direction: arguments.string("direction"),
                amount: arguments.integer("amount"),
                deltaX: arguments.integer("deltaX"),
                deltaY: arguments.integer("deltaY")) {
                set("delta_x", delta.x)
                set("delta_y", delta.y)
            }

        case "browser_wait":
            set("profile", profile())
            addTarget(defaultKind: "timer")
            addTargetPosition()
            set("state", normalizedBrowserWaitState(arguments.string("state")))
            set("timeout_millis", arguments.integer("timeoutMillis") ?? 10_000)

        case "browser_screenshot":
            set("profile", profile())
            set("browser_mode", browserMode())
            set("channel", channel())
            set("url", arguments.string("url") ?? "current_live_page")
            set("output_path", arguments.string("outputPath"))
            set("full_page", arguments.bool("fullPage") ?? true)

        case "browser_upload_file":
            set("profile", profile())
            set("browser_mode", browserMode())
            addTarget()
            addTargetPosition()
            set("file_path", arguments.string("filePath"))

        case "browser_download":
            let selectedProfile = profile()
            set("profile", selectedProfile)
            set("browser_mode", browserMode())
            addTarget()
            addTargetPosition()
            set("download_scope", ".intatis/browser/downloads/\(selectedProfile)")
            set("timeout_millis", arguments.integer("downloadTimeoutMillis") ?? 15_000)

        case "browser_downloads":
            let selectedProfile = profile()
            set("profile", selectedProfile)
            set("limit", arguments.integer("limit") ?? 20)
            set("scope", ".intatis/browser/downloads/\(selectedProfile)")

        case "browser_search":
            set("profile", profile())
            set("browser_mode", browserMode())
            set("channel", channel())
            set("query", arguments.string("query"))
            let engine = arguments.string("engine")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            set("engine", ["duckduckgo", "google", "bing"].contains(engine ?? "")
                ? engine
                : "duckduckgo")

        default:
            return nil
        }

        return PermissionActionPreview(kind: toolName, fields: fields)
    }
}

protocol BrowserPermissionPreviewingTool: Tool {}

extension BrowserPermissionPreviewingTool {
    public func permissionActionPreview(_ args: ToolArgs) -> PermissionActionPreview? {
        BrowserPermissionPreview.make(
            toolName: Self.descriptor.name,
            args: args)
    }
}

private struct BrowserPaths {
    let profile: String
    let profileDir: URL
    let downloadsDir: URL
    let stateFile: URL
    let historyFile: URL
}

private struct BrowserLink: Decodable {
    let text: String?
    let href: String?
}

private struct BrowserInteractiveElement: Decodable {
    let role: String?
    let name: String?
    let text: String?
    let selector: String?
    let tag: String?
    let type: String?
    let placeholder: String?
    let disabled: Bool?
    let checked: Bool?
    let options: [String]?
}

private struct BrowserDownloadEntry: Decodable {
    let filename: String?
    let path: String?
    let url: String?
    let bytes: Int?
}

private struct BrowserOpenedPage: Decodable {
    let url: String?
    let title: String?
}

private struct BrowserActionResult: Decodable {
    let action: String?
    let profile: String?
    let backend: String?
    let backendDetail: String?
    let url: String?
    let title: String?
    let text: String?
    let links: [BrowserLink]?
    let elements: [BrowserInteractiveElement]?
    let screenshotPath: String?
    let uploadedFiles: [String]?
    let downloads: [BrowserDownloadEntry]?
    let openedPage: BrowserOpenedPage?
    let pageCount: Int?
}

private struct BrowserBackendFailureResult: Decodable {
    let marker: String?
    let code: String?
    let effectDisposition: String?
}

private struct BrowserHistoryEntry: Decodable {
    let ts: String?
    let profile: String?
    let action: String?
    let url: String?
    let title: String?
    let screenshotPath: String?
}

private struct BrowserProfileHistorySummary {
    var count: Int = 0
    var latestTimestamp: String?
    var latestAction: String?
    var latestURL: String?
    var latestTitle: String?
}

private struct BrowserDirectoryMetadata {
    let exists: Bool
    let fileCount: Int?
    let bytes: Int?
    let modifiedAt: Date?
}

private struct BrowserProfileRuntimeMetadata {
    let activeBrowserMarkerPresent: Bool
    let profileLockMarkerPresent: Bool

    var hasAnyMarker: Bool {
        activeBrowserMarkerPresent || profileLockMarkerPresent
    }
}

private struct BrowserProfileMetadata {
    let profile: String
    let profileDir: String
    let downloadsDir: String
    let stateFile: String
    let profileDirectory: BrowserDirectoryMetadata
    let downloadDirectory: BrowserDirectoryMetadata
    let runtime: BrowserProfileRuntimeMetadata
    let stateExists: Bool
    let currentURL: String?
    let currentTitle: String?
    let updatedAt: String?
    let screenshotPath: String?
    let navigationCount: Int?
    let navigationIndex: Int?
    let history: BrowserProfileHistorySummary
}

private struct BrowserDiagnosticsResult: Decodable {
    let action: String?
    let nodeVersion: String?
    let platform: String?
    let arch: String?
    let channel: String?
    let profile: String?
    let profileDir: String?
    let downloadsDir: String?
    let stateFile: String?
    let historyFile: String?
    let playwrightAvailable: Bool?
    let playwrightVersion: String?
    let playwrightResolvedFrom: String?
    let checkedLocations: [String]?
    let nodeWebSocketAvailable: Bool?
    let cdpAvailable: Bool?
    let cdpExecutable: String?
    let browserApps: [String: Bool]?
}

private func browserBackendInvocation(
    javaScript: String,
    encodedArguments: String,
    arguments: [String: Any]
) -> BrowserBackendInvocation {
    let readable = ["filePath"].compactMap { arguments[$0] as? String }
    let writable = [
        "profileDir",
        "downloadsDir",
        "stateFile",
        "outputPath",
    ].compactMap { arguments[$0] as? String }
    let session: BrowserBackendSessionSpec?
    if let profileDirectory = arguments["profileDir"] as? String,
       let action = arguments["action"] as? String,
       action != "diagnostics" {
        session = BrowserBackendSessionSpec(
            profileDirectory: profileDirectory,
            channel: arguments["channel"] as? String ?? BrowserToolConfig.defaultChannel,
            headless: arguments["headless"] as? Bool ?? true)
    } else {
        session = nil
    }
    return BrowserBackendInvocation(
        javaScript: javaScript,
        encodedArguments: encodedArguments,
        readableWorkspacePaths: Array(Set(readable)).sorted(),
        writableWorkspacePaths: Array(Set(writable)).sorted(),
        session: session)
}

private func browserJSONLine(from stdout: String) throws -> String {
    for line in stdout.split(separator: "\n").reversed() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }
    }
    throw IntatisError.decoding("browser backend did not return JSON")
}

private func browserBackendFailure(from stdout: String) -> BrowserBackendFailureResult? {
    guard let line = try? browserJSONLine(from: stdout) else { return nil }
    return try? JSONDecoder().decode(
        BrowserBackendFailureResult.self,
        from: Data(line.utf8))
}

private func browserNoEffectRejection(
    from result: ShellResult,
    arguments: [String: Any]
) -> ToolExecutionRejectedWithoutSideEffect? {
    guard let failure = browserBackendFailure(from: result.stdout),
          failure.marker == "intatis_browser_backend_error_v1",
          failure.effectDisposition == ToolExecutionEffectDisposition.notStarted.rawValue,
          let code = failure.code else {
        return nil
    }
    let action = (arguments["action"] as? String) ?? "action"
    switch code {
    case "browser_action_target_not_found":
        return ToolExecutionRejectedWithoutSideEffect(
            code: code,
            message: "browser_\(action) could not find a matching usable element before the action started; take a fresh browser_snapshot and retry using its exact selector or current role+name")
    case "browser_sensitive_target_refused":
        return ToolExecutionRejectedWithoutSideEffect(
            code: code,
            message: "browser_type refused a likely credential or secret field before typing began; use browser_handoff so the user can enter sensitive data directly")
    default:
        return nil
    }
}

private func redactedBrowserText(_ text: String, redactions: [String]) -> String {
    var output = text
    for redaction in redactions where !redaction.isEmpty {
        output = output.replacingOccurrences(of: redaction, with: "[redacted input]")
    }
    return output
}

private func browserSensitiveTypeTargetReason(selector: String?, text: String?, role: String?, name: String?) -> String? {
    let raw = [selector, text, role, name]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    guard !raw.isEmpty else { return nil }

    let tokens = Set(raw.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
    if !tokens.isDisjoint(with: ["password", "passwd", "pwd", "passcode"]) {
        return "password field"
    }
    if !tokens.isDisjoint(with: ["otp", "totp", "2fa", "mfa"]) ||
        raw.contains("two factor") ||
        raw.contains("two-factor") {
        return "two-factor code field"
    }
    if raw.contains("verification code") ||
        raw.contains("security code") ||
        raw.contains("authentication code") ||
        raw.contains("recovery code") ||
        raw.contains("backup code") {
        return "verification code field"
    }
    if tokens.contains("token") ||
        tokens.contains("secret") ||
        tokens.contains("credential") ||
        tokens.contains("apikey") ||
        (tokens.contains("api") && tokens.contains("key")) ||
        (tokens.contains("private") && tokens.contains("key")) {
        return "secret or token field"
    }
    return nil
}

private func browserOutputText(_ result: BrowserActionResult, maxCharacters: Int, redactions: [String] = []) -> String {
    var lines: [String] = []
    lines.append("browser action: \(result.action ?? "unknown")")
    lines.append("profile: \(result.profile ?? BrowserToolConfig.defaultProfile)")
    if let backend = result.backend, !backend.isEmpty {
        var backendLine = "backend: \(backend)"
        if let backendDetail = result.backendDetail, !backendDetail.isEmpty {
            backendLine += " (\(backendDetail))"
        }
        lines.append(backendLine)
    }
    if let title = result.title, !title.isEmpty {
        lines.append("title: \(title)")
    }
    if let url = result.url, !url.isEmpty {
        lines.append("url: \(url)")
    }
    if let openedPage = result.openedPage {
        let title = (openedPage.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let url = (openedPage.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty || !url.isEmpty {
            var line = "selected new page"
            if !title.isEmpty { line += ": \(title)" }
            if !url.isEmpty { line += title.isEmpty ? ": \(url)" : " - \(url)" }
            lines.append(line)
        }
    }
    if let pageCount = result.pageCount, pageCount > 1 {
        lines.append("open pages observed: \(pageCount)")
    }
    if let screenshotPath = result.screenshotPath, !screenshotPath.isEmpty {
        lines.append("screenshot: \(screenshotPath)")
    }
    if let uploadedFiles = result.uploadedFiles, !uploadedFiles.isEmpty {
        lines.append("uploaded files:")
        for file in uploadedFiles.prefix(20) {
            lines.append("- \(file)")
        }
    }
    if let downloads = result.downloads, !downloads.isEmpty {
        lines.append("downloads:")
        for download in downloads.prefix(20) {
            let path = download.path ?? ""
            let name = download.filename ?? (path.isEmpty ? "download" : path)
            var line = "- \(name)"
            if !path.isEmpty { line += " -> \(path)" }
            if let bytes = download.bytes { line += " (\(bytes) bytes)" }
            if let url = download.url, !url.isEmpty { line += " from \(url)" }
            lines.append(line)
        }
    }
    if let elements = result.elements, !elements.isEmpty {
        lines.append("")
        lines.append("interactive elements:")
        for (index, element) in elements.prefix(50).enumerated() {
            let role = redactedBrowserText((element.role ?? "element").trimmingCharacters(in: .whitespacesAndNewlines), redactions: redactions)
            let name = redactedBrowserText((element.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines), redactions: redactions)
            let text = redactedBrowserText((element.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines), redactions: redactions)
            let placeholder = redactedBrowserText((element.placeholder ?? "").trimmingCharacters(in: .whitespacesAndNewlines), redactions: redactions)
            let selector = redactedBrowserText((element.selector ?? "").trimmingCharacters(in: .whitespacesAndNewlines), redactions: redactions)
            let type = redactedBrowserText((element.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines), redactions: redactions)
            let label = [name, text, placeholder].first(where: { !$0.isEmpty }) ?? ""
            var line = "\(index + 1). \(role)"
            if !label.isEmpty { line += " \"\(label)\"" }
            if !selector.isEmpty { line += " selector=\(selector)" }
            if !type.isEmpty { line += " type=\(type)" }
            if let checked = element.checked { line += " checked=\(checked)" }
            if element.disabled == true { line += " disabled=true" }
            if let options = element.options, !options.isEmpty {
                let optionText = options.prefix(8)
                    .map { redactedBrowserText($0.trimmingCharacters(in: .whitespacesAndNewlines), redactions: redactions) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                if !optionText.isEmpty { line += " options=[\(optionText)]" }
            }
            lines.append(line)
        }
    }
    if let links = result.links, !links.isEmpty {
        lines.append("")
        lines.append("links:")
        for (index, link) in links.prefix(30).enumerated() {
            let text = redactedBrowserText((link.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines), redactions: redactions)
            let href = redactedBrowserText((link.href ?? "").trimmingCharacters(in: .whitespacesAndNewlines), redactions: redactions)
            if !text.isEmpty || !href.isEmpty {
                lines.append("\(index + 1). \(text.isEmpty ? "(untitled)" : text) - \(href)")
            }
        }
    }
    let body = redactedBrowserText((result.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines), redactions: redactions)
    if !body.isEmpty {
        lines.append("")
        lines.append("page text:")
        lines.append(String(body.prefix(maxCharacters)))
        if body.count > maxCharacters {
            lines.append("[truncated]")
        }
    }
    return lines.joined(separator: "\n")
}

private struct BrowserDownloadFile {
    let relativePath: String
    let bytes: Int
    let modifiedAt: Date?
}

private func browserDownloadFiles(profile: String, workspace: URL, limit: Int) throws -> [BrowserDownloadFile] {
    let downloadsURL = try BrowserToolConfig.downloadsURL(profile: profile, workspace: workspace)
    guard FileManager.default.fileExists(atPath: downloadsURL.path) else { return [] }
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
    guard let enumerator = FileManager.default.enumerator(at: downloadsURL,
                                                          includingPropertiesForKeys: Array(keys),
                                                          options: [.skipsHiddenFiles]) else {
        return []
    }
    var files: [BrowserDownloadFile] = []
    for case let url as URL in enumerator {
        let values = try url.resourceValues(forKeys: keys)
        guard values.isRegularFile == true else { continue }
        if url.lastPathComponent.hasSuffix(".crdownload") { continue }
        files.append(BrowserDownloadFile(
            relativePath: PathConfinement.relativePath(of: url, root: workspace),
            bytes: values.fileSize ?? 0,
            modifiedAt: values.contentModificationDate))
    }
    return files
        .sorted { lhs, rhs in
            switch (lhs.modifiedAt, rhs.modifiedAt) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.relativePath < rhs.relativePath
            }
        }
        .prefix(limit)
        .map { $0 }
}

private func browserDownloadsOutput(_ files: [BrowserDownloadFile], profile: String, limit: Int) -> String {
    var lines: [String] = []
    lines.append("browser downloads: \(files.count) file\(files.count == 1 ? "" : "s")")
    lines.append("profile: \(profile)")
    lines.append("limit: \(limit)")
    lines.append("downloads dir: .intatis/browser/downloads/\(profile)")
    if files.isEmpty {
        lines.append("")
        lines.append("no downloaded files")
        return lines.joined(separator: "\n")
    }
    lines.append("")
    for (index, file) in files.enumerated() {
        var line = "\(index + 1). \(file.relativePath) (\(file.bytes) bytes)"
        if let modifiedAt = file.modifiedAt {
            line += " modified \(ISO8601DateFormatter().string(from: modifiedAt))"
        }
        lines.append(line)
    }
    return lines.joined(separator: "\n")
}

private func browserProfileNamesFromDirectories(at url: URL) -> Set<String> {
    let keys: Set<URLResourceKey> = [.isDirectoryKey]
    guard let urls = try? FileManager.default.contentsOfDirectory(at: url,
                                                                  includingPropertiesForKeys: Array(keys),
                                                                  options: []) else {
        return []
    }
    return Set(urls.compactMap { item in
        guard (try? item.resourceValues(forKeys: keys).isDirectory) == true else { return nil }
        let raw = item.lastPathComponent
        return try? BrowserToolConfig.normalizedProfile(raw)
    })
}

private func browserProfileNamesFromStateFiles(at url: URL) -> Set<String> {
    let keys: Set<URLResourceKey> = [.isRegularFileKey]
    guard let urls = try? FileManager.default.contentsOfDirectory(at: url,
                                                                  includingPropertiesForKeys: Array(keys),
                                                                  options: []) else {
        return []
    }
    return Set(urls.compactMap { item in
        guard item.pathExtension == "json",
              (try? item.resourceValues(forKeys: keys).isRegularFile) == true else {
            return nil
        }
        let raw = item.deletingPathExtension().lastPathComponent
        return try? BrowserToolConfig.normalizedProfile(raw)
    })
}

private func browserHistorySummaries(at historyURL: URL) -> [String: BrowserProfileHistorySummary] {
    guard FileManager.default.fileExists(atPath: historyURL.path),
          let text = try? String(contentsOf: historyURL, encoding: .utf8) else {
        return [:]
    }
    let decoder = JSONDecoder()
    var summaries: [String: BrowserProfileHistorySummary] = [:]
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let entry = try? decoder.decode(BrowserHistoryEntry.self, from: Data(line.utf8)) else {
            continue
        }
        let profile = (try? BrowserToolConfig.normalizedProfile(entry.profile)) ?? BrowserToolConfig.defaultProfile
        var summary = summaries[profile] ?? BrowserProfileHistorySummary()
        summary.count += 1
        summary.latestTimestamp = entry.ts
        summary.latestAction = entry.action
        summary.latestURL = BrowserToolConfig.httpURLStringIfValid(entry.url)
        summary.latestTitle = entry.title
        summaries[profile] = summary
    }
    return summaries
}

private func browserDirectoryMetadata(at url: URL, includeRecursiveSize: Bool) -> BrowserDirectoryMetadata {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        return BrowserDirectoryMetadata(exists: false, fileCount: nil, bytes: nil, modifiedAt: nil)
    }
    let directoryModifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    guard includeRecursiveSize else {
        return BrowserDirectoryMetadata(exists: true, fileCount: nil, bytes: nil, modifiedAt: directoryModifiedAt ?? nil)
    }

    let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
    guard let enumerator = FileManager.default.enumerator(at: url,
                                                          includingPropertiesForKeys: Array(keys),
                                                          options: []) else {
        return BrowserDirectoryMetadata(exists: true, fileCount: 0, bytes: 0, modifiedAt: directoryModifiedAt ?? nil)
    }
    var fileCount = 0
    var bytes = 0
    var latestModifiedAt = directoryModifiedAt ?? nil
    for case let item as URL in enumerator {
        guard let values = try? item.resourceValues(forKeys: keys),
              values.isRegularFile == true else {
            continue
        }
        fileCount += 1
        bytes += values.fileSize ?? 0
        if let modifiedAt = values.contentModificationDate,
           latestModifiedAt == nil || modifiedAt > latestModifiedAt! {
            latestModifiedAt = modifiedAt
        }
    }
    return BrowserDirectoryMetadata(exists: true, fileCount: fileCount, bytes: bytes, modifiedAt: latestModifiedAt)
}

private let browserActiveRuntimeMarkerNames = [
    "DevToolsActivePort",
]

private let browserProfileLockMarkerNames = [
    "SingletonLock",
    "SingletonCookie",
    "SingletonSocket",
]

private func browserProfileRuntimeMetadata(at profileURL: URL) -> BrowserProfileRuntimeMetadata {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: profileURL.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        return BrowserProfileRuntimeMetadata(activeBrowserMarkerPresent: false,
                                             profileLockMarkerPresent: false)
    }

    let activeMarkerPresent = browserActiveRuntimeMarkerNames.contains { marker in
        FileManager.default.fileExists(atPath: profileURL.appendingPathComponent(marker).path)
    }
    let profileLockMarkerPresent = browserProfileLockMarkerNames.contains { marker in
        FileManager.default.fileExists(atPath: profileURL.appendingPathComponent(marker).path)
    }
    return BrowserProfileRuntimeMetadata(activeBrowserMarkerPresent: activeMarkerPresent,
                                         profileLockMarkerPresent: profileLockMarkerPresent)
}

private func browserProfileMetadata(profile: String,
                                    workspace: URL,
                                    history: BrowserProfileHistorySummary,
                                    includeProfileSize: Bool) throws -> BrowserProfileMetadata {
    let profileURL = try BrowserToolConfig.profileURL(profile: profile, workspace: workspace)
    let downloadsURL = try BrowserToolConfig.downloadsURL(profile: profile, workspace: workspace)
    let stateURL = try BrowserToolConfig.stateURL(profile: profile, workspace: workspace)
    let state = browserStateDictionary(at: stateURL)
    let navigationStack = (state["navigationStack"] as? [Any])?.compactMap {
        BrowserToolConfig.httpURLStringIfValid($0 as? String)
    }
    let navigationIndex = state["navigationIndex"] as? Int
        ?? (state["navigationIndex"] as? NSNumber)?.intValue
        ?? ((state["navigationIndex"] as? String).flatMap(Int.init))
    return BrowserProfileMetadata(
        profile: profile,
        profileDir: ".intatis/browser/profiles/\(profile)",
        downloadsDir: ".intatis/browser/downloads/\(profile)",
        stateFile: ".intatis/browser/state/\(profile).json",
        profileDirectory: browserDirectoryMetadata(at: profileURL, includeRecursiveSize: includeProfileSize),
        downloadDirectory: browserDirectoryMetadata(at: downloadsURL, includeRecursiveSize: true),
        runtime: browserProfileRuntimeMetadata(at: profileURL),
        stateExists: FileManager.default.fileExists(atPath: stateURL.path),
        currentURL: BrowserToolConfig.httpURLStringIfValid(state["url"] as? String),
        currentTitle: state["title"] as? String,
        updatedAt: state["updatedAt"] as? String,
        screenshotPath: state["screenshotPath"] as? String,
        navigationCount: navigationStack?.count,
        navigationIndex: navigationIndex,
        history: history)
}

private func browserKnownProfiles(workspace: URL,
                                  filter: String?,
                                  includeProfileSize: Bool,
                                  limit: Int) throws -> [BrowserProfileMetadata] {
    let browserRoot = try BrowserToolConfig.browserRoot(in: workspace)
    let profilesURL = browserRoot.appendingPathComponent("profiles", isDirectory: true)
    let stateURL = browserRoot.appendingPathComponent("state", isDirectory: true)
    let downloadsURL = browserRoot.appendingPathComponent("downloads", isDirectory: true)
    let historyURL = try BrowserToolConfig.historyURL(workspace: workspace)
    let histories = browserHistorySummaries(at: historyURL)

    var profiles = Set<String>()
    profiles.formUnion(browserProfileNamesFromDirectories(at: profilesURL))
    profiles.formUnion(browserProfileNamesFromStateFiles(at: stateURL))
    profiles.formUnion(browserProfileNamesFromDirectories(at: downloadsURL))
    profiles.formUnion(histories.keys)

    if let filter {
        profiles = [filter]
    }

    return try profiles
        .sorted()
        .prefix(limit)
        .map { profile in
            try browserProfileMetadata(profile: profile,
                                       workspace: workspace,
                                       history: histories[profile] ?? BrowserProfileHistorySummary(),
                                       includeProfileSize: includeProfileSize)
        }
}

private func browserDirectoryMetadataSummary(_ metadata: BrowserDirectoryMetadata, includeSizeWasRequested: Bool) -> String {
    guard metadata.exists else { return "absent" }
    var parts = ["present"]
    if includeSizeWasRequested,
       let fileCount = metadata.fileCount,
       let bytes = metadata.bytes {
        parts.append("\(fileCount) file\(fileCount == 1 ? "" : "s")")
        parts.append("\(bytes) bytes")
    } else if includeSizeWasRequested {
        parts.append("size unavailable")
    }
    if let modifiedAt = metadata.modifiedAt {
        parts.append("modified \(ISO8601DateFormatter().string(from: modifiedAt))")
    }
    return parts.joined(separator: "; ")
}

private func browserProfileRuntimeMetadataSummary(_ metadata: BrowserProfileRuntimeMetadata) -> String {
    var parts: [String] = []
    if metadata.activeBrowserMarkerPresent {
        parts.append("active browser marker present")
    }
    if metadata.profileLockMarkerPresent {
        parts.append("profile lock marker present")
    }
    return parts.isEmpty ? "none detected" : parts.joined(separator: "; ")
}

private func browserProfilesOutput(_ profiles: [BrowserProfileMetadata],
                                   filter: String?,
                                   limit: Int,
                                   includeProfileSize: Bool) -> String {
    var lines: [String] = []
    lines.append("browser profiles: \(profiles.count) profile\(profiles.count == 1 ? "" : "s")")
    if let filter {
        lines.append("profile filter: \(filter)")
    }
    lines.append("limit: \(limit)")
    lines.append("metadata only: reads Intatis profile names, state, history, download metadata, directory stats, and browser runtime marker existence; does not read cookies, localStorage, marker contents, or browser profile databases.")
    if profiles.isEmpty {
        lines.append("")
        lines.append("no browser profiles found")
        return lines.joined(separator: "\n")
    }
    for (index, profile) in profiles.enumerated() {
        lines.append("")
        lines.append("\(index + 1). profile: \(profile.profile)")
        if let title = profile.currentTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            lines.append("   title: \(title)")
        }
        if let url = profile.currentURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            lines.append("   url: \(url)")
        }
        if let updatedAt = profile.updatedAt?.trimmingCharacters(in: .whitespacesAndNewlines), !updatedAt.isEmpty {
            lines.append("   updated: \(updatedAt)")
        }
        if let screenshotPath = profile.screenshotPath?.trimmingCharacters(in: .whitespacesAndNewlines), !screenshotPath.isEmpty {
            lines.append("   screenshot: \(screenshotPath)")
        }
        if let navigationCount = profile.navigationCount {
            var navigation = "   navigation: \(navigationCount) entr\(navigationCount == 1 ? "y" : "ies")"
            if let navigationIndex = profile.navigationIndex {
                navigation += ", index \(navigationIndex)"
            }
            lines.append(navigation)
        }
        lines.append("   history entries: \(profile.history.count)")
        lines.append("   runtime markers: \(browserProfileRuntimeMetadataSummary(profile.runtime))")
        if let latestTimestamp = profile.history.latestTimestamp, !latestTimestamp.isEmpty {
            var latest = "   latest history: \(latestTimestamp)"
            if let action = profile.history.latestAction, !action.isEmpty { latest += " \(action)" }
            if let title = profile.history.latestTitle, !title.isEmpty { latest += " - \(title)" }
            if let url = profile.history.latestURL, !url.isEmpty { latest += " - \(url)" }
            lines.append(latest)
        }
        let downloadCount = profile.downloadDirectory.fileCount ?? 0
        let downloadBytes = profile.downloadDirectory.bytes ?? 0
        var downloadsLine = "   downloads: \(downloadCount) file\(downloadCount == 1 ? "" : "s"), \(downloadBytes) bytes"
        if let modifiedAt = profile.downloadDirectory.modifiedAt {
            downloadsLine += ", modified \(ISO8601DateFormatter().string(from: modifiedAt))"
        }
        lines.append(downloadsLine)
        lines.append("   profile dir: \(profile.profileDir) (\(browserDirectoryMetadataSummary(profile.profileDirectory, includeSizeWasRequested: includeProfileSize)))")
        lines.append("   state file: \(profile.stateFile) (\(profile.stateExists ? "present" : "absent"))")
        lines.append("   downloads dir: \(profile.downloadsDir) (\(profile.downloadDirectory.exists ? "present" : "absent"))")
    }
    return lines.joined(separator: "\n")
}

private let browserStateHistoryWriteLock = NSLock()

private actor BrowserProfileCommandLocks {
    private var lockedProfiles: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(_ key: String) async {
        if lockedProfiles.contains(key) == false {
            lockedProfiles.insert(key)
            return
        }

        await withCheckedContinuation { continuation in
            waiters[key, default: []].append(continuation)
        }
    }

    func release(_ key: String) {
        guard var queue = waiters[key], queue.isEmpty == false else {
            lockedProfiles.remove(key)
            return
        }
        let next = queue.removeFirst()
        waiters[key] = queue.isEmpty ? nil : queue
        next.resume()
    }
}

private let browserProfileCommandLocks = BrowserProfileCommandLocks()

private func browserProfileCommandLockKey(paths: BrowserPaths) -> String {
    paths.profileDir.standardizedFileURL.path
}

private func withBrowserProfileCommandLock<T>(
    paths: BrowserPaths,
    operation: () async throws -> T
) async throws -> T {
    let key = browserProfileCommandLockKey(paths: paths)
    await browserProfileCommandLocks.acquire(key)
    do {
        let value = try await operation()
        await browserProfileCommandLocks.release(key)
        return value
    } catch {
        await browserProfileCommandLocks.release(key)
        throw error
    }
}

private enum BrowserHistoryDirection {
    case back
    case forward

    var actionName: String {
        switch self {
        case .back: return "back"
        case .forward: return "forward"
        }
    }

    var offset: Int {
        switch self {
        case .back: return -1
        case .forward: return 1
        }
    }

    var missingEntryMessage: String {
        switch self {
        case .back: return "no previous browser history entry for this profile"
        case .forward: return "no next browser history entry for this profile"
        }
    }
}

private func browserStateDictionary(at url: URL) -> [String: Any] {
    guard FileManager.default.fileExists(atPath: url.path),
          let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return object
}

private func browserHistoryStackFromMetadata(paths: BrowserPaths) -> [String] {
    guard FileManager.default.fileExists(atPath: paths.historyFile.path),
          let text = try? String(contentsOf: paths.historyFile, encoding: .utf8) else {
        return []
    }
    let decoder = JSONDecoder()
    var stack: [String] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let entry = try? decoder.decode(BrowserHistoryEntry.self, from: Data(line.utf8)),
              entry.profile == paths.profile,
              let url = BrowserToolConfig.httpURLStringIfValid(entry.url) else {
            continue
        }
        if stack.last != url {
            stack.append(url)
        }
    }
    return stack
}

private func browserNavigationSnapshot(paths: BrowserPaths) -> (stack: [String], index: Int, currentURL: String?) {
    let previousState = browserStateDictionary(at: paths.stateFile)
    let currentURL = BrowserToolConfig.httpURLStringIfValid(previousState["url"] as? String)
    let rawStack = previousState["navigationStack"] as? [Any]
    var stack = rawStack?.compactMap {
        BrowserToolConfig.httpURLStringIfValid($0 as? String)
    } ?? []
    if stack.isEmpty {
        stack = browserHistoryStackFromMetadata(paths: paths)
    }
    if stack.isEmpty, let currentURL, currentURL.isEmpty == false {
        stack = [currentURL]
    }

    let rawIndex = previousState["navigationIndex"]
    var index = rawIndex as? Int
        ?? (rawIndex as? NSNumber)?.intValue
        ?? ((rawIndex as? String).flatMap(Int.init))
    if index == nil,
       let currentURL,
       currentURL.isEmpty == false,
       let existingIndex = stack.lastIndex(of: currentURL) {
        index = existingIndex
    }
    if index == nil {
        index = stack.isEmpty ? 0 : stack.count - 1
    }
    let clampedIndex: Int
    if stack.isEmpty {
        clampedIndex = 0
    } else {
        clampedIndex = min(max(index ?? 0, 0), stack.count - 1)
    }
    return (stack, clampedIndex, currentURL)
}

private func browserHistoryNavigationURL(direction: BrowserHistoryDirection, paths: BrowserPaths) throws -> String {
    let snapshot = browserNavigationSnapshot(paths: paths)
    guard snapshot.stack.isEmpty == false else {
        throw IntatisError.config("no current browser history for this profile; call browser_navigate or browser_search first")
    }
    let targetIndex = snapshot.index + direction.offset
    guard snapshot.stack.indices.contains(targetIndex) else {
        throw IntatisError.config(direction.missingEntryMessage)
    }
    return try BrowserToolConfig.validatedHTTPURLString(snapshot.stack[targetIndex])
}

private func updateBrowserStateAndHistory(_ result: BrowserActionResult, paths: BrowserPaths) throws {
    browserStateHistoryWriteLock.lock()
    defer { browserStateHistoryWriteLock.unlock() }

    let timestamp = ISO8601DateFormatter().string(from: Date())
    let snapshot = browserNavigationSnapshot(paths: paths)
    let rawResultURL = (result.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let resultURL = rawResultURL.isEmpty
        ? ""
        : try BrowserToolConfig.validatedHTTPURLString(rawResultURL)
    var navigationStack = snapshot.stack
    var navigationIndex = snapshot.index
    if resultURL.isEmpty == false {
        switch result.action ?? "" {
        case BrowserHistoryDirection.back.actionName:
            if let targetIndex = navigationStack.lastIndex(of: resultURL), targetIndex <= navigationIndex {
                navigationIndex = targetIndex
            } else if navigationStack.indices.contains(navigationIndex - 1) {
                navigationIndex -= 1
                navigationStack[navigationIndex] = resultURL
            }
        case BrowserHistoryDirection.forward.actionName:
            if let targetIndex = navigationStack.lastIndex(of: resultURL), targetIndex >= navigationIndex {
                navigationIndex = targetIndex
            } else if navigationStack.indices.contains(navigationIndex + 1) {
                navigationIndex += 1
                navigationStack[navigationIndex] = resultURL
            }
        default:
            if navigationStack.isEmpty {
                navigationStack = [resultURL]
                navigationIndex = 0
            } else if navigationStack.indices.contains(navigationIndex),
                      navigationStack[navigationIndex] == resultURL {
                // Keep the current stack position for reload/snapshot and same-page actions.
            } else {
                if navigationStack.indices.contains(navigationIndex),
                   navigationIndex < navigationStack.count - 1 {
                    navigationStack = Array(navigationStack.prefix(navigationIndex + 1))
                }
                if navigationStack.last != resultURL {
                    navigationStack.append(resultURL)
                }
                navigationIndex = navigationStack.count - 1
            }
        }
    }

    var state: [String: Any] = [
        "profile": result.profile ?? paths.profile,
        "url": result.url ?? "",
        "title": result.title ?? "",
        "updatedAt": timestamp,
        "navigationStack": navigationStack,
        "navigationIndex": navigationIndex,
    ]
    if let screenshotPath = result.screenshotPath, !screenshotPath.isEmpty {
        state["screenshotPath"] = screenshotPath
    }
    let stateData = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
    try stateData.write(to: paths.stateFile, options: .atomic)

    var history: [String: String] = [
        "ts": timestamp,
        "profile": result.profile ?? paths.profile,
        "action": result.action ?? "unknown",
        "url": result.url ?? "",
        "title": result.title ?? "",
    ]
    if let screenshotPath = result.screenshotPath, !screenshotPath.isEmpty {
        history["screenshotPath"] = screenshotPath
    }
    var line = try JSONSerialization.data(withJSONObject: history, options: [.sortedKeys])
    line.append(Data("\n".utf8))
    if FileManager.default.fileExists(atPath: paths.historyFile.path),
       let handle = try? FileHandle(forWritingTo: paths.historyFile) {
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    } else {
        try line.write(to: paths.historyFile, options: .atomic)
    }
}

private struct BrowserProfileDeleteSummary {
    let removedProfileData: Bool
    let removedDownloads: Bool
    let removedState: Bool
    let removedHistoryEntries: Int
    let keptHistoryEntries: Int
    let runtimeBeforeDelete: BrowserProfileRuntimeMetadata
}

private func removeBrowserItemIfPresent(_ url: URL) throws -> Bool {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return false
    }
    try FileManager.default.removeItem(at: url)
    return true
}

private func removeBrowserStateAndPruneHistory(profile: String, paths: BrowserPaths) throws -> (removedState: Bool, removedHistoryEntries: Int, keptHistoryEntries: Int) {
    browserStateHistoryWriteLock.lock()
    defer { browserStateHistoryWriteLock.unlock() }

    let removedState = try removeBrowserItemIfPresent(paths.stateFile)
    guard FileManager.default.fileExists(atPath: paths.historyFile.path) else {
        return (removedState, 0, 0)
    }

    let text = try String(contentsOf: paths.historyFile, encoding: .utf8)
    let decoder = JSONDecoder()
    var keptLines: [String] = []
    var removed = 0
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
        let rawLine = String(line)
        if let entry = try? decoder.decode(BrowserHistoryEntry.self, from: Data(line.utf8)) {
            let entryProfile = (try? BrowserToolConfig.normalizedProfile(entry.profile)) ?? BrowserToolConfig.defaultProfile
            if entryProfile == profile {
                removed += 1
                continue
            }
        }
        keptLines.append(rawLine)
    }

    if keptLines.isEmpty {
        _ = try removeBrowserItemIfPresent(paths.historyFile)
    } else {
        let keptText = keptLines.joined(separator: "\n") + "\n"
        try Data(keptText.utf8).write(to: paths.historyFile, options: .atomic)
    }
    return (removedState, removed, keptLines.count)
}

private func browserProfileDeleteOutput(profile: String,
                                        paths: BrowserPaths,
                                        summary: BrowserProfileDeleteSummary,
                                        workspace: URL) -> String {
    let profileDir = PathConfinement.relativePath(of: paths.profileDir, root: workspace)
    let stateFile = PathConfinement.relativePath(of: paths.stateFile, root: workspace)
    let downloadsDir = PathConfinement.relativePath(of: paths.downloadsDir, root: workspace)
    let historyFile = PathConfinement.relativePath(of: paths.historyFile, root: workspace)
    var lines = [
        "browser profile deleted: \(profile)",
        "removed profile data: \(summary.removedProfileData ? "yes" : "no") (\(profileDir))",
        "removed state file: \(summary.removedState ? "yes" : "no") (\(stateFile))",
        "removed downloads: \(summary.removedDownloads ? "yes" : "no") (\(downloadsDir))",
        "removed history entries: \(summary.removedHistoryEntries) (\(historyFile))",
        "kept history entries: \(summary.keptHistoryEntries)",
        "scope: workspace .intatis/browser metadata and profile data only",
    ]
    if summary.runtimeBeforeDelete.hasAnyMarker {
        lines.insert("profile runtime markers: present before delete (\(browserProfileRuntimeMetadataSummary(summary.runtimeBeforeDelete)); close any browser using this profile before retrying if cleanup fails)", at: 1)
    }
    return lines.joined(separator: "\n")
}

private func playwrightCommand(
    arguments: [String: Any]
) throws -> BrowserBackendInvocation {
    let data = try JSONSerialization.data(withJSONObject: arguments, options: [])
    let payload = data.base64EncodedString()
    let javaScript = """
    const fs = require('fs');
    const path = require('path');
    const childProcess = require('child_process');

    const args = JSON.parse(Buffer.from(process.env.INTATIS_BROWSER_ARGS, 'base64').toString('utf8'));
    const maxText = Math.max(1, Math.min(args.maxCharacters || 20000, 100000));
    const waitMillis = Math.max(0, Math.min(args.waitMillis || 600, 10000));
    const handoffMillis = Math.max(1000, Math.min(args.handoffTimeoutMillis || 30000, 600000));
    class BrowserActionNotStartedError extends Error {
      constructor(code) {
        super(code);
        this.name = 'BrowserActionNotStartedError';
        this.code = code;
      }
    }
    function actionTargetNotFound() {
      return new BrowserActionNotStartedError('browser_action_target_not_found');
    }
    function emitNoEffectFailure(error) {
      if (!(error instanceof BrowserActionNotStartedError)) return;
      console.log(JSON.stringify({
        marker: 'intatis_browser_backend_error_v1',
        code: error.code,
        effectDisposition: 'not_started'
      }));
    }
    const commandWatchdogMillis = Math.max(60000, handoffMillis + 20000);
    const commandWatchdog = setTimeout(() => {
      console.error('browser command timed out');
      process.exit(124);
    }, commandWatchdogMillis);

    function unique(values) {
      return [...new Set(values.filter((value) => typeof value === 'string' && value.length > 0))];
    }

    function safeFilename(raw) {
      const base = path.basename(String(raw || 'download')).replace(/[^A-Za-z0-9._ -]/g, '_').slice(0, 120);
      return base.length ? base : 'download';
    }

    function uniqueDownloadPath(filename) {
      fs.mkdirSync(args.downloadsDir, { recursive: true });
      const parsed = path.parse(safeFilename(filename));
      let candidate = path.join(args.downloadsDir, parsed.base);
      let index = 1;
      while (fs.existsSync(candidate)) {
        candidate = path.join(args.downloadsDir, `${parsed.name}-${index}${parsed.ext}`);
        index += 1;
      }
      return candidate;
    }

    function fileSize(outputPath) {
      try { return fs.statSync(outputPath).size; } catch (_) { return 0; }
    }

    function relativeDownloadPath(outputPath) {
      const base = args.downloadsRelativeDir || '';
      return base ? path.join(base, path.basename(outputPath)) : outputPath;
    }

    function trustedPlaywrightModules() {
      // Never resolve from cwd, NODE_PATH, npm's dynamic global root, or a
      // caller-provided environment variable. The workspace is model-writable,
      // so loading workspace/node_modules would turn a browser action into
      // arbitrary native-code execution outside the tool contract.
      return unique([
        '/opt/homebrew/lib/node_modules/playwright',
        '/usr/local/lib/node_modules/playwright',
        '/usr/lib/node_modules/playwright'
      ]);
    }

    function trustedModuleInfo(candidate) {
      const moduleRoot = fs.realpathSync(candidate);
      const trustedParent = fs.realpathSync(path.dirname(candidate));
      if (moduleRoot !== candidate && !moduleRoot.startsWith(trustedParent + path.sep)) {
        throw new Error('trusted Playwright module resolves outside its fixed runtime root');
      }
      const entry = fs.realpathSync(require.resolve(moduleRoot));
      if (entry !== moduleRoot && !entry.startsWith(moduleRoot + path.sep)) {
        throw new Error('Playwright entry resolves outside its fixed module root');
      }
      return { moduleRoot, entry };
    }

    function loadPlaywright() {
      const checked = [];
      for (const candidate of trustedPlaywrightModules()) {
        checked.push(candidate);
        try {
          const trusted = trustedModuleInfo(candidate);
          const mod = require(trusted.entry);
          return { mod, resolvedFrom: trusted.entry, moduleRoot: trusted.moduleRoot, checked };
        } catch (error) {
          checked.push(`${candidate} failed: ${error.message}`);
        }
      }
      const error = new Error([
        'playwright is not installed or not resolvable by Node.',
        'Install Playwright in a trusted fixed global runtime root (/opt/homebrew, /usr/local, or /usr).',
        'Workspace-local node_modules and environment-selected module paths are intentionally ignored.'
      ].join(' '));
      error.checked = checked;
      throw error;
    }

    function playwrightVersion(moduleRoot) {
      if (moduleRoot) {
        try { return JSON.parse(fs.readFileSync(path.join(moduleRoot, 'package.json'), 'utf8')).version || ''; } catch (_) {}
      }
      return '';
    }

    function browserAppStatus() {
      if (process.platform !== 'darwin') return {};
      return {
        chrome: fs.existsSync('/Applications/Google Chrome.app'),
        edge: fs.existsSync('/Applications/Microsoft Edge.app'),
        chromium: fs.existsSync('/Applications/Chromium.app')
      };
    }

    function cdpExecutableForChannel(channel) {
      const value = (channel || 'chromium').toLowerCase();
      const candidates = [];
      if (process.platform === 'darwin') {
        if (value.startsWith('msedge')) candidates.push('/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge');
        if (value.startsWith('chrome')) candidates.push('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome');
        if (value === 'chromium') candidates.push('/Applications/Chromium.app/Contents/MacOS/Chromium');
        candidates.push('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome');
        candidates.push('/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge');
        candidates.push('/Applications/Chromium.app/Contents/MacOS/Chromium');
      } else {
        if (value.startsWith('msedge')) candidates.push('microsoft-edge', 'microsoft-edge-stable');
        if (value.startsWith('chrome')) candidates.push('google-chrome', 'google-chrome-stable');
        candidates.push('chromium', 'chromium-browser', 'google-chrome', 'microsoft-edge');
      }
      for (const candidate of unique(candidates)) {
        try {
          if (candidate.includes('/')) {
            if (fs.existsSync(candidate)) return candidate;
          } else {
            childProcess.execFileSync('which', [candidate], { stdio: ['ignore', 'ignore', 'ignore'] });
            return candidate;
          }
        } catch (_) {}
      }
      return '';
    }

    if (args.action === 'diagnostics') {
      let available = false;
      let resolvedFrom = '';
      let version = '';
      let checked = trustedPlaywrightModules();
      try {
        const info = loadPlaywright();
        available = true;
        resolvedFrom = info.resolvedFrom || '';
        version = playwrightVersion(info.moduleRoot);
        checked = info.checked || checked;
      } catch (error) {
        checked = error.checked || checked.concat([String(error && error.message ? error.message : error)]);
      }
      console.log(JSON.stringify({
        action: 'diagnostics',
        nodeVersion: process.version,
        platform: process.platform,
        arch: process.arch,
        channel: args.channel,
        profile: args.profile,
        profileDir: args.profileDir,
        downloadsDir: args.downloadsDir,
        stateFile: args.stateFile,
        historyFile: args.historyFile,
        playwrightAvailable: available,
        playwrightVersion: version,
        playwrightResolvedFrom: resolvedFrom,
        checkedLocations: checked,
        nodeWebSocketAvailable: typeof WebSocket === 'function',
        cdpAvailable: typeof WebSocket === 'function' && !!cdpExecutableForChannel(args.channel),
        cdpExecutable: cdpExecutableForChannel(args.channel),
        browserApps: browserAppStatus()
      }));
      process.exit(0);
    }

    let chromium;
    let playwrightInfo = loadPlaywright();
    ({ chromium } = playwrightInfo.mod);

    function validatedNavigationURL(value) {
      if (typeof value !== 'string' || !value.trim()) return undefined;
      try {
        const parsed = new URL(value.trim());
        if (!['http:', 'https:'].includes(parsed.protocol) || !parsed.hostname) {
          throw new Error('unsupported browser URL');
        }
        return parsed.toString();
      } catch (_) {
        throw new Error('browser URL must be http(s) with a host');
      }
    }

    function readStateURL() {
      let state;
      try {
        if (!args.stateFile || !fs.existsSync(args.stateFile)) return undefined;
        state = JSON.parse(fs.readFileSync(args.stateFile, 'utf8'));
      } catch (_) {
        return undefined;
      }
      return validatedNavigationURL(state && state.url);
    }

    function launchOptions() {
      const options = {
        headless: args.headless !== false,
        acceptDownloads: true,
        downloadsPath: args.downloadsDir,
        viewport: { width: 1280, height: 900 },
        args: [
          '--disable-breakpad',
          '--disable-crashpad-for-testing'
        ]
      };
      if (args.channel && args.channel !== 'chromium') options.channel = args.channel;
      return options;
    }

    function interactiveElementsScript() {
      return `(() => {
        function trim(value, max = 160) {
          const normalized = Array.from(String(value || ''), (character) =>
            character.trim() ? character : ' ').join('');
          return normalized.split(' ').filter(Boolean).join(' ').slice(0, max);
        }
        function cssString(value) {
          return JSON.stringify(String(value || '')).slice(1, -1);
        }
        function cssIdent(value) {
          try {
            if (window.CSS && CSS.escape) return CSS.escape(String(value || ''));
          } catch (_) {}
          return String(value || '').replace(/[^A-Za-z0-9_-]/g, (ch) =>
            String.fromCharCode(92) + ch.codePointAt(0).toString(16) + ' ');
        }
        function textOf(el) {
          return trim(el.innerText || el.textContent || el.value || '');
        }
        function labelFor(el) {
          const aria = trim(el.getAttribute('aria-label'));
          if (aria) return aria;
          const labelledBy = trim(el.getAttribute('aria-labelledby'));
          if (labelledBy) {
            const text = trim(labelledBy).split(' ')
              .map((id) => document.getElementById(id))
              .filter(Boolean)
              .map((node) => trim(node.innerText || node.textContent || ''))
              .filter(Boolean)
              .join(' ');
            if (text) return trim(text);
          }
          if (el.labels && el.labels.length) {
            const labelText = Array.from(el.labels).map((label) => trim(label.innerText || label.textContent || '')).filter(Boolean).join(' ');
            if (labelText) return trim(labelText);
          }
          const id = el.getAttribute('id');
          if (id) {
            const label = document.querySelector('label[for="' + cssString(id) + '"]');
            const labelText = label ? trim(label.innerText || label.textContent || '') : '';
            if (labelText) return labelText;
          }
          const tag = el.tagName ? el.tagName.toLowerCase() : '';
          const type = String(el.getAttribute('type') || '').toLowerCase();
          const fallbackText = tag === 'input' && !['button', 'submit', 'reset', 'image'].includes(type) ? '' : textOf(el);
          return trim(el.getAttribute('placeholder') || el.getAttribute('title') || fallbackText);
        }
        function inferredRole(el) {
          const explicit = trim(el.getAttribute('role'), 64).toLowerCase();
          if (explicit) return explicit;
          const tag = el.tagName ? el.tagName.toLowerCase() : '';
          const type = String(el.getAttribute('type') || '').toLowerCase();
          if (tag === 'button') return 'button';
          if (tag === 'a') return 'link';
          if (tag === 'textarea') return 'textbox';
          if (tag === 'select') return 'combobox';
          if (tag === 'input') {
            if (['button', 'submit', 'reset', 'image', 'file'].includes(type)) return 'button';
            if (['checkbox'].includes(type)) return 'checkbox';
            if (['radio'].includes(type)) return 'radio';
            return 'textbox';
          }
          if (el.isContentEditable) return 'textbox';
          return tag || 'element';
        }
        function isVisible(el) {
          if (!el || !el.isConnected || el.hidden) return false;
          const style = window.getComputedStyle(el);
          if (!style || style.display === 'none' || style.visibility === 'hidden'
              || style.visibility === 'collapse' || Number(style.opacity) === 0) return false;
          const rect = el.getBoundingClientRect();
          return !!rect && rect.width > 0 && rect.height > 0 && el.getClientRects().length > 0;
        }
        function selectorFor(el, index) {
          const tag = el.tagName ? el.tagName.toLowerCase() : '*';
          const id = el.getAttribute('id');
          function uniquelyIdentifies(candidate) {
            try {
              const matches = document.querySelectorAll(candidate);
              return matches.length === 1 && matches[0] === el;
            } catch (_) {
              return false;
            }
          }
          if (id) {
            const candidate = '#' + cssIdent(id);
            if (uniquelyIdentifies(candidate)) return candidate;
          }
          for (const attribute of ['data-testid', 'data-test', 'data-qa']) {
            const testId = el.getAttribute(attribute);
            if (testId) {
              const candidate = '[' + attribute + '="' + cssString(testId) + '"]';
              if (uniquelyIdentifies(candidate)) return candidate;
            }
          }
          const name = el.getAttribute('name');
          if (name && tag !== '*') {
            const candidate = tag + '[name="' + cssString(name) + '"]';
            if (uniquelyIdentifies(candidate)) return candidate;
          }
          const placeholder = el.getAttribute('placeholder');
          if (placeholder && tag !== '*') {
            const candidate = tag + '[placeholder="' + cssString(placeholder) + '"]';
            if (uniquelyIdentifies(candidate)) return candidate;
          }
          const role = el.getAttribute('role');
          if (role) {
            const candidate = '[role="' + cssString(role) + '"]';
            if (uniquelyIdentifies(candidate)) return candidate;
          }
          const segments = [];
          let current = el;
          while (current && current.nodeType === 1 && segments.length < 8) {
            const currentTag = current.tagName.toLowerCase();
            const parent = current.parentElement;
            const siblings = parent
              ? Array.from(parent.children).filter((node) => node.tagName === current.tagName)
              : [];
            const position = siblings.indexOf(current);
            segments.unshift(currentTag + (siblings.length > 1 && position >= 0
              ? ':nth-of-type(' + (position + 1) + ')'
              : ''));
            const candidate = segments.join(' > ');
            if (uniquelyIdentifies(candidate)) return candidate;
            current = parent;
          }
          return tag + ':nth-of-type(' + Math.max(1, index + 1) + ')';
        }
        const selector = [
          'button',
          'input',
          'textarea',
          'select',
          '[role]',
          '[aria-label]',
          '[placeholder]',
          '[contenteditable="true"]'
        ].join(',');
        return Array.from(document.querySelectorAll(selector)).filter(isVisible).slice(0, 120).map((el, index) => {
          const tag = el.tagName ? el.tagName.toLowerCase() : '';
          const type = trim(el.getAttribute('type'), 64).toLowerCase();
          const name = labelFor(el);
          const text = tag === 'input' && !['button', 'submit', 'reset'].includes(type) ? '' : textOf(el);
          const item = {
            role: inferredRole(el),
            name,
            text,
            selector: selectorFor(el, index),
            tag,
            type,
            placeholder: trim(el.getAttribute('placeholder')),
            disabled: !!el.disabled || el.getAttribute('aria-disabled') === 'true'
          };
          if (tag === 'input' && ['checkbox', 'radio'].includes(type)) item.checked = !!el.checked;
          if (tag === 'select') {
            item.options = Array.from(el.options || []).slice(0, 12).map((option) => trim(option.textContent || option.label || '')).filter(Boolean);
          }
          return item;
        }).filter((item) => item.name || item.text || item.placeholder || item.selector).slice(0, 50);
      })()`;
    }

    async function pageSummary(page, action) {
      if (waitMillis > 0) await page.waitForTimeout(waitMillis);
      const title = await page.title().catch(() => '');
      const url = page.url();
      const text = await page.locator('body').innerText({ timeout: 5000 }).catch(() => '');
      const links = await page.locator('a').evaluateAll((anchors) => anchors.slice(0, 80).map((a) => ({
        text: (a.innerText || a.textContent || '').trim().slice(0, 160),
        href: a.href || ''
      })).filter((item) => item.text || item.href)).catch(() => []);
      const elements = await page.evaluate(interactiveElementsScript());
      return { action, profile: args.profile, backend: 'playwright', backendDetail: playwrightInfo.resolvedFrom || '', url, title, text: text.slice(0, maxText), links: links.slice(0, 40), elements };
    }

    async function openPage(context, forceNavigation = false) {
      const pages = context.pages().filter((candidate) => !candidate.isClosed());
      const page = pages[pages.length - 1] || await context.newPage();
      const targetURL = args.url ? validatedNavigationURL(args.url) : readStateURL();
      const currentURL = page.url();
      const currentIsUsable = /^https?:\\/\\//i.test(currentURL);
      const shouldNavigate = forceNavigation || !Number.isInteger(args.cdpPort) || !currentIsUsable;
      if (shouldNavigate) {
        if (!targetURL) throw new Error('no current browser URL; call browser_navigate or browser_search first');
        await page.goto(targetURL, { waitUntil: 'domcontentloaded', timeout: 45000 });
      }
      return page;
    }

    function newPageFollowMillis() {
      return Math.max(250, Math.min(args.newPageTimeoutMillis || 1200, 5000));
    }

    async function pageMetadata(page) {
      return {
        url: page.url(),
        title: await page.title().catch(() => '')
      };
    }

    async function followNewPageDuring(context, page, action) {
      const beforePages = context.pages();
      const popupPromise = page.waitForEvent('popup', { timeout: 5000 }).catch(() => null);
      const pagePromise = context.waitForEvent('page', { timeout: 5000 }).catch(() => null);
      await action();
      const opened = await Promise.race([
        popupPromise,
        pagePromise,
        page.waitForTimeout(newPageFollowMillis()).then(() => null)
      ]);
      const selected = opened || context.pages().find((candidate) => !beforePages.includes(candidate)) || null;
      if (!selected) return { page, openedPage: null };
      await selected.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => undefined);
      await selected.bringToFront().catch(() => undefined);
      return { page: selected, openedPage: await pageMetadata(selected) };
    }

    function locatorFor(page) {
      const nth = Math.max(0, args.nth || 0);
      if (args.selector) return page.locator(args.selector).nth(nth);
      if (args.role && args.name) return page.getByRole(args.role, { name: args.name }).nth(nth);
      if (args.text) return page.getByText(args.text, { exact: args.exact === true }).nth(nth);
      throw new Error('selector, role+name, or text is required for this browser action');
    }

    async function locatorForAction(page, options = {}) {
      const requiresVisible = options.requiresVisible !== false;
      const requiresEnabled = options.requiresEnabled !== false;
      let locator;
      try {
        locator = locatorFor(page);
        if (await locator.count() < 1) throw actionTargetNotFound();
        if (requiresVisible && !(await locator.isVisible())) throw actionTargetNotFound();
        if (requiresEnabled && !(await locator.isEnabled())) throw actionTargetNotFound();
      } catch (error) {
        if (error instanceof BrowserActionNotStartedError) throw error;
        throw actionTargetNotFound();
      }
      return locator;
    }

    function sensitiveTypeReasonForElement(el) {
      function text(value) {
        return String(value || '').toLowerCase();
      }
      function tokens(value) {
        return new Set(text(value).split(/[^a-z0-9]+/).filter(Boolean));
      }
      function labelText(node) {
        if (!node || !node.getAttribute) return '';
        const parts = [
          node.getAttribute('type'),
          node.getAttribute('name'),
          node.getAttribute('id'),
          node.getAttribute('autocomplete'),
          node.getAttribute('placeholder'),
          node.getAttribute('aria-label'),
          node.getAttribute('title')
        ];
        if (node.labels && node.labels.length) {
          parts.push(Array.from(node.labels).map((label) => label.innerText || label.textContent || '').join(' '));
        }
        return parts.filter(Boolean).join(' ');
      }
      const haystack = labelText(el);
      const lowered = text(haystack);
      const terms = tokens(haystack);
      if (terms.has('password') || terms.has('passwd') || terms.has('pwd') || terms.has('passcode')) return 'password field';
      if (terms.has('otp') || terms.has('totp') || terms.has('2fa') || terms.has('mfa') || lowered.includes('two factor') || lowered.includes('two-factor')) return 'two-factor code field';
      if (lowered.includes('verification code') || lowered.includes('security code') || lowered.includes('authentication code') || lowered.includes('recovery code') || lowered.includes('backup code')) return 'verification code field';
      if (terms.has('token') || terms.has('secret') || terms.has('credential') || terms.has('apikey') || (terms.has('api') && terms.has('key')) || (terms.has('private') && terms.has('key'))) return 'secret or token field';
      return '';
    }

    async function typeLocatorFor(page) {
      const locator = await locatorForAction(page);
      let reason;
      try {
        reason = await locator.evaluate(sensitiveTypeReasonForElement);
      } catch (_) {
        throw actionTargetNotFound();
      }
      if (reason) {
        throw new BrowserActionNotStartedError('browser_sensitive_target_refused');
      }
      return locator;
    }

    function selectOptionForAction() {
      if (typeof args.optionValue === 'string' && args.optionValue.length) return args.optionValue;
      if (typeof args.optionLabel === 'string' && args.optionLabel.length) return { label: args.optionLabel };
      if (Number.isInteger(args.optionIndex)) return { index: args.optionIndex };
      throw new Error('optionValue, optionLabel, or optionIndex is required for browser_select_option');
    }

    function hasTargetLocator() {
      return !!(args.selector || args.text || (args.role && args.name));
    }

    function submitTarget(target) {
      function isSubmitter(el) {
        if (!el || !el.tagName) return false;
        const tag = el.tagName.toLowerCase();
        const type = String(el.getAttribute('type') || '').toLowerCase();
        return tag === 'button' || (tag === 'input' && ['submit', 'image'].includes(type));
      }
      function formFor(el) {
        if (el && el.tagName && el.tagName.toLowerCase() === 'form') return el;
        if (el && el.form) return el.form;
        if (el && el.closest) {
          const form = el.closest('form');
          if (form) return form;
        }
        return document.querySelector('form');
      }
      const el = target || document.activeElement || document.querySelector('form');
      const form = formFor(el);
      if (!form) throw new Error('no form found to submit');
      if (typeof form.requestSubmit === 'function') {
        try {
          if (isSubmitter(el) && el.form === form) form.requestSubmit(el);
          else form.requestSubmit();
        } catch (_) {
          form.requestSubmit();
        }
      } else if (typeof form.submit === 'function') {
        form.submit();
      } else {
        throw new Error('target form cannot be submitted');
      }
      return true;
    }

    async function submitCurrentPage(page) {
      const timeout = Math.max(1000, Math.min(args.timeoutMillis || 5000, 30000));
      let target = null;
      if (hasTargetLocator()) {
        target = await locatorForAction(page, { requiresVisible: false });
      } else if (await page.locator('form').count() < 1) {
        throw actionTargetNotFound();
      }
      const navigation = page.waitForNavigation({ waitUntil: 'domcontentloaded', timeout }).catch(() => null);
      if (target) {
        await target.evaluate(submitTarget);
      } else {
        await page.evaluate(submitTarget);
      }
      await Promise.race([
        navigation,
        page.waitForTimeout(Math.min(Math.max(waitMillis || 600, 250), 1200))
      ]);
    }

    function waitStateForAction() {
      const state = String(args.state || 'visible').toLowerCase();
      return ['attached', 'detached', 'visible', 'hidden'].includes(state) ? state : 'visible';
    }

    function waitTimeoutForAction() {
      return Math.max(1000, Math.min(args.timeoutMillis || 10000, 30000));
    }

    async function captureDownload(page, action) {
      const timeout = Math.max(1000, Math.min(args.downloadTimeoutMillis || 15000, 60000));
      const downloadPromise = page.waitForEvent('download', { timeout }).catch(() => null);
      await action();
      const download = await downloadPromise;
      if (!download) throw new Error('no download was started before the timeout');
      const outputPath = uniqueDownloadPath(download.suggestedFilename());
      await download.saveAs(outputPath);
      return [{
        filename: path.basename(outputPath),
        path: relativeDownloadPath(outputPath),
        url: download.url(),
        bytes: fileSize(outputPath)
      }];
    }

    (async () => {
      const managedConnection = Number.isInteger(args.cdpPort);
      const browser = managedConnection
        ? await chromium.connectOverCDP(`http://127.0.0.1:${args.cdpPort}`)
        : null;
      const context = managedConnection
        ? browser.contexts()[0]
        : await chromium.launchPersistentContext(args.profileDir, launchOptions());
      if (!context) throw new Error('managed browser did not expose its persistent context');
      try {
        let page;
        let downloads = [];
        let openedPage = null;
        switch (args.action) {
          case 'navigate':
          case 'snapshot':
            page = await openPage(context, args.action !== 'snapshot');
            break;
          case 'back':
          case 'forward':
            page = await openPage(context, true);
            break;
          case 'handoff':
            page = await openPage(context, !!args.url);
            await page.waitForTimeout(handoffMillis);
            break;
          case 'reload':
            page = await openPage(context);
            await page.reload({ waitUntil: 'domcontentloaded', timeout: 45000 });
            break;
          case 'click':
            page = await openPage(context);
            {
              const locator = await locatorForAction(page);
              const followed = await followNewPageDuring(context, page, async () => {
                await locator.click({ timeout: 15000 });
              });
              page = followed.page;
              openedPage = followed.openedPage;
            }
            break;
          case 'type':
            page = await openPage(context);
            {
              const followed = await followNewPageDuring(context, page, async () => {
                const typeLocator = await typeLocatorFor(page);
                if (args.clear === false) {
                  await typeLocator.type(args.value || '', { timeout: 15000 });
                } else {
                  await typeLocator.fill(args.value || '', { timeout: 15000 });
                }
                if (args.submit === true) {
                  const navigation = page.waitForNavigation({ waitUntil: 'domcontentloaded', timeout: 10000 }).catch(() => null);
                  await page.keyboard.press('Enter');
                  await Promise.race([
                    navigation,
                    page.waitForTimeout(Math.min(Math.max(waitMillis || 600, 250), 1200))
                  ]);
                }
              });
              page = followed.page;
              openedPage = followed.openedPage;
            }
            break;
          case 'select':
            page = await openPage(context);
            {
              const locator = await locatorForAction(page, { requiresVisible: false });
              const followed = await followNewPageDuring(context, page, async () => {
                await locator.selectOption(selectOptionForAction(), { timeout: 15000 });
              });
              page = followed.page;
              openedPage = followed.openedPage;
            }
            break;
          case 'submit':
            page = await openPage(context);
            {
              const followed = await followNewPageDuring(context, page, async () => {
                await submitCurrentPage(page);
              });
              page = followed.page;
              openedPage = followed.openedPage;
            }
            break;
          case 'press':
            page = await openPage(context);
            {
              const locator = (args.selector || (args.role && args.name) || args.text)
                ? await locatorForAction(page)
                : null;
              const followed = await followNewPageDuring(context, page, async () => {
                if (locator) {
                  await locator.press(args.key || '', { timeout: 15000 });
                } else {
                  await page.keyboard.press(args.key || '');
                }
              });
              page = followed.page;
              openedPage = followed.openedPage;
            }
            break;
          case 'scroll':
            page = await openPage(context);
            if (args.selector || (args.role && args.name) || args.text) {
              const locator = await locatorForAction(page, { requiresEnabled: false });
              await locator.scrollIntoViewIfNeeded({ timeout: 15000 });
              const box = await locator.boundingBox().catch(() => null);
              if (box) await page.mouse.move(box.x + Math.min(Math.max(box.width / 2, 1), 400), box.y + Math.min(Math.max(box.height / 2, 1), 400));
            } else {
              await page.mouse.move(640, 450).catch(() => undefined);
            }
            await page.mouse.wheel(args.deltaX || 0, args.deltaY || 0);
            break;
          case 'wait':
            page = await openPage(context);
            if (args.selector || (args.role && args.name) || args.text) {
              await locatorFor(page).waitFor({ state: waitStateForAction(), timeout: waitTimeoutForAction() });
            } else {
              await page.waitForTimeout(waitTimeoutForAction());
            }
            break;
          case 'upload':
            page = await openPage(context);
            {
              const locator = await locatorForAction(page, {
                requiresVisible: false,
                requiresEnabled: false
              });
              const isFileInput = await locator.evaluate((element) => {
                if (element && element.tagName && element.tagName.toLowerCase() === 'input'
                    && String(element.type || '').toLowerCase() === 'file') return true;
                return !!(element && element.querySelector && element.querySelector('input[type="file"]'));
              }).catch(() => false);
              if (!isFileInput) throw actionTargetNotFound();
              await locator.setInputFiles(args.filePath, { timeout: 15000 });
            }
            break;
          case 'download':
            page = await openPage(context);
            {
              const locator = await locatorForAction(page);
            downloads = await captureDownload(page, async () => {
              await locator.click({ timeout: 15000 });
            });
            }
            break;
          case 'search': {
            const pages = context.pages().filter((candidate) => !candidate.isClosed());
            page = pages[pages.length - 1] || await context.newPage();
            const encoded = encodeURIComponent(args.query || '');
            const engine = args.engine || 'duckduckgo';
            let url = `https://duckduckgo.com/?q=${encoded}`;
            if (engine === 'google') url = `https://www.google.com/search?q=${encoded}`;
            if (engine === 'bing') url = `https://www.bing.com/search?q=${encoded}`;
            await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
            break;
          }
          case 'screenshot':
            page = await openPage(context, !!args.url);
            if (!args.outputPath) throw new Error('outputPath is required for browser_screenshot');
            fs.mkdirSync(path.dirname(args.outputPath), { recursive: true });
            await page.screenshot({ path: args.outputPath, fullPage: args.fullPage === true });
            break;
          default:
            throw new Error(`unsupported browser action: ${args.action}`);
        }
        const summary = await pageSummary(page, args.action);
        if (args.action === 'screenshot') summary.screenshotPath = args.relativeOutputPath || args.outputPath;
        if (args.action === 'upload') summary.uploadedFiles = [args.relativeFilePath || args.filePath];
        if (downloads.length) summary.downloads = downloads;
        if (openedPage) summary.openedPage = openedPage;
        summary.pageCount = context.pages().length;
        console.log(JSON.stringify(summary));
      } finally {
        if (!managedConnection) await context.close();
      }
    })()
    .then(() => {
      clearTimeout(commandWatchdog);
      // Playwright has no disconnect-only API for connectOverCDP. Exiting the
      // one-shot broker drops its WebSocket while leaving the runtime-owned
      // browser process and live pages intact.
      if (Number.isInteger(args.cdpPort)) process.exit(0);
    })
    .catch((error) => {
      clearTimeout(commandWatchdog);
      emitNoEffectFailure(error);
      console.error(error && error.stack ? error.stack : String(error));
      process.exit(1);
    });
    """
    return browserBackendInvocation(
        javaScript: javaScript,
        encodedArguments: payload,
        arguments: arguments)
}

private func cdpCommand(
    arguments: [String: Any]
) throws -> BrowserBackendInvocation {
    let data = try JSONSerialization.data(withJSONObject: arguments, options: [])
    let payload = data.base64EncodedString()
    let javaScript = """
    const fs = require('fs');
    const path = require('path');
    const childProcess = require('child_process');

    const args = JSON.parse(Buffer.from(process.env.INTATIS_BROWSER_ARGS, 'base64').toString('utf8'));
    const maxText = Math.max(1, Math.min(args.maxCharacters || 20000, 100000));
    const waitMillis = Math.max(0, Math.min(args.waitMillis || 600, 10000));
    const handoffMillis = Math.max(1000, Math.min(args.handoffTimeoutMillis || 30000, 600000));
    class BrowserActionNotStartedError extends Error {
      constructor(code) {
        super(code);
        this.name = 'BrowserActionNotStartedError';
        this.code = code;
      }
    }
    function actionTargetNotFound() {
      return new BrowserActionNotStartedError('browser_action_target_not_found');
    }
    function emitNoEffectFailure(error) {
      if (!(error instanceof BrowserActionNotStartedError)) return;
      console.log(JSON.stringify({
        marker: 'intatis_browser_backend_error_v1',
        code: error.code,
        effectDisposition: 'not_started'
      }));
    }
    let activeBrowser = null;
    const commandWatchdogMillis = Math.max(60000, handoffMillis + 20000);
    const commandWatchdog = setTimeout(() => {
      try {
        if (activeBrowser && activeBrowser.exitCode === null) activeBrowser.kill('SIGKILL');
      } catch (_) {}
      console.error('browser command timed out');
      process.exit(124);
    }, commandWatchdogMillis);

    function unique(values) {
      return [...new Set(values.filter((value) => typeof value === 'string' && value.length > 0))];
    }

    function safeFilename(raw) {
      const base = path.basename(String(raw || 'download')).replace(/[^A-Za-z0-9._ -]/g, '_').slice(0, 120);
      return base.length ? base : 'download';
    }

    function relativeDownloadPath(outputPath) {
      const base = args.downloadsRelativeDir || '';
      return base ? path.join(base, path.basename(outputPath)) : outputPath;
    }

    function listDownloadFiles() {
      try { fs.mkdirSync(args.downloadsDir, { recursive: true }); } catch (_) {}
      let entries = [];
      try {
        entries = fs.readdirSync(args.downloadsDir)
          .filter((name) => !name.startsWith('.') && !name.endsWith('.crdownload'))
          .map((name) => {
            const fullPath = path.join(args.downloadsDir, name);
            const stat = fs.statSync(fullPath);
            return stat.isFile() ? {
              filename: safeFilename(name),
              path: relativeDownloadPath(fullPath),
              bytes: stat.size,
              mtimeMs: stat.mtimeMs
            } : null;
          })
          .filter(Boolean);
      } catch (_) {}
      return entries;
    }

    async function waitForNewDownloads(before) {
      const timeout = Math.max(1000, Math.min(args.downloadTimeoutMillis || 15000, 60000));
      const started = Date.now();
      const seen = new Set(before.map((item) => item.path));
      while (Date.now() - started < timeout) {
        const current = listDownloadFiles();
        const fresh = current.filter((item) => !seen.has(item.path));
        if (fresh.length > 0) {
          fresh.sort((a, b) => b.mtimeMs - a.mtimeMs);
          return fresh.map(({ mtimeMs, ...item }) => item);
        }
        await wait(200);
      }
      throw new Error('no downloaded file appeared before the timeout');
    }

    function cdpExecutableForChannel(channel) {
      const value = (channel || 'chromium').toLowerCase();
      const candidates = [];
      if (process.platform === 'darwin') {
        if (value.startsWith('msedge')) candidates.push('/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge');
        if (value.startsWith('chrome')) candidates.push('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome');
        if (value === 'chromium') candidates.push('/Applications/Chromium.app/Contents/MacOS/Chromium');
        candidates.push('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome');
        candidates.push('/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge');
        candidates.push('/Applications/Chromium.app/Contents/MacOS/Chromium');
      } else {
        if (value.startsWith('msedge')) candidates.push('microsoft-edge', 'microsoft-edge-stable');
        if (value.startsWith('chrome')) candidates.push('google-chrome', 'google-chrome-stable');
        candidates.push('chromium', 'chromium-browser', 'google-chrome', 'microsoft-edge');
      }
      for (const candidate of unique(candidates)) {
        try {
          if (candidate.includes('/')) {
            if (fs.existsSync(candidate)) return candidate;
          } else {
            childProcess.execFileSync('which', [candidate], { stdio: ['ignore', 'ignore', 'ignore'] });
            return candidate;
          }
        } catch (_) {}
      }
      return '';
    }

    function validatedNavigationURL(value) {
      if (typeof value !== 'string' || !value.trim()) return undefined;
      try {
        const parsed = new URL(value.trim());
        if (!['http:', 'https:'].includes(parsed.protocol) || !parsed.hostname) {
          throw new Error('unsupported browser URL');
        }
        return parsed.toString();
      } catch (_) {
        throw new Error('browser URL must be http(s) with a host');
      }
    }

    function readStateURL() {
      let state;
      try {
        if (!args.stateFile || !fs.existsSync(args.stateFile)) return undefined;
        state = JSON.parse(fs.readFileSync(args.stateFile, 'utf8'));
      } catch (_) {
        return undefined;
      }
      return validatedNavigationURL(state && state.url);
    }

    function searchURL() {
      const encoded = encodeURIComponent(args.query || '');
      const engine = args.engine || 'duckduckgo';
      if (engine === 'google') return `https://www.google.com/search?q=${encoded}`;
      if (engine === 'bing') return `https://www.bing.com/search?q=${encoded}`;
      return `https://duckduckgo.com/?q=${encoded}`;
    }

    function targetURL() {
      if (args.action === 'search') return searchURL();
      return args.url ? validatedNavigationURL(args.url) : readStateURL();
    }

    function wait(ms) {
      return new Promise((resolve) => setTimeout(resolve, ms));
    }

    function waitForProcessExit(process, timeoutMillis) {
      return new Promise((resolve) => {
        if (process.exitCode !== null || process.signalCode !== null) {
          resolve(true);
          return;
        }
        const timer = setTimeout(() => resolve(false), timeoutMillis);
        process.once('exit', () => {
          clearTimeout(timer);
          resolve(true);
        });
      });
    }

    function generationMismatch(message) {
      const error = new Error(message);
      error.generationMismatch = true;
      return error;
    }

    function prepareDevToolsActivePort(profileDir) {
      const activePortFile = path.join(profileDir, 'DevToolsActivePort');
      try {
        fs.unlinkSync(activePortFile);
      } catch (error) {
        if (!error || error.code !== 'ENOENT') {
          throw generationMismatch('could not remove the previous DevToolsActivePort safely');
        }
      }
      return {
        activePortFile,
        notBeforeMillis: Date.now()
      };
    }

    async function waitForDevToolsActivePort(generation, timeoutMillis, browserProcess, spawnError) {
      const started = Date.now();
      while (Date.now() - started < timeoutMillis) {
        const launchError = spawnError();
        if (launchError) {
          throw new Error(`browser process failed to launch before exposing a DevTools port: ${launchError.message || launchError}`);
        }
        if (browserProcess.exitCode !== null || browserProcess.signalCode !== null) {
          const outcome = browserProcess.exitCode !== null
            ? `exit ${browserProcess.exitCode}`
            : `signal ${browserProcess.signalCode}`;
          throw new Error(`browser exited before exposing a DevTools port (${outcome})`);
        }
        try {
          const stat = fs.lstatSync(generation.activePortFile);
          const newestTimestamp = Math.max(stat.birthtimeMs || 0, stat.ctimeMs || 0, stat.mtimeMs || 0);
          const currentUID = typeof process.getuid === 'function' ? process.getuid() : undefined;
          if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1
              || (currentUID !== undefined && stat.uid !== currentUID)
              || stat.size <= 0 || stat.size > 1024
              || newestTimestamp + 1000 < generation.notBeforeMillis) {
            throw generationMismatch('DevToolsActivePort does not belong to the current browser launch');
          }
          const lines = fs.readFileSync(generation.activePortFile, 'utf8').trim().split(/\\r?\\n/);
          if (lines.length >= 2) {
            const port = Number(lines[0]);
            const browserPath = String(lines[1] || '').trim();
            if (!Number.isInteger(port) || port < 1 || port > 65535
                || !/^\\/devtools\\/browser\\/[A-Za-z0-9._-]+$/.test(browserPath)) {
              throw generationMismatch('DevToolsActivePort has an invalid current-launch endpoint');
            }
            const candidate = { port, browserPath };
            try {
              await validateDevToolsEndpoint(candidate);
              return candidate;
            } catch (error) {
              if (error && error.generationMismatch) throw error;
            }
          }
        } catch (error) {
          if (error && error.generationMismatch) throw error;
          if (error && error.code && error.code !== 'ENOENT') {
            throw generationMismatch('DevToolsActivePort could not be validated for the current launch');
          }
        }
        await wait(100);
      }
      throw new Error('browser did not expose a DevTools port');
    }

    async function fetchJSON(url, options = {}) {
      const requestOptions = Object.assign({}, options);
      if (!requestOptions.signal && typeof AbortSignal !== 'undefined'
          && typeof AbortSignal.timeout === 'function') {
        requestOptions.signal = AbortSignal.timeout(5000);
      }
      const response = await fetch(url, requestOptions);
      if (!response.ok) throw new Error(`CDP HTTP ${response.status} for ${url}`);
      return await response.json();
    }

    function validatedLoopbackWebSocketURL(raw, port, expectedPath) {
      let parsed;
      try {
        parsed = new URL(String(raw || ''));
      } catch (_) {
        throw generationMismatch('CDP returned an invalid WebSocket endpoint');
      }
      const hostname = parsed.hostname.toLowerCase().replace(/^\\[|\\]$/g, '');
      const isLoopback = hostname === '127.0.0.1' || hostname === 'localhost' || hostname === '::1';
      if (parsed.protocol !== 'ws:' || !isLoopback || Number(parsed.port) !== port
          || (expectedPath && parsed.pathname !== expectedPath)) {
        throw generationMismatch('CDP WebSocket endpoint does not match the current loopback launch');
      }
      return parsed.toString();
    }

    async function validateDevToolsEndpoint(candidate) {
      const version = await fetchJSON(`http://127.0.0.1:${candidate.port}/json/version`);
      validatedLoopbackWebSocketURL(
        version && version.webSocketDebuggerUrl,
        candidate.port,
        candidate.browserPath
      );
    }

    async function listPageTargets(port) {
      const targets = await fetchJSON(`http://127.0.0.1:${port}/json/list`);
      return targets
        .filter((item) => item.type === 'page' && item.webSocketDebuggerUrl)
        .map((item) => Object.assign({}, item, {
          webSocketDebuggerUrl: validatedLoopbackWebSocketURL(item.webSocketDebuggerUrl, port)
        }));
    }

    async function pageTarget(port, preferredURL) {
      let targets = await listPageTargets(port);
      let target = preferredURL
        ? targets.find((item) => item.url === preferredURL)
        : null;
      if (!target) target = targets[0];
      if (!target) {
        try {
          target = await fetchJSON(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' });
        } catch (_) {
          target = await fetchJSON(`http://127.0.0.1:${port}/json/new?about:blank`);
        }
      }
      if (!target || !target.webSocketDebuggerUrl) throw new Error('CDP page target is unavailable');
      return Object.assign({}, target, {
        webSocketDebuggerUrl: validatedLoopbackWebSocketURL(target.webSocketDebuggerUrl, port)
      });
    }

    class CDPClient {
      constructor(webSocketURL) {
        this.webSocketURL = webSocketURL;
        this.nextID = 1;
        this.pending = new Map();
        this.waiters = new Map();
      }

      async connect() {
        this.socket = new WebSocket(this.webSocketURL);
        await new Promise((resolve, reject) => {
          const timer = setTimeout(() => reject(new Error('CDP WebSocket connection timed out')), 10000);
          this.socket.onopen = () => { clearTimeout(timer); resolve(); };
          this.socket.onerror = () => { clearTimeout(timer); reject(new Error('CDP WebSocket connection failed')); };
        });
        this.socket.onmessage = (event) => {
          let message;
          try { message = JSON.parse(String(event.data)); } catch (_) { return; }
          if (message.id && this.pending.has(message.id)) {
            const callbacks = this.pending.get(message.id);
            this.pending.delete(message.id);
            if (message.error) callbacks.reject(new Error(message.error.message || JSON.stringify(message.error)));
            else callbacks.resolve(message.result || {});
            return;
          }
          if (message.method && this.waiters.has(message.method)) {
            const waiters = this.waiters.get(message.method);
            this.waiters.delete(message.method);
            for (const waiter of waiters) waiter.resolve(message.params || {});
          }
        };
      }

      send(method, params = {}, timeoutMillis = 30000) {
        const id = this.nextID++;
        const payload = JSON.stringify({ id, method, params });
        return new Promise((resolve, reject) => {
          const timer = setTimeout(() => {
            this.pending.delete(id);
            reject(new Error(`${method} timed out`));
          }, timeoutMillis);
          this.pending.set(id, {
            resolve: (value) => {
              clearTimeout(timer);
              resolve(value);
            },
            reject: (error) => {
              clearTimeout(timer);
              reject(error);
            }
          });
          try {
            this.socket.send(payload);
          } catch (error) {
            clearTimeout(timer);
            this.pending.delete(id);
            reject(error);
          }
        });
      }

      once(method, timeoutMillis) {
        return new Promise((resolve, reject) => {
          let wrappedResolve;
          const timer = setTimeout(() => {
            const waiters = this.waiters.get(method) || [];
            const remaining = waiters.filter((item) => item.resolve !== wrappedResolve);
            if (remaining.length > 0) this.waiters.set(method, remaining);
            else this.waiters.delete(method);
            reject(new Error(`${method} timed out`));
          }, timeoutMillis);
          wrappedResolve = (params) => {
            clearTimeout(timer);
            resolve(params);
          };
          const waiters = this.waiters.get(method) || [];
          waiters.push({ resolve: wrappedResolve, reject });
          this.waiters.set(method, waiters);
        });
      }

      close() {
        try { this.socket.close(); } catch (_) {}
      }
    }

    async function enablePageClient(client) {
      await client.send('Page.enable');
      await client.send('Runtime.enable');
      await client.send('Browser.setDownloadBehavior', {
        behavior: 'allow',
        downloadPath: args.downloadsDir,
        eventsEnabled: true
      }).catch(() => undefined);
    }

    async function maybeNewPageTarget(port, beforeTargetIDs, currentTargetID) {
      const timeout = Math.max(250, Math.min(args.newPageTimeoutMillis || 1200, 5000));
      const started = Date.now();
      let latestTargets = [];
      while (Date.now() - started < timeout) {
        latestTargets = await listPageTargets(port).catch(() => []);
        const fresh = latestTargets.find((item) => !beforeTargetIDs.has(item.id) && item.id !== currentTargetID);
        if (fresh) {
          const newClient = new CDPClient(fresh.webSocketDebuggerUrl);
          await newClient.connect();
          await enablePageClient(newClient);
          return { client: newClient, target: fresh, pageCount: latestTargets.length };
        }
        await wait(100);
      }
      latestTargets = await listPageTargets(port).catch(() => latestTargets);
      return { client: null, target: null, pageCount: latestTargets.length || beforeTargetIDs.size };
    }

    function jsValue(result) {
      if (!result || !result.result) return undefined;
      if ('value' in result.result) return result.result.value;
      return undefined;
    }

    function evaluationExceptionMessage(details, fallback) {
      const summary = String(details && details.text ? details.text : fallback || 'page evaluation failed');
      const exception = details && details.exception ? details.exception : {};
      const description = String(
        exception.description || exception.value || ''
      ).trim();
      if (!description || description === summary) return summary;
      return `${summary}: ${description}`;
    }

    async function evaluate(client, expression, timeoutMillis = 10000) {
      const result = await client.send('Runtime.evaluate', {
        expression,
        returnByValue: true,
        awaitPromise: true,
        timeout: Math.max(1000, Math.min(timeoutMillis, 31000))
      });
      if (result.exceptionDetails) {
        throw new Error(evaluationExceptionMessage(
          result.exceptionDetails,
          'page evaluation failed'
        ));
      }
      return jsValue(result);
    }

    async function fileInputObjectId(client) {
      const result = await client.send('Runtime.evaluate', {
        expression: fileInputScript(),
        returnByValue: false,
        awaitPromise: true,
        timeout: 10000
      });
      if (result.exceptionDetails) {
        throw new Error(evaluationExceptionMessage(
          result.exceptionDetails,
          'file input lookup failed'
        ));
      }
      const objectId = result.result && result.result.objectId;
      if (!objectId) throw new Error('file input lookup did not return a DOM object');
      return objectId;
    }

    async function dispatchInputEvents(client, objectId) {
      await client.send('Runtime.callFunctionOn', {
        objectId,
        functionDeclaration: `function() {
          this.dispatchEvent(new Event('input', { bubbles: true }));
          this.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        }`,
        returnByValue: true,
        awaitPromise: true
      });
    }

    function keyDescriptor(rawKey) {
      const raw = String(rawKey || '').trim();
      if (!raw) throw new Error('browser_press_key requires key');
      const parts = raw.split('+').filter((part) => part.length > 0);
      let finalKey = parts.pop() || '';
      let modifiers = 0;
      for (const part of parts) {
        const lower = part.toLowerCase();
        if (lower === 'alt' || lower === 'option') modifiers |= 1;
        else if (lower === 'control' || lower === 'ctrl') modifiers |= 2;
        else if (lower === 'meta' || lower === 'cmd' || lower === 'command') modifiers |= 4;
        else if (lower === 'shift') modifiers |= 8;
        else throw new Error(`unsupported key modifier: ${part}`);
      }

      const aliases = {
        return: 'Enter',
        enter: 'Enter',
        esc: 'Escape',
        escape: 'Escape',
        space: ' ',
        spacebar: ' ',
        tab: 'Tab',
        backspace: 'Backspace',
        del: 'Delete',
        delete: 'Delete',
        up: 'ArrowUp',
        down: 'ArrowDown',
        left: 'ArrowLeft',
        right: 'ArrowRight',
        home: 'Home',
        end: 'End',
        pagedown: 'PageDown',
        pageup: 'PageUp',
        insert: 'Insert'
      };
      let key = aliases[finalKey.toLowerCase()] || finalKey;
      const special = {
        Enter: { code: 'Enter', vk: 13, text: '\\r' },
        Tab: { code: 'Tab', vk: 9, text: '\\t' },
        Escape: { code: 'Escape', vk: 27 },
        Backspace: { code: 'Backspace', vk: 8 },
        Delete: { code: 'Delete', vk: 46 },
        Insert: { code: 'Insert', vk: 45 },
        Home: { code: 'Home', vk: 36 },
        End: { code: 'End', vk: 35 },
        PageUp: { code: 'PageUp', vk: 33 },
        PageDown: { code: 'PageDown', vk: 34 },
        ArrowLeft: { code: 'ArrowLeft', vk: 37 },
        ArrowUp: { code: 'ArrowUp', vk: 38 },
        ArrowRight: { code: 'ArrowRight', vk: 39 },
        ArrowDown: { code: 'ArrowDown', vk: 40 },
        ' ': { code: 'Space', vk: 32, text: ' ' }
      };
      let info = special[key];
      if (!info && /^F([1-9]|1[0-2])$/.test(key)) {
        const number = Number(key.slice(1));
        info = { code: key, vk: 111 + number };
      }
      if (!info && /^[A-Za-z]$/.test(key)) {
        const upper = key.toUpperCase();
        info = { code: `Key${upper}`, vk: upper.charCodeAt(0), text: modifiers ? '' : key };
      }
      if (!info && /^[0-9]$/.test(key)) {
        info = { code: `Digit${key}`, vk: key.charCodeAt(0), text: modifiers ? '' : key };
      }
      if (!info && key.length === 1) {
        info = { code: '', vk: key.toUpperCase().charCodeAt(0), text: modifiers ? '' : key };
      }
      if (!info) throw new Error(`unsupported key: ${raw}`);
      return {
        key,
        code: info.code || '',
        windowsVirtualKeyCode: info.vk || 0,
        nativeVirtualKeyCode: info.vk || 0,
        modifiers,
        text: info.text || ''
      };
    }

    async function dispatchKey(client, rawKey) {
      const desc = keyDescriptor(rawKey);
      const base = {
        key: desc.key,
        code: desc.code,
        windowsVirtualKeyCode: desc.windowsVirtualKeyCode,
        nativeVirtualKeyCode: desc.nativeVirtualKeyCode,
        modifiers: desc.modifiers
      };
      await client.send('Input.dispatchKeyEvent', Object.assign({ type: 'rawKeyDown' }, base));
      if (desc.text && desc.modifiers === 0 && desc.key !== 'Enter' && desc.key !== 'Tab') {
        await client.send('Input.dispatchKeyEvent', Object.assign({
          type: 'char',
          text: desc.text,
          unmodifiedText: desc.text
        }, base));
      }
      await client.send('Input.dispatchKeyEvent', Object.assign({ type: 'keyUp' }, base));
    }

    async function navigate(client, url) {
      if (!url) throw new Error('no current browser URL; call browser_navigate or browser_search first');
      const loaded = client.once('Page.loadEventFired', 45000).catch(() => undefined);
      await client.send('Page.navigate', { url });
      await loaded;
      if (waitMillis > 0) await wait(waitMillis);
    }

    async function ensureCurrentPage(client, fallbackURL, forceNavigation = false) {
      const currentURL = await evaluate(
        client,
        `(() => String(location.href || ''))()`
      ).catch(() => '');
      if (forceNavigation || !/^https?:\\/\\//i.test(String(currentURL || ''))) {
        await navigate(client, fallbackURL);
      }
    }

    function actionScript(action) {
      const params = JSON.stringify({
        selector: args.selector || '',
        text: args.text || '',
        role: args.role || '',
        name: args.name || '',
        exact: args.exact === true,
        nth: Math.max(0, args.nth || 0),
        value: args.value || '',
        clear: args.clear !== false,
        submit: args.submit === true,
        optionValue: args.optionValue || '',
        optionLabel: args.optionLabel || '',
        optionIndex: Number.isInteger(args.optionIndex) ? args.optionIndex : null
      });
      return `(() => {
        ${locatorSupportScript(params)}
        function sensitiveTypeReasonForElement(node) {
          function lowered(value) {
            return String(value || '').toLowerCase();
          }
          function tokens(value) {
            return new Set(lowered(value).split(/[^a-z0-9]+/).filter(Boolean));
          }
          function labelText(el) {
            if (!el || !el.getAttribute) return '';
            const parts = [
              el.getAttribute('type'),
              el.getAttribute('name'),
              el.getAttribute('id'),
              el.getAttribute('autocomplete'),
              el.getAttribute('placeholder'),
              el.getAttribute('aria-label'),
              el.getAttribute('title')
            ];
            if (el.labels && el.labels.length) {
              parts.push(Array.from(el.labels).map((label) => label.innerText || label.textContent || '').join(' '));
            }
            return parts.filter(Boolean).join(' ');
          }
          const haystack = labelText(node);
          const lower = lowered(haystack);
          const terms = tokens(haystack);
          if (terms.has('password') || terms.has('passwd') || terms.has('pwd') || terms.has('passcode')) return 'password field';
          if (terms.has('otp') || terms.has('totp') || terms.has('2fa') || terms.has('mfa') || lower.includes('two factor') || lower.includes('two-factor')) return 'two-factor code field';
          if (lower.includes('verification code') || lower.includes('security code') || lower.includes('authentication code') || lower.includes('recovery code') || lower.includes('backup code')) return 'verification code field';
          if (terms.has('token') || terms.has('secret') || terms.has('credential') || terms.has('apikey') || (terms.has('api') && terms.has('key')) || (terms.has('private') && terms.has('key'))) return 'secret or token field';
          return '';
        }
        const el = findElement();
        if ('${action}' === 'submit') {
          const target = el || (document.activeElement && document.activeElement !== document.body ? document.activeElement : null) || document.querySelector('form');
          if (!target) throw new Error('no form found to submit');
          function isSubmitter(candidate) {
            if (!candidate || !candidate.tagName) return false;
            const tag = candidate.tagName.toLowerCase();
            const type = String(candidate.getAttribute('type') || '').toLowerCase();
            return tag === 'button' || (tag === 'input' && ['submit', 'image'].includes(type));
          }
          function formFor(candidate) {
            if (candidate && candidate.tagName && candidate.tagName.toLowerCase() === 'form') return candidate;
            if (candidate && candidate.form) return candidate.form;
            if (candidate && candidate.closest) {
              const form = candidate.closest('form');
              if (form) return form;
            }
            return document.querySelector('form');
          }
          const form = formFor(target);
          if (!form) throw new Error('no form found to submit');
          if (typeof form.requestSubmit === 'function') {
            try {
              if (isSubmitter(target) && target.form === form) form.requestSubmit(target);
              else form.requestSubmit();
            } catch (_) {
              form.requestSubmit();
            }
          } else if (typeof form.submit === 'function') {
            form.submit();
          } else {
            throw new Error('target form cannot be submitted');
          }
          return true;
        }
        if (!el) throw new Error('element not found for browser action');
        el.scrollIntoView({ block: 'center', inline: 'center' });
        if ('${action}' === 'select') {
          let select = el;
          if (select.tagName && select.tagName.toLowerCase() === 'label') {
            const id = select.getAttribute('for');
            if (id) select = document.getElementById(id) || select;
          }
          if (!select || !select.tagName || select.tagName.toLowerCase() !== 'select') {
            const nested = select && select.querySelector && select.querySelector('select');
            if (nested) select = nested;
          }
          if (!select || !select.tagName || select.tagName.toLowerCase() !== 'select') {
            throw new Error('element is not a select control');
          }
          const options = Array.from(select.options || []);
          let option = null;
          if (args.optionValue) {
            option = options.find((candidate) => candidate.value === args.optionValue);
          } else if (args.optionLabel) {
            option = options.find((candidate) => candidate.label === args.optionLabel || String(candidate.text || '').trim() === args.optionLabel);
          } else if (Number.isInteger(args.optionIndex)) {
            option = options[args.optionIndex];
          }
          if (!option) throw new Error('select option not found');
          if (!select.multiple) options.forEach((candidate) => { candidate.selected = false; });
          option.selected = true;
          select.value = option.value;
          select.dispatchEvent(new Event('input', { bubbles: true }));
          select.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        }
        if ('${action}' === 'press') {
          el.focus();
          return true;
        }
        if ('${action}' === 'click') {
          el.click();
          return true;
        }
        if ('${action}' === 'type') {
          const reason = sensitiveTypeReasonForElement(el);
          if (reason) throw new Error('browser_type refuses likely sensitive credential entry target (' + reason + '); use browser_handoff for login, password, 2FA, token, or API key entry');
        }
        el.focus();
        if ('value' in el) {
          el.value = args.clear ? args.value : String(el.value || '') + args.value;
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
        } else {
          el.textContent = args.clear ? args.value : String(el.textContent || '') + args.value;
          el.dispatchEvent(new Event('input', { bubbles: true }));
        }
        if (args.submit) {
          if (el.form && typeof el.form.requestSubmit === 'function') el.form.requestSubmit();
          else el.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
        }
        return true;
      })()`;
    }

    function locatorParams(extra = {}) {
      return JSON.stringify(Object.assign({
        selector: args.selector || '',
        text: args.text || '',
        role: args.role || '',
        name: args.name || '',
        exact: args.exact === true,
        nth: Math.max(0, args.nth || 0)
      }, extra));
    }

    function locatorSupportScript(paramsExpression) {
      return `
        const args = ${paramsExpression};
        function compactText(value) {
          const normalized = Array.from(String(value || ''), (character) =>
            character.trim() ? character : ' ').join('');
          return normalized.split(' ').filter(Boolean).join(' ');
        }
        function associatedName(el) {
          if (!el || !el.getAttribute) return '';
          const aria = compactText(el.getAttribute('aria-label'));
          if (aria) return aria;
          const labelledBy = compactText(el.getAttribute('aria-labelledby'));
          if (labelledBy) {
            const text = labelledBy.split(' ')
              .map((id) => document.getElementById(id))
              .filter(Boolean)
              .map((node) => compactText(node.innerText || node.textContent || ''))
              .filter(Boolean)
              .join(' ');
            if (text) return compactText(text);
          }
          if (el.labels && el.labels.length) {
            const text = Array.from(el.labels)
              .map((label) => compactText(label.innerText || label.textContent || ''))
              .filter(Boolean)
              .join(' ');
            if (text) return compactText(text);
          }
          const id = el.getAttribute('id');
          if (id) {
            const label = Array.from(document.querySelectorAll('label'))
              .find((candidate) => candidate.getAttribute('for') === id);
            const text = label ? compactText(label.innerText || label.textContent || '') : '';
            if (text) return text;
          }
          return compactText(el.getAttribute('placeholder') || el.getAttribute('title') || '');
        }
        function textOf(el) {
          const tag = el.tagName ? el.tagName.toLowerCase() : '';
          const renderedText = tag === 'script' || tag === 'style' || tag === 'noscript'
            ? ''
            : (typeof el.innerText === 'string' && el.innerText.length ? el.innerText : el.textContent);
          return [
            associatedName(el),
            el.getAttribute && el.getAttribute('placeholder'),
            el.value,
            renderedText,
            el.getAttribute && el.getAttribute('name')
          ].filter(Boolean).join(' ').trim();
        }
        function inferredRole(el) {
          const explicit = el.getAttribute && el.getAttribute('role');
          if (explicit) return String(explicit).toLowerCase();
          const tag = el.tagName ? el.tagName.toLowerCase() : '';
          const type = String(el.getAttribute && el.getAttribute('type') || '').toLowerCase();
          if (tag === 'button') return 'button';
          if (tag === 'a' && el.href) return 'link';
          if (tag === 'select') return 'combobox';
          if (tag === 'textarea') return 'textbox';
          if (tag === 'input') {
            if (['button', 'submit', 'reset', 'image', 'file'].includes(type)) return 'button';
            if (type === 'checkbox') return 'checkbox';
            if (type === 'radio') return 'radio';
            return 'textbox';
          }
          if (el.isContentEditable) return 'textbox';
          return '';
        }
        function nameMatches(el, value, exact) {
          if (!value) return true;
          const expected = compactText(value);
          const candidates = [
            associatedName(el),
            compactText(el.innerText || el.textContent || ''),
            compactText(el.value),
            compactText(el.getAttribute && el.getAttribute('name'))
          ].filter(Boolean);
          if (exact) return candidates.some((candidate) => candidate === expected);
          const lowered = expected.toLowerCase();
          return candidates.some((candidate) => candidate.toLowerCase().includes(lowered));
        }
        function isVisible(el) {
          if (!el || !el.isConnected) return false;
          const style = window.getComputedStyle(el);
          if (!style || style.display === 'none' || style.visibility === 'hidden'
              || style.visibility === 'collapse' || Number(style.opacity) === 0) return false;
          const rect = el.getBoundingClientRect();
          return !!rect && rect.width > 0 && rect.height > 0 && el.getClientRects().length > 0;
        }
        function isEligible(el) {
          return args.includeHidden === true ? !!el && el.isConnected : isVisible(el);
        }
        function isActionable(el) {
          const tag = el.tagName ? el.tagName.toLowerCase() : '';
          const role = inferredRole(el);
          return ['button', 'a', 'input', 'textarea', 'select', 'summary', 'label'].includes(tag)
            || ['button', 'link', 'checkbox', 'radio', 'menuitem', 'option', 'tab', 'textbox', 'combobox'].includes(role)
            || el.isContentEditable;
        }
        function hasMatchingDescendant(el, value, exact) {
          return Array.from(el.children || []).some((child) =>
            isVisible(child) && nameMatches(child, value, exact));
        }
        function findElement() {
          if (args.selector) {
            return Array.from(document.querySelectorAll(args.selector))
              .filter(isEligible)[args.nth];
          }
          let candidates;
          if (args.role || args.name) {
            candidates = Array.from(document.querySelectorAll('input, textarea, button, a, select, [role], [aria-label], [placeholder], label, [contenteditable="true"]'));
          } else if (args.text) {
            candidates = Array.from(document.querySelectorAll('body *'))
              .filter((el) => !['script', 'style', 'noscript'].includes(el.tagName ? el.tagName.toLowerCase() : ''));
          } else {
            return null;
          }
          candidates = candidates.filter(isEligible);
          if (args.role) {
            const expectedRole = String(args.role).toLowerCase();
            candidates = candidates.filter((el) => inferredRole(el).toLowerCase() === expectedRole);
          }
          const query = args.name || args.text;
          if (query) candidates = candidates.filter((el) => nameMatches(el, query, args.exact));
          candidates.sort((left, right) => {
            const leftRank = isActionable(left) ? 0
              : (hasMatchingDescendant(left, query, args.exact) ? 2 : 1);
            const rightRank = isActionable(right) ? 0
              : (hasMatchingDescendant(right, query, args.exact) ? 2 : 1);
            if (leftRank !== rightRank) return leftRank - rightRank;
            return textOf(left).length - textOf(right).length;
          });
          return candidates[args.nth];
        }
      `;
    }

    function actionTargetExistsScript(includeHidden = false) {
      const params = locatorParams({ includeHidden });
      return `(() => {
        ${locatorSupportScript(params)}
        return !!findElement();
      })()`;
    }

    async function requireActionTarget(client, includeHidden = false) {
      let found = false;
      try {
        found = await evaluate(client, actionTargetExistsScript(includeHidden));
      } catch (_) {
        throw actionTargetNotFound();
      }
      if (!found) throw actionTargetNotFound();
    }

    async function requireSubmitTarget(client) {
      if (args.selector || args.text || (args.role && args.name)) {
        await requireActionTarget(client);
        return;
      }
      let found = false;
      try {
        found = await evaluate(client, `(() => !!document.querySelector('form'))()`);
      } catch (_) {
        throw actionTargetNotFound();
      }
      if (!found) throw actionTargetNotFound();
    }

    function clickPointScript() {
      const params = locatorParams();
      return `(() => {
        ${locatorSupportScript(params)}
        const located = findElement();
        if (!located) throw new Error('visible element not found for browser action');
        const target = isActionable(located)
          ? located
          : (located.closest('button, a[href], input, select, textarea, summary, label, [role="button"], [role="link"], [role="menuitem"]') || located);
        target.scrollIntoView({ block: 'center', inline: 'center' });
        const rect = target.getBoundingClientRect();
        if (!rect || rect.width <= 0 || rect.height <= 0) {
          throw new Error('target element is not clickable');
        }
        return {
          x: Math.max(0, rect.left + Math.min(Math.max(rect.width / 2, 1), rect.width - 1)),
          y: Math.max(0, rect.top + Math.min(Math.max(rect.height / 2, 1), rect.height - 1))
        };
      })()`;
    }

    async function dispatchMouseClick(client) {
      const point = await evaluate(client, clickPointScript());
      const x = Number(point && point.x);
      const y = Number(point && point.y);
      if (!Number.isFinite(x) || !Number.isFinite(y)) {
        throw new Error('target element click point is unavailable');
      }
      await client.send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y, button: 'none', buttons: 0 });
      await client.send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', buttons: 1, clickCount: 1 });
      await client.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', buttons: 0, clickCount: 1 });
    }

    function scrollScript() {
      const params = locatorParams({
        deltaX: args.deltaX || 0,
        deltaY: args.deltaY || 0
      });
      return `(() => {
        ${locatorSupportScript(params)}
        const deltaX = Number(args.deltaX || 0);
        const deltaY = Number(args.deltaY || 0);
        const target = findElement();
        if (target) {
          target.scrollIntoView({ block: 'center', inline: 'center' });
          let scrollable = target;
          while (scrollable && scrollable !== document.body && scrollable !== document.documentElement) {
            if ((scrollable.scrollHeight > scrollable.clientHeight) || (scrollable.scrollWidth > scrollable.clientWidth)) break;
            scrollable = scrollable.parentElement;
          }
          if (scrollable && scrollable !== document.body && scrollable !== document.documentElement) {
            scrollable.scrollBy(deltaX, deltaY);
          } else {
            window.scrollBy(deltaX, deltaY);
          }
        } else {
          window.scrollBy(deltaX, deltaY);
        }
        window.dispatchEvent(new Event('scroll'));
        return { x: window.scrollX || 0, y: window.scrollY || 0 };
      })()`;
    }

    function waitScript() {
      const state = ['attached', 'detached', 'visible', 'hidden'].includes(String(args.state || '').toLowerCase())
        ? String(args.state).toLowerCase()
        : 'visible';
      const timeoutMillis = Math.max(1000, Math.min(args.timeoutMillis || 10000, 30000));
      const params = locatorParams({ state, timeoutMillis, includeHidden: true });
      return `new Promise((resolve, reject) => {
        ${locatorSupportScript(params)}
        const deadline = Date.now() + Number(args.timeoutMillis || 10000);
        function elementIsVisibleForWait(el) {
          if (!el) return false;
          const rect = el.getBoundingClientRect();
          const style = window.getComputedStyle(el);
          return (rect.width > 0 || rect.height > 0) && style.visibility !== 'hidden' && style.display !== 'none';
        }
        function satisfied() {
          const el = findElement();
          if (args.state === 'attached') return !!el;
          if (args.state === 'detached') return !el;
          if (args.state === 'hidden') return !el || !elementIsVisibleForWait(el);
          return !!el && elementIsVisibleForWait(el);
        }
        function tick() {
          if (satisfied()) {
            resolve(true);
          } else if (Date.now() >= deadline) {
            reject(new Error('browser_wait timed out'));
          } else {
            setTimeout(tick, 100);
          }
        }
        tick();
      })`;
    }

    function fileInputScript() {
      const params = JSON.stringify({
        selector: args.selector || '',
        text: args.text || '',
        role: args.role || '',
        name: args.name || '',
        exact: args.exact === true,
        nth: Math.max(0, args.nth || 0),
        includeHidden: true
      });
      return `(() => {
        ${locatorSupportScript(params)}
        function fileInputFrom(candidate) {
          let el = candidate;
          if (el && el.tagName && el.tagName.toLowerCase() === 'label') {
            const id = el.getAttribute('for');
            if (id) el = document.getElementById(id) || el;
          }
          if (el && (!el.tagName || el.tagName.toLowerCase() !== 'input' || String(el.type || '').toLowerCase() !== 'file')) {
            const nested = el.querySelector && el.querySelector('input[type="file"]');
            if (nested) el = nested;
          }
          if (!el || !el.tagName || el.tagName.toLowerCase() !== 'input' || String(el.type || '').toLowerCase() !== 'file') {
            throw new Error('element is not a file input');
          }
          el.scrollIntoView({ block: 'center', inline: 'center' });
          return el;
        }
        return fileInputFrom(findElement());
      })()`;
    }

    function interactiveElementsScript() {
      return `(() => {
        function trim(value, max = 160) {
          const normalized = Array.from(String(value || ''), (character) =>
            character.trim() ? character : ' ').join('');
          return normalized.split(' ').filter(Boolean).join(' ').slice(0, max);
        }
        function cssString(value) {
          return JSON.stringify(String(value || '')).slice(1, -1);
        }
        function cssIdent(value) {
          try {
            if (window.CSS && CSS.escape) return CSS.escape(String(value || ''));
          } catch (_) {}
          return String(value || '').replace(/[^A-Za-z0-9_-]/g, (ch) =>
            String.fromCharCode(92) + ch.codePointAt(0).toString(16) + ' ');
        }
        function textOf(el) {
          return trim(el.innerText || el.textContent || el.value || '');
        }
        function labelFor(el) {
          const aria = trim(el.getAttribute('aria-label'));
          if (aria) return aria;
          const labelledBy = trim(el.getAttribute('aria-labelledby'));
          if (labelledBy) {
            const text = trim(labelledBy).split(' ')
              .map((id) => document.getElementById(id))
              .filter(Boolean)
              .map((node) => trim(node.innerText || node.textContent || ''))
              .filter(Boolean)
              .join(' ');
            if (text) return trim(text);
          }
          if (el.labels && el.labels.length) {
            const labelText = Array.from(el.labels).map((label) => trim(label.innerText || label.textContent || '')).filter(Boolean).join(' ');
            if (labelText) return trim(labelText);
          }
          const id = el.getAttribute('id');
          if (id) {
            const label = document.querySelector('label[for="' + cssString(id) + '"]');
            const labelText = label ? trim(label.innerText || label.textContent || '') : '';
            if (labelText) return labelText;
          }
          const tag = el.tagName ? el.tagName.toLowerCase() : '';
          const type = String(el.getAttribute('type') || '').toLowerCase();
          const fallbackText = tag === 'input' && !['button', 'submit', 'reset', 'image'].includes(type) ? '' : textOf(el);
          return trim(el.getAttribute('placeholder') || el.getAttribute('title') || fallbackText);
        }
        function inferredRole(el) {
          const explicit = trim(el.getAttribute('role'), 64).toLowerCase();
          if (explicit) return explicit;
          const tag = el.tagName ? el.tagName.toLowerCase() : '';
          const type = String(el.getAttribute('type') || '').toLowerCase();
          if (tag === 'button') return 'button';
          if (tag === 'a') return 'link';
          if (tag === 'textarea') return 'textbox';
          if (tag === 'select') return 'combobox';
          if (tag === 'input') {
            if (['button', 'submit', 'reset', 'image', 'file'].includes(type)) return 'button';
            if (['checkbox'].includes(type)) return 'checkbox';
            if (['radio'].includes(type)) return 'radio';
            return 'textbox';
          }
          if (el.isContentEditable) return 'textbox';
          return tag || 'element';
        }
        function isVisible(el) {
          if (!el || !el.isConnected || el.hidden) return false;
          const style = window.getComputedStyle(el);
          if (!style || style.display === 'none' || style.visibility === 'hidden'
              || style.visibility === 'collapse' || Number(style.opacity) === 0) return false;
          const rect = el.getBoundingClientRect();
          return !!rect && rect.width > 0 && rect.height > 0 && el.getClientRects().length > 0;
        }
        function selectorFor(el, index) {
          const tag = el.tagName ? el.tagName.toLowerCase() : '*';
          const id = el.getAttribute('id');
          function uniquelyIdentifies(candidate) {
            try {
              const matches = document.querySelectorAll(candidate);
              return matches.length === 1 && matches[0] === el;
            } catch (_) {
              return false;
            }
          }
          if (id) {
            const candidate = '#' + cssIdent(id);
            if (uniquelyIdentifies(candidate)) return candidate;
          }
          for (const attribute of ['data-testid', 'data-test', 'data-qa']) {
            const testId = el.getAttribute(attribute);
            if (testId) {
              const candidate = '[' + attribute + '="' + cssString(testId) + '"]';
              if (uniquelyIdentifies(candidate)) return candidate;
            }
          }
          const name = el.getAttribute('name');
          if (name && tag !== '*') {
            const candidate = tag + '[name="' + cssString(name) + '"]';
            if (uniquelyIdentifies(candidate)) return candidate;
          }
          const placeholder = el.getAttribute('placeholder');
          if (placeholder && tag !== '*') {
            const candidate = tag + '[placeholder="' + cssString(placeholder) + '"]';
            if (uniquelyIdentifies(candidate)) return candidate;
          }
          const role = el.getAttribute('role');
          if (role) {
            const candidate = '[role="' + cssString(role) + '"]';
            if (uniquelyIdentifies(candidate)) return candidate;
          }
          const segments = [];
          let current = el;
          while (current && current.nodeType === 1 && segments.length < 8) {
            const currentTag = current.tagName.toLowerCase();
            const parent = current.parentElement;
            const siblings = parent
              ? Array.from(parent.children).filter((node) => node.tagName === current.tagName)
              : [];
            const position = siblings.indexOf(current);
            segments.unshift(currentTag + (siblings.length > 1 && position >= 0
              ? ':nth-of-type(' + (position + 1) + ')'
              : ''));
            const candidate = segments.join(' > ');
            if (uniquelyIdentifies(candidate)) return candidate;
            current = parent;
          }
          return tag + ':nth-of-type(' + Math.max(1, index + 1) + ')';
        }
        const selector = [
          'button',
          'input',
          'textarea',
          'select',
          '[role]',
          '[aria-label]',
          '[placeholder]',
          '[contenteditable="true"]'
        ].join(',');
        return Array.from(document.querySelectorAll(selector)).filter(isVisible).slice(0, 120).map((el, index) => {
          const tag = el.tagName ? el.tagName.toLowerCase() : '';
          const type = trim(el.getAttribute('type'), 64).toLowerCase();
          const name = labelFor(el);
          const text = tag === 'input' && !['button', 'submit', 'reset'].includes(type) ? '' : textOf(el);
          const item = {
            role: inferredRole(el),
            name,
            text,
            selector: selectorFor(el, index),
            tag,
            type,
            placeholder: trim(el.getAttribute('placeholder')),
            disabled: !!el.disabled || el.getAttribute('aria-disabled') === 'true'
          };
          if (tag === 'input' && ['checkbox', 'radio'].includes(type)) item.checked = !!el.checked;
          if (tag === 'select') {
            item.options = Array.from(el.options || []).slice(0, 12).map((option) => trim(option.textContent || option.label || '')).filter(Boolean);
          }
          return item;
        }).filter((item) => item.name || item.text || item.placeholder || item.selector).slice(0, 50);
      })()`;
    }

    async function pageSummary(client, action) {
      if (waitMillis > 0) await wait(waitMillis);
      const summary = await evaluate(client, `(() => {
        const links = Array.from(document.querySelectorAll('a')).slice(0, 80).map((a) => ({
          text: String(a.innerText || a.textContent || '').trim().slice(0, 160),
          href: a.href || ''
        })).filter((item) => item.text || item.href).slice(0, 40);
        return {
          title: document.title || '',
          url: location.href,
          text: String(document.body ? document.body.innerText || '' : '').slice(0, ${maxText}),
          links
        };
      })()`) || {};
      const elements = await evaluate(client, interactiveElementsScript());
      return {
        action,
        profile: args.profile,
        backend: 'cdp',
        backendDetail: args.executablePath || '',
        url: summary.url || '',
        title: summary.title || '',
        text: summary.text || '',
        links: summary.links || [],
        elements: elements || []
      };
    }

    async function main() {
      if (typeof WebSocket !== 'function') {
        throw new Error('Node.js WebSocket is unavailable; install Playwright or use Node 22+ for CDP fallback');
      }
      const managedConnection = Number.isInteger(args.cdpPort);
      const executable = managedConnection
        ? String(args.managedBrowserExecutable || '')
        : cdpExecutableForChannel(args.channel);
      if (!managedConnection && !executable) {
        throw new Error('no Chromium/Chrome/Edge executable found for CDP fallback');
      }
      args.executablePath = executable || 'runtime-owned browser session';
      fs.mkdirSync(args.profileDir, { recursive: true });
      fs.mkdirSync(args.downloadsDir, { recursive: true });
      let stderr = '';
      let browserSpawnError = null;
      let browser = null;
      let devToolsEndpoint;
      if (managedConnection) {
        if (args.cdpPort < 1 || args.cdpPort > 65535
            || !/^\\/devtools\\/browser\\/[A-Za-z0-9._-]+$/.test(String(args.cdpBrowserPath || ''))) {
          throw new Error('managed browser session supplied an invalid DevTools endpoint');
        }
        devToolsEndpoint = {
          port: args.cdpPort,
          browserPath: String(args.cdpBrowserPath)
        };
        await validateDevToolsEndpoint(devToolsEndpoint);
      } else {
        const devToolsGeneration = prepareDevToolsActivePort(args.profileDir);
        const launchArgs = [
          `--user-data-dir=${args.profileDir}`,
          '--remote-debugging-port=0',
          '--remote-debugging-address=127.0.0.1',
          '--remote-allow-origins=*',
          '--no-first-run',
          '--no-default-browser-check',
          '--disable-breakpad',
          '--disable-crashpad-for-testing',
          '--use-mock-keychain',
          `--window-size=1280,900`,
          'about:blank'
        ];
        if (args.headless !== false) {
          launchArgs.unshift('--headless=new', '--disable-gpu');
        }
        browser = childProcess.spawn(executable, launchArgs, { stdio: ['ignore', 'ignore', 'pipe'] });
        activeBrowser = browser;
        browser.once('error', (error) => { browserSpawnError = error; });
        browser.stderr.on('data', (chunk) => {
          if (stderr.length < 4000) stderr += chunk.toString().slice(0, 4000 - stderr.length);
        });
        devToolsEndpoint = await waitForDevToolsActivePort(
          devToolsGeneration,
          15000,
          browser,
          () => browserSpawnError
        ).catch((error) => {
          if (stderr.trim()) throw new Error(`${error.message}: ${stderr.trim()}`);
          throw error;
        });
      }
      const clients = [];
      let client = null;

      try {
        const port = devToolsEndpoint.port;
        const url = targetURL();
        const target = await pageTarget(port, url);
        client = new CDPClient(target.webSocketDebuggerUrl);
        clients.push(client);
        let currentTargetID = target.id;
        await client.connect();
        await enablePageClient(client);

        let downloads = [];
        let openedNewPage = false;
        let pageCount = 1;
        async function runAndFollowNewPage(action) {
          const beforeTargets = await listPageTargets(port).catch(() => []);
          const beforeTargetIDs = new Set(beforeTargets.map((item) => item.id));
          await action();
          const followed = await maybeNewPageTarget(port, beforeTargetIDs, currentTargetID);
          pageCount = followed.pageCount || pageCount;
          if (followed.client && followed.target) {
            client = followed.client;
            clients.push(client);
            currentTargetID = followed.target.id;
            openedNewPage = true;
          }
        }
        switch (args.action) {
          case 'navigate':
          case 'back':
          case 'forward':
            await navigate(client, url);
            break;
          case 'snapshot':
            await ensureCurrentPage(client, url);
            break;
          case 'screenshot':
            await ensureCurrentPage(client, url, !!args.url);
            break;
          case 'handoff':
            await ensureCurrentPage(client, url, !!args.url);
            await wait(handoffMillis);
            break;
          case 'reload':
            await ensureCurrentPage(client, url);
            {
              const loaded = client.once('Page.loadEventFired', 45000).catch(() => undefined);
              await client.send('Page.reload', { ignoreCache: args.ignoreCache === true });
              await loaded;
              if (waitMillis > 0) await wait(waitMillis);
            }
            break;
          case 'search':
            await navigate(client, searchURL());
            break;
          case 'click':
            await ensureCurrentPage(client, url);
            await requireActionTarget(client);
            await runAndFollowNewPage(async () => {
              await dispatchMouseClick(client);
            });
            break;
          case 'type':
            await ensureCurrentPage(client, url);
            await requireActionTarget(client);
            await runAndFollowNewPage(async () => {
              await evaluate(client, actionScript('type'));
              if (args.submit === true) await wait(800);
            });
            break;
          case 'select':
            await ensureCurrentPage(client, url);
            await requireActionTarget(client);
            await runAndFollowNewPage(async () => {
              await evaluate(client, actionScript('select'));
            });
            break;
          case 'submit':
            await ensureCurrentPage(client, url);
            await requireSubmitTarget(client);
            await runAndFollowNewPage(async () => {
              await evaluate(client, actionScript('submit'));
              await wait(Math.min(Math.max(waitMillis || 600, 250), 1200));
            });
            break;
          case 'press':
            await ensureCurrentPage(client, url);
            if (args.selector || args.text || (args.role && args.name)) {
              await requireActionTarget(client);
            }
            await runAndFollowNewPage(async () => {
              if (args.selector || args.text || (args.role && args.name)) {
                await evaluate(client, actionScript('press'));
              }
              await dispatchKey(client, args.key || '');
            });
            break;
          case 'scroll':
            await ensureCurrentPage(client, url);
            if (args.selector || args.text || (args.role && args.name)) {
              await requireActionTarget(client);
            }
            await evaluate(client, scrollScript());
            break;
          case 'wait':
            await ensureCurrentPage(client, url);
            if (args.selector || args.text || (args.role && args.name)) {
              await evaluate(client, waitScript(), Math.max(1000, Math.min(args.timeoutMillis || 10000, 30000)) + 1000);
            } else {
              await wait(Math.max(1000, Math.min(args.timeoutMillis || 10000, 30000)));
            }
            break;
          case 'upload': {
            await ensureCurrentPage(client, url);
            await requireActionTarget(client, true);
            await client.send('DOM.enable');
            const objectId = await fileInputObjectId(client);
            await client.send('DOM.setFileInputFiles', {
              objectId,
              files: [args.filePath]
            });
            await dispatchInputEvents(client, objectId);
            break;
          }
          case 'download': {
            await ensureCurrentPage(client, url);
            await requireActionTarget(client);
            const before = listDownloadFiles();
            await dispatchMouseClick(client);
            downloads = await waitForNewDownloads(before);
            break;
          }
          default:
            throw new Error(`unsupported CDP browser action: ${args.action}`);
        }

        let summary = await pageSummary(client, args.action);
        if (args.action === 'screenshot') {
          if (!args.outputPath) throw new Error('outputPath is required for browser_screenshot');
          fs.mkdirSync(path.dirname(args.outputPath), { recursive: true });
          const shot = await client.send('Page.captureScreenshot', {
            format: 'png',
            captureBeyondViewport: args.fullPage === true
          });
          fs.writeFileSync(args.outputPath, Buffer.from(shot.data || '', 'base64'));
          summary.screenshotPath = args.relativeOutputPath || args.outputPath;
        }
        if (args.action === 'upload') summary.uploadedFiles = [args.relativeFilePath || args.filePath];
        if (downloads.length) summary.downloads = downloads;
        if (openedNewPage) summary.openedPage = { url: summary.url || '', title: summary.title || '' };
        const targetsAfter = await listPageTargets(port).catch(() => []);
        summary.pageCount = Math.max(pageCount, targetsAfter.length || 0);
        console.log(JSON.stringify(summary));
      } finally {
        if (!managedConnection && client) {
          try { await client.send('Browser.close', {}, 1500); } catch (_) {}
        }
        for (const item of clients) item.close();
        if (browser) {
          if (!(await waitForProcessExit(browser, 1500))) {
            try { browser.kill('SIGTERM'); } catch (_) {}
            if (!(await waitForProcessExit(browser, 1500))) {
              try { browser.kill('SIGKILL'); } catch (_) {}
              await waitForProcessExit(browser, 1000);
            }
          }
        }
        activeBrowser = null;
      }
    }

    main()
      .then(() => {
        clearTimeout(commandWatchdog);
      })
      .catch((error) => {
        clearTimeout(commandWatchdog);
        emitNoEffectFailure(error);
        console.error(error && error.stack ? error.stack : String(error));
        process.exit(1);
      });
    """
    return browserBackendInvocation(
        javaScript: javaScript,
        encodedArguments: payload,
        arguments: arguments)
}

private func browserBackendMissing(_ result: ShellResult) -> Bool {
    let message = result.stderr.isEmpty ? result.stdout : result.stderr
    return message.contains("playwright is not installed or not resolvable by Node")
        || message.contains("Cannot find module 'playwright'")
}

private func validateBrowserNavigationInput(arguments: [String: Any],
                                            paths: BrowserPaths) throws {
    if let explicitURL = arguments["url"] as? String,
       explicitURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
        _ = try BrowserToolConfig.validatedHTTPURLString(explicitURL)
        return
    }
    guard (arguments["action"] as? String) != "search" else {
        return
    }
    let state = browserStateDictionary(at: paths.stateFile)
    guard let persistedURL = state["url"] as? String,
          persistedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
        return
    }
    _ = try BrowserToolConfig.validatedHTTPURLString(persistedURL)
}

private func runPlaywright(arguments: [String: Any],
                           paths: BrowserPaths,
                           context: ToolContext,
                           maxCharacters: Int,
                           redactions: [String] = [],
                           changedFiles: [String]? = nil) async throws -> ToolObservation {
    try await withBrowserProfileCommandLock(paths: paths) {
        try await runPlaywrightUnlocked(arguments: arguments,
                                        paths: paths,
                                        context: context,
                                        maxCharacters: maxCharacters,
                                        redactions: redactions,
                                        changedFiles: changedFiles)
    }
}

private func runPlaywrightUnlocked(arguments: [String: Any],
                                   paths: BrowserPaths,
                                   context: ToolContext,
                                   maxCharacters: Int,
                                   redactions: [String] = [],
                                   changedFiles: [String]? = nil) async throws -> ToolObservation {
    try validateBrowserNavigationInput(arguments: arguments, paths: paths)
    let command = try playwrightCommand(arguments: arguments)
    var shellResult = try await context.browserBackend.run(
        command,
        cwd: context.workspaceRoot)
    if shellResult.exitCode != 0 && browserBackendMissing(shellResult) {
        let fallbackCommand = try cdpCommand(arguments: arguments)
        shellResult = try await context.browserBackend.run(
            fallbackCommand,
            cwd: context.workspaceRoot)
    }
    guard shellResult.exitCode == 0 else {
        if let rejection = browserNoEffectRejection(
            from: shellResult,
            arguments: arguments) {
            throw rejection
        }
        var message = shellResult.stderr.isEmpty ? shellResult.stdout : shellResult.stderr
        if message.count > 10_000 { message = String(message.prefix(10_000)) + "\n[truncated]" }
        throw IntatisError.io("browser backend failed: \(message)")
    }
    let jsonLine = try browserJSONLine(from: shellResult.stdout)
    let decoded = try JSONDecoder().decode(BrowserActionResult.self, from: Data(jsonLine.utf8))
    try updateBrowserStateAndHistory(decoded, paths: paths)
    let output = browserOutputText(decoded, maxCharacters: maxCharacters, redactions: redactions)
    let profileHint = "\n\nPersistent browser profile: .intatis/browser/profiles/\(paths.profile)\nHistory metadata: .intatis/browser/history.jsonl"
    var observedChangedFiles = changedFiles ?? []
    if let downloads = decoded.downloads {
        observedChangedFiles.append(contentsOf: downloads.compactMap { entry in
            guard let path = entry.path, !path.isEmpty else { return nil }
            return path
        })
    }
    return ToolObservation(
        text: output + profileHint,
        changedFiles: observedChangedFiles.isEmpty ? nil : observedChangedFiles)
}

private func maxCharacters(_ raw: Int?) -> Int {
    min(max(raw ?? 20_000, 1), BrowserToolConfig.maxSnapshotCharacters)
}

private func normalizedBrowserKey(_ raw: String) throws -> String {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.count <= 80 else {
        throw IntatisError.decoding("browser_press_key key must be 1-80 characters")
    }
    guard value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
        throw IntatisError.decoding("browser_press_key key must not contain control characters")
    }
    return value
}

private func normalizedBrowserWaitState(_ raw: String?) -> String {
    let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    switch value {
    case "attached", "detached", "visible", "hidden":
        return value
    default:
        return "visible"
    }
}

private func browserScrollDelta(direction: String?, amount: Int?, deltaX: Int?, deltaY: Int?) throws -> (x: Int, y: Int) {
    if deltaX != nil || deltaY != nil {
        let x = deltaX ?? 0
        let y = deltaY ?? 0
        guard x != 0 || y != 0 else {
            throw IntatisError.decoding("browser_scroll requires a non-zero delta")
        }
        return (x, y)
    }

    let pixels = min(max(amount ?? 900, 1), 10_000)
    let value = direction?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "down"
    switch value {
    case "down":
        return (0, pixels)
    case "up":
        return (0, -pixels)
    case "right":
        return (pixels, 0)
    case "left":
        return (-pixels, 0)
    default:
        throw IntatisError.decoding("browser_scroll direction must be down, up, right, or left")
    }
}

private func browserDiagnosticsOutput(_ result: BrowserDiagnosticsResult) -> String {
    var lines: [String] = []
    lines.append("browser action: \(result.action ?? "diagnostics")")
    lines.append("node: \(result.nodeVersion ?? "unknown")")
    lines.append("platform: \(result.platform ?? "unknown")/\(result.arch ?? "unknown")")
    lines.append("channel: \(result.channel ?? BrowserToolConfig.defaultChannel)")
    lines.append("profile: \(result.profile ?? BrowserToolConfig.defaultProfile)")
    lines.append("playwright available: \((result.playwrightAvailable ?? false) ? "yes" : "no")")
    if let version = result.playwrightVersion, !version.isEmpty {
        lines.append("playwright version: \(version)")
    }
    if let resolvedFrom = result.playwrightResolvedFrom, !resolvedFrom.isEmpty {
        lines.append("playwright resolved from: \(resolvedFrom)")
    }
    lines.append("node WebSocket available: \((result.nodeWebSocketAvailable ?? false) ? "yes" : "no")")
    lines.append("cdp fallback available: \((result.cdpAvailable ?? false) ? "yes" : "no")")
    if let cdpExecutable = result.cdpExecutable, !cdpExecutable.isEmpty {
        lines.append("cdp executable: \(cdpExecutable)")
    }
    lines.append("profile dir: \(result.profileDir ?? "unknown")")
    lines.append("downloads dir: \(result.downloadsDir ?? "unknown")")
    lines.append("state file: \(result.stateFile ?? "unknown")")
    lines.append("history file: \(result.historyFile ?? "unknown")")
    if let browserApps = result.browserApps, !browserApps.isEmpty {
        lines.append("")
        lines.append("installed app probes:")
        for key in browserApps.keys.sorted() {
            lines.append("- \(key): \(browserApps[key] == true ? "yes" : "no")")
        }
    }
    if let checked = result.checkedLocations, !checked.isEmpty {
        lines.append("")
        lines.append("checked Playwright locations:")
        for item in checked.prefix(20) {
            lines.append("- \(item)")
        }
        if checked.count > 20 {
            lines.append("[truncated]")
        }
    }
    return lines.joined(separator: "\n")
}

private func browserHistoryOutput(_ entries: [BrowserHistoryEntry], profile: String?, limit: Int) -> String {
    var lines: [String] = []
    lines.append("browser history: \(entries.count) entr\(entries.count == 1 ? "y" : "ies")")
    if let profile {
        lines.append("profile filter: \(profile)")
    }
    lines.append("limit: \(limit)")
    if entries.isEmpty {
        lines.append("")
        lines.append("no matching history entries")
        return lines.joined(separator: "\n")
    }
    lines.append("")
    for (index, entry) in entries.enumerated() {
        var line = "\(index + 1). \(entry.ts ?? "unknown-time")"
        line += " [\(entry.profile ?? BrowserToolConfig.defaultProfile)]"
        line += " \(entry.action ?? "unknown")"
        if let title = entry.title, !title.isEmpty {
            line += " - \(title)"
        }
        if let url = entry.url, !url.isEmpty {
            line += " - \(url)"
        }
        if let screenshotPath = entry.screenshotPath, !screenshotPath.isEmpty {
            line += " - screenshot: \(screenshotPath)"
        }
        lines.append(line)
    }
    lines.append("")
    lines.append("History metadata: .intatis/browser/history.jsonl")
    return lines.joined(separator: "\n")
}

// MARK: - web_fetch

public struct WebFetchTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "web_fetch",
        description: "Fetch an HTTP(S) URL without browser state. Use browser_* tools when login, JavaScript, cookies, or history are needed.",
        sideEffect: .network,
        parameters: Schema.object([
            "url": Schema.nonEmptyString,
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: ["url"])
    )

    struct Args: Decodable {
        let url: String
        let maxCharacters: Int?
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let url = try BrowserToolConfig.validatedHTTPURL(a.url)
        var request = URLRequest(url: url)
        request.setValue("IntatisAgent/0.16", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let limit = maxCharacters(a.maxCharacters)
        let body = String(data: data, encoding: .utf8)
            ?? String(decoding: data.prefix(limit), as: UTF8.self)
        let truncated = body.count > limit
        let shown = truncated ? String(body.prefix(limit)) : body
        let lines = [
            "status: \(http?.statusCode ?? 0)",
            "url: \(http?.url?.absoluteString ?? url.absoluteString)",
            "content-type: \(http?.value(forHTTPHeaderField: "Content-Type") ?? "unknown")",
            "",
            shown,
        ]
        return ToolObservation(text: lines.joined(separator: "\n"), truncated: truncated)
    }
}

// MARK: - browser_diagnostics

public struct BrowserDiagnosticsTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_diagnostics",
        description: "Report local Node, Playwright, browser channel, profile, download, state, and history paths for the persistent browser backend.",
        sideEffect: .exec,
        parameters: Schema.object([
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
        ], required: [])
    )

    struct Args: Decodable {
        let profile: String?
        let channel: String?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let profile = (try? BrowserToolConfig.normalizedProfile((try? args.decode(Args.self))?.profile)) ?? BrowserToolConfig.defaultProfile
        return [
            ".intatis/browser/profiles/\(profile)",
            ".intatis/browser/history.jsonl",
        ]
    }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let profileURL = try BrowserToolConfig.profileURL(profile: profile, workspace: context.workspaceRoot)
        let downloadsURL = try BrowserToolConfig.downloadsURL(profile: profile, workspace: context.workspaceRoot)
        let stateURL = try BrowserToolConfig.stateURL(profile: profile, workspace: context.workspaceRoot)
        let historyURL = try BrowserToolConfig.historyURL(workspace: context.workspaceRoot)
        let payload: [String: Any] = [
            "action": "diagnostics",
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "profileDir": profileURL.path,
            "downloadsDir": downloadsURL.path,
            "stateFile": stateURL.path,
            "historyFile": historyURL.path,
        ]
        let command = try playwrightCommand(arguments: payload)
        let shellResult = try await context.structuredShell.run(
            command.injectedShellCommand,
            cwd: context.workspaceRoot)
        guard shellResult.exitCode == 0 else {
            var message = shellResult.stderr.isEmpty ? shellResult.stdout : shellResult.stderr
            if message.count > 10_000 { message = String(message.prefix(10_000)) + "\n[truncated]" }
            throw IntatisError.io("browser diagnostics failed: \(message)")
        }
        let jsonLine = try browserJSONLine(from: shellResult.stdout)
        let decoded = try JSONDecoder().decode(BrowserDiagnosticsResult.self, from: Data(jsonLine.utf8))
        return ToolObservation(text: browserDiagnosticsOutput(decoded))
    }
}

// MARK: - browser_profiles

public struct BrowserProfilesTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_profiles",
        description: "List persistent browser profiles and safe metadata without reading cookies, localStorage, or browser profile databases.",
        sideEffect: .readOnly,
        parameters: Schema.object([
            "profile": Schema.nonEmptyString,
            "limit": Schema.boundedInteger(minimum: 1, maximum: 100),
            "includeProfileSize": Schema.boolean,
        ], required: [])
    )

    struct Args: Decodable {
        let profile: String?
        let limit: Int?
        let includeProfileSize: Bool?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        guard let decoded = try? args.decode(Args.self),
              let rawProfile = decoded.profile?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawProfile.isEmpty == false,
              let profile = try? BrowserToolConfig.normalizedProfile(rawProfile) else {
            return [
                ".intatis/browser/profiles",
                ".intatis/browser/state",
                ".intatis/browser/history.jsonl",
                ".intatis/browser/downloads",
            ]
        }
        return [
            ".intatis/browser/profiles/\(profile)",
            ".intatis/browser/state/\(profile).json",
            ".intatis/browser/history.jsonl",
            ".intatis/browser/downloads/\(profile)",
        ]
    }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let limit = min(max(a.limit ?? 20, 1), 100)
        let rawProfile = a.profile?.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = rawProfile?.isEmpty == false ? try BrowserToolConfig.normalizedProfile(rawProfile) : nil
        let includeProfileSize = a.includeProfileSize ?? false
        let profiles = try browserKnownProfiles(workspace: context.workspaceRoot,
                                                filter: profile,
                                                includeProfileSize: includeProfileSize,
                                                limit: limit)
        return ToolObservation(text: browserProfilesOutput(profiles,
                                                           filter: profile,
                                                           limit: limit,
                                                           includeProfileSize: includeProfileSize))
    }
}

// MARK: - browser_profile_delete

public struct BrowserProfileDeleteTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_profile_delete",
        description: "Delete one workspace-scoped persistent browser profile, including its state, downloads, and Intatis history metadata. Requires confirmProfile to match profile.",
        sideEffect: .destructive,
        parameters: Schema.object([
            "profile": Schema.nonEmptyString,
            "confirmProfile": Schema.nonEmptyString,
        ], required: ["profile", "confirmProfile"])
    )

    struct Args: Decodable {
        let profile: String
        let confirmProfile: String
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let decoded = try? args.decode(Args.self)
        let profile = (try? BrowserToolConfig.normalizedProfile(decoded?.profile)) ?? BrowserToolConfig.defaultProfile
        return [
            ".intatis/browser/profiles/\(profile)",
            ".intatis/browser/state/\(profile).json",
            ".intatis/browser/downloads/\(profile)",
            ".intatis/browser/history.jsonl",
        ]
    }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let confirmed = try BrowserToolConfig.normalizedProfile(a.confirmProfile)
        guard confirmed == profile else {
            throw IntatisError.config("confirmProfile must exactly match profile to delete browser profile data")
        }

        let paths = try BrowserToolConfig.paths(profile: profile, workspace: context.workspaceRoot)
        let summary = try await withBrowserProfileCommandLock(paths: paths) {
            let runtimeBeforeDelete = browserProfileRuntimeMetadata(at: paths.profileDir)
            await context.browserSession?.terminate(
                profileDirectory: paths.profileDir,
                reason: "browser profile deleted")
            let removedProfileData = try removeBrowserItemIfPresent(paths.profileDir)
            let removedDownloads = try removeBrowserItemIfPresent(paths.downloadsDir)
            let metadata = try removeBrowserStateAndPruneHistory(profile: profile, paths: paths)
            return BrowserProfileDeleteSummary(removedProfileData: removedProfileData,
                                               removedDownloads: removedDownloads,
                                               removedState: metadata.removedState,
                                               removedHistoryEntries: metadata.removedHistoryEntries,
                                               keptHistoryEntries: metadata.keptHistoryEntries,
                                               runtimeBeforeDelete: runtimeBeforeDelete)
        }

        return ToolObservation(text: browserProfileDeleteOutput(profile: profile,
                                                                paths: paths,
                                                                summary: summary,
                                                                workspace: context.workspaceRoot),
                               changedFiles: [
                                   PathConfinement.relativePath(of: paths.profileDir, root: context.workspaceRoot),
                                   PathConfinement.relativePath(of: paths.stateFile, root: context.workspaceRoot),
                                   PathConfinement.relativePath(of: paths.downloadsDir, root: context.workspaceRoot),
                                   PathConfinement.relativePath(of: paths.historyFile, root: context.workspaceRoot),
                               ])
    }
}

// MARK: - browser_history

public struct BrowserHistoryTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_history",
        description: "Read recent Intatis browser history metadata without exposing cookies, local storage, or credential files.",
        sideEffect: .readOnly,
        parameters: Schema.object([
            "profile": Schema.nonEmptyString,
            "limit": Schema.boundedInteger(minimum: 1, maximum: 100),
        ], required: [])
    )

    struct Args: Decodable {
        let profile: String?
        let limit: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        [".intatis/browser/history.jsonl"]
    }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let limit = min(max(a.limit ?? 20, 1), 100)
        let rawProfile = a.profile?.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = rawProfile?.isEmpty == false ? try BrowserToolConfig.normalizedProfile(rawProfile) : nil
        let historyURL = try BrowserToolConfig.historyURL(workspace: context.workspaceRoot)
        guard FileManager.default.fileExists(atPath: historyURL.path) else {
            return ToolObservation(text: browserHistoryOutput([], profile: profile, limit: limit))
        }
        let text = try String(contentsOf: historyURL, encoding: .utf8)
        let decoder = JSONDecoder()
        let entries = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> BrowserHistoryEntry? in
                guard let entry = try? decoder.decode(BrowserHistoryEntry.self, from: Data(line.utf8)) else {
                    return nil
                }
                if let profile, entry.profile != profile { return nil }
                return entry
            }
            .suffix(limit)
            .reversed()
        return ToolObservation(text: browserHistoryOutput(Array(entries), profile: profile, limit: limit))
    }
}

// MARK: - browser_navigate

public struct BrowserNavigateTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_navigate",
        description: "Open an HTTP(S) URL in a live workspace-scoped Chromium/Chrome/Edge profile session and return page text plus links.",
        sideEffect: .exec,
        parameters: Schema.object([
            "url": Schema.nonEmptyString,
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "headless": Schema.boolean,
            "waitMillis": Schema.boundedInteger(minimum: 0, maximum: 10_000),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: ["url"])
    )

    struct Args: Decodable {
        let url: String
        let profile: String?
        let channel: String?
        let headless: Bool?
        let waitMillis: Int?
        let maxCharacters: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let profile = (try? BrowserToolConfig.normalizedProfile((try? args.decode(Args.self))?.profile)) ?? BrowserToolConfig.defaultProfile
        return BrowserToolConfig.executionTouchedPaths(profile: profile)
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        _ = try BrowserToolConfig.validatedHTTPURL(a.url)
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let paths = try BrowserToolConfig.prepare(
            profile: profile,
            workspace: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        let limit = maxCharacters(a.maxCharacters)
        let payload: [String: Any] = [
            "action": "navigate",
            "url": a.url,
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "headless": a.headless ?? true,
            "waitMillis": a.waitMillis ?? 600,
            "maxCharacters": limit,
            "profileDir": paths.profileDir.path,
            "downloadsDir": paths.downloadsDir.path,
            "stateFile": paths.stateFile.path,
        ]
        return try await runPlaywright(arguments: payload, paths: paths, context: context, maxCharacters: limit)
    }
}

// MARK: - browser_snapshot

public struct BrowserSnapshotTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_snapshot",
        description: "Inspect the current live page in a persistent browser profile without reloading it, and return page text plus links.",
        sideEffect: .exec,
        parameters: Schema.object([
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "headless": Schema.boolean,
            "waitMillis": Schema.boundedInteger(minimum: 0, maximum: 10_000),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: [])
    )

    struct Args: Decodable {
        let profile: String?
        let channel: String?
        let headless: Bool?
        let waitMillis: Int?
        let maxCharacters: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let profile = (try? BrowserToolConfig.normalizedProfile((try? args.decode(Args.self))?.profile)) ?? BrowserToolConfig.defaultProfile
        return BrowserToolConfig.executionTouchedPaths(profile: profile)
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let paths = try BrowserToolConfig.prepare(
            profile: profile,
            workspace: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        let limit = maxCharacters(a.maxCharacters)
        let payload: [String: Any] = [
            "action": "snapshot",
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "headless": a.headless ?? true,
            "waitMillis": a.waitMillis ?? 600,
            "maxCharacters": limit,
            "profileDir": paths.profileDir.path,
            "downloadsDir": paths.downloadsDir.path,
            "stateFile": paths.stateFile.path,
        ]
        return try await runPlaywright(arguments: payload, paths: paths, context: context, maxCharacters: limit)
    }
}

// MARK: - browser_handoff

public struct BrowserHandoffTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_handoff",
        description: "Expose the live persistent Chromium/Chrome/Edge profile in a headed window for user login or manual interaction, then continue with that same session.",
        sideEffect: .exec,
        parameters: Schema.object([
            "url": Schema.nonEmptyString,
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "handoffSeconds": Schema.boundedInteger(minimum: 1, maximum: 600),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: [])
    )

    struct Args: Decodable {
        let url: String?
        let profile: String?
        let channel: String?
        let handoffSeconds: Int?
        let maxCharacters: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let profile = (try? BrowserToolConfig.normalizedProfile((try? args.decode(Args.self))?.profile)) ?? BrowserToolConfig.defaultProfile
        return BrowserToolConfig.executionTouchedPaths(profile: profile)
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let paths = try BrowserToolConfig.prepare(
            profile: profile,
            workspace: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        let limit = maxCharacters(a.maxCharacters)
        let handoffSeconds = min(max(a.handoffSeconds ?? 60, 1), 600)
        var payload: [String: Any] = [
            "action": "handoff",
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "headless": false,
            "handoffTimeoutMillis": handoffSeconds * 1000,
            "waitMillis": 0,
            "maxCharacters": limit,
            "profileDir": paths.profileDir.path,
            "downloadsDir": paths.downloadsDir.path,
            "stateFile": paths.stateFile.path,
        ]
        if let url = a.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            _ = try BrowserToolConfig.validatedHTTPURL(url)
            payload["url"] = url
        }
        return try await runPlaywright(arguments: payload, paths: paths, context: context, maxCharacters: limit)
    }
}

// MARK: - browser_reload

public struct BrowserReloadTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_reload",
        description: "Reload the current page in a persistent Chromium/Chrome/Edge browser profile and return page text plus links.",
        sideEffect: .exec,
        parameters: Schema.object([
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "headless": Schema.boolean,
            "ignoreCache": Schema.boolean,
            "waitMillis": Schema.boundedInteger(minimum: 0, maximum: 10_000),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: [])
    )

    struct Args: Decodable {
        let profile: String?
        let channel: String?
        let headless: Bool?
        let ignoreCache: Bool?
        let waitMillis: Int?
        let maxCharacters: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let profile = (try? BrowserToolConfig.normalizedProfile((try? args.decode(Args.self))?.profile)) ?? BrowserToolConfig.defaultProfile
        return BrowserToolConfig.executionTouchedPaths(profile: profile)
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let paths = try BrowserToolConfig.prepare(
            profile: profile,
            workspace: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        let limit = maxCharacters(a.maxCharacters)
        let payload: [String: Any] = [
            "action": "reload",
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "headless": a.headless ?? true,
            "ignoreCache": a.ignoreCache ?? false,
            "waitMillis": a.waitMillis ?? 600,
            "maxCharacters": limit,
            "profileDir": paths.profileDir.path,
            "downloadsDir": paths.downloadsDir.path,
            "stateFile": paths.stateFile.path,
        ]
        return try await runPlaywright(arguments: payload, paths: paths, context: context, maxCharacters: limit)
    }
}

private struct BrowserHistoryNavigationArgs: Decodable {
    let profile: String?
    let channel: String?
    let headless: Bool?
    let waitMillis: Int?
    let maxCharacters: Int?
}

private func browserHistoryNavigationTouchedPaths(_ args: ToolArgs) -> [String] {
    let profile = (try? BrowserToolConfig.normalizedProfile((try? args.decode(BrowserHistoryNavigationArgs.self))?.profile))
        ?? BrowserToolConfig.defaultProfile
    return BrowserToolConfig.executionTouchedPaths(profile: profile)
}

private func executeBrowserHistoryNavigation(_ args: ToolArgs,
                                             in context: ToolContext,
                                             direction: BrowserHistoryDirection) async throws -> ToolObservation {
    let a = try args.decode(BrowserHistoryNavigationArgs.self)
    let profile = try BrowserToolConfig.normalizedProfile(a.profile)
    let paths = try BrowserToolConfig.prepare(
        profile: profile,
        workspace: context.workspaceRoot,
        workspaceLease: context.workspaceLease)
    return try await withBrowserProfileCommandLock(paths: paths) {
        let targetURL = try browserHistoryNavigationURL(direction: direction, paths: paths)
        let limit = maxCharacters(a.maxCharacters)
        let payload: [String: Any] = [
            "action": direction.actionName,
            "url": targetURL,
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "headless": a.headless ?? true,
            "waitMillis": a.waitMillis ?? 600,
            "maxCharacters": limit,
            "profileDir": paths.profileDir.path,
            "downloadsDir": paths.downloadsDir.path,
            "stateFile": paths.stateFile.path,
        ]
        return try await runPlaywrightUnlocked(arguments: payload,
                                               paths: paths,
                                               context: context,
                                               maxCharacters: limit)
    }
}

// MARK: - browser_back

public struct BrowserBackTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_back",
        description: "Go back to the previous URL recorded for a persistent Chromium/Chrome/Edge browser profile.",
        sideEffect: .exec,
        parameters: Schema.object([
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "headless": Schema.boolean,
            "waitMillis": Schema.boundedInteger(minimum: 0, maximum: 10_000),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: [])
    )

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        browserHistoryNavigationTouchedPaths(args)
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        try await executeBrowserHistoryNavigation(args, in: context, direction: .back)
    }
}

// MARK: - browser_forward

public struct BrowserForwardTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_forward",
        description: "Go forward to the next URL recorded for a persistent Chromium/Chrome/Edge browser profile.",
        sideEffect: .exec,
        parameters: Schema.object([
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "headless": Schema.boolean,
            "waitMillis": Schema.boundedInteger(minimum: 0, maximum: 10_000),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: [])
    )

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        browserHistoryNavigationTouchedPaths(args)
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        try await executeBrowserHistoryNavigation(args, in: context, direction: .forward)
    }
}

// MARK: - browser_click

public struct BrowserClickTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_click",
        description: "Click an element on the current live browser page by CSS selector, visible text, or accessibility role/name without reloading first.",
        sideEffect: .exec,
        parameters: Schema.object([
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "headless": Schema.boolean,
            "selector": Schema.nonEmptyString,
            "text": Schema.nonEmptyString,
            "role": Schema.nonEmptyString,
            "name": Schema.nonEmptyString,
            "exact": Schema.boolean,
            "nth": Schema.boundedInteger(minimum: 0, maximum: 100),
            "waitMillis": Schema.boundedInteger(minimum: 0, maximum: 10_000),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: [])
    )

    struct Args: Decodable {
        let profile: String?
        let channel: String?
        let headless: Bool?
        let selector: String?
        let text: String?
        let role: String?
        let name: String?
        let exact: Bool?
        let nth: Int?
        let waitMillis: Int?
        let maxCharacters: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let profile = (try? BrowserToolConfig.normalizedProfile((try? args.decode(Args.self))?.profile)) ?? BrowserToolConfig.defaultProfile
        return BrowserToolConfig.executionTouchedPaths(profile: profile)
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        guard a.selector?.isEmpty == false || a.text?.isEmpty == false || (a.role?.isEmpty == false && a.name?.isEmpty == false) else {
            throw IntatisError.decoding("browser_click requires selector, text, or role+name")
        }
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let paths = try BrowserToolConfig.prepare(
            profile: profile,
            workspace: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        let limit = maxCharacters(a.maxCharacters)
        var payload: [String: Any] = [
            "action": "click",
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "headless": a.headless ?? true,
            "exact": a.exact ?? false,
            "nth": a.nth ?? 0,
            "waitMillis": a.waitMillis ?? 600,
            "maxCharacters": limit,
            "profileDir": paths.profileDir.path,
            "downloadsDir": paths.downloadsDir.path,
            "stateFile": paths.stateFile.path,
        ]
        if let selector = a.selector { payload["selector"] = selector }
        if let text = a.text { payload["text"] = text }
        if let role = a.role { payload["role"] = role }
        if let name = a.name { payload["name"] = name }
        return try await runPlaywright(arguments: payload, paths: paths, context: context, maxCharacters: limit)
    }
}

// MARK: - browser_type

public struct BrowserTypeTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_type",
        description: "Type or fill non-secret text into an element on the current live browser page; use browser_handoff for passwords, 2FA, tokens, or other credentials.",
        sideEffect: .exec,
        parameters: Schema.object([
            "value": Schema.nonEmptyString,
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "headless": Schema.boolean,
            "selector": Schema.nonEmptyString,
            "text": Schema.nonEmptyString,
            "role": Schema.nonEmptyString,
            "name": Schema.nonEmptyString,
            "clear": Schema.boolean,
            "submit": Schema.boolean,
            "nth": Schema.boundedInteger(minimum: 0, maximum: 100),
            "waitMillis": Schema.boundedInteger(minimum: 0, maximum: 10_000),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: ["value"])
    )

    struct Args: Decodable {
        let value: String
        let profile: String?
        let channel: String?
        let headless: Bool?
        let selector: String?
        let text: String?
        let role: String?
        let name: String?
        let clear: Bool?
        let submit: Bool?
        let nth: Int?
        let waitMillis: Int?
        let maxCharacters: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let profile = (try? BrowserToolConfig.normalizedProfile((try? args.decode(Args.self))?.profile)) ?? BrowserToolConfig.defaultProfile
        return BrowserToolConfig.executionTouchedPaths(profile: profile)
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        guard a.selector?.isEmpty == false || a.text?.isEmpty == false || (a.role?.isEmpty == false && a.name?.isEmpty == false) else {
            throw IntatisError.decoding("browser_type requires selector, text, or role+name")
        }
        if let reason = browserSensitiveTypeTargetReason(selector: a.selector, text: a.text, role: a.role, name: a.name) {
            throw IntatisError.config("browser_type refuses likely sensitive credential entry target (\(reason)); use browser_handoff for login, password, 2FA, token, or API key entry")
        }
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let paths = try BrowserToolConfig.prepare(
            profile: profile,
            workspace: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        let limit = maxCharacters(a.maxCharacters)
        var payload: [String: Any] = [
            "action": "type",
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "headless": a.headless ?? true,
            "value": a.value,
            "clear": a.clear ?? true,
            "submit": a.submit ?? false,
            "nth": a.nth ?? 0,
            "waitMillis": a.waitMillis ?? 600,
            "maxCharacters": limit,
            "profileDir": paths.profileDir.path,
            "downloadsDir": paths.downloadsDir.path,
            "stateFile": paths.stateFile.path,
        ]
        if let selector = a.selector { payload["selector"] = selector }
        if let text = a.text { payload["text"] = text }
        if let role = a.role { payload["role"] = role }
        if let name = a.name { payload["name"] = name }
        return try await runPlaywright(arguments: payload, paths: paths, context: context, maxCharacters: limit, redactions: [a.value])
    }
}

// MARK: - browser_submit

public struct BrowserSubmitTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_submit",
        description: "Submit the current form in the persistent browser profile, optionally targeting a form control or submit button first.",
        sideEffect: .exec,
        parameters: Schema.object([
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "headless": Schema.boolean,
            "selector": Schema.nonEmptyString,
            "text": Schema.nonEmptyString,
            "role": Schema.nonEmptyString,
            "name": Schema.nonEmptyString,
            "exact": Schema.boolean,
            "nth": Schema.boundedInteger(minimum: 0, maximum: 100),
            "timeoutMillis": Schema.boundedInteger(minimum: 1000, maximum: 30_000),
            "waitMillis": Schema.boundedInteger(minimum: 0, maximum: 10_000),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: [])
    )

    struct Args: Decodable {
        let profile: String?
        let channel: String?
        let headless: Bool?
        let selector: String?
        let text: String?
        let role: String?
        let name: String?
        let exact: Bool?
        let nth: Int?
        let timeoutMillis: Int?
        let waitMillis: Int?
        let maxCharacters: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let profile = (try? BrowserToolConfig.normalizedProfile((try? args.decode(Args.self))?.profile)) ?? BrowserToolConfig.defaultProfile
        return BrowserToolConfig.executionTouchedPaths(profile: profile)
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let paths = try BrowserToolConfig.prepare(
            profile: profile,
            workspace: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        let limit = maxCharacters(a.maxCharacters)
        var payload: [String: Any] = [
            "action": "submit",
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "headless": a.headless ?? true,
            "exact": a.exact ?? false,
            "nth": a.nth ?? 0,
            "timeoutMillis": min(max(a.timeoutMillis ?? 5000, 1000), 30_000),
            "waitMillis": a.waitMillis ?? 600,
            "maxCharacters": limit,
            "profileDir": paths.profileDir.path,
            "downloadsDir": paths.downloadsDir.path,
            "stateFile": paths.stateFile.path,
        ]
        if let selector = a.selector { payload["selector"] = selector }
        if let text = a.text { payload["text"] = text }
        if let role = a.role { payload["role"] = role }
        if let name = a.name { payload["name"] = name }
        return try await runPlaywright(arguments: payload, paths: paths, context: context, maxCharacters: limit)
    }
}

// MARK: - browser_select_option

public struct BrowserSelectOptionTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_select_option",
        description: "Select an option from a select/dropdown control in the persistent browser profile by value, label, or index.",
        sideEffect: .exec,
        parameters: Schema.object([
            "optionValue": Schema.nonEmptyString,
            "optionLabel": Schema.nonEmptyString,
            "optionIndex": Schema.boundedInteger(minimum: 0, maximum: 500),
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "headless": Schema.boolean,
            "selector": Schema.nonEmptyString,
            "text": Schema.nonEmptyString,
            "role": Schema.nonEmptyString,
            "name": Schema.nonEmptyString,
            "exact": Schema.boolean,
            "nth": Schema.boundedInteger(minimum: 0, maximum: 100),
            "waitMillis": Schema.boundedInteger(minimum: 0, maximum: 10_000),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: [])
    )

    struct Args: Decodable {
        let optionValue: String?
        let optionLabel: String?
        let optionIndex: Int?
        let profile: String?
        let channel: String?
        let headless: Bool?
        let selector: String?
        let text: String?
        let role: String?
        let name: String?
        let exact: Bool?
        let nth: Int?
        let waitMillis: Int?
        let maxCharacters: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let profile = (try? BrowserToolConfig.normalizedProfile((try? args.decode(Args.self))?.profile)) ?? BrowserToolConfig.defaultProfile
        return BrowserToolConfig.executionTouchedPaths(profile: profile)
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        guard a.selector?.isEmpty == false || a.text?.isEmpty == false || (a.role?.isEmpty == false && a.name?.isEmpty == false) else {
            throw IntatisError.decoding("browser_select_option requires selector, text, or role+name")
        }
        let optionValue = a.optionValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let optionLabel = a.optionLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let optionIndex = a.optionIndex, optionIndex < 0 || optionIndex > 500 {
            throw IntatisError.decoding("browser_select_option optionIndex must be between 0 and 500")
        }
        guard optionValue?.isEmpty == false || optionLabel?.isEmpty == false || a.optionIndex != nil else {
            throw IntatisError.decoding("browser_select_option requires optionValue, optionLabel, or optionIndex")
        }
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let paths = try BrowserToolConfig.prepare(
            profile: profile,
            workspace: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        let limit = maxCharacters(a.maxCharacters)
        var payload: [String: Any] = [
            "action": "select",
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "headless": a.headless ?? true,
            "exact": a.exact ?? false,
            "nth": a.nth ?? 0,
            "waitMillis": a.waitMillis ?? 600,
            "maxCharacters": limit,
            "profileDir": paths.profileDir.path,
            "downloadsDir": paths.downloadsDir.path,
            "stateFile": paths.stateFile.path,
        ]
        if let optionValue, !optionValue.isEmpty { payload["optionValue"] = optionValue }
        if let optionLabel, !optionLabel.isEmpty { payload["optionLabel"] = optionLabel }
        if let optionIndex = a.optionIndex { payload["optionIndex"] = optionIndex }
        if let selector = a.selector { payload["selector"] = selector }
        if let text = a.text { payload["text"] = text }
        if let role = a.role { payload["role"] = role }
        if let name = a.name { payload["name"] = name }
        return try await runPlaywright(arguments: payload, paths: paths, context: context, maxCharacters: limit)
    }
}

// MARK: - browser_press_key

public struct BrowserPressKeyTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_press_key",
        description: "Press a key or shortcut in the persistent browser profile, optionally targeting an element first.",
        sideEffect: .exec,
        parameters: Schema.object([
            "key": Schema.nonEmptyString,
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "headless": Schema.boolean,
            "selector": Schema.nonEmptyString,
            "text": Schema.nonEmptyString,
            "role": Schema.nonEmptyString,
            "name": Schema.nonEmptyString,
            "exact": Schema.boolean,
            "nth": Schema.boundedInteger(minimum: 0, maximum: 100),
            "waitMillis": Schema.boundedInteger(minimum: 0, maximum: 10_000),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: ["key"])
    )

    struct Args: Decodable {
        let key: String
        let profile: String?
        let channel: String?
        let headless: Bool?
        let selector: String?
        let text: String?
        let role: String?
        let name: String?
        let exact: Bool?
        let nth: Int?
        let waitMillis: Int?
        let maxCharacters: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let profile = (try? BrowserToolConfig.normalizedProfile((try? args.decode(Args.self))?.profile)) ?? BrowserToolConfig.defaultProfile
        return BrowserToolConfig.executionTouchedPaths(profile: profile)
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let key = try normalizedBrowserKey(a.key)
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let paths = try BrowserToolConfig.prepare(
            profile: profile,
            workspace: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        let limit = maxCharacters(a.maxCharacters)
        var payload: [String: Any] = [
            "action": "press",
            "key": key,
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "headless": a.headless ?? true,
            "exact": a.exact ?? false,
            "nth": a.nth ?? 0,
            "waitMillis": a.waitMillis ?? 600,
            "maxCharacters": limit,
            "profileDir": paths.profileDir.path,
            "downloadsDir": paths.downloadsDir.path,
            "stateFile": paths.stateFile.path,
        ]
        if let selector = a.selector { payload["selector"] = selector }
        if let text = a.text { payload["text"] = text }
        if let role = a.role { payload["role"] = role }
        if let name = a.name { payload["name"] = name }
        return try await runPlaywright(arguments: payload, paths: paths, context: context, maxCharacters: limit)
    }
}

// MARK: - browser_scroll

public struct BrowserScrollTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_scroll",
        description: "Scroll the current persistent browser page or a targeted element by direction/amount or explicit pixel deltas.",
        sideEffect: .exec,
        parameters: Schema.object([
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "headless": Schema.boolean,
            "selector": Schema.nonEmptyString,
            "text": Schema.nonEmptyString,
            "role": Schema.nonEmptyString,
            "name": Schema.nonEmptyString,
            "exact": Schema.boolean,
            "nth": Schema.boundedInteger(minimum: 0, maximum: 100),
            "direction": Schema.nonEmptyString,
            "amount": Schema.boundedInteger(minimum: 1, maximum: 10_000),
            "deltaX": Schema.boundedInteger(minimum: -10_000, maximum: 10_000),
            "deltaY": Schema.boundedInteger(minimum: -10_000, maximum: 10_000),
            "waitMillis": Schema.boundedInteger(minimum: 0, maximum: 10_000),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: [])
    )

    struct Args: Decodable {
        let profile: String?
        let channel: String?
        let headless: Bool?
        let selector: String?
        let text: String?
        let role: String?
        let name: String?
        let exact: Bool?
        let nth: Int?
        let direction: String?
        let amount: Int?
        let deltaX: Int?
        let deltaY: Int?
        let waitMillis: Int?
        let maxCharacters: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let profile = (try? BrowserToolConfig.normalizedProfile((try? args.decode(Args.self))?.profile)) ?? BrowserToolConfig.defaultProfile
        return BrowserToolConfig.executionTouchedPaths(profile: profile)
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let delta = try browserScrollDelta(direction: a.direction, amount: a.amount, deltaX: a.deltaX, deltaY: a.deltaY)
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let paths = try BrowserToolConfig.prepare(
            profile: profile,
            workspace: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        let limit = maxCharacters(a.maxCharacters)
        var payload: [String: Any] = [
            "action": "scroll",
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "headless": a.headless ?? true,
            "deltaX": delta.x,
            "deltaY": delta.y,
            "exact": a.exact ?? false,
            "nth": a.nth ?? 0,
            "waitMillis": a.waitMillis ?? 600,
            "maxCharacters": limit,
            "profileDir": paths.profileDir.path,
            "downloadsDir": paths.downloadsDir.path,
            "stateFile": paths.stateFile.path,
        ]
        if let selector = a.selector { payload["selector"] = selector }
        if let text = a.text { payload["text"] = text }
        if let role = a.role { payload["role"] = role }
        if let name = a.name { payload["name"] = name }
        return try await runPlaywright(arguments: payload, paths: paths, context: context, maxCharacters: limit)
    }
}

// MARK: - browser_wait

public struct BrowserWaitTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_wait",
        description: "Wait in the persistent browser profile for text or an element state, or pause briefly for dynamic page updates.",
        sideEffect: .exec,
        parameters: Schema.object([
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "headless": Schema.boolean,
            "selector": Schema.nonEmptyString,
            "text": Schema.nonEmptyString,
            "role": Schema.nonEmptyString,
            "name": Schema.nonEmptyString,
            "exact": Schema.boolean,
            "nth": Schema.boundedInteger(minimum: 0, maximum: 100),
            "state": Schema.nonEmptyString,
            "timeoutMillis": Schema.boundedInteger(minimum: 1000, maximum: 30_000),
            "waitMillis": Schema.boundedInteger(minimum: 0, maximum: 10_000),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: [])
    )

    struct Args: Decodable {
        let profile: String?
        let channel: String?
        let headless: Bool?
        let selector: String?
        let text: String?
        let role: String?
        let name: String?
        let exact: Bool?
        let nth: Int?
        let state: String?
        let timeoutMillis: Int?
        let waitMillis: Int?
        let maxCharacters: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let profile = (try? BrowserToolConfig.normalizedProfile((try? args.decode(Args.self))?.profile)) ?? BrowserToolConfig.defaultProfile
        return BrowserToolConfig.executionTouchedPaths(profile: profile)
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let paths = try BrowserToolConfig.prepare(
            profile: profile,
            workspace: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        let limit = maxCharacters(a.maxCharacters)
        var payload: [String: Any] = [
            "action": "wait",
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "headless": a.headless ?? true,
            "state": normalizedBrowserWaitState(a.state),
            "timeoutMillis": min(max(a.timeoutMillis ?? 10_000, 1000), 30_000),
            "exact": a.exact ?? false,
            "nth": a.nth ?? 0,
            "waitMillis": a.waitMillis ?? 100,
            "maxCharacters": limit,
            "profileDir": paths.profileDir.path,
            "downloadsDir": paths.downloadsDir.path,
            "stateFile": paths.stateFile.path,
        ]
        if let selector = a.selector { payload["selector"] = selector }
        if let text = a.text { payload["text"] = text }
        if let role = a.role { payload["role"] = role }
        if let name = a.name { payload["name"] = name }
        return try await runPlaywright(arguments: payload, paths: paths, context: context, maxCharacters: limit)
    }
}

// MARK: - browser_screenshot

public struct BrowserScreenshotTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_screenshot",
        description: "Capture a PNG screenshot of the current or requested page in a persistent Chromium/Chrome/Edge browser profile.",
        sideEffect: .exec,
        parameters: Schema.object([
            "outputPath": Schema.nonEmptyString,
            "url": Schema.nonEmptyString,
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "headless": Schema.boolean,
            "fullPage": Schema.boolean,
            "waitMillis": Schema.boundedInteger(minimum: 0, maximum: 10_000),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: ["outputPath"])
    )

    struct Args: Decodable {
        let outputPath: String
        let url: String?
        let profile: String?
        let channel: String?
        let headless: Bool?
        let fullPage: Bool?
        let waitMillis: Int?
        let maxCharacters: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let decoded = try? args.decode(Args.self)
        let profile = (try? BrowserToolConfig.normalizedProfile(decoded?.profile)) ?? BrowserToolConfig.defaultProfile
        var paths = BrowserToolConfig.executionTouchedPaths(profile: profile)
        if let outputPath = decoded?.outputPath {
            paths.append(outputPath)
        }
        return paths
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        if let url = a.url {
            _ = try BrowserToolConfig.validatedHTTPURL(url)
        }
        let outputURL = try PathConfinement.resolve(a.outputPath, within: context.workspaceRoot)
        guard outputURL.pathExtension.lowercased() == "png" else {
            throw IntatisError.decoding("browser_screenshot outputPath must end with .png")
        }
        _ = try validateBrowserWorkspaceAccess(
            readablePaths: [],
            writablePaths: [outputURL.path],
            cwd: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        let relativeOutputPath = PathConfinement.relativePath(of: outputURL, root: context.workspaceRoot)
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let paths = try BrowserToolConfig.prepare(
            profile: profile,
            workspace: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        let limit = maxCharacters(a.maxCharacters)
        var payload: [String: Any] = [
            "action": "screenshot",
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "headless": a.headless ?? true,
            "fullPage": a.fullPage ?? true,
            "waitMillis": a.waitMillis ?? 600,
            "maxCharacters": limit,
            "profileDir": paths.profileDir.path,
            "downloadsDir": paths.downloadsDir.path,
            "stateFile": paths.stateFile.path,
            "outputPath": outputURL.path,
            "relativeOutputPath": relativeOutputPath,
        ]
        if let url = a.url {
            payload["url"] = url
        }
        return try await runPlaywright(arguments: payload,
                                       paths: paths,
                                       context: context,
                                       maxCharacters: limit,
                                       changedFiles: [relativeOutputPath])
    }
}

// MARK: - browser_upload_file

public struct BrowserUploadFileTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_upload_file",
        description: "Attach a workspace file to a file input in the persistent Chromium/Chrome/Edge browser profile.",
        sideEffect: .exec,
        parameters: Schema.object([
            "filePath": Schema.nonEmptyString,
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "headless": Schema.boolean,
            "selector": Schema.nonEmptyString,
            "text": Schema.nonEmptyString,
            "role": Schema.nonEmptyString,
            "name": Schema.nonEmptyString,
            "exact": Schema.boolean,
            "nth": Schema.boundedInteger(minimum: 0, maximum: 100),
            "waitMillis": Schema.boundedInteger(minimum: 0, maximum: 10_000),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: ["filePath"])
    )

    struct Args: Decodable {
        let filePath: String
        let profile: String?
        let channel: String?
        let headless: Bool?
        let selector: String?
        let text: String?
        let role: String?
        let name: String?
        let exact: Bool?
        let nth: Int?
        let waitMillis: Int?
        let maxCharacters: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let decoded = try? args.decode(Args.self)
        let profile = (try? BrowserToolConfig.normalizedProfile(decoded?.profile)) ?? BrowserToolConfig.defaultProfile
        var paths = BrowserToolConfig.executionTouchedPaths(profile: profile)
        if let filePath = decoded?.filePath {
            paths.append(filePath)
        }
        return paths
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        guard a.selector?.isEmpty == false || a.text?.isEmpty == false || (a.role?.isEmpty == false && a.name?.isEmpty == false) else {
            throw IntatisError.decoding("browser_upload_file requires selector, text, or role+name")
        }
        let fileURL = try PathConfinement.resolve(a.filePath, within: context.workspaceRoot)
        _ = try validateBrowserWorkspaceAccess(
            readablePaths: [fileURL.path],
            writablePaths: [],
            cwd: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw IntatisError.notFound("upload file not found: \(a.filePath)")
        }
        let relativeFilePath = PathConfinement.relativePath(of: fileURL, root: context.workspaceRoot)
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let paths = try BrowserToolConfig.prepare(
            profile: profile,
            workspace: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        let limit = maxCharacters(a.maxCharacters)
        var payload: [String: Any] = [
            "action": "upload",
            "filePath": fileURL.path,
            "relativeFilePath": relativeFilePath,
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "headless": a.headless ?? true,
            "exact": a.exact ?? false,
            "nth": a.nth ?? 0,
            "waitMillis": a.waitMillis ?? 600,
            "maxCharacters": limit,
            "profileDir": paths.profileDir.path,
            "downloadsDir": paths.downloadsDir.path,
            "stateFile": paths.stateFile.path,
        ]
        if let selector = a.selector { payload["selector"] = selector }
        if let text = a.text { payload["text"] = text }
        if let role = a.role { payload["role"] = role }
        if let name = a.name { payload["name"] = name }
        return try await runPlaywright(arguments: payload, paths: paths, context: context, maxCharacters: limit)
    }
}

// MARK: - browser_download

public struct BrowserDownloadTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_download",
        description: "Click an element on the current live browser page, wait for its download to finish, and save it under the persistent profile downloads directory.",
        sideEffect: .exec,
        parameters: Schema.object([
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "headless": Schema.boolean,
            "selector": Schema.nonEmptyString,
            "text": Schema.nonEmptyString,
            "role": Schema.nonEmptyString,
            "name": Schema.nonEmptyString,
            "exact": Schema.boolean,
            "nth": Schema.boundedInteger(minimum: 0, maximum: 100),
            "waitMillis": Schema.boundedInteger(minimum: 0, maximum: 10_000),
            "downloadTimeoutMillis": Schema.boundedInteger(minimum: 1000, maximum: 60_000),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: [])
    )

    struct Args: Decodable {
        let profile: String?
        let channel: String?
        let headless: Bool?
        let selector: String?
        let text: String?
        let role: String?
        let name: String?
        let exact: Bool?
        let nth: Int?
        let waitMillis: Int?
        let downloadTimeoutMillis: Int?
        let maxCharacters: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let profile = (try? BrowserToolConfig.normalizedProfile((try? args.decode(Args.self))?.profile)) ?? BrowserToolConfig.defaultProfile
        return BrowserToolConfig.executionTouchedPaths(profile: profile)
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        guard a.selector?.isEmpty == false || a.text?.isEmpty == false || (a.role?.isEmpty == false && a.name?.isEmpty == false) else {
            throw IntatisError.decoding("browser_download requires selector, text, or role+name")
        }
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let paths = try BrowserToolConfig.prepare(
            profile: profile,
            workspace: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        let limit = maxCharacters(a.maxCharacters)
        var payload: [String: Any] = [
            "action": "download",
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "headless": a.headless ?? true,
            "exact": a.exact ?? false,
            "nth": a.nth ?? 0,
            "waitMillis": a.waitMillis ?? 600,
            "downloadTimeoutMillis": a.downloadTimeoutMillis ?? 15_000,
            "maxCharacters": limit,
            "profileDir": paths.profileDir.path,
            "downloadsDir": paths.downloadsDir.path,
            "downloadsRelativeDir": ".intatis/browser/downloads/\(profile)",
            "stateFile": paths.stateFile.path,
        ]
        if let selector = a.selector { payload["selector"] = selector }
        if let text = a.text { payload["text"] = text }
        if let role = a.role { payload["role"] = role }
        if let name = a.name { payload["name"] = name }
        return try await runPlaywright(arguments: payload, paths: paths, context: context, maxCharacters: limit)
    }
}

// MARK: - browser_downloads

public struct BrowserDownloadsTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_downloads",
        description: "List downloaded file metadata for a persistent browser profile without reading file contents.",
        sideEffect: .readOnly,
        parameters: Schema.object([
            "profile": Schema.nonEmptyString,
            "limit": Schema.boundedInteger(minimum: 1, maximum: 100),
        ], required: [])
    )

    struct Args: Decodable {
        let profile: String?
        let limit: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let profile = (try? BrowserToolConfig.normalizedProfile((try? args.decode(Args.self))?.profile)) ?? BrowserToolConfig.defaultProfile
        return [".intatis/browser/downloads/\(profile)"]
    }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let limit = min(max(a.limit ?? 20, 1), 100)
        let files = try browserDownloadFiles(profile: profile, workspace: context.workspaceRoot, limit: limit)
        return ToolObservation(text: browserDownloadsOutput(files, profile: profile, limit: limit))
    }
}

// MARK: - browser_search

public struct BrowserSearchTool: BrowserPermissionPreviewingTool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "browser_search",
        description: "Search the web in a persistent Chromium/Chrome/Edge browser profile and return visible result text and links.",
        sideEffect: .exec,
        parameters: Schema.object([
            "query": Schema.nonEmptyString,
            "engine": Schema.nonEmptyString,
            "profile": Schema.nonEmptyString,
            "channel": Schema.nonEmptyString,
            "headless": Schema.boolean,
            "waitMillis": Schema.boundedInteger(minimum: 0, maximum: 10_000),
            "maxCharacters": Schema.boundedInteger(minimum: 1, maximum: BrowserToolConfig.maxSnapshotCharacters),
        ], required: ["query"])
    )

    struct Args: Decodable {
        let query: String
        let engine: String?
        let profile: String?
        let channel: String?
        let headless: Bool?
        let waitMillis: Int?
        let maxCharacters: Int?
    }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let profile = (try? BrowserToolConfig.normalizedProfile((try? args.decode(Args.self))?.profile)) ?? BrowserToolConfig.defaultProfile
        return BrowserToolConfig.executionTouchedPaths(profile: profile)
    }

    public func risksNetwork(_ args: ToolArgs) -> Bool { true }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let profile = try BrowserToolConfig.normalizedProfile(a.profile)
        let paths = try BrowserToolConfig.prepare(
            profile: profile,
            workspace: context.workspaceRoot,
            workspaceLease: context.workspaceLease)
        let limit = maxCharacters(a.maxCharacters)
        let engine = (a.engine ?? "duckduckgo").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var payload: [String: Any] = [
            "action": "search",
            "query": a.query,
            "engine": ["duckduckgo", "google", "bing"].contains(engine) ? engine : "duckduckgo",
            "profile": profile,
            "channel": BrowserToolConfig.normalizedChannel(a.channel),
            "headless": a.headless ?? true,
            "waitMillis": a.waitMillis ?? 600,
            "maxCharacters": limit,
            "profileDir": paths.profileDir.path,
            "downloadsDir": paths.downloadsDir.path,
            "stateFile": paths.stateFile.path,
        ]
        if let headless = a.headless { payload["headless"] = headless }
        return try await runPlaywright(arguments: payload, paths: paths, context: context, maxCharacters: limit)
    }
}
