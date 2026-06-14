import Foundation

/// A runtime error captured from the preview WebView's JS bridge
/// (window.onerror / console.error / unhandledrejection). Produced by the app
/// target and fed to `ErrorCollector`.
public struct RuntimeIssue: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case onerror
        case consoleError
        case unhandledRejection
    }

    public let kind: Kind
    public let message: String
    public let source: String?
    public let line: Int?

    public init(kind: Kind, message: String, source: String? = nil, line: Int? = nil) {
        self.kind = kind
        self.message = message
        self.source = source
        self.line = line
    }

    public var displayMessage: String {
        var text = message
        if let source, let line { text += " (\(source):\(line))" }
        else if let source { text += " (\(source))" }
        return text
    }
}
