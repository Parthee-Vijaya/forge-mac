import XCTest
@testable import ForgeKit

/// Layout solver tests (Part 3, phase 3).
final class TUILayoutTests: XCTestCase {

    func testFixedPlusFlexVertical() {
        let r = splitRects(Rect(x: 0, y: 0, w: 100, h: 10), .vertical, [.fixed(1), .flex, .fixed(1)])
        XCTAssertEqual(r.map { $0.h }, [1, 8, 1])
        XCTAssertEqual(r.map { $0.y }, [0, 1, 9])
        XCTAssertTrue(r.allSatisfy { $0.w == 100 })
    }

    func testRatioHorizontal() {
        let r = splitRects(Rect(x: 0, y: 0, w: 100, h: 10), .horizontal, [.ratio(3), .ratio(2)])
        XCTAssertEqual(r.map { $0.w }, [60, 40])          // 3:2 of 100, last absorbs remainder
        XCTAssertEqual(r.map { $0.x }, [0, 60])
    }

    func testTinyTerminalClampsNonNegative() {
        let r = splitRects(Rect(x: 0, y: 0, w: 10, h: 3), .vertical,
                           [.fixed(1), .fixed(1), .fixed(1), .fixed(5)])
        XCTAssertTrue(r.allSatisfy { $0.h >= 0 })          // never negative
        XCTAssertLessThanOrEqual(r.reduce(0) { $0 + $1.h }, 3)
    }

    func testForgeLayoutStandard() {
        let l = ForgeLayout.compute(Size(cols: 80, rows: 24))
        XCTAssertEqual(l.header.h, 1)
        XCTAssertEqual(l.header.y, 0)
        XCTAssertEqual(l.status.h, 1)
        XCTAssertEqual(l.input.y, 23)
        XCTAssertEqual(l.transcript.y, 1)
        XCTAssertEqual(l.transcript.h, 21)                 // body fills the middle
        XCTAssertGreaterThan(l.transcript.w, l.side.w)     // 3:2 → transcript wider
        XCTAssertGreaterThan(l.side.w, 0)                  // side shown at 80 cols
        XCTAssertEqual(l.transcript.maxX, l.side.x)        // panes are adjacent, no gap
    }

    func testForgeLayoutNarrowCollapsesSide() {
        let l = ForgeLayout.compute(Size(cols: 50, rows: 24))
        XCTAssertEqual(l.side.w, 0)                        // collapsed below 60 cols
        XCTAssertEqual(l.transcript.w, 50)                 // transcript takes everything
    }

    func testSlashAnchorSitsAboveInput() {
        let l = ForgeLayout.compute(Size(cols: 80, rows: 24))
        XCTAssertLessThanOrEqual(l.slashAnchor.maxY, l.input.y)
        XCTAssertEqual(l.slashAnchor.x, l.transcript.x)
    }
}
