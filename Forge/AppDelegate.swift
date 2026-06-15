import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Notification authorization is requested lazily on the first real
        // notification (see Notifier.post) — not on launch, so we don't nag.
        Task { await model.refreshGitBranch() }         // status-bar git segment for the resumed project
    }

    /// Async-cleanup termination: stop the dev server (SIGTERM→SIGKILL) before
    /// the app exits so no vite/node process is orphaned. The forge-run.sh
    /// watchdog is the backstop if this is skipped.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let devServer = model.devServer
        Task {
            await devServer.shutdown()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
