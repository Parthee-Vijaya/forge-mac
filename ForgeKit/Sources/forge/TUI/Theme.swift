import ForgeKit

// ─────────────────────────────────────────────────────────────────────────────
// ANSITheme (Part 3) — one palette for the whole TUI: a themed background + text,
// chrome accents, TS/JSX syntax colors, and diff colors. Read by the App chrome,
// the syntax colorizer, and the diff renderer; switched with /theme and chosen in
// onboarding. Ships opencode's popular themes (tokyonight/catppuccin/nord/gruvbox)
// alongside Forge's own — plus `mono`, which uses the terminal's own colors.
// ─────────────────────────────────────────────────────────────────────────────

struct ANSITheme: Sendable, Equatable {
    var name: String
    var bg: TermColor          // full-screen background
    var text: TermColor        // default foreground
    var accent: TermColor
    var error: TermColor
    var ok: TermColor
    var warn: TermColor
    var muted: TermColor       // borders, hints, comments
    // Syntax (TS/JSX)
    var keyword: TermColor
    var type: TermColor
    var number: TermColor
    var string: TermColor
    var comment: TermColor
    // Diff
    var diffAdd: TermColor
    var diffDel: TermColor
    var diffHunk: TermColor

    /// A style on the theme background (so text never punches holes in the fill).
    func on(_ fg: TermColor, bold: Bool = false, dim: Bool = false, underline: Bool = false) -> Style {
        Style(fg: fg, bg: bg, bold: bold, dim: dim, underline: underline)
    }
    var base: Style { Style(fg: text, bg: bg) }
    var accentStyle: Style { on(accent) }
    var accentBold: Style { on(accent, bold: true) }
    var dimStyle: Style { on(muted) }
    var errorStyle: Style { on(error) }
    var okStyle: Style { on(ok) }
    var warnStyle: Style { on(warn, bold: true) }
    var diffMeta: TermColor { muted }

    static let midnight = ANSITheme(
        name: "Midnat", bg: .hex(0x0D1117), text: .hex(0xC9D1D9),
        accent: .hex(0x9B87F5), error: .hex(0xF7768E), ok: .hex(0x57B85A), warn: .hex(0xE0A030), muted: .hex(0x6B7180),
        keyword: .hex(0xC792EA), type: .hex(0x82AAFF), number: .hex(0xF78C6C), string: .hex(0xC3E88D), comment: .hex(0x6B7180),
        diffAdd: .hex(0x57B85A), diffDel: .hex(0xF7768E), diffHunk: .hex(0x82AAFF))

    static let tokyonight = ANSITheme(
        name: "Tokyonight", bg: .hex(0x1A1B26), text: .hex(0xC0CAF5),
        accent: .hex(0x7AA2F7), error: .hex(0xF7768E), ok: .hex(0x9ECE6A), warn: .hex(0xE0AF68), muted: .hex(0x565F89),
        keyword: .hex(0xBB9AF7), type: .hex(0x7DCFFF), number: .hex(0xFF9E64), string: .hex(0x9ECE6A), comment: .hex(0x565F89),
        diffAdd: .hex(0x9ECE6A), diffDel: .hex(0xF7768E), diffHunk: .hex(0x7AA2F7))

    static let catppuccin = ANSITheme(
        name: "Catppuccin", bg: .hex(0x1E1E2E), text: .hex(0xCDD6F4),
        accent: .hex(0xCBA6F7), error: .hex(0xF38BA8), ok: .hex(0xA6E3A1), warn: .hex(0xF9E2AF), muted: .hex(0x6C7086),
        keyword: .hex(0xCBA6F7), type: .hex(0x89B4FA), number: .hex(0xFAB387), string: .hex(0xA6E3A1), comment: .hex(0x6C7086),
        diffAdd: .hex(0xA6E3A1), diffDel: .hex(0xF38BA8), diffHunk: .hex(0x89B4FA))

    static let nord = ANSITheme(
        name: "Nord", bg: .hex(0x2E3440), text: .hex(0xD8DEE9),
        accent: .hex(0x88C0D0), error: .hex(0xBF616A), ok: .hex(0xA3BE8C), warn: .hex(0xEBCB8B), muted: .hex(0x616E88),
        keyword: .hex(0x81A1C1), type: .hex(0x8FBCBB), number: .hex(0xB48EAD), string: .hex(0xA3BE8C), comment: .hex(0x616E88),
        diffAdd: .hex(0xA3BE8C), diffDel: .hex(0xBF616A), diffHunk: .hex(0x88C0D0))

    static let gruvbox = ANSITheme(
        name: "Gruvbox", bg: .hex(0x282828), text: .hex(0xEBDBB2),
        accent: .hex(0xFABD2F), error: .hex(0xFB4934), ok: .hex(0xB8BB26), warn: .hex(0xFE8019), muted: .hex(0x928374),
        keyword: .hex(0xFB4934), type: .hex(0xFABD2F), number: .hex(0xD3869B), string: .hex(0xB8BB26), comment: .hex(0x928374),
        diffAdd: .hex(0xB8BB26), diffDel: .hex(0xFB4934), diffHunk: .hex(0x83A598))

    static let light = ANSITheme(
        name: "Lys", bg: .hex(0xF6F8FA), text: .hex(0x24292F),
        accent: .hex(0x6D28D9), error: .hex(0xC2181B), ok: .hex(0x15803D), warn: .hex(0xB45309), muted: .hex(0x9AA0AE),
        keyword: .hex(0x7C3AED), type: .hex(0x2563EB), number: .hex(0xC2410C), string: .hex(0x16A34A), comment: .hex(0x9AA0AE),
        diffAdd: .hex(0x15803D), diffDel: .hex(0xC2181B), diffHunk: .hex(0x2563EB))

    /// Terminal-default colors — the low-color / "respect my terminal" fallback.
    static let mono = ANSITheme(
        name: "Mono", bg: .default, text: .default,
        accent: .default, error: .default, ok: .default, warn: .default, muted: .default,
        keyword: .default, type: .default, number: .default, string: .default, comment: .default,
        diffAdd: .default, diffDel: .default, diffHunk: .default)

    static let all: [ANSITheme] = [.tokyonight, .catppuccin, .nord, .gruvbox, .midnight, .light, .mono]
    static func named(_ n: String) -> ANSITheme? { all.first { $0.name.lowercased() == n.lowercased() } }
}
