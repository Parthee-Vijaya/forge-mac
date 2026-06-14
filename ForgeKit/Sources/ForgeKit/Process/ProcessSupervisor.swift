import Foundation

/// Tracks the dev-server PID in `<project>/.forge/devserver.pid` so a process
/// left behind (if Forge and its watchdog both died) can be reclaimed on the
/// next launch. `Sendable` value type.
public struct ProcessSupervisor: Sendable {
    public let pidFileURL: URL
    public let projectRoot: URL

    public init(projectRoot: URL) {
        self.projectRoot = projectRoot.standardizedFileURL
        self.pidFileURL = projectRoot.appendingPathComponent(".forge/devserver.pid")
    }

    public func record(pid: Int32) {
        try? FileManager.default.createDirectory(
            at: pidFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "\(pid)".write(to: pidFileURL, atomically: true, encoding: .utf8)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: pidFileURL)
    }

    /// If a stale PID file points at a live process that looks like our dev
    /// server, terminate it. Verified via `ps` before signalling so we don't
    /// kill an unrelated process that reused the PID.
    public func reclaimOrphan() {
        guard let text = try? String(contentsOf: pidFileURL, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        defer { clear() }
        guard kill(pid, 0) == 0 else { return }          // not alive
        guard processLooksLikeOurs(pid) else { return }   // not ours — leave it
        kill(pid, SIGTERM)
        usleep(500_000)
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    private func processLooksLikeOurs(_ pid: Int32) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "command=", "-p", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            process.waitUntilExit()
            let command = String(decoding: data, as: UTF8.self)
            return command.contains("vite")
                || command.contains("node")
                || command.contains(projectRoot.path)
        } catch {
            return false
        }
    }
}
