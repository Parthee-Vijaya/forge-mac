import SwiftUI

// B19 — Forge Companion (iOS). A thin client for the Mac's RemoteServer (port 7842):
// poll GET /status, mirror the current project, and show its live dev-server preview
// in a WKWebView over LAN / Tailscale. The Mac host side already exists; this is the
// app that consumes it.
@main
struct ForgeCompanionApp: App {
    var body: some Scene {
        WindowGroup { CompanionView() }
    }
}
