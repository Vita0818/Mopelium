import Foundation

// MARK: - Shell

/// Runs a command via `/bin/sh -c` in a working directory. Used by the
/// Developer-ID build; in the sandboxed App Store build `run_shell` is denied by
/// the permission gate before reaching here (ARCHITECTURE.md §9.1).
public struct ProcessShellRunner: ShellRunner {
    public init() {}

    public func run(_ command: String, cwd: URL) async throws -> ShellResult {
        #if os(macOS) || os(Linux)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = cwd
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        // Read to EOF before waiting to avoid pipe-buffer deadlock on moderate output.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ShellResult(stdout: String(decoding: outData, as: UTF8.self),
                           stderr: String(decoding: errData, as: UTF8.self),
                           exitCode: Int(process.terminationStatus))
        #else
        throw MopeliumToolError.io("shell execution is unavailable on this platform")
        #endif
    }
}

public struct RunShellTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "run_shell",
        description: "Run a shell command in the workspace directory.",
        sideEffect: .exec,
        parameters: Schema.object(["command": Schema.nonEmptyString], required: ["command"])
    )
    struct Args: Decodable { let command: String }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let result = try await context.shell.run(a.command, cwd: context.workspaceRoot)
        var out = result.stdout
        if !result.stderr.isEmpty { out += (out.isEmpty ? "" : "\n") + "[stderr]\n" + result.stderr }
        out += "\n[exit \(result.exitCode)]"
        return ToolObservation(text: out)
    }
}

// MARK: - Git

public enum GitStatus {
    public struct Entry: Equatable, Sendable {
        public let x: Character   // index status
        public let y: Character   // worktree status
        public let path: String
        public init(x: Character, y: Character, path: String) {
            self.x = x; self.y = y; self.path = path
        }
    }

    /// Parse `git status --porcelain=v1` output (`XY <path>` per line).
    public static func parse(_ porcelain: String) -> [Entry] {
        porcelain.split(separator: "\n", omittingEmptySubsequences: true).compactMap { sub in
            let line = String(sub)
            guard line.count >= 4 else { return nil }
            let chars = Array(line)
            return Entry(x: chars[0], y: chars[1], path: String(line.dropFirst(3)))
        }
    }
}

/// Spawns `git` directly with argument arrays. A future sandbox build can
/// replace this with a libgit2-backed `GitService` implementation.
private final class GitProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) {
        self.process = process
    }
}

private final class GitProcessTimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var timedOut = false

    func expire(_ box: GitProcessBox) {
        lock.lock()
        let shouldTerminate = !finished
        if shouldTerminate { timedOut = true }
        lock.unlock()
        if shouldTerminate, box.process.isRunning {
            box.process.terminate()
        }
    }

    func finish() {
        lock.lock()
        finished = true
        lock.unlock()
    }

    var didTimeOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }
}

public struct ProcessGitService: GitService {
    public init(runner _: ShellRunner = ProcessShellRunner()) {}

    public func status(workspace: URL) async throws -> String {
        try await runGit(["status", "--porcelain=v1"], workspace: workspace).stdout
    }

    public func diff(workspace: URL) async throws -> String {
        try await runGit(["diff"], workspace: workspace).stdout
    }

    public func stagedDiff(workspace: URL) async throws -> String {
        try await runGit(["diff", "--staged"], workspace: workspace).stdout
    }

    public func repositoryInfo(workspace: URL) async throws -> String {
        let root = try await runGit(["rev-parse", "--show-toplevel"], workspace: workspace).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = try await runGit(["branch", "--show-current"], workspace: workspace).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let head = await optionalGitOutput(["rev-parse", "--short=12", "HEAD"], workspace: workspace) ?? "(unborn)"
        let defaultBranch = await defaultBranch(workspace: workspace)
        let remotes = await optionalGitOutput(["remote", "-v"], workspace: workspace) ?? ""
        let statusText = try await status(workspace: workspace)
        let hasChanges = GitStatus.parse(statusText).isEmpty ? "false" : "true"
        return [
            "root: \(root)",
            "branch: \(branch.isEmpty ? "(detached HEAD)" : branch)",
            "head: \(head)",
            "defaultBranch: \(defaultBranch ?? "(unknown)")",
            "hasChanges: \(hasChanges)",
            "remotes:",
            remotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(none)" : remotes.trimmingCharacters(in: .whitespacesAndNewlines),
        ].joined(separator: "\n")
    }

