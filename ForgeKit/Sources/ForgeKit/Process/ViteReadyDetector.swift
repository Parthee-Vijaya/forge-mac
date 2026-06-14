import Foundation

/// Detects the "server ready" line in Vite's stdout and extracts the local URL.
///
/// Vite prints something like:
/// ```
///   ➜  Local:   http://localhost:5173/
/// ```
/// The port is not guaranteed to be 5173 (Vite picks the next free port when
/// busy), so we always parse the actual URL rather than assume it.
public struct ViteReadyDetector: Sendable {
    private static let regex = try! NSRegularExpression(
        pattern: #"Local:\s*(https?://(?:localhost|127\.0\.0\.1)(?::\d+)?[^\s]*)"#,
        options: [.caseInsensitive]
    )

    public init() {}

    /// Returns the local URL if `line` is Vite's ready line, else nil.
    /// `line` may still contain ANSI codes; they are stripped defensively.
    public func detect(in line: String) -> URL? {
        let clean = ANSI.strip(line)
        let range = NSRange(clean.startIndex..., in: clean)
        guard let match = Self.regex.firstMatch(in: clean, range: range),
              let captured = Range(match.range(at: 1), in: clean) else {
            return nil
        }
        var urlString = String(clean[captured])
        // Trim a trailing slash for a cleaner base URL (WKWebView handles both).
        if urlString.hasSuffix("/") { urlString.removeLast() }
        return URL(string: urlString)
    }
}
