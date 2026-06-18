import StormbreakerKit

/// Colorizes a unified diff into themed Style spans for the side pane — mirroring
/// the GUI DiffView's line classification (+ green, - red, @@ hunk, meta faint).
enum DiffRenderer {
    static func lines(_ diff: String, theme: ANSITheme) -> [(String, Style)] {
        diff.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
            let line = String(raw)
            let style: Style
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ")
                || line.hasPrefix("index ") || line.hasPrefix("new file") || line.hasPrefix("deleted") {
                style = theme.on(theme.diffMeta, dim: true)
            } else if line.hasPrefix("@@") {
                style = theme.on(theme.diffHunk)
            } else if line.hasPrefix("+") {
                style = theme.on(theme.diffAdd)
            } else if line.hasPrefix("-") {
                style = theme.on(theme.diffDel)
            } else {
                style = theme.base
            }
            return (line, style)
        }
    }
}
