import Foundation
import CryptoKit

/// Speeds up the first build of a new project by reusing a previously-installed
/// `node_modules` for the same dependency set. Most projects start from the same
/// framework template, so their `package.json` — and thus their install — is
/// identical; the first install populates the cache and every later project with
/// the same `package.json` gets an APFS copy-on-write clone (`cp -c`) instead of a
/// fresh `npm install`. Clones are near-instant and disk is shared.
///
/// Entirely best-effort: any failure (no cache dir, non-APFS volume, hash miss)
/// just falls through to a normal install — correctness never depends on it.
public enum DependencyCache {
    /// Test seam: when set, overrides the cache root (so tests don't touch the real
    /// ~/Library/Caches). Not part of the public API.
    nonisolated(unsafe) static var rootOverrideForTesting: URL?

    /// Regenerable, so it lives under Caches, not Application Support.
    private static var root: URL? {
        if let rootOverrideForTesting { return rootOverrideForTesting }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Forge/depcache", isDirectory: true)
    }

    /// Cache entry for a project, keyed by the SHA-256 of its `package.json` so
    /// identical dependency sets share one entry (stable across launches, unlike
    /// Swift's `Hasher`).
    private static func entry(for projectRoot: URL) -> URL? {
        guard let root,
              let data = try? Data(contentsOf: projectRoot.appendingPathComponent("package.json"))
        else { return nil }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(hash, isDirectory: true)
            .appendingPathComponent("node_modules", isDirectory: true)
    }

    /// If the project has no `node_modules` yet but a matching cache entry exists,
    /// clone it in. Returns true on success (so the caller can skip re-caching).
    @discardableResult
    public static func restore(into projectRoot: URL) -> Bool {
        let fm = FileManager.default
        let dest = projectRoot.appendingPathComponent("node_modules")
        guard !fm.fileExists(atPath: dest.path),
              let src = entry(for: projectRoot), fm.fileExists(atPath: src.path)
        else { return false }
        return clone(src, to: dest)
    }

    /// After a successful install, cache this project's `node_modules` for the next
    /// project — but only if the dependency set isn't cached yet.
    public static func populate(from projectRoot: URL) {
        let fm = FileManager.default
        let src = projectRoot.appendingPathComponent("node_modules")
        guard fm.fileExists(atPath: src.path),
              let dest = entry(for: projectRoot), !fm.fileExists(atPath: dest.path)
        else { return }
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = clone(src, to: dest)
    }

    /// `cp -c -R` (APFS clonefile) with a plain-copy fallback for non-APFS volumes.
    private static func clone(_ src: URL, to dest: URL) -> Bool {
        if run(["/bin/cp", "-c", "-R", src.path, dest.path]) { return true }
        try? FileManager.default.removeItem(at: dest)   // partial clone → clean before fallback
        return run(["/bin/cp", "-R", src.path, dest.path])
    }

    private static func run(_ argv: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { return false }
        return p.terminationStatus == 0
    }
}
