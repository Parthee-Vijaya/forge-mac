import Foundation

/// A deduplicated set of errors for one self-correction turn.
public struct ErrorReport: Sendable, Equatable {
    public struct Item: Sendable, Equatable, Hashable {
        public enum Source: String, Sendable { case build, runtime }
        public let source: Source
        public let message: String
        public init(source: Source, message: String) {
            self.source = source
            self.message = message
        }
    }

    public var items: [Item]

    public init(items: [Item] = []) { self.items = items }

    public var isClean: Bool { items.isEmpty }

    public func formatted() -> String {
        items.map { "[\($0.source.rawValue)] \($0.message)" }.joined(separator: "\n")
    }

    /// Stable fingerprint (line/column numbers normalized away) used by the
    /// loop's no-progress guard so a repeated error stops the loop.
    public var signature: String {
        items
            .map { $0.message.replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression) }
            .sorted()
            .joined(separator: "|")
    }
}
