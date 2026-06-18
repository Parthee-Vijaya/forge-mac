import StormbreakerKit

/// Colorizes one line of TS/JSX source into styled segments for the ScreenBuffer,
/// using the shared `SyntaxRules` patterns + the active theme. Per-line (good
/// enough for the live-write side pane). Powers phase-8 streaming highlight.
enum ANSIColorizer {
    static func spans(_ line: String, theme: ANSITheme) -> [(String, Style)] {
        let chars = Array(line)
        guard !chars.isEmpty else { return [] }
        let map = SyntaxRules.classify(line)
        var out: [(String, Style)] = []
        var i = 0
        while i < chars.count {
            let tok = i < map.count ? map[i] : nil
            var seg = String(chars[i])
            var j = i + 1
            while j < chars.count, (j < map.count ? map[j] : nil) == tok {
                seg.append(chars[j]); j += 1
            }
            out.append((seg, style(for: tok, theme: theme)))
            i = j
        }
        return out
    }

    static func style(for token: SyntaxRules.Token?, theme: ANSITheme) -> Style {
        switch token {
        case .keyword: return theme.on(theme.keyword)
        case .type:    return theme.on(theme.type)
        case .number:  return theme.on(theme.number)
        case .string:  return theme.on(theme.string)
        case .comment: return theme.on(theme.comment, dim: true)
        case nil:      return theme.base
        }
    }
}