    public func recentCommits(limit: Int, workspace: URL) async throws -> String {
        let bounded = max(1, min(limit, 50))
        let result = try await runGit([
            "log",
            "-n", "\(bounded)",
            "--pretty=format:%h%x09%an%x09%ad%x09%s",
            "--date=short",
        ], workspace: workspace, checked: false)
        if result.exitCode != 0 {
            return "(no commits)"
        }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "(no commits)" : text
    }

    public func diffAgainst(base: String, workspace: URL) async throws -> String {
        try await runGit(["diff", base, "--"], workspace: workspace).stdout
    }

    public func branchInfo(workspace: URL) async throws -> String {
        let current = try await runGit(["branch", "--show-current"], workspace: workspace).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let branches = try await runGit(["branch", "--list"], workspace: workspace).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentText = current.isEmpty ? "(detached HEAD)" : current
        return "current: \(currentText)\nbranches:\n\(branches.isEmpty ? "(none)" : branches)"
    }

    public func createBranch(name: String, startPoint: String?, workspace: URL) async throws -> String {
        var args = ["branch", name]
        if let startPoint, !startPoint.isEmpty {
            args.append(startPoint)
        }
        let result = try await runGit(args, workspace: workspace)
        return summarize(result, fallback: "created branch \(name)")
    }

    public func stage(paths: [String], workspace: URL) async throws -> String {
        let result = try await runGit(["add", "--"] + paths, workspace: workspace)
        return summarize(result, fallback: "staged \(paths.count) path(s)")
    }

    public func unstage(paths: [String], workspace: URL) async throws -> String {
        let result = try await runGit(["restore", "--staged", "--"] + paths, workspace: workspace)
        return summarize(result, fallback: "unstaged \(paths.count) path(s)")
    }

    public func commit(message: String, workspace: URL) async throws -> String {
        let result = try await runGit(["commit", "--no-gpg-sign", "-m", message], workspace: workspace)
        return summarize(result, fallback: "commit created")
    }

    public func applyPatch(diff: String,
                           reverse: Bool,
                           checkOnly: Bool,
                           cached: Bool,
                           workspace: URL) async throws -> GitPatchResult {
        let changedFiles = try GitToolInput.normalizedPatchPaths(diff, workspace: workspace)
        let patchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mopelium-git-\(UUID().uuidString).patch")
        try diff.write(to: patchURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: patchURL) }

