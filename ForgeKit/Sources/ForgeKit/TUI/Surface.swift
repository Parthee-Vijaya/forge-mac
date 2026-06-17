/// A composable grid of `Cell`s. Widgets draw into it as pure functions; the whole
/// frame is composed here, then `TUIRenderer.renderDiff` turns (old, new) into the
/// minimal ANSI byte stream. Row-major, `cols * rows` cells.
public final class ScreenBuffer {
    public let size: Size
    public private(set) var cells: [Cell]

    public init(size: Size) {
        self.size = size
        self.cells = Array(repeating: .blank, count: max(0, size.cols * size.rows))
    }

    @inline(__always)
    private func index(_ x: Int, _ y: Int) -> Int? {
        guard x >= 0, y >= 0, x < size.cols, y < size.rows else { return nil }
        return y * size.cols + x
    }

    public subscript(_ x: Int, _ y: Int) -> Cell {
        get { index(x, y).map { cells[$0] } ?? .blank }
        set { if let i = index(x, y) { cells[i] = newValue } }
    }

    /// Reset every cell to a blank of `style`.
    public func clear(_ style: Style = .default) {
        let blank = Cell(" ", style)
        for i in cells.indices { cells[i] = blank }
    }

    /// Fill a rectangle with `ch`.
    public func fill(_ rect: Rect, _ ch: Character = " ", _ style: Style = .default) {
        let w = TextWidth.width(ch)
        var yy = max(0, rect.y)
        while yy < min(size.rows, rect.maxY) {
            var xx = max(0, rect.x)
            while xx < min(size.cols, rect.maxX) {
                self[xx, yy] = Cell(ch, style, width: Int8(w == 2 ? 2 : 1))
                if w == 2, xx + 1 < min(size.cols, rect.maxX) { self[xx + 1, yy] = .continuation(style) }
                xx += max(1, w)
            }
            yy += 1
        }
    }

    /// Draw `string` starting at (x, y), advancing by display width. Wide glyphs
    /// occupy a lead (width 2) + a continuation cell. Clipped to `clip` (or the
    /// whole buffer). Returns the x just past the last cell written.
    @discardableResult
    public func text(_ string: String, x: Int, y: Int, _ style: Style = .default, clip: Rect? = nil) -> Int {
        let region = clip ?? Rect(x: 0, y: 0, w: size.cols, h: size.rows)
        guard region.contains(Point(x: max(x, region.x), y: y)) || (y >= region.y && y < region.maxY) else { return x }
        guard y >= region.y, y < region.maxY else { return x }
        var cx = x
        for ch in string {
            let w = TextWidth.width(ch)
            if w == 0 { continue }                                   // skip zero-width (already in cluster)
            if cx < region.x { cx += w; continue }                   // before clip → advance only
            if cx + w > region.maxX { break }                        // would overflow clip → stop
            self[cx, y] = Cell(ch, style, width: Int8(w))
            if w == 2 { self[cx + 1, y] = .continuation(style) }
            cx += w
        }
        return cx
    }

    /// Draw a box border around `rect` (rounded by default), with an optional title
    /// inset into the top edge.
    public func box(_ rect: Rect, _ style: Style = .default, rounded: Bool = true, title: String? = nil) {
        guard rect.w >= 2, rect.h >= 2 else { return }
        let tl: Character = rounded ? "╭" : "┌"
        let tr: Character = rounded ? "╮" : "┐"
        let bl: Character = rounded ? "╰" : "└"
        let br: Character = rounded ? "╯" : "┘"
        let h: Character = "─", v: Character = "│"
        let x0 = rect.x, y0 = rect.y, x1 = rect.maxX - 1, y1 = rect.maxY - 1
        self[x0, y0] = Cell(tl, style); self[x1, y0] = Cell(tr, style)
        self[x0, y1] = Cell(bl, style); self[x1, y1] = Cell(br, style)
        for xx in (x0 + 1)..<x1 { self[xx, y0] = Cell(h, style); self[xx, y1] = Cell(h, style) }
        for yy in (y0 + 1)..<y1 { self[x0, yy] = Cell(v, style); self[x1, yy] = Cell(v, style) }
        if let title, rect.w > 4 {
            let label = " " + TextWidth.truncate(title, toWidth: rect.w - 4) + " "
            text(label, x: x0 + 2, y: y0, style, clip: rect)
        }
    }
}
