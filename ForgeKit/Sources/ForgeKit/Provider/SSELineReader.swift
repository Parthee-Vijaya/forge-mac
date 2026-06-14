import Foundation

/// A line iterator over `URLSession.AsyncBytes` that PRESERVES blank lines.
///
/// `URLSession.AsyncBytes.lines` silently drops empty lines, which breaks SSE
/// event framing (a blank line terminates an event). We split raw bytes on
/// `\n` ourselves. Works for both SSE (`data:` lines separated by blanks) and
/// NDJSON (one JSON object per line).
struct SSELineReader: AsyncSequence {
    typealias Element = String
    let bytes: URLSession.AsyncBytes

    init(_ bytes: URLSession.AsyncBytes) { self.bytes = bytes }

    func makeAsyncIterator() -> Iterator { Iterator(bytes.makeAsyncIterator()) }

    struct Iterator: AsyncIteratorProtocol {
        private var byteIterator: URLSession.AsyncBytes.AsyncIterator
        private var buffer: [UInt8] = []

        init(_ iterator: URLSession.AsyncBytes.AsyncIterator) {
            self.byteIterator = iterator
        }

        mutating func next() async throws -> String? {
            while let byte = try await byteIterator.next() {
                if byte == 0x0A {                  // newline → emit (possibly empty) line
                    return decodeAndReset()
                }
                buffer.append(byte)
            }
            guard !buffer.isEmpty else { return nil }   // EOF: flush trailing partial line
            return decodeAndReset()
        }

        private mutating func decodeAndReset() -> String {
            var line = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll(keepingCapacity: true)
            if line.hasSuffix("\r") { line.removeLast() }
            return line
        }
    }
}