        var args = ["apply"]
        if cached { args.append("--cached") }
        if reverse { args.append("-R") }
        if checkOnly {
            args.append("--check")
        } else if !cached && !reverse {
            args.append("--3way")
        }
        args.append(patchURL.path)
        let result = try await runGit(args, workspace: workspace)
        let action: String
        if checkOnly {
            action = "patch applies cleanly"
        } else if cached && reverse {
            action = "unstaged patch"
        } else if cached {
            action = "staged patch"
        } else if reverse {
            action = "reverted patch"
        } else {
            action = "applied patch"
        }
        return GitPatchResult(
            text: summarize(result, fallback: "\(action) touching \(changedFiles.count) path(s)"),
            changedFiles: changedFiles,
            diff: diff)
    }

    public func worktrees(workspace: URL) async throws -> String {
        let result = try await runGit(["worktree", "list", "--porcelain"], workspace: workspace)
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "(no worktrees)" : text
    }

    public func createWorktree(name: String, startPoint: String?, branch: String?, workspace: URL) async throws -> String {
        let safeName = try GitToolInput.worktreeName(name)
        let directory = workspace
            .appendingPathComponent(".mopelium", isDirectory: true)
            .appendingPathComponent("git-worktrees", isDirectory: true)
            .appendingPathComponent(safeName, isDirectory: true)
        let parent = directory.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        var args = ["worktree", "add"]
        if let branch, !branch.isEmpty {
            args.append(contentsOf: ["-b", branch])
        } else {
            args.append("--detach")
        }
        args.append(directory.path)
        if let startPoint, !startPoint.isEmpty {
            args.append(startPoint)
        }
        let result = try await runGit(args, workspace: workspace)
        return summarize(result, fallback: "created worktree \(safeName)")
    }

    public func removeWorktree(name: String, force: Bool, workspace: URL) async throws -> String {
        let safeName = try GitToolInput.worktreeName(name)
        let directory = workspace
            .appendingPathComponent(".mopelium", isDirectory: true)
            .appendingPathComponent("git-worktrees", isDirectory: true)
            .appendingPathComponent(safeName, isDirectory: true)
        var args = ["worktree", "remove"]
        if force { args.append("--force") }
        args.append(directory.path)
        let result = try await runGit(args, workspace: workspace)
        return summarize(result, fallback: "removed worktree \(safeName)")
    }

    private func runGit(_ args: [String], workspace: URL, checked: Bool = true) async throws -> ShellResult {
        try await validateRepository(workspace: workspace)
        return try await runRawGit(gitConfigArgs() + args, workspace: workspace, checked: checked)
    }

    private func validateRepository(workspace: URL) async throws {
        let workspaceURL = workspace.resolvingSymlinksInPath().standardizedFileURL
        let workspacePath = workspaceURL.path
        let root = try await runRawGit(["rev-parse", "--show-toplevel"], workspace: workspace, checked: true)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let repoRoot = URL(fileURLWithPath: root)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        guard repoRoot == workspacePath else {
            throw MopeliumToolError.permissionDenied("git repository root must match the agent workspace root")
        }

        let gitDirText = try await runRawGit(["rev-parse", "--git-dir"], workspace: workspace, checked: true)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let gitDirInput = gitDirText.hasPrefix("/")
            ? URL(fileURLWithPath: gitDirText)
            : workspaceURL.appendingPathComponent(gitDirText)
        let gitDir = gitDirInput.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = workspacePath.hasSuffix("/") ? workspacePath : workspacePath + "/"
        if gitDir == workspacePath || gitDir.hasPrefix(prefix) {
            return
        }

        let dotGit = workspaceURL.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw MopeliumToolError.permissionDenied("git metadata directory escapes the agent workspace")
        }

        let commonDirText = try await runRawGit(["rev-parse", "--git-common-dir"], workspace: workspace, checked: true)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let commonDirInput = commonDirText.hasPrefix("/")
            ? URL(fileURLWithPath: commonDirText)
            : workspaceURL.appendingPathComponent(commonDirText)
        let commonDir = commonDirInput.resolvingSymlinksInPath().standardizedFileURL.path
        let worktreePrefix = URL(fileURLWithPath: commonDir)
            .appendingPathComponent("worktrees", isDirectory: true)
            .path + "/"
        let ownerRoot = URL(fileURLWithPath: commonDir).deletingLastPathComponent().path
        let ownerPrefix = ownerRoot.hasSuffix("/") ? ownerRoot : ownerRoot + "/"
        guard gitDir.hasPrefix(worktreePrefix),
              workspacePath == ownerRoot || workspacePath.hasPrefix(ownerPrefix) else {
            throw MopeliumToolError.permissionDenied("git worktree metadata must stay under the owning workspace repository")
        }
    }

    private func gitConfigArgs() -> [String] {
        ["-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false"]
    }

    private func runRawGit(_ args: [String], workspace: URL, checked: Bool) async throws -> ShellResult {
        #if os(macOS) || os(Linux)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = workspace
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()
        let timeoutState = GitProcessTimeoutState()
        let processBox = GitProcessBox(process)
        let timeoutWorkItem = DispatchWorkItem {
            timeoutState.expire(processBox)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(15), execute: timeoutWorkItem)
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutState.finish()
        timeoutWorkItem.cancel()
        let result = ShellResult(stdout: String(decoding: outData, as: UTF8.self),
                                 stderr: String(decoding: errData, as: UTF8.self),
                                 exitCode: Int(process.terminationStatus))
        let command = args.first { !$0.hasPrefix("-") && !$0.contains("=") } ?? args.first ?? "command"
        if timeoutState.didTimeOut {
            throw MopeliumToolError.io("git \(command) timed out after 15s")
        }
        if checked, result.exitCode != 0 {
            let message = summarize(result, fallback: "exit \(result.exitCode)")
            let renderedArgs = args.joined(separator: " ")
            throw MopeliumToolError.io("git \(command) failed (\(renderedArgs)): \(message)")
        }
        return result
        #else
        throw MopeliumToolError.io("git execution is unavailable on this platform")
        #endif
    }

    private func optionalGitOutput(_ args: [String], workspace: URL) async -> String? {
        guard let result = try? await runGit(args, workspace: workspace, checked: false),
              result.exitCode == 0 else { return nil }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func defaultBranch(workspace: URL) async -> String? {
        if let remoteHead = await optionalGitOutput(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], workspace: workspace) {
            return remoteHead.replacingOccurrences(of: "origin/", with: "")
        }
        for candidate in ["main", "master", "trunk"] {
            if let output = await optionalGitOutput(["show-ref", "--verify", "--quiet", "refs/heads/\(candidate)"], workspace: workspace),
               output.isEmpty {
                return candidate
            }
        }
        let result = try? await runGit(["show-ref", "--verify", "--quiet", "refs/heads/main"], workspace: workspace, checked: false)
        if result?.exitCode == 0 { return "main" }
        let master = try? await runGit(["show-ref", "--verify", "--quiet", "refs/heads/master"], workspace: workspace, checked: false)
        if master?.exitCode == 0 { return "master" }
        return nil
    }

    private func summarize(_ result: ShellResult, fallback: String) -> String {
        let combined = [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return combined.isEmpty ? fallback : String(combined.prefix(12_000))
    }
}

