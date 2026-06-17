import Foundation
import ForgeKit
#if canImport(Darwin)
import Darwin
#endif

// ─────────────────────────────────────────────────────────────────────────────
// The TUI event loop (Part 3, phase 5). One @MainActor owner of all UI state,
// consuming a single merged stream of input + resize + tick events. Widgets are
// pure (state, Rect) → draws into a ScreenBuffer; one render pass per event,
// throttled to ~60fps. Phase 6 attaches the agent stream + permission modal.
// ─────────────────────────────────────────────────────────────────────────────

/// Everything the loop reacts to. (`.agent`/`.permission` join in phase 6.)
enum AppEvent: Sendable {
    case key(Key)
    case resize(Size)
    case tick
}

/// Read the current terminal size (Sendable free function — safe from the SIGWINCH
/// handler on any queue).
func currentTerminalSize() -> Size {
    var ws = winsize()
    if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0, ws.ws_row > 0, ws.ws_col > 0 {
        return Size(cols: Int(ws.ws_col), rows: Int(ws.ws_row))
    }
    return Size(cols: 80, rows: 24)
}

@MainActor
final class TUIApp {
    struct Line { enum Role { case user, assistant, system }; var role: Role; var text: String }

    // Palette (generalized into ANSITheme in phase 7).
    private let accent = Style(fg: .hex(0x9B87F5))
    private let accentBold = Style(fg: .hex(0x9B87F5), bold: true)
    private let dimStyle = Style(dim: true)

    private let subtitle: String
    private var size: Size
    private var prev: ScreenBuffer?

    private var transcript: [Line] = []
    private var input = ""
    private var cursor = 0                    // char index within `input`
    private var scroll = 0                    // visual lines scrolled up from the bottom
    private var sideTitle = "Info"
    private var status = "Klar."
    private var running = true
    private var needsRender = true
    private var lastRender = DispatchTime.now()
    private var channel: AsyncStream<AppEvent>.Continuation?
    private var winch: DispatchSourceSignal?

    init(size: Size, subtitle: String = "demo") {
        self.subtitle = subtitle
        self.size = size
        transcript.append(Line(role: .system, text: "forge TUI — skriv noget og tryk Enter. Tab skifter panel · Ctrl-C afslutter."))
    }

