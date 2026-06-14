import Foundation

/// Gathers self-correction inputs for the agent loop: dev-server log lines (from
/// the `DevServerManager` ring buffer) plus runtime issues pushed from the
/// preview WebView's JS bridge. The app calls `submit` from the bridge and
/// `reset` at the start of each turn.
public actor ErrorCollector {
    private let devServer: DevServerManager
    private let classifier = ErrorClassifier()
    private var runtimeIssues: [RuntimeIssue] = []

    public init(devServer: DevServerManager) {
        self.devServer = devServer
    }

    public func submit(_ issues: [RuntimeIssue]) {
        runtimeIssues.append(contentsOf: issues)
    }

    public func reset() {
        runtimeIssues.removeAll()
    }

    public func collect() async -> ErrorReport {
        let logs = await devServer.recentLogLines()
        return classifier.report(logs: logs, runtime: runtimeIssues)
    }
}