private enum GitToolInput {
    static func normalizedPaths(_ paths: [String], workspace: URL) throws -> [String] {
        guard !paths.isEmpty else {
            throw MopeliumToolError.decoding("git paths must not be empty")
        }
        return try paths.map { rawPath in
            let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else {
                throw MopeliumToolError.decoding("git paths must not contain empty entries")
            }
            let url = try PathConfinement.resolve(path, within: workspace)
            return PathConfinement.relativePath(of: url, root: workspace)
        }
    }

    static func branchName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw MopeliumToolError.decoding("branch name must not be empty")
        }
        guard name.count <= 255 else {
            throw MopeliumToolError.decoding("branch name is too long")
        }
        let forbidden = ["..", "@{", "\\", "~", "^", ":", "?", "*", "[", "\n", "\r", "\t"]
        guard !forbidden.contains(where: { name.contains($0) }),
              !name.hasPrefix("-"),
              !name.hasPrefix("/"),
              !name.hasSuffix("/"),
              !name.hasSuffix("."),
              !name.contains("//"),
              name != "@" else {
            throw MopeliumToolError.decoding("branch name contains characters Git refs cannot safely use")
        }
        return name
    }

    static func optionalRef(_ raw: String?) throws -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard value.count <= 255,
              !value.hasPrefix("-"),
              !value.contains("\n"),
              !value.contains("\r"),
              !value.contains("\t") else {
            throw MopeliumToolError.decoding("git start point is not a safe ref")
        }
        return value
    }

    static func requiredRef(_ raw: String) throws -> String {
        guard let value = try optionalRef(raw) else {
            throw MopeliumToolError.decoding("git ref must not be empty")
        }
        return value
    }

    static func boundedLimit(_ raw: Int?) -> Int {
        max(1, min(raw ?? 10, 50))
    }

    static func worktreeName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw MopeliumToolError.decoding("worktree name must not be empty")
        }
        guard name.count <= 80 else {
            throw MopeliumToolError.decoding("worktree name is too long")
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              !name.hasPrefix("."),
              !name.hasPrefix("-"),
              !name.contains("..") else {
            throw MopeliumToolError.decoding("worktree name must be a simple safe directory name")
        }
        return name
    }

    static func normalizedPatchPaths(_ diff: String, workspace: URL) throws -> [String] {
        let rawPaths = try patchPaths(diff)
        return try normalizedPaths(rawPaths, workspace: workspace)
    }

    static func patchPathsForPermission(_ diff: String) -> [String] {
        (try? patchPaths(diff)) ?? ["."]
    }

    private static func patchPaths(_ diff: String) throws -> [String] {
        guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MopeliumToolError.decoding("git patch must not be empty")
        }
        var result: [String] = []
        var seen = Set<String>()

        func append(_ raw: String) {
            guard let path = normalizePatchPath(raw), !seen.contains(path) else { return }
            seen.insert(path)
            result.append(path)
        }

        for line in diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("+++ ") || line.hasPrefix("--- ") {
                append(String(line.dropFirst(4)))
            } else if line.hasPrefix("diff --git ") {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                if parts.count >= 4 {
                    append(parts[2])
                    append(parts[3])
                }
            }
        }

        guard !result.isEmpty else {
            throw MopeliumToolError.decoding("git patch does not expose any changed paths")
        }
        return result
    }

    private static func normalizePatchPath(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tab = value.firstIndex(of: "\t") {
            value = String(value[..<tab])
        }
        if value == "/dev/null" { return nil }
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            value.removeFirst()
            value.removeLast()
        }
        if value.hasPrefix("a/") || value.hasPrefix("b/") {
            value = String(value.dropFirst(2))
        }
        return value.isEmpty ? nil : value
    }
}

