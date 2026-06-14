import Foundation

/// Coarse lifecycle phase of a managed dev server. Mirrored into the app's
/// `@MainActor` state so the preview pane can show the right placeholder.
public enum DevServerPhase: Sendable, Equatable {
    case idle
    case installingDependencies
    case startingServer
    case running(url: URL)
    case failed(reason: String)
    case stopped
}

/// A single event emitted by `DevServerManager.events()`. The agent loop
/// consumes one multiplexed stream for logs, phase changes, the ready signal,
/// and process exit.
public enum ServerEvent: Sendable {
    case log(LogLine)
    case phase(DevServerPhase)
    case ready(url: URL)
    case exited(code: Int32)
}
