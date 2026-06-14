import Foundation

/// Coarse state of one agent turn, surfaced to the UI.
public enum AgentState: Sendable, Equatable {
    case idle
    case building            // streaming model output + applying actions
    case applying            // running install/start at artifact close
    case awaitingHMR         // edits applied; waiting for Vite/console to settle
    case collectingErrors
    case repairing(attempt: Int)
    case clean               // converged: app runs with no errors
    case failed(String)
}

/// Streamed output of `AgentLoop.run`. The app renders these into the chat,
/// the preview, and a status line.
public enum AgentEvent: Sendable {
    case assistantText(String)   // prose for the chat pane (artifact internals excluded)
    case state(AgentState)
    case fileWriting(String)
    case fileWritten(String)
    case previewReady(URL)
}