public struct GitStatusTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_status",
        description: "Show working-tree status (porcelain).",
        sideEffect: .readOnly,
        parameters: Schema.object([:], required: [])
    )

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let porcelain = try await context.git.status(workspace: context.workspaceRoot)
        let entries = GitStatus.parse(porcelain)
        if entries.isEmpty { return ToolObservation(text: "clean") }
        let lines = entries.map { "\($0.x)\($0.y) \($0.path)" }
        return ToolObservation(text: lines.joined(separator: "\n"))
    }
}

public struct GitDiffTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_diff",
        description: "Show unstaged changes as a unified diff.",
        sideEffect: .readOnly,
        parameters: Schema.object([:], required: [])
    )

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let diff = try await context.git.diff(workspace: context.workspaceRoot)
        let limit = 200_000
        let truncated = diff.utf8.count > limit
        let text = truncated ? String(diff.prefix(limit)) : diff
        return ToolObservation(text: text.isEmpty ? "(no changes)" : text, truncated: truncated, diff: diff)
    }
}

public struct GitStagedDiffTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_diff_staged",
        description: "Show staged changes as a unified diff.",
        sideEffect: .readOnly,
        parameters: Schema.object([:], required: [])
    )

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let diff = try await context.git.stagedDiff(workspace: context.workspaceRoot)
        let limit = 200_000
        let truncated = diff.utf8.count > limit
        let text = truncated ? String(diff.prefix(limit)) : diff
        return ToolObservation(text: text.isEmpty ? "(no staged changes)" : text, truncated: truncated, diff: diff)
    }
}

public struct GitInfoTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_info",
        description: "Show repository metadata: root, branch, HEAD, default branch, change state, and remotes.",
        sideEffect: .readOnly,
        parameters: Schema.object([:], required: [])
    )

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        ToolObservation(text: try await context.git.repositoryInfo(workspace: context.workspaceRoot))
    }
}

public struct GitRecentCommitsTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_recent_commits",
        description: "Show recent local commits as short hash, author, date, and subject.",
        sideEffect: .readOnly,
        parameters: Schema.object([
            "limit": Schema.boundedInteger(minimum: 1, maximum: 50),
        ], required: [])
    )

    struct Args: Decodable { let limit: Int? }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let limit = GitToolInput.boundedLimit(a.limit)
        return ToolObservation(text: try await context.git.recentCommits(limit: limit, workspace: context.workspaceRoot))
    }
}

