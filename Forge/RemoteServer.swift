import Foundation
import Network

/// B19 (host side): a tiny HTTP server the iOS companion app polls over LAN /
/// Tailscale to mirror the Mac's current project — its name, framework and live
/// dev-server preview URL. AppModel pushes a status snapshot whenever it changes;
/// the listener serves that snapshot (a pre-rendered JSON string), so connection
/// handlers never touch @MainActor state. Bound to 0.0.0.0:<port> so a phone on the
/// same network (or Tailscale) can reach it.
///
/// START: the host serves GET /status (+ /health). The SwiftUI iOS app target that
/// consumes it — load the previewURL in a WKWebView, send prompts back — is the
/// remaining XL piece.
final class RemoteServer: @unchecked Sendable {
    private let port: UInt16
    private var listener: NWListener?
    private let lock = NSLock()
    private var statusJSON = "{}"
    private(set) var isRunning = false

    init(port: UInt16 = 7842) { self.port = port }

    /// Update the snapshot served at /status (called from AppModel on the main actor).
    func setStatus(_ object: [String: Any]) {
        let json = (try? JSONSerialization.data(withJSONObject: object))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        lock.lock(); statusJSON = json; lock.unlock()
    }

    private func currentStatus() -> String {
        lock.lock(); defer { lock.unlock() }; return statusJSON
    }

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            listener.start(queue: .global(qos: .utility))
            self.listener = listener
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { connection.cancel(); return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let path = Self.requestPath(request)
            let body: String
            switch path {
            case "/status": body = self.currentStatus()
            case "/health": body = #"{"ok":true}"#
            default: body = #"{"error":"not found"}"#
            }
            let status = (path == "/status" || path == "/health") ? "200 OK" : "404 Not Found"
            let bodyData = Data(body.utf8)
            let headers = "HTTP/1.1 \(status)\r\n"
                + "Content-Type: application/json; charset=utf-8\r\n"
                + "Access-Control-Allow-Origin: *\r\n"
                + "Content-Length: \(bodyData.count)\r\n"
                + "Connection: close\r\n\r\n"
            connection.send(content: Data(headers.utf8) + bodyData,
                            completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// Extract the path from an HTTP request line ("GET /status HTTP/1.1").
    private static func requestPath(_ request: String) -> String {
        guard let line = request.split(whereSeparator: \.isNewline).first else { return "/" }
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        return String(parts[1].split(separator: "?").first ?? "/")
    }
}
