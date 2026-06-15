import Foundation

/// The primary façade the agent loop calls. For one project it coordinates:
/// dependency install → dev-server launch (via the forge-run.sh wrapper) →
/// ready detection → multiplexed log/event broadcast → crash handling →
/// shutdown.
///
/// Lifecycle rules (enforced here, asserted by the system prompt):
/// - `start()` runs install + dev once and resolves when Vite is ready.
/// - Source edits do NOT restart the server — Vite HMR applies them.
/// - `restartForDependencyChange()` is the only re-install/restart path.
public actor DevServerManager {
    private let workspace: ProjectWorkspace
    private let resolver: NodeResolver
    private let packageManager: PackageManager
    private let runner = ProcessRunner()
    private let detector = ViteReadyDetector()
    private let supervisor: ProcessSupervisor

    private var phaseValue: DevServerPhase = .idle
    private var readyURLValue: URL?
    private var devProcess: RunningProcess?
    private var subscribers: [UUID: AsyncStream<ServerEvent>.Continuation] = [:]

    // Ready handshake for start().
    private var readyContinuation: CheckedContinuation<URL, Error>?
    private var readyResolved = false

    // Ring buffer of recent log lines for error tails on failure.
    private var recentLog: [LogLine] = []
    private let recentLogCap = 80

    public init(
        workspace: ProjectWorkspace,
        nodeResolver: NodeResolver = .shared,
        packageManager: PackageManager = .npm
    ) {
        self.workspace = workspace
        self.resolver = nodeResolver
        self.packageManager = packageManager
        self.supervisor = ProcessSupervisor(projectRoot: workspace.root)
    }

    // MARK: - Observable state

    public var phase: DevServerPhase { phaseValue }
    public var serverReadyURL: URL? { readyURLValue }

    /// Subscribe to the multiplexed event stream (logs, phase, ready, exit).
    /// Each caller gets an independent stream.
    public func events() -> AsyncStream<ServerEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: ServerEvent.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    // MARK: - Lifecycle

    /// Install dependencies if needed, then start the dev server. Resolves with
    /// the local URL when Vite is ready, or throws.
    @discardableResult
    public func start(timeout: Duration = .seconds(120)) async throws -> URL {
        guard readyURLValue == nil else { throw DevServerError.alreadyRunning }
        try await workspace.ensureRootExists()
        supervisor.reclaimOrphan()

        let (managerURL, nodeDir) = try await resolveTooling()
        let env = childEnvironment(nodeBinDir: nodeDir)
        let root = workspace.root

        // 1. Install dependencies. First reuse a cached node_modules for this exact
        //    package.json if we have one (APFS clone — near-instant) so the install
        //    becomes a quick reconcile instead of a full download. Off-actor so the
        //    clone/copy doesn't block.
        setPhase(.installingDependencies)
        let restored = await Task.detached { DependencyCache.restore(into: root) }.value
        let installCode = try await runToCompletion(
            executableURL: managerURL,
            arguments: packageManager.installArgs,
            workingDirectory: root,
            environment: env
        )
        guard installCode == 0 else {
            let tail = recentLogTail()
            setPhase(.failed(reason: "Dependency install failed (\(installCode))"))
            throw DevServerError.installFailed(exitCode: installCode, tail: tail)
        }
        // Cache this dependency set for the next project (only on a cold install).
        if !restored { Task.detached { DependencyCache.populate(from: root) } }

        // 2. Start the dev server.
        setPhase(.startingServer)
        return try await launchDevServer(managerURL: managerURL, env: env, root: root, timeout: timeout)
    }

    /// Re-install and restart. Call ONLY when dependencies changed — never on
    /// source edits (HMR handles those).
    @discardableResult
    public func restartForDependencyChange(timeout: Duration = .seconds(120)) async throws -> URL {
        await stopDevProcessQuietly()
        return try await start(timeout: timeout)
    }

    /// Run a one-shot command (e.g. `npm run build`) without disturbing the dev
    /// server. The caller consumes the returned stream.
    public func runCommand(
        _ tool: NodeResolver.Tool, _ arguments: [String]
    ) async throws -> (events: AsyncStream<ServerEvent>, process: RunningProcess) {
        let resolver = self.resolver
        let resolved: (URL, URL) = try await Task.detached {
            (try resolver.resolve(tool), try resolver.nodeBinDirectory())
        }.value
        return try runner.run(
            executableURL: resolved.0,
            arguments: arguments,
            workingDirectory: workspace.root,
            environment: childEnvironment(nodeBinDir: resolved.1)
        )
    }

    /// Run an arbitrary shell command in the project dir with the node-augmented
    /// PATH (e.g. `npm install clsx`, `npx shadcn add button`). One-shot; does
    /// not touch the dev server.
    public func runShellCommand(
        _ command: String
    ) async throws -> (events: AsyncStream<ServerEvent>, process: RunningProcess) {
        let resolver = self.resolver
        let nodeDir = try await Task.detached { try resolver.nodeBinDirectory() }.value
        return try runner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", command],
            workingDirectory: workspace.root,
            environment: childEnvironment(nodeBinDir: nodeDir)
        )
    }

    /// One-shot TypeScript type-check (`tsc --noEmit`) feeding the self-correction
    /// loop. Vite's dev server transpiles with esbuild, which *strips* types
    /// without checking them, so a real type error otherwise ships silently as
    /// "clean". Returns tsc's output as log lines for `ErrorClassifier` (which
    /// already parses the `file(line,col): error TSxxxx` format and dedups against
    /// the Vite overlay).
    ///
    /// Returns `[]` — never fabricated errors — when the project can't be checked:
    /// no `tsconfig.json` or no locally-installed `tsc` (e.g. the Svelte/Vue
    /// scaffolds, which would need svelte-check / vue-tsc instead). A watchdog
    /// terminates a tsc that runs past `timeout` so the loop can't stall.
    public func typeCheck(timeout: Duration = .seconds(60)) async -> [LogLine] {
        let fm = FileManager.default
        let bin = workspace.root.appendingPathComponent("node_modules/.bin")
        func has(_ tool: String) -> Bool { fm.fileExists(atPath: bin.appendingPathComponent(tool).path) }
        let hasTSConfig = fm.fileExists(atPath: workspace.root.appendingPathComponent("tsconfig.json").path)

        // Pick the framework's checker. vue-tsc/svelte-check both depend on tsc,
        // so probe the framework-specific tools first. All emit `file:line:col`
        // diagnostics the ErrorClassifier already parses (svelte-check via its
        // line-oriented machine format).
        let command: String
        if has("vue-tsc"), hasTSConfig {
            command = "node_modules/.bin/vue-tsc --noEmit --pretty false"
        } else if has("svelte-check") {
            command = "node_modules/.bin/svelte-check --output machine --threshold error"
        } else if has("tsc"), hasTSConfig {
            command = "node_modules/.bin/tsc --noEmit --pretty false"
        } else {
            return []   // not a type-checkable project (or deps not installed)
        }

        let isSvelteCheck = command.contains("svelte-check")
        do {
            // The relative bin resolves against cwd (the project root).
            let (events, process) = try await runShellCommand(command)
            let watchdog = Task {
                try? await Task.sleep(for: timeout)
                if process.isRunning { await process.terminate() }
            }
            defer { watchdog.cancel() }
            // Consume privately (do NOT broadcast): checker output belongs in the
            // error report, not the live dev-server log pane.
            var lines: [LogLine] = []
            for await event in events {
                if case .log(let line) = event { lines.append(line) }
            }
            // tsc/vue-tsc already emit the `file(line,col): error TSxxxx` form the
            // classifier parses; svelte-check's machine format needs reshaping.
            return isSvelteCheck ? lines.compactMap(Self.normalizeSvelteCheckLine) : lines
        } catch {
            return []
        }
    }

    /// Reshape one `svelte-check --output machine` line into the tsc-style
    /// `file(line,col): error: message` the `ErrorClassifier` parses structurally.
    /// Real diagnostics look like `<epochMs> ERROR "src/App.svelte" 67:7 "msg"`.
    /// Returns nil for everything else — crucially the trailing
    /// `<epochMs> COMPLETED … 1 ERRORS …` summary, which contains the word
    /// "ERRORS" and would otherwise surface as a phantom error.
    nonisolated static func normalizeSvelteCheckLine(_ line: LogLine) -> LogLine? {
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let re = try? NSRegularExpression(
            pattern: #"^\d+\s+ERROR\s+"([^"]+)"\s+(\d+):(\d+)\s+"(.*)"\s*$"#),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let file = m.text(at: 1, in: text),
              let row = m.text(at: 2, in: text),
              let col = m.text(at: 3, in: text),
              let message = m.text(at: 4, in: text) else { return nil }
        return LogLine(stream: line.stream, text: "\(file)(\(row),\(col)): error: \(message)")
    }

    /// Graceful stop + cleanup. Safe to call multiple times.
    public func shutdown() async {
        await stopDevProcessQuietly()
        setPhase(.stopped)
        for continuation in subscribers.values { continuation.finish() }
        subscribers.removeAll()
    }

    // MARK: - Internals

    private func resolveTooling() async throws -> (managerURL: URL, nodeDir: URL) {
        let resolver = self.resolver
        let pm = self.packageManager
        return try await Task.detached {
            let managerURL = try resolver.resolve(pm.tool)
            let nodeDir = try resolver.nodeBinDirectory()
            return (managerURL, nodeDir)
        }.value
    }

    private func runToCompletion(
        executableURL: URL, arguments: [String],
        workingDirectory: URL, environment: [String: String]
    ) async throws -> Int32 {
        let (events, _) = try runner.run(
            executableURL: executableURL, arguments: arguments,
            workingDirectory: workingDirectory, environment: environment)
        var exitCode: Int32 = -1
        for await event in events {
            broadcast(event)
            if case .exited(let code) = event { exitCode = code }
        }
        return exitCode
    }

    private func launchDevServer(
        managerURL: URL, env: [String: String], root: URL, timeout: Duration
    ) async throws -> URL {
        readyResolved = false

        var devEnv = env
        var executableURL = managerURL
        // Give each project its own port (off Vite's default 5173) so projects
        // don't collide with each other or with other dev tools (e.g. OrbStack on
        // 5173) and end up serving the wrong app. strictPort is false in the
        // template, so Vite picks the next free port if even this is taken — and
        // Forge parses the actual port from stdout.
        // `--host` binds LAN interfaces too, so the preview is reachable over
        // LAN/Tailscale (the "Del live-link" feature). The preview still loads
        // via 127.0.0.1; Forge parses the actual Local port from stdout.
        let portArgs = ["--", "--port", "\(projectPort)", "--host"]
        var arguments = packageManager.devArgs + portArgs

        // Prefer the forge-run.sh wrapper for orphan safety; fall back to a
        // direct launch if it can't be written.
        if let wrapper = try? materializeRunWrapper() {
            devEnv["FORGE_PARENT_PID"] = "\(ProcessInfo.processInfo.processIdentifier)"
            executableURL = URL(fileURLWithPath: "/bin/sh")
            arguments = [wrapper.path, managerURL.path] + packageManager.devArgs + portArgs
        }

        let (events, process) = try runner.run(
            executableURL: executableURL, arguments: arguments,
            workingDirectory: root, environment: devEnv)
        devProcess = process
        supervisor.record(pid: process.pid)

        consumeDevServerEvents(events)
        scheduleReadyTimeout(timeout)

        return try await withCheckedThrowingContinuation { continuation in
            self.readyContinuation = continuation
        }
    }

    /// Long-lived consumer for the dev server's event stream: broadcasts every
    /// event, resolves the ready handshake on the Vite ready line, and surfaces
    /// crashes. Runs for the life of the dev server (keeps the stream drained so
    /// it never buffers unboundedly).
    private func consumeDevServerEvents(_ events: AsyncStream<ServerEvent>) {
        let detector = self.detector
        Task { [weak self] in
            for await event in events {
                guard let self else { break }
                await self.broadcast(event)
                switch event {
                case .log(let line):
                    if let url = detector.detect(in: line.text) {
                        await self.resolveReady(url)
                    }
                case .exited(let code):
                    await self.handleDevServerExit(code)
                default:
                    break
                }
            }
            await self?.handleDevServerStreamEnd()
        }
    }

    private func scheduleReadyTimeout(_ timeout: Duration) {
        let seconds = Int(timeout.components.seconds)
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.timeoutReadyIfPending(seconds: seconds)
        }
    }

    private func resolveReady(_ url: URL) {
        guard !readyResolved else { return }
        readyResolved = true
        readyURLValue = url
        setPhase(.running(url: url))
        broadcast(.ready(url: url))
        readyContinuation?.resume(returning: url)
        readyContinuation = nil
    }

    private func failReady(_ error: Error) {
        guard !readyResolved else { return }
        readyResolved = true
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
    }

    private func handleDevServerExit(_ code: Int32) {
        if !readyResolved {
            setPhase(.failed(reason: "Dev server exited (\(code)) before ready"))
            failReady(DevServerError.serverFailedToStart(tail: recentLogTail()))
        } else {
            setPhase(.failed(reason: "Dev server exited (\(code))"))
        }
        devProcess = nil
        supervisor.clear()
    }

    private func handleDevServerStreamEnd() {
        if !readyResolved {
            failReady(DevServerError.serverFailedToStart(tail: recentLogTail()))
        }
    }

    private func timeoutReadyIfPending(seconds: Int) {
        guard !readyResolved else { return }
        setPhase(.failed(reason: "Timed out after \(seconds)s waiting for the dev server"))
        failReady(DevServerError.readyTimedOut(seconds: seconds))
        Task { await stopDevProcessQuietly() }
    }

    private func stopDevProcessQuietly() async {
        if let process = devProcess { await process.terminate() }
        devProcess = nil
        supervisor.clear()
        readyURLValue = nil
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private func broadcast(_ event: ServerEvent) {
        if case .log(let line) = event {
            recentLog.append(line)
            if recentLog.count > recentLogCap {
                recentLog.removeFirst(recentLog.count - recentLogCap)
            }
        }
        for continuation in subscribers.values { continuation.yield(event) }
    }

    private func setPhase(_ phase: DevServerPhase) {
        phaseValue = phase
        broadcast(.phase(phase))
    }

    private func recentLogTail() -> [LogLine] { Array(recentLog.suffix(20)) }

    /// A stable, per-project dev-server port in a Forge range (5300–5699), well
    /// clear of Vite's default 5173. Derived from the project folder via FNV-1a
    /// so a project always prefers the same port; collisions fall through to the
    /// next free port (strictPort is false).
    private var projectPort: Int {
        var hash: UInt32 = 2_166_136_261
        for byte in workspace.root.lastPathComponent.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return 5300 + Int(hash % 400)
    }

    /// Public snapshot of recent log lines, for the agent loop's error probe.
    public func recentLogLines(limit: Int = 40) -> [LogLine] {
        Array(recentLog.suffix(limit))
    }

    /// Write the dev-server wrapper script into the project's .forge directory.
    private func materializeRunWrapper() throws -> URL {
        let dir = workspace.root.appendingPathComponent(".forge", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("forge-run.sh")
        try RunWrapper.script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func childEnvironment(nodeBinDir: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existingPATH = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "\(nodeBinDir.path):\(existingPATH)"
        env["CI"] = "1"                    // non-interactive installs
        env["NO_UPDATE_NOTIFIER"] = "1"
        return env
    }
}