public struct GitDiffBaseTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_diff_base",
        description: "Show the workspace diff against a safe Git base ref such as main or origin/main.",
        sideEffect: .readOnly,
        parameters: Schema.object([
            "base": Schema.boundedString(minLength: 1, maxLength: 255),
        ], required: ["base"])
    )

    struct Args: Decodable { let base: String }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let base = try GitToolInput.requiredRef(a.base)
        let diff = try await context.git.diffAgainst(base: base, workspace: context.workspaceRoot)
        let limit = 200_000
        let truncated = diff.utf8.count > limit
        let text = truncated ? String(diff.prefix(limit)) : diff
        return ToolObservation(text: text.isEmpty ? "(no changes against \(base))" : text,
                               truncated: truncated,
                               diff: diff)
    }
}

public struct GitBranchTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_branch",
        description: "Show current branch and local branches.",
        sideEffect: .readOnly,
        parameters: Schema.object([:], required: [])
    )

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        ToolObservation(text: try await context.git.branchInfo(workspace: context.workspaceRoot))
    }
}

public struct GitCreateBranchTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_create_branch",
        description: "Create a local branch without switching branches.",
        sideEffect: .write,
        parameters: Schema.object([
            "name": Schema.boundedString(minLength: 1, maxLength: 255),
            "startPoint": Schema.boundedString(minLength: 1, maxLength: 255),
        ], required: ["name"])
    )

    struct Args: Decodable { let name: String; let startPoint: String? }

    public func touchedPaths(_ args: ToolArgs) -> [String] { [".git"] }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let name = try GitToolInput.branchName(a.name)
        let startPoint = try GitToolInput.optionalRef(a.startPoint)
        let output = try await context.git.createBranch(name: name, startPoint: startPoint, workspace: context.workspaceRoot)
        return ToolObservation(text: output)
    }
}

public struct GitStageTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_stage",
        description: "Stage workspace-confined paths in the Git index.",
        sideEffect: .write,
        parameters: Schema.object([
            "paths": .object([
                "type": .string("array"),
                "items": Schema.nonEmptyString,
                "minItems": .number(1),
            ]),
        ], required: ["paths"])
    )

    struct Args: Decodable { let paths: [String] }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let decoded = try? args.decode(Args.self)
        return [".git/index"] + (decoded?.paths ?? [])
    }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let paths = try GitToolInput.normalizedPaths(a.paths, workspace: context.workspaceRoot)
        let output = try await context.git.stage(paths: paths, workspace: context.workspaceRoot)
        return ToolObservation(text: output, changedFiles: paths)
    }
}

public struct GitUnstageTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_unstage",
        description: "Remove workspace-confined paths from the Git index without changing working-tree files.",
        sideEffect: .write,
        parameters: Schema.object([
            "paths": .object([
                "type": .string("array"),
                "items": Schema.nonEmptyString,
                "minItems": .number(1),
            ]),
        ], required: ["paths"])
    )

    struct Args: Decodable { let paths: [String] }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let decoded = try? args.decode(Args.self)
        return [".git/index"] + (decoded?.paths ?? [])
    }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let paths = try GitToolInput.normalizedPaths(a.paths, workspace: context.workspaceRoot)
        let output = try await context.git.unstage(paths: paths, workspace: context.workspaceRoot)
        return ToolObservation(text: output, changedFiles: paths)
    }
}

public struct GitCommitTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_commit",
        description: "Create a local commit from the staged index. Hooks and GPG signing are disabled for agent safety.",
        sideEffect: .write,
        parameters: Schema.object([
            "message": Schema.boundedString(minLength: 1, maxLength: 4_000),
        ], required: ["message"])
    )

    struct Args: Decodable { let message: String }

    public func touchedPaths(_ args: ToolArgs) -> [String] { [".git"] }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let message = a.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            throw MopeliumToolError.decoding("commit message must not be empty")
        }
        let stagedEntries = GitStatus.parse(try await context.git.status(workspace: context.workspaceRoot))
            .filter { $0.x != " " && $0.x != "?" }
        if let sensitive = stagedEntries.first(where: { PathConfinement.isSensitivePath($0.path) }) {
            throw MopeliumToolError.permissionDenied("refusing to commit staged sensitive path: \(sensitive.path)")
        }
        let output = try await context.git.commit(message: message, workspace: context.workspaceRoot)
        return ToolObservation(text: output)
    }
}

