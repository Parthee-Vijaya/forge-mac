import Foundation

/// Strips ANSI / VT100 escape sequences (colors, cursor moves, OSC) from
/// terminal output so log lines render cleanly and the ready-detector regex
/// matches reliably.
enum ANSI {
    private static let csi = try! NSRegularExpression(
        pattern: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]"
    )
    private static let osc = try! NSRegularExpression(
        pattern: "\u{001B}\\][^\u{0007}]*(?:\u{0007}|\u{001B}\\\\)"
    )

    static func strip(_ string: String) -> String {
        var out = string
        for regex in [osc, csi] {
            out = regex.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..., in: out),
                withTemplate: ""
            )
        }
        return out
    }
}
