/// Terminal dimensions in character cells.
public struct Size: Sendable, Equatable {
    public var cols: Int
    public var rows: Int
    public init(cols: Int, rows: Int) { self.cols = cols; self.rows = rows }
}

/// A 0-based cell coordinate (x = column, y = row).
public struct Point: Sendable, Equatable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

/// A rectangular region of the screen, in cells. Origin top-left.
public struct Rect: Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var w: Int
    public var h: Int
    public init(x: Int, y: Int, w: Int, h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }

    public var isEmpty: Bool { w <= 0 || h <= 0 }
    public var maxX: Int { x + w }
    public var maxY: Int { y + h }

    public func contains(_ p: Point) -> Bool {
        p.x >= x && p.x < maxX && p.y >= y && p.y < maxY
    }

    /// Shrink on all sides by `d` (clamped at zero).
    public func inset(_ d: Int) -> Rect {
        Rect(x: x + d, y: y + d, w: max(0, w - 2 * d), h: max(0, h - 2 * d))
    }
}
