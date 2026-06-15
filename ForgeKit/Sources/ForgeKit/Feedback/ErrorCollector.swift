import Foundation

/// Gathers self-correction inputs for the agent loop: dev-server log lines (from
/// the `DevServerManager` ring buffer) plus runtime issues pushed from the
/// preview WebView's JS bridge. The app calls `submit` from the bridge and
/// `reset` at the start of each turn.
public actor ErrorCollector {
    private let devServer: DevServerManager
    private let classifier = ErrorClassifier()
    private var runtimeIssues: [RuntimeIssue] = []
    /// Keep only the most recent issues so a runaway render-loop can't grow the
    /// buffer unboundedly and blow up the next prompt's token budget.
    private let cap = 50

    public init(devServer: DevServerManager) {
        self.devServer = devServer
    }

    public func submit(_ issues: [RuntimeIssue]) {
        runtimeIssues.append(contentsOf: issues)
        if runtimeIssues.count > cap { runtimeIssues.removeFirst(runtimeIssues.count - cap) }
    }

    public func reset() {
        runtimeIssues.removeAll()
    }

    public func collect() async -> ErrorReport {
        let logs = await devServer.recentLogLines()
        // A real `tsc --noEmit` pass — the dev server (esbuild) never type-checks,
        // so without this a type error reads as "clean". No-op for projects that
        // can't be checked (returns []), and the classifier dedups any error the
        // Vite overlay also reported.
        let typeErrors = await devServer.typeCheck()
        return classifier.report(logs: logs + typeErrors, runtime: runtimeIssues)
    }
}
