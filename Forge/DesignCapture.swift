import AppKit
import WebKit

/// Loads a URL in an offscreen WKWebView and snapshots it to an image, so Forge
/// can "copy this design" from a link the same way it does from an uploaded
/// screenshot (the snapshot rides the existing image → UI pipeline).
@MainActor
final class DesignCapture: NSObject, WKNavigationDelegate {
    enum CaptureError: Error { case failed, timedOut }

    private var window: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<NSImage, Error>?
    private var finished = false

    /// Render `url` and return a snapshot. Throws on load failure / timeout.
    func capture(_ url: URL, timeout: Duration = .seconds(22)) async throws -> NSImage {
        let size = NSSize(width: 1280, height: 900)
        let webView = WKWebView(frame: NSRect(origin: .zero, size: size))
        webView.navigationDelegate = self
        // Host in an offscreen window so WebKit lays out + paints before snapshot.
        let window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderFrontRegardless()
        self.window = window
        self.webView = webView

        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            self.finish(nil, error: CaptureError.timedOut)
        }
        defer { timeoutTask.cancel() }

        webView.load(URLRequest(url: url))
        return try await withCheckedThrowingContinuation { self.continuation = $0 }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            await self.settleForSnapshot(webView)
            guard !self.finished else { return }
            webView.takeSnapshot(with: WKSnapshotConfiguration()) { [weak self] image, error in
                Task { @MainActor in self?.finish(image, error: error) }
            }
        }
    }

    /// Marketing sites commonly fade their hero/sections in via IntersectionObserver
    /// on scroll, so a bare wait snapshots a half-empty page. Scroll to the bottom
    /// and back to the top to trigger those entrance animations + lazy images, then
    /// let it settle (and fonts paint) before snapshotting. (`; true` so the async
    /// evaluateJavaScript doesn't surface a nil-result error for the void call.)
    private func settleForSnapshot(_ webView: WKWebView) async {
        try? await Task.sleep(for: .milliseconds(700))
        _ = try? await webView.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight); true")
        try? await Task.sleep(for: .milliseconds(1000))
        _ = try? await webView.evaluateJavaScript("window.scrollTo(0, 0); true")
        try? await Task.sleep(for: .milliseconds(1600))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil, error: error)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil, error: error)
    }

    private func finish(_ image: NSImage?, error: Error?) {
        guard !finished else { return }
        finished = true
        window?.orderOut(nil)
        window = nil
        webView = nil
        if let image, image.size.width > 1 {
            continuation?.resume(returning: image)
        } else {
            continuation?.resume(throwing: error ?? CaptureError.failed)
        }
        continuation = nil
    }
}
