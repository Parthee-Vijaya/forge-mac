import Foundation

/// Throws `ProviderError.http` (carrying the response body) for non-2xx
/// responses, reading the body from the streaming bytes. On success it returns
/// without consuming `bytes`, so the caller can iterate the stream itself.
func ensureOK(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
    guard let http = response as? HTTPURLResponse else {
        throw ProviderError.transport("no HTTP response")
    }
    guard (200..<300).contains(http.statusCode) else {
        var body = ""
        for try await line in SSELineReader(bytes) {
            body += line + "\n"
            if body.count > 2000 { break }
        }
        throw ProviderError.http(status: http.statusCode, body: body)
    }
}
