import Foundation

/// Runs a command through the user's login shell (so it inherits the full PATH —
/// gh/vercel live in /opt/homebrew/bin which a GUI app doesn't get by default).
/// Read-only detection use in onboarding (gh auth status, vercel whoami, …).
enum Shell {
    static func login(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = ["-ilc", command]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: "")
                    return
                }
                // Terminate a hanging login shell after 8s (a stuck .zshrc would
                // otherwise block onboarding detection forever).
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: watchdog)
                let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
                process.waitUntilExit()
                watchdog.cancel()
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
        }
    }

    /// Runs a long command through the login shell, streaming each output line to
    /// `onLine` (on the main actor) as it arrives, and returns the exit code. No
    /// short watchdog — installs/pulls take minutes. A hard cap (default 10 min)
    /// terminates a genuinely stuck process. Use for `brew install` / `ollama pull`.
    @discardableResult
    static func stream(_ command: String,
                       timeout: TimeInterval = 600,
                       onLine: @escaping @MainActor (String) -> Void) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = ["-ilc", command]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                let handle = pipe.fileHandleForReading
                let buffer = LineBuffer()   // reference type: safe to mutate from the serialized handler
                handle.readabilityHandler = { fh in
                    let chunk = fh.availableData
                    guard !chunk.isEmpty else { return }
                    buffer.data.append(chunk)
                    while let nl = buffer.data.firstIndex(of: 0x0A) {
                        let line = String(decoding: buffer.data[buffer.data.startIndex..<nl], as: UTF8.self)
                        buffer.data.removeSubrange(buffer.data.startIndex...nl)
                        Task { @MainActor in onLine(line) }
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: -1)
                    return
                }
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                process.waitUntilExit()
                watchdog.cancel()
                handle.readabilityHandler = nil
                // Flush any trailing partial line.
                if !buffer.data.isEmpty {
                    let tail = String(decoding: buffer.data, as: UTF8.self)
                    Task { @MainActor in onLine(tail) }
                }
                continuation.resume(returning: process.terminationStatus)
            }
        }
    }
}

/// Mutable byte accumulator for `Shell.stream`'s pipe handler. A reference type so
/// the (serialized) readability handler can append to it without tripping Swift 6's
/// captured-var concurrency check.
private final class LineBuffer: @unchecked Sendable {
    var data = Data()
}
