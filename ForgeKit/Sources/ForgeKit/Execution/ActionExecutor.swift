import Foundation

/// Applies `ParserEvent`s to the project in order: writes files as they close
/// (write-as-you-go), coalesces `add-dependency` into a single install, runs
/// shell commands, and starts the dev server exactly once. Source edits never
/// restart the server — Vite HMR owns them — so a stray `start` while the
/// server is up is ignored.
public actor ActionExecutor {
    private let process: any ProcessLayer
    private var pendingDeps: [String] = []
    private var pendingShell: [String] = []
    private var startRequested = false
    private var filesWritten: [String] = []

    public init(process: any ProcessLayer) {
        self.process = process
    }

    /// Process one event in stream order.
    public func handle(_ event: ParserEvent) async throws {
        switch event {
        case .fileClose(let path, let contents):
            try await process.writeFile(path, contents: contents)
            filesWritten.append(path)
        case .inlineAction(.addDependency(let package)):
            pendingDeps.append(package)
        case .inlineAction(.shell(let command)):
            pendingShell.append(command)
        case .inlineAction(.start):
            startRequested = true
        case .artifactClose:
            try await flush()
        case .text, .artifactOpen, .fileOpen, .fileChunk, .inlineAction(.file):
            break
        }
    }

    /// Run queued commands and start the dev server if needed. Called at
    /// artifact close.
    public func flush() async throws {
        if !pendingDeps.isEmpty {
            try await process.addDependencies(pendingDeps)
            pendingDeps.removeAll()
        }
        for command in pendingShell {
            _ = try await process.runShell(command)
        }
        pendingShell.removeAll()

        let running = await process.serverReadyURL != nil
        if !running {
            _ = try await process.startDevServerIfNeeded()
        }
        // Already running → do nothing: HMR applies file edits and Vite picks up
        // newly-installed deps on the next import/reload.
        startRequested = false
    }

    public var writtenFiles: [String] { filesWritten }
}