    func run() async {
        let (stream, cont) = AsyncStream.makeStream(of: AppEvent.self, bufferingPolicy: .bufferingNewest(256))
        channel = cont
        let keyTask = Task { for await k in StdinReader().keys() { cont.yield(.key(k)) } }
        let tickTask = Task {
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)); cont.yield(.tick) }
        }
        signal(SIGWINCH, SIG_IGN)
        let ws = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .global())
        ws.setEventHandler { cont.yield(.resize(currentTerminalSize())) }
        ws.resume()
        winch = ws
        defer { keyTask.cancel(); tickTask.cancel(); ws.cancel(); cont.finish() }

        render(force: true)
        for await ev in stream {
            switch ev {
            case .key(let k):    handle(k)
            case .resize(let s): size = s; prev = nil; needsRender = true
            case .tick:          break
            }
            if !running { break }
            if needsRender { render() }
        }
    }

    // MARK: - Input handling

    private func handle(_ key: Key) {
        switch key {
        case .ctrl("c"):
            running = false
        case .char(let c):
            input.insert(c, at: input.index(input.startIndex, offsetBy: cursor)); cursor += 1; needsRender = true
        case .backspace:
            if cursor > 0 { input.remove(at: input.index(input.startIndex, offsetBy: cursor - 1)); cursor -= 1; needsRender = true }
        case .delete:
            if cursor < input.count { input.remove(at: input.index(input.startIndex, offsetBy: cursor)); needsRender = true }
        case .left:  if cursor > 0 { cursor -= 1; needsRender = true }
        case .right: if cursor < input.count { cursor += 1; needsRender = true }
        case .home:  cursor = 0; needsRender = true
        case .end:   cursor = input.count; needsRender = true
        case .up:    scroll += 1; needsRender = true
        case .down:  scroll = max(0, scroll - 1); needsRender = true
        case .pageUp:   scroll += max(1, bodyHeight - 1); needsRender = true
        case .pageDown: scroll = max(0, scroll - max(1, bodyHeight - 1)); needsRender = true
        case .tab:   sideTitle = sideTitle == "Info" ? "Kode" : "Info"; needsRender = true
        case .enter: submit()
        default: break
        }
    }

    /// Phase-5 placeholder turn: echo. Phase 6 replaces this with the AgentLoop.
    private func submit() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        transcript.append(Line(role: .user, text: text))
        transcript.append(Line(role: .assistant, text: "Du skrev: \(text)"))
        input = ""; cursor = 0; scroll = 0; status = "Klar."; needsRender = true
    }

    private var bodyHeight: Int { max(1, size.rows - 3) }

    // MARK: - Rendering

    private func render(force: Bool = false) {
        let now = DispatchTime.now()
        if !force {
            let ms = Double(now.uptimeNanoseconds &- lastRender.uptimeNanoseconds) / 1_000_000
            if ms < 16 { needsRender = true; return }     // throttle to ~60fps; a tick flushes the rest
        }
        lastRender = now
        needsRender = false

        let layout = ForgeLayout.compute(size)
        let buf = ScreenBuffer(size: size)

        // Header
        buf.fill(layout.header, " ", dimStyle)
        let head = "⬢ forge"
        var hx = buf.text(head, x: layout.header.x, y: layout.header.y, accentBold)
        hx = buf.text("  ·  \(subtitle)", x: hx, y: layout.header.y, dimStyle)

        // Transcript
        let vis = transcriptVisualLines(width: max(1, layout.transcript.w))
        let h = layout.transcript.h
        let maxScroll = max(0, vis.count - h)
        if scroll > maxScroll { scroll = maxScroll }
        let start = max(0, vis.count - h - scroll)
        for i in 0..<min(h, max(0, vis.count - start)) {
            let (txt, st) = vis[start + i]
            buf.text(txt, x: layout.transcript.x, y: layout.transcript.y + i, st, clip: layout.transcript)
        }

        // Side pane
        if !layout.side.isEmpty {
            buf.box(layout.side, dimStyle, title: sideTitle)
            buf.text("(Tab skifter panel)", x: layout.side.x + 2, y: layout.side.y + 2, dimStyle, clip: layout.side)
        }

        // Status bar
        buf.fill(layout.status, " ", dimStyle)
        buf.text(status, x: layout.status.x, y: layout.status.y, dimStyle)
        let hint = "^C afslut · Tab panel · ↑↓ scroll"
        let hintX = max(layout.status.x, layout.status.maxX - TextWidth.width(hint))
        buf.text(hint, x: hintX, y: layout.status.y, dimStyle, clip: layout.status)

        // Input line
        let prompt = "› "
        buf.text(prompt, x: layout.input.x, y: layout.input.y, accent)
        buf.text(input, x: layout.input.x + TextWidth.width(prompt), y: layout.input.y, .default, clip: layout.input)

        // Cursor in the input field
        let before = String(input.prefix(cursor))
        let curX = min(layout.input.x + TextWidth.width(prompt) + TextWidth.width(before), layout.input.maxX - 1)
        let cursorPt = Point(x: curX, y: layout.input.y)

        TUIOutput.emit(TUIRenderer.renderDiff(old: prev, new: buf, cursor: cursorPt))
        prev = buf
    }

    private func transcriptVisualLines(width: Int) -> [(String, Style)] {
        var out: [(String, Style)] = []
        for line in transcript {
            let style: Style
            let prefix: String
            switch line.role {
            case .user:      style = accentBold; prefix = "› "
            case .assistant: style = .default;   prefix = ""
            case .system:    style = dimStyle;   prefix = "· "
            }
            for w in TextWidth.wrap(prefix + line.text, width: width) { out.append((w, style)) }
            if line.role == .assistant { out.append(("", .default)) }   // spacer between turns
        }
        return out
    }
}
