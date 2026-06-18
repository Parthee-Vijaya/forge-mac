import Foundation

/// Typed failures from the process / dev-server layer. Each case carries enough
/// context (searched paths, log tails) for the UI to tell the user what went
/// wrong without digging through raw output.
public enum DevServerError: Error, Sendable, Equatable {
    case nodeRuntimeNotFound(searched: [String])
    case packageManagerNotFound(name: String)
    case installFailed(exitCode: Int32, tail: [LogLine])
    case serverFailedToStart(tail: [LogLine])
    case readyTimedOut(seconds: Int)
    case projectDirectoryUnwritable(path: String)
    case alreadyRunning
}

extension DevServerError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .nodeRuntimeNotFound(let searched):
            return "Node runtime not found. Searched: \(searched.joined(separator: ", "))"
        case .packageManagerNotFound(let name):
            return "Package manager '\(name)' not found on PATH."
        case .installFailed(let code, _):
            return "Dependency install failed (exit code \(code))."
        case .serverFailedToStart:
            return "The dev server exited before it became ready."
        case .readyTimedOut(let seconds):
            return "Timed out after \(seconds)s waiting for the dev server to start."
        case .projectDirectoryUnwritable(let path):
            return "Project directory is not writable: \(path)"
        case .alreadyRunning:
            return "The dev server is already running."
        }
    }
}
