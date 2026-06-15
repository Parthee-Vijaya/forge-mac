import Foundation

/// File I/O for one generated project, jailed to `root`. The artifact executor
/// writes every file through here, so a path that escapes the project root
/// (e.g. `../../etc/passwd`) is rejected rather than written.
public actor ProjectWorkspace {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// Create the project root directory if it does not exist.
    public func ensureRootExists() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Resolve a relative path to an absolute URL, verifying it stays inside the
    /// project root.
    public func absoluteURL(for relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = root.path
        guard url.path == rootPath || url.path.hasPrefix(rootPath + "/") else {
            throw DevServerError.projectDirectoryUnwritable(path: relativePath)
        }
        return url
    }

    public func ensureDirectory(_ relativePath: String) throws {
        let url = try absoluteURL(for: relativePath)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Atomically write text to a file, creating parent directories as needed.
    public func writeFile(_ relativePath: String, contents: String) throws {
        let url = try absoluteURL(for: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    public func writeFile(_ relativePath: String, data: Data) throws {
        let url = try absoluteURL(for: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func readFile(_ relativePath: String) throws -> String {
        let url = try absoluteURL(for: relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func removeItem(_ relativePath: String) throws {
        let url = try absoluteURL(for: relativePath)
        try FileManager.default.removeItem(at: url)
    }

    public func fileExists(_ relativePath: String) -> Bool {
        guard let url = try? absoluteURL(for: relativePath) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Shallow list of relative file paths under the project (skips
    /// node_modules / .git / dist / .forge), used to build the model's file map.
    public func fileMap(maxDepth: Int = 6) -> [String] {
        let skip: Set<String> = ["node_modules", ".git", "dist", ".forge", ".DS_Store"]
        // Resolve symlinks so the base prefix matches the enumerator's URLs —
        // macOS temp dirs live under /var, a symlink to /private/var, and
        // FileManager.enumerator returns the resolved form.
        let base = root.resolvingSymlinksInPath()
        let basePrefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        guard let enumerator = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [String] = []
        for case let url as URL in enumerator {
            if skip.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(basePrefix) else { continue }
            let rel = String(path.dropFirst(basePrefix.count))
            if rel.split(separator: "/").count > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            if isRegular { results.append(rel) }
        }
        // Surface .env / .env.local — they're hidden (skipped by .skipsHiddenFiles)
        // but the user edits them via the code view (B17 — env editor).
        for env in [".env", ".env.local"] where FileManager.default.fileExists(
            atPath: base.appendingPathComponent(env).path) {
            results.append(env)
        }
        return results.sorted()
    }
}
