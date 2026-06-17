import ForgeKit

/// Colorizes a unified diff into themed Style spans for the side pane — mirroring
/// the GUI DiffView's line classification (+ green, - red, @@ hunk, meta faint).
enum DiffRenderer {
    static func lines(_ diff: String, theme: ANSITheme) -> [(String, Style)] {
        diff.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
            let line = String(raw)
            let style: Style
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ")
                || line.hasPrefix("index ") || line.hasPrefix("new file") || line.hasPrefix("deleted") {
                style = Style(fg: theme.diffMeta, dim: true)
            } else if line.hasPrefix("@@") {
                style = Style(fg: theme.diffHunk)
            } else if line.hasPrefix("+") {
                style = Style(fg: theme.diffAdd)
            } else if line.hasPrefix("-") {
                style = Style(fg: theme.diffDel)
            } else {
                style = .default
            }
            return (line, style)
        }
    }
}
