/// Display-width of text in terminal columns. A table-light `wcwidth` approximation:
/// it iterates grapheme clusters (so combining marks / ZWJ emoji are one unit) and
/// measures each by its first scalar. Correct for CJK + the common emoji blocks
/// (the stated bar); a rare cluster off by one self-heals on the next full repaint.
public enum TextWidth {

    /// Columns occupied by one grapheme cluster (0, 1, or 2).
    public static func width(_ ch: Character) -> Int {
        guard let first = ch.unicodeScalars.first else { return 0 }
        return scalarWidth(first)
    }

    /// Columns occupied by a string.
    public static func width(_ s: String) -> Int {
        var total = 0
        for ch in s { total += width(ch) }
        return total
    }

    /// Truncate to at most `maxWidth` columns, appending `ellipsis` if it had to cut.
    public static func truncate(_ s: String, toWidth maxWidth: Int, ellipsis: Character = "…") -> String {
        if maxWidth <= 0 { return "" }
        if width(s) <= maxWidth { return s }
        let ellipsisW = width(ellipsis)
        let budget = max(0, maxWidth - ellipsisW)
        var out = "", used = 0
        for ch in s {
            let w = width(ch)
            if used + w > budget { break }
            out.append(ch); used += w
        }
        out.append(ellipsis)
        return out
    }

    /// Greedy word-wrap to `width` columns. Breaks on spaces; hard-breaks a single
    /// word longer than the line. Preserves no trailing spaces.
    public static func wrap(_ s: String, width maxWidth: Int) -> [String] {
        guard maxWidth > 0 else { return [s] }
        var lines: [String] = []
        for paragraph in s.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = "", lineW = 0
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
                let wordStr = String(word)
                let wordW = width(wordStr)
                if wordW > maxWidth {                       // word longer than the line → hard-break
                    if !line.isEmpty { lines.append(line); line = ""; lineW = 0 }
                    for ch in wordStr {
                        let cw = width(ch)
                        if lineW + cw > maxWidth { lines.append(line); line = ""; lineW = 0 }
                        line.append(ch); lineW += cw
                    }
                    continue
                }
                let sep = line.isEmpty ? 0 : 1
                if lineW + sep + wordW > maxWidth {
                    lines.append(line); line = wordStr; lineW = wordW
                } else {
                    if !line.isEmpty { line.append(" "); lineW += 1 }
                    line.append(wordStr); lineW += wordW
                }
            }
            lines.append(line)
        }
        return lines
    }

    // MARK: - Scalar width table

    static func scalarWidth(_ u: Unicode.Scalar) -> Int {
        let v = u.value
        // Control + zero-width + combining + variation selectors + ZWJ → 0 columns.
        if v < 0x20 || v == 0x7F { return 0 }
        if (0x0300...0x036F).contains(v)        // combining diacritical marks
            || v == 0x200B || v == 0x200D        // ZWSP / ZWJ
            || (0xFE00...0xFE0F).contains(v) {   // variation selectors
            return 0
        }
        // Wide (2 columns): CJK, Hangul, fullwidth forms, and the emoji blocks.
        if isWide(v) { return 2 }
        return 1
    }

    private static func isWide(_ v: UInt32) -> Bool {
        switch v {
        case 0x1100...0x115F,        // Hangul Jamo
             0x2329...0x232A,        // angle brackets
             0x2E80...0x303E,        // CJK radicals … Kangxi … punctuation
             0x3041...0x33FF,        // Hiragana … CJK symbols
             0x3400...0x4DBF,        // CJK Ext A
             0x4E00...0x9FFF,        // CJK Unified
             0xA000...0xA4CF,        // Yi
             0xAC00...0xD7A3,        // Hangul Syllables
             0xF900...0xFAFF,        // CJK Compatibility Ideographs
             0xFE10...0xFE19,        // vertical forms
             0xFE30...0xFE6F,        // CJK compat forms / small forms
             0xFF00...0xFF60,        // Fullwidth forms
             0xFFE0...0xFFE6,        // Fullwidth signs
             0x1F1E6...0x1F1FF,      // regional indicators (flags)
             0x1F300...0x1FAFF,      // emoji: symbols & pictographs … supplemental
             0x1F000...0x1F0FF,      // mahjong / dominoes / playing cards
             0x20000...0x3FFFD:      // CJK Ext B and beyond
            return true
        default:
            return false
        }
    }
}
