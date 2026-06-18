import Foundation

/// A read-only snapshot of the project's REAL git state, surfaced in the TUI
/// "GIT" sidebar section. `nil`/`false` fields mean "not a repo yet" — the UI
/// shows an invitation to publish rather than an error.
public struct GitStatus: Sendable, Equatable {
    public var isRepo: Bool
    /// Current branch name (e.g. "main"), or "HEAD" when detached.
    public var branch: String
    /// The `origin` remote URL, if one is configured.
    public var remoteURL: String?
    /// True when the current branch tracks an upstream (so ahead/behind apply).
    public var hasUpstream: Bool
    /// Commits the local branch is ahead of / behind its upstream.
    public var ahead: Int
    public var behind: Int
    /// Number of changed (staged + unstaged + untracked) paths.
    public var dirty: Int
    /// Open PR for the current branch, if `gh` could find one ("#42 · title").
    public var openPR: String?

    public static let none = GitStatus(
        isRepo: false, branch: "", remoteURL: nil, hasUpstream: false,
        ahead: 0, behind: 0, dirty: 0, openPR: nil)

    public var owner: String? { remoteURL.flatMap(GitService.ownerRepo)?.owner }
    public var repoName: String? { remoteURL.flatMap(GitService.ownerRepo)?.repo }
    public var hasRemote: Bool { remoteURL != nil }
}

/// Drives the project's REAL `.git` (default git-dir) plus the GitHub CLI (`gh`)
/// for publish/PR. Deliberately separate from `CheckpointManager`, which owns an
/// ISOLATED shadow repo via `--git-dir`; nothing here passes `--git-dir`, so it
/// always acts on the project's own history — the thing a beginner pushes to
/// GitHub. `Sendable` and stateless apart from `root`.
///
/// Network ops (`gh`, push, pull) can take seconds, so every invocation runs on
/// `DispatchQueue.global` via a continuation — never on the Swift-concurrency
/// cooperative pool, where a blocking `waitUntilExit` would starve other tasks.
public struct GitService: Sendable {
    public let root: URL
    private static let gitPath = "/usr/bin/git"   // Apple shim; present with CLT/Xcode

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    // MARK: - Status

    /// Probe the full git state in one pass. Cheap (all local plumbing) except
    /// the optional PR lookup, which is skipped when there's no remote.
    public func status() async -> GitStatus {
        let inside = await run(["rev-parse", "--is-inside-work-tree"], tool: Self.gitPath)
        guard inside.status == 0,
              inside.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        else { return .none }

        async let branchR = run(["rev-parse", "--abbrev-ref", "HEAD"], tool: Self.gitPath)
        async let remoteR = run(["remote", "get-url", "origin"], tool: Self.gitPath)
        async let upstreamR = run(["rev-list", "--left-right", "--count", "@{u}...HEAD"], tool: Self.gitPath)
        async let dirtyR = run(["status", "--porcelain"], tool: Self.gitPath)

        let branch = (await branchR).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteOut = await remoteR
        let remote = remoteOut.status == 0
            ? remoteOut.output.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let upstream = await upstreamR
        let (behind, ahead) = Self.parseAheadBehind(upstream.output)
        let dirty = (await dirtyR).output
            .split(separator: "\n", omittingEmptySubsequences: true).count

        var st = GitStatus(
            isRepo: true,
            branch: branch.isEmpty ? "HEAD" : branch,
            remoteURL: remote.isEmpty ? nil : remote,
            hasUpstream: upstream.status == 0,
            ahead: ahead, behind: behind,
            dirty: dirty, openPR: nil)

        if st.remoteURL != nil { st.openPR = await openPRSummary() }
        return st
    }

