import SwiftUI
import WebKit

/// Renders the Mac's live dev-server preview. Reloads only when the host/port
/// changes (a new project/port) — never on in-app SPA path changes, so navigating
/// inside the previewed app doesn't trigger a reload loop.
struct PreviewWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.isOpaque = false
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let current = web.url
        if current?.host != url.host || current?.port != url.port {
            web.load(URLRequest(url: url))
        }
    }
}
