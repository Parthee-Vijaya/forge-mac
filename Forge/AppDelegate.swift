import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

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
