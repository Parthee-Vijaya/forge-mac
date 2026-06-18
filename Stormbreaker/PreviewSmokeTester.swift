import AppKit
import WebKit
import StormbreakerKit

/// Functional smoke test for a freshly-built app. Loads the running preview in an
/// OFFSCREEN WKWebView and auto-exercises the UI — types into inputs, presses
/// Enter, clicks buttons — while capturing runtime errors via the SAME JS bridge
/// the live preview uses (`WebView.bridgeJS`). This surfaces interaction-triggered
/// crashes that the static gates (build logs, tsc/vue-tsc/svelte-check) and a
/// passive render can't see: a handler that throws, a bad state update, an
/// undefined access on click.
///
/// Isolated by design:
/// - a **non-persistent** data store, so the smoke test's typing/clicking writes
///   to its own ephemeral localStorage and never pollutes the user's real preview;
/// - offscreen, so the visible preview isn't disturbed;
/// - never throws — a preview that won't load just yields no issues.
@MainActor
final class PreviewSmokeTester: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var issues: [RuntimeIssue] = []
    private var continuation: CheckedContinuation<[RuntimeIssue], Never>?
    private var finished = false

    /// Render `url` offscreen, drive the auto-interaction script, and return any
    /// runtime issues observed. Resolves when the script signals completion or
    /// `timeout` elapses, whichever comes first.
    func run(_ url: URL, timeout: Duration = .seconds(15)) async -> [RuntimeIssue] {
        let size = NSSize(width: 1100, height: 820)
        let controller = WKUserContentController()
        controller.add(self, name: "storm")
        // Same error bridge as the live preview, plus the interaction driver.
        controller.addUserScript(WKUserScript(
            source: WebView.bridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(
            source: Self.smokeJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        // Ephemeral store: the smoke test's localStorage writes stay isolated from
        // the user's visible preview (same origin would otherwise share it).
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: configuration)
        webView.navigationDelegate = self
        let window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderFrontRegardless()
        self.window = window
        self.webView = webView

        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            self.finish()
        }
        defer { timeoutTask.cancel() }

        webView.load(URLRequest(url: url))
        return await withCheckedContinuation { self.continuation = $0 }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "storm", message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any] else { return }
        let kind = body["kind"] as? String ?? ""
        if kind == "smokeDone" { finish(); return }   // interaction script finished
        if kind == "select" { return }                // visual-select events are irrelevant here
        let issueKind = RuntimeIssue.Kind(rawValue: kind) ?? .consoleError
        issues.append(RuntimeIssue(
            kind: issueKind,
            message: body["message"] as? String ?? "Unknown error",
            source: body["source"] as? String,
            line: body["line"] as? Int))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        window?.orderOut(nil)
        window = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "storm")
        webView = nil
        continuation?.resume(returning: issues)
        continuation = nil
    }

    /// Runs after document load: waits for the app to mount, then exercises it.
    /// Wrapped so the driver itself never throws uncaught — only the app's own
    /// errors should reach the bridge. Neutralizes blocking dialogs (alert /
    /// confirm / prompt) so an offscreen run can't hang. Posts `smokeDone` when
    /// finished so the Swift side resolves immediately instead of waiting out the
    /// timeout.
    static let smokeJS = """
    (function () {
      try { window.alert = function(){}; window.confirm = function(){return false}; window.prompt = function(){return null}; } catch (e) {}
      function sleep(ms){ return new Promise(function(r){ setTimeout(r, ms); }); }
      function fire(el, type, init){
        try {
          var Ctor = (type.indexOf('key') === 0) ? KeyboardEvent : Event;
          el.dispatchEvent(new Ctor(type, Object.assign({ bubbles: true }, init || {})));
        } catch (e) {}
      }
      // React/Vue/Svelte track value via the native setter — set through it so the
      // framework sees the change, then fire input/change.
      function setValue(el, val){
        try {
          var proto = (el.tagName === 'TEXTAREA') ? window.HTMLTextAreaElement.prototype
                                                   : window.HTMLInputElement.prototype;
          var setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
          setter.call(el, val);
        } catch (e) { try { el.value = val; } catch (_) {} }
        fire(el, 'input'); fire(el, 'change');
      }
      async function run(){
        await sleep(450); // let the app mount
        try {
          var inputs = Array.prototype.slice.call(document.querySelectorAll(
            'input:not([type=checkbox]):not([type=radio]):not([type=file]):not([type=submit]):not([disabled]), textarea')).slice(0, 12);
          for (var i = 0; i < inputs.length; i++){
            var el = inputs[i]; if (!el) continue;
            try { el.focus(); } catch (e) {}
            setValue(el, 'Smoke ' + (i + 1));
            fire(el, 'keydown', { key: 'Enter', keyCode: 13, which: 13 });
            fire(el, 'keyup',   { key: 'Enter', keyCode: 13, which: 13 });
            await sleep(70);
          }
          var buttons = Array.prototype.slice.call(document.querySelectorAll(
            'button:not([disabled]), [role=button]')).slice(0, 30);
          for (var j = 0; j < buttons.length; j++){
            try { buttons[j].click(); } catch (e) {}
            await sleep(55);
          }
        } catch (e) { /* surfaced via window.onerror */ }
        await sleep(300); // let async handlers settle / throw
        try { window.webkit.messageHandlers.storm.postMessage({ kind: 'smokeDone' }); } catch (e) {}
      }
      if (document.readyState !== 'loading') run();
      else document.addEventListener('DOMContentLoaded', run);
    })();
    """
}