public struct GitApplyPatchCheckTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_apply_patch_check",
        description: "Validate whether a unified diff can be applied by Git without changing the workspace.",
        sideEffect: .readOnly,
        parameters: Schema.object([
            "diff": Schema.boundedString(minLength: 1, maxLength: 500_000),
            "reverse": Schema.boolean,
        ], required: ["diff"])
    )

    struct Args: Decodable { let diff: String; let reverse: Bool? }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let decoded = try? args.decode(Args.self)
        return decoded.map { GitToolInput.patchPathsForPermission($0.diff) } ?? ["."]
    }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        _ = try GitToolInput.normalizedPatchPaths(a.diff, workspace: context.workspaceRoot)
        let result = try await context.git.applyPatch(diff: a.diff,
                                                       reverse: a.reverse ?? false,
                                                       checkOnly: true,
                                                       cached: false,
                                                       workspace: context.workspaceRoot)
        return ToolObservation(text: result.text)
    }
}

public struct GitApplyPatchTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_apply_patch",
        description: "Apply a unified diff to the working tree through git apply --3way.",
        sideEffect: .write,
        parameters: Schema.object([
            "diff": Schema.boundedString(minLength: 1, maxLength: 500_000),
        ], required: ["diff"])
    )

    struct Args: Decodable { let diff: String }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let decoded = try? args.decode(Args.self)
        return decoded.map { GitToolInput.patchPathsForPermission($0.diff) } ?? ["."]
    }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        _ = try GitToolInput.normalizedPatchPaths(a.diff, workspace: context.workspaceRoot)
        let result = try await context.git.applyPatch(diff: a.diff,
                                                       reverse: false,
                                                       checkOnly: false,
                                                       cached: false,
                                                       workspace: context.workspaceRoot)
        return ToolObservation(text: result.text, diff: result.diff, changedFiles: result.changedFiles)
    }
}

public struct GitStagePatchTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_stage_patch",
        description: "Stage a provided unified diff hunk in the Git index without changing working-tree files.",
        sideEffect: .write,
        parameters: Schema.object([
            "diff": Schema.boundedString(minLength: 1, maxLength: 500_000),
        ], required: ["diff"])
    )

    struct Args: Decodable { let diff: String }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let decoded = try? args.decode(Args.self)
        return [".git/index"] + (decoded.map { GitToolInput.patchPathsForPermission($0.diff) } ?? ["."])
    }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        _ = try GitToolInput.normalizedPatchPaths(a.diff, workspace: context.workspaceRoot)
        let result = try await context.git.applyPatch(diff: a.diff,
                                                       reverse: false,
                                                       checkOnly: false,
                                                       cached: true,
                                                       workspace: context.workspaceRoot)
        return ToolObservation(text: result.text, changedFiles: result.changedFiles)
    }
}

public struct GitUnstagePatchTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_unstage_patch",
        description: "Reverse a provided unified diff hunk out of the Git index without changing working-tree files.",
        sideEffect: .write,
        parameters: Schema.object([
            "diff": Schema.boundedString(minLength: 1, maxLength: 500_000),
        ], required: ["diff"])
    )

    struct Args: Decodable { let diff: String }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let decoded = try? args.decode(Args.self)
        return [".git/index"] + (decoded.map { GitToolInput.patchPathsForPermission($0.diff) } ?? ["."])
    }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        _ = try GitToolInput.normalizedPatchPaths(a.diff, workspace: context.workspaceRoot)
        let result = try await context.git.applyPatch(diff: a.diff,
                                                       reverse: true,
                                                       checkOnly: false,
                                                       cached: true,
                                                       workspace: context.workspaceRoot)
        return ToolObservation(text: result.text, changedFiles: result.changedFiles)
    }
}