    /// "#42 · Add login screen" for the current branch, or nil. Needs `gh`; a
    /// missing/unauthed `gh` simply yields no PR (never an error to the user).
    private func openPRSummary() async -> String? {
        let r = await run(
            ["pr", "view", "--json", "number,title", "-q", "\"#\\(.number) · \\(.title)\""],
            tool: ghPath())
        guard r.status == 0 else { return nil }
        let s = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    // MARK: - Operations

    public struct OpResult: Sendable, Equatable {
        public let ok: Bool
        /// Human-facing line for the transcript (last meaningful output line).
        public let message: String
        /// A URL worth surfacing (repo or PR), parsed from the tool output.
        public let url: String?
    }

    /// Create a GitHub repo from the current project and push to it. Runs
    /// `git init` first when the dir isn't a repo yet, then `gh repo create
    /// --source=. --push`. Requires an authed `gh`.
    public func publish(name: String, isPrivate: Bool) async -> OpResult {
        if !(await isRepo()) {
            _ = await run(["init", "-q"], tool: Self.gitPath)
            _ = await run(["add", "-A"], tool: Self.gitPath)
            _ = await run(["commit", "-q", "-m", "Initial commit"], tool: Self.gitPath)
        }
        let vis = isPrivate ? "--private" : "--public"
        let r = await run(
            ["repo", "create", name, "--source=.", "--remote=origin", "--push", vis],
            tool: ghPath())
        return Self.opResult(r, fallback: "Udgivet til GitHub")
    }

    /// Stage everything and commit. No-op commit is reported as a soft failure
    /// (nothing to commit) rather than an error.
    public func commitAll(message: String) async -> OpResult {
        _ = await run(["add", "-A"], tool: Self.gitPath)
        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = await run(["commit", "-m", msg.isEmpty ? "Update" : msg], tool: Self.gitPath)
        if r.status != 0,
           r.output.localizedCaseInsensitiveContains("nothing to commit") {
            return OpResult(ok: false, message: "Intet at committe", url: nil)
        }
        return Self.opResult(r, fallback: "Committet")
    }

    /// Push the current branch, setting upstream on first push.
    public func push() async -> OpResult {
        let r = await run(["push", "-u", "origin", "HEAD"], tool: Self.gitPath)
        return Self.opResult(r, fallback: "Pushet")
    }

    /// Pull with rebase to keep a linear history (beginner-friendly: no merge
    /// bubbles). Falls back cleanly when there's no upstream.
    public func pull() async -> OpResult {
        let r = await run(["pull", "--rebase"], tool: Self.gitPath)
        return Self.opResult(r, fallback: "Pullet")
    }

    /// Open a draft PR. If on the default branch, first carve off a
    /// `storm/<slug>` feature branch (committing any pending work) so the PR has
    /// somewhere to point — GitHub can't PR a branch against itself.
    public func openPR(title: String) async -> OpResult {
        let branch = (await run(["rev-parse", "--abbrev-ref", "HEAD"], tool: Self.gitPath))
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
        if branch == "main" || branch == "master" || branch.isEmpty {
            let feature = "storm/" + Self.slug(title)
            _ = await run(["checkout", "-b", feature], tool: Self.gitPath)
            _ = await run(["add", "-A"], tool: Self.gitPath)
            _ = await run(["commit", "-q", "-m", title.isEmpty ? "Stormbreaker changes" : title],
                          tool: Self.gitPath)
            _ = await run(["push", "-u", "origin", "HEAD"], tool: Self.gitPath)
        }
        let r = await run(["pr", "create", "--draft", "--fill"], tool: ghPath())
        return Self.opResult(r, fallback: "Udkast til PR oprettet")
    }

    private func isRepo() async -> Bool {
        let r = await run(["rev-parse", "--is-inside-work-tree"], tool: Self.gitPath)
        return r.status == 0 &&
            r.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    // MARK: - Testable pure helpers

    /// `git rev-list --left-right --count @{u}...HEAD` prints "behind\tahead".
    /// Returns (0, 0) on any malformed input (e.g. no upstream → stderr).
    public static func parseAheadBehind(_ raw: String) -> (behind: Int, ahead: Int) {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == "\t" || $0 == " " })
        guard parts.count == 2, let behind = Int(parts[0]), let ahead = Int(parts[1])
        else { return (0, 0) }
        return (behind, ahead)
    }

    /// A branch-safe slug from a free-text title: lowercase, alnum→keep,
    /// everything else→`-`, collapsed, trimmed, capped. Empty → "change".
    public static func slug(_ title: String) -> String {
        var out = ""
        var lastDash = false
        for ch in title.lowercased() {
            if ch.isLetter || ch.isNumber {
                out.append(ch); lastDash = false
            } else if !lastDash {
                out.append("-"); lastDash = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let capped = String(trimmed.prefix(40))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return capped.isEmpty ? "change" : capped
    }

    /// First http(s) URL found in tool output (gh prints the repo/PR URL).
    public static func firstURL(_ text: String) -> String? {
        for token in text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            if token.hasPrefix("https://") || token.hasPrefix("http://") {
                return String(token).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    /// Parse "owner/repo" out of an SSH or HTTPS GitHub remote URL.
    public static func ownerRepo(_ remote: String) -> (owner: String, repo: String)? {
        var s = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(".git") { s.removeLast(4) }
        // git@github.com:owner/repo  |  https://github.com/owner/repo
        if let range = s.range(of: "github.com") {
            var tail = String(s[range.upperBound...])
            tail = tail.trimmingCharacters(in: CharacterSet(charactersIn: ":/"))
            let parts = tail.split(separator: "/")
            if parts.count >= 2 { return (String(parts[0]), String(parts[1])) }
        }
        let parts = s.split(separator: "/")
        if parts.count >= 2 {
            return (String(parts[parts.count - 2]), String(parts[parts.count - 1]))
        }
        return nil
    }

    private static func opResult(
        _ r: (status: Int32, output: String), fallback: String
    ) -> OpResult {
        let lines = r.output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let last = lines.last ?? fallback
        return OpResult(ok: r.status == 0,
                        message: r.status == 0 ? fallback : last,
                        url: firstURL(r.output))
    }

    // MARK: - Process runner

    /// Resolve `gh` from PATH (Homebrew installs to /opt/homebrew/bin on Apple
    /// silicon, /usr/local/bin on Intel). Falls back to the bare name so
    /// `/usr/bin/env` can still find it.
    private func ghPath() -> String {
        for p in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return "gh"
    }

    /// Run a tool to completion off the cooperative pool. `tool` is either an
    /// absolute path or a bare name resolved via `/usr/bin/env`.
    private func run(_ args: [String], tool: String) async -> (status: Int32, output: String) {
        let rootPath = root.path
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                if tool.hasPrefix("/") {
                    process.executableURL = URL(fileURLWithPath: tool)
                    process.arguments = args
                } else {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = [tool] + args
                }
                process.currentDirectoryURL = URL(fileURLWithPath: rootPath)
                var env = ProcessInfo.processInfo.environment
                env["GIT_TERMINAL_PROMPT"] = "0"   // never block on a credential prompt
                process.environment = env
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do { try process.run() } catch {
                    cont.resume(returning: (-1, "\(error.localizedDescription)"))
                    return
                }
                let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
                process.waitUntilExit()
                cont.resume(returning: (process.terminationStatus,
                                        String(decoding: data, as: UTF8.self)))
            }
        }
    }
}
