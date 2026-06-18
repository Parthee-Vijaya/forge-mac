/// SGR (Select Graphic Rendition) encoding for a style.
extension Style {
    /// A canonical, self-contained ANSI sequence: reset, then this style's attrs +
    /// truecolor fg/bg. `.default` collapses to a plain reset.
    public var ansi: String {
        if self == .default { return "\u{1B}[0m" }
        var s = "\u{1B}[0"
        if bold { s += ";1" }
        if dim { s += ";2" }
        if underline { s += ";4" }
        if reverse { s += ";7" }
        if fg.isDefault { s += ";39" } else { s += ";38;2;\(fg.r);\(fg.g);\(fg.b)" }
        if bg.isDefault { s += ";49" } else { s += ";48;2;\(bg.r);\(bg.g);\(bg.b)" }
        s += "m"
        return s
    }
}

/// Turns two frames into the minimal ANSI to repaint. This is what keeps the TUI
/// flicker-free: only changed cell-runs are emitted (with SGR coalescing), and the
/// whole result is written with one write(2) by the caller.
public enum TUIRenderer {

    /// Emit the bytes that transform `old` into `new`. If `old` is nil or differs in
    /// size, do a full clear + repaint. `cursor` (if given) leaves the hardware cursor
    /// shown at that cell (e.g. the input caret); otherwise the cursor stays hidden.
    public static func renderDiff(old: ScreenBuffer?, new: ScreenBuffer, cursor: Point? = nil) -> [UInt8] {
        var out: [UInt8] = []
        func push(_ s: String) { out.append(contentsOf: s.utf8) }

        let full = (old == nil) || old!.size != new.size
        if full { push("\u{1B}[2J\u{1B}[H") }

        var active: Style? = nil
        for y in 0..<new.size.rows {
            // Find the first and last column that changed on this row.
            var first = -1, last = -1
            for x in 0..<new.size.cols {
                let changed = full || new[x, y] != old![x, y]
                if changed { if first < 0 { first = x }; last = x }
            }
            if first < 0 { continue }                              // row unchanged → emit nothing

            push("\u{1B}[\(y + 1);\(first + 1)H")                  // cursor to first changed cell
            var x = first
            while x <= last {
                let c = new[x, y]
                if c.width == 0 { x += 1; continue }               // continuation slot of a wide glyph
                if active != c.style { push(c.style.ansi); active = c.style }
                push(String(c.grapheme))
                x += (c.width == 2 ? 2 : 1)
            }
        }

        push("\u{1B}[0m")
        if let cursor { push("\u{1B}[\(cursor.y + 1);\(cursor.x + 1)H\u{1B}[?25h") }
        else { push("\u{1B}[?25l") }
        return out
    }
}