public struct GitRevertPatchTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_revert_patch",
        description: "Destructively reverse a provided unified diff from the working tree through git apply -R --3way.",
        sideEffect: .destructive,
        parameters: Schema.object([
            "diff": Schema.boundedString(minLength: 1, maxLength: 500_000),
            "confirmRevert": Schema.boolean,
        ], required: ["diff", "confirmRevert"])
    )

    struct Args: Decodable { let diff: String; let confirmRevert: Bool }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let decoded = try? args.decode(Args.self)
        return decoded.map { GitToolInput.patchPathsForPermission($0.diff) } ?? ["."]
    }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        guard a.confirmRevert else {
            throw MopeliumToolError.permissionDenied("git_revert_patch requires confirmRevert=true")
        }
        _ = try GitToolInput.normalizedPatchPaths(a.diff, workspace: context.workspaceRoot)
        let result = try await context.git.applyPatch(diff: a.diff,
                                                       reverse: true,
                                                       checkOnly: false,
                                                       cached: false,
                                                       workspace: context.workspaceRoot)
        return ToolObservation(text: result.text, diff: result.diff, changedFiles: result.changedFiles)
    }
}

public struct GitWorktreeListTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_worktree_list",
        description: "List Git worktrees for the current repository.",
        sideEffect: .readOnly,
        parameters: Schema.object([:], required: [])
    )

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        ToolObservation(text: try await context.git.worktrees(workspace: context.workspaceRoot))
    }
}

public struct GitWorktreeCreateTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_worktree_create",
        description: "Create a workspace-contained managed Git worktree under .mopelium/git-worktrees. Defaults to detached HEAD.",
        sideEffect: .write,
        parameters: Schema.object([
            "name": Schema.boundedString(minLength: 1, maxLength: 80),
            "startPoint": Schema.boundedString(minLength: 1, maxLength: 255),
            "branch": Schema.boundedString(minLength: 1, maxLength: 255),
        ], required: ["name"])
    )

    struct Args: Decodable { let name: String; let startPoint: String?; let branch: String? }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let decoded = try? args.decode(Args.self)
        let name = (try? decoded.map { try GitToolInput.worktreeName($0.name) }) ?? "unknown"
        return [".git", ".mopelium/git-worktrees/\(name)"]
    }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let name = try GitToolInput.worktreeName(a.name)
        let startPoint = try GitToolInput.optionalRef(a.startPoint)
        let branch = try a.branch.map { try GitToolInput.branchName($0) }
        let output = try await context.git.createWorktree(name: name,
                                                          startPoint: startPoint,
                                                          branch: branch,
                                                          workspace: context.workspaceRoot)
        return ToolObservation(text: output, changedFiles: [".mopelium/git-worktrees/\(name)"])
    }
}

public struct GitWorktreeRemoveTool: Tool {
    public init() {}
    public static let descriptor = ToolDescriptor(
        name: "git_worktree_remove",
        description: "Destructively remove a managed worktree under .mopelium/git-worktrees after exact name confirmation.",
        sideEffect: .destructive,
        parameters: Schema.object([
            "name": Schema.boundedString(minLength: 1, maxLength: 80),
            "confirmName": Schema.boundedString(minLength: 1, maxLength: 80),
            "force": Schema.boolean,
        ], required: ["name", "confirmName"])
    )

    struct Args: Decodable { let name: String; let confirmName: String; let force: Bool? }

    public func touchedPaths(_ args: ToolArgs) -> [String] {
        let decoded = try? args.decode(Args.self)
        let name = (try? decoded.map { try GitToolInput.worktreeName($0.name) }) ?? "unknown"
        return [".git", ".mopelium/git-worktrees/\(name)"]
    }

    public func execute(_ args: ToolArgs, in context: ToolContext) async throws -> ToolObservation {
        let a = try args.decode(Args.self)
        let name = try GitToolInput.worktreeName(a.name)
        let confirmName = try GitToolInput.worktreeName(a.confirmName)
        guard name == confirmName else {
            throw MopeliumToolError.permissionDenied("git_worktree_remove confirmName must match name")
        }
        let output = try await context.git.removeWorktree(name: name,
                                                          force: a.force ?? false,
                                                          workspace: context.workspaceRoot)
        return ToolObservation(text: output, changedFiles: [".mopelium/git-worktrees/\(name)"])
    }
}
