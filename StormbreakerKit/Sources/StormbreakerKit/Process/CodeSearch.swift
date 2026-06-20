import Foundation

/// Read-only code search for the agent (opencode `grep`/`glob` parity). Runs ripgrep
/// (falling back to `grep`) for content search and `find` for filename globbing —
/// always rooted at the project dir, never following the query as a path, so it can't
/// escape the workspace. The model-supplied query is passed as a process ARGUMENT
/// (never through `sh -c`), so it can't inject a shell command.
public enum CodeSearch {
    /// Heavy build dirs we never search.
    private static let pruneDirs = ["node_modules", ".git", ".next", "dist", "build", ".cache"]

    public static func run(_ kind: SearchKind, query: String, root: URL, maxChars: Int = 12_000) async -> String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return "Tom søgning." }
        switch kind {
        case .grep: return await grep(q, root: root, maxChars: maxChars)
        case .glob: return await glob(q, root: root, maxChars: maxChars)
        }
    }

    // MARK: - grep (file contents)

    static func grep(_ query: String, root: URL, maxChars: Int) async -> String {
        // Prefer ripgrep (fast, .gitignore-aware) by ABSOLUTE path — a GUI app's PATH
        // doesn't include homebrew, so `env rg` would fail to resolve. Fall back to
        // the always-present BSD grep.
        if let rg = resolve(["/opt/homebrew/bin/rg", "/usr/local/bin/rg", "/usr/bin/rg",
                             NSHomeDirectory() + "/.cargo/bin/rg"]) {
            var args = ["--line-number", "--no-heading", "--color=never", "-S", "--max-count=80"]
            for d in pruneDirs { args += ["--glob", "!\(d)/**"] }
            args += ["--", query]
            let (out, code) = await capture(rg, args, root: root, maxChars: maxChars)
            // code 0 = matches, 1 = no matches: trust rg. Anything else (failed to
            // launch, internal error) → fall through to the always-present grep.
            if code == 0 || code == 1 {
                return out.isEmpty ? "Ingen match for: \(query)" : "GREP: \(query)\n\n" + out
            }
        }
        var args = ["-rnI", "--max-count=5"]
        for d in pruneDirs { args += ["--exclude-dir=\(d)"] }
        args += ["--", query, "."]
        let (out, _) = await capture("/usr/bin/grep", args, root: root, maxChars: maxChars)
        return out.isEmpty ? "Ingen match for: \(query)" : "GREP: \(query)\n\n" + out
    }

    // MARK: - glob (filenames)

    static func glob(_ pattern: String, root: URL, maxChars: Int) async -> String {
        var args = [".", "-type", "f"]
        for d in pruneDirs { args += ["-not", "-path", "*/\(d)/*"] }
        args += ["-name", pattern]
        let (out, _) = await capture("/usr/bin/find", args, root: root, maxChars: maxChars)
        return out.isEmpty ? "Ingen filer matcher: \(pattern)" : "GLOB: \(pattern)\n\n" + out
    }

    /// First existing executable among `candidates`, or nil.
    private static func resolve(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Process capture (argument array — no shell, no injection)

    private static func capture(_ exe: String, _ args: [String], root: URL, maxChars: Int) async -> (String, Int32) {
        await withCheckedContinuation { (cont: CheckedContinuation<(String, Int32), Never>) in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                p.currentDirectoryURL = root
                let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
                do { try p.run() } catch { cont.resume(returning: ("", -1)); return }
                let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
                p.waitUntilExit()
                let text = String(decoding: data.prefix(maxChars), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: (text, p.terminationStatus))
            }
        }
    }
}
