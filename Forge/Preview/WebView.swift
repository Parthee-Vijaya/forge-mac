import SwiftUI
import WebKit
import ForgeKit

/// WKWebView wrapped for SwiftUI. JS bridge: (1) posts window.onerror /
/// console.error / unhandledrejection for self-correction, and (2) a "select
/// mode" that highlights elements on hover and posts the clicked element for
/// visual editing. Bump `reloadToken` to reload.
struct WebView: NSViewRepresentable {
    let url: URL?
    var reloadToken: Int = 0
    var selectMode: Bool = false
    let onRuntimeIssue: (RuntimeIssue) -> Void
    let onElementSelected: (String, String, String, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRuntimeIssue: onRuntimeIssue, onElementSelected: onElementSelected)
    }

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
        webView.setValue(false, forKey: "drawsBackground")
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
        if context.coordinator.selectMode != selectMode {
            context.coordinator.selectMode = selectMode
            webView.evaluateJavaScript("window.__forgeSetSelect && window.__forgeSetSelect(\(selectMode))")
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
        private let onElementSelected: (String, String, String, String) -> Void
        weak var webView: WKWebView?
        var loadedURL: URL?
        var retryCount = 0
        var lastReloadToken = 0
        var selectMode = false

        init(onRuntimeIssue: @escaping (RuntimeIssue) -> Void,
             onElementSelected: @escaping (String, String, String, String) -> Void) {
            self.onRuntimeIssue = onRuntimeIssue
            self.onElementSelected = onElementSelected
        }

        func userContentController(
            _ controller: WKUserContentController, didReceive message: WKScriptMessage
        ) {
            guard message.name == "forge", let body = message.body as? [String: Any] else { return }
            let kind = body["kind"] as? String ?? ""
            if kind == "select" {
                onElementSelected(
                    body["tag"] as? String ?? "element",
                    body["text"] as? String ?? "",
                    body["className"] as? String ?? "",
                    body["selector"] as? String ?? "")
                return
            }
            let issueKind = RuntimeIssue.Kind(rawValue: kind) ?? .consoleError
            onRuntimeIssue(RuntimeIssue(
                kind: issueKind,
                message: body["message"] as? String ?? "Unknown error",
                source: body["source"] as? String,
                line: body["line"] as? Int))
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
            // Re-apply select mode after a (re)load re-injects the bridge.
            webView.evaluateJavaScript("window.__forgeSetSelect && window.__forgeSetSelect(\(selectMode))")
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
        post({ kind: 'unhandledRejection', message: (r.message || String(r)), source: null, line: null });
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

      // Visual select mode
      var selecting = false, hovered = null;
      function classOf(el) { return (typeof el.className === 'string') ? el.className : ''; }
      function selectorOf(el) {
        if (!el || !el.tagName || el === document.body) return 'body';
        var i = 0, sib = el;
        while ((sib = sib.previousElementSibling) != null) i++;
        var parent = el.parentElement ? selectorOf(el.parentElement) : '';
        return parent + '>' + el.tagName.toLowerCase() + ':nth-child(' + (i + 1) + ')';
      }
      document.addEventListener('mouseover', function (e) {
        if (!selecting) return;
        if (hovered) hovered.style.outline = '';
        hovered = e.target;
        e.target.style.outline = '2px solid #2563eb';
        e.target.style.outlineOffset = '-2px';
      }, true);
      document.addEventListener('mouseout', function (e) { if (selecting) e.target.style.outline = ''; }, true);
      document.addEventListener('click', function (e) {
        if (!selecting) return;
        e.preventDefault(); e.stopPropagation();
        var el = e.target;
        post({ kind: 'select', tag: el.tagName.toLowerCase(),
               text: (el.innerText || '').trim().slice(0, 80),
               className: classOf(el), selector: selectorOf(el) });
      }, true);
      window.__forgeSetSelect = function (v) {
        selecting = !!v;
        document.documentElement.style.cursor = v ? 'crosshair' : '';
        if (!v && hovered) { hovered.style.outline = ''; hovered = null; }
      };
    })();
    """
}
