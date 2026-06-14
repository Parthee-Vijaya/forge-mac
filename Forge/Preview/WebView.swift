import SwiftUI
import WebKit
import ForgeKit

/// WKWebView (not the new SwiftUI WebView/WebPage, which lacks
/// WKScriptMessageHandler) wrapped for SwiftUI, with a JS bridge that posts
/// window.onerror / console.error / unhandledrejection back to the app for the
/// self-correction loop. Bump `reloadToken` to force a reload.
struct WebView: NSViewRepresentable {
    let url: URL?
    var reloadToken: Int = 0
    let onRuntimeIssue: (RuntimeIssue) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onRuntimeIssue: onRuntimeIssue) }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "forge")
        controller.addUserScript(WKUserScript(
            source: Self.bridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isInspectable = true
        webView.setValue(false, forKey: "drawsBackground") // avoid white flash before load
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let url else { return }
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            context.coordinator.retryCount = 0
            webView.load(URLRequest(url: url))
        } else if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            webView.reload()
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "forge")
        controller.removeAllUserScripts()
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let onRuntimeIssue: (RuntimeIssue) -> Void
        weak var webView: WKWebView?
        var loadedURL: URL?
        var retryCount = 0
        var lastReloadToken = 0

        init(onRuntimeIssue: @escaping (RuntimeIssue) -> Void) {
            self.onRuntimeIssue = onRuntimeIssue
        }

        func userContentController(
            _ controller: WKUserContentController, didReceive message: WKScriptMessage
        ) {
            guard message.name == "forge", let body = message.body as? [String: Any] else { return }
            let kind = RuntimeIssue.Kind(rawValue: body["kind"] as? String ?? "") ?? .consoleError
            let issue = RuntimeIssue(
                kind: kind,
                message: body["message"] as? String ?? "Unknown error",
                source: body["source"] as? String,
                line: body["line"] as? Int)
            onRuntimeIssue(issue)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
        ) {
            guard retryCount < 4, let url = loadedURL else { return }
            retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak webView] in
                webView?.load(URLRequest(url: url))
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            retryCount = 0
        }
    }

    static let bridgeJS = """
    (function () {
      function post(payload) {
        try { window.webkit.messageHandlers.forge.postMessage(payload); } catch (e) {}
      }
      window.addEventListener('error', function (e) {
        post({ kind: 'onerror',
               message: (e && e.message) ? e.message : String(e),
               source: (e && e.filename) ? e.filename : null,
               line: (e && e.lineno) ? e.lineno : null });
      }, true);
      window.addEventListener('unhandledrejection', function (e) {
        var r = (e && e.reason) || {};
        post({ kind: 'unhandledRejection',
               message: (r.message || String(r)), source: null, line: null });
      });
      var original = console.error;
      console.error = function () {
        try {
          post({ kind: 'consoleError',
                 message: Array.prototype.map.call(arguments, String).join(' '),
                 source: null, line: null });
        } catch (_) {}
        return original.apply(console, arguments);
      };
    })();
    """
}
