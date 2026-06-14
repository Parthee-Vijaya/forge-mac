import Foundation

/// Turns raw dev-server log lines + browser runtime issues into a deduplicated
/// `ErrorReport`. Pure and `Sendable`.
public struct ErrorClassifier: Sendable {
    public init() {}

    public func report(logs: [LogLine], runtime: [RuntimeIssue]) -> ErrorReport {
        var items: [ErrorReport.Item] = []
        var seen = Set<String>()

        for line in logs where looksLikeError(line.text) {
            let key = normalize(line.text)
            if seen.insert(key).inserted {
                items.append(.init(source: .build, message: line.text))
            }
        }
        for issue in runtime {
            let key = normalize(issue.message)
            if seen.insert(key).inserted {
                items.append(.init(source: .runtime, message: issue.displayMessage))
            }
        }
        return ErrorReport(items: items)
    }

    private func looksLikeError(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("0 error") || lower.contains("no error") { return false }
        let markers = [
            "error", "failed to compile", "cannot find", "is not defined",
            "unexpected token", "syntaxerror", "pre-transform error",
            "[plugin:", "✘", "internal server error",
        ]
        return markers.contains { lower.contains($0) }
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
