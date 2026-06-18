import XCTest
@testable import StormbreakerKit

/// Pure render-core tests (Part 3, phase 2): width, surface drawing, and the
/// minimal-diff renderer. No terminal needed — fully deterministic.
final class TUICoreTests: XCTestCase {

    // MARK: - TextWidth

    func testDisplayWidth() {
        XCTAssertEqual(TextWidth.width("a"), 1)
        XCTAssertEqual(TextWidth.width("ab"), 2)
        XCTAssertEqual(TextWidth.width("한"), 2)              // Hangul syllable → wide
        XCTAssertEqual(TextWidth.width("🚀"), 2)             // emoji → wide
        XCTAssertEqual(TextWidth.width("→"), 1)              // U+2192 arrow → narrow
        XCTAssertEqual(TextWidth.width("e\u{0301}"), 1)      // e + combining acute → one column
        XCTAssertEqual(TextWidth.width("日本語"), 6)
    }

    func testTruncate() {
        XCTAssertEqual(TextWidth.truncate("hello", toWidth: 5), "hello")
        XCTAssertEqual(TextWidth.truncate("hello", toWidth: 3), "he…")
        XCTAssertEqual(TextWidth.truncate("hello", toWidth: 0), "")
        // a wide glyph that doesn't fit is dropped wholesale
        XCTAssertEqual(TextWidth.width(TextWidth.truncate("🚀🚀🚀", toWidth: 3)), 3)
    }

    func testWrap() {
        XCTAssertEqual(TextWidth.wrap("the quick brown fox", width: 9), ["the quick", "brown fox"])
        XCTAssertEqual(TextWidth.wrap("supercalifragilistic", width: 5).first, "super")   // hard-break long word
        XCTAssertEqual(TextWidth.wrap("a\nb", width: 9), ["a", "b"])                       // honor newlines
    }

    // MARK: - ScreenBuffer

    func testTextDrawAndWideGlyph() {
        let buf = ScreenBuffer(size: Size(cols: 10, rows: 2))
        buf.text("🚀x", x: 0, y: 0)
        XCTAssertEqual(buf[0, 0].grapheme, "🚀")
        XCTAssertEqual(buf[0, 0].width, 2)
        XCTAssertEqual(buf[1, 0].width, 0)                  // continuation slot reserved
        XCTAssertEqual(buf[2, 0].grapheme, "x")
    }

    func testTextClipsAtRegionEdge() {
        let buf = ScreenBuffer(size: Size(cols: 10, rows: 2))
        let end = buf.text("hello", x: 0, y: 0, clip: Rect(x: 0, y: 0, w: 3, h: 1))
        XCTAssertEqual(end, 3)
        XCTAssertEqual(buf[2, 0].grapheme, "l")
        XCTAssertEqual(buf[3, 0].grapheme, " ")             // clipped — never written
    }

    func testFillAndBox() {
        let buf = ScreenBuffer(size: Size(cols: 6, rows: 4))
        buf.box(Rect(x: 0, y: 0, w: 6, h: 4))
        XCTAssertEqual(buf[0, 0].grapheme, "╭")
        XCTAssertEqual(buf[5, 0].grapheme, "╮")
        XCTAssertEqual(buf[0, 3].grapheme, "╰")
        XCTAssertEqual(buf[5, 3].grapheme, "╯")
    }

    // MARK: - Style → ANSI

    func testStyleANSI() {
        XCTAssertEqual(Style.default.ansi, "\u{1B}[0m")
        XCTAssertTrue(Style(fg: .hex(0xFF0000)).ansi.contains("38;2;255;0;0"))
        XCTAssertTrue(Style(bold: true).ansi.contains(";1"))
    }

    // MARK: - Diff renderer

    func testFullRepaintClearsScreen() {
        let buf = ScreenBuffer(size: Size(cols: 4, rows: 2))
        let bytes = TUIRenderer.renderDiff(old: nil, new: buf)
        let s = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(s.hasPrefix("\u{1B}[2J\u{1B}[H"))     // full clear + home
    }

    func testSingleCellDiffIsMinimal() {
        let old = ScreenBuffer(size: Size(cols: 10, rows: 3))
        let new = ScreenBuffer(size: Size(cols: 10, rows: 3))
        new[2, 1] = Cell("X")
        let s = String(decoding: TUIRenderer.renderDiff(old: old, new: new), as: UTF8.self)
        XCTAssertFalse(s.contains("\u{1B}[2J"))             // no full clear
        XCTAssertTrue(s.contains("\u{1B}[2;3H"))            // cursor to row 2, col 3 (1-based)
        XCTAssertTrue(s.contains("X"))
    }

    func testUnchangedFrameEmitsNoMoves() {
        let old = ScreenBuffer(size: Size(cols: 8, rows: 3))
        let new = ScreenBuffer(size: Size(cols: 8, rows: 3))
        let s = String(decoding: TUIRenderer.renderDiff(old: old, new: new), as: UTF8.self)
        XCTAssertFalse(s.contains("H"))                     // no cursor-position moves at all
    }

    func testSGRCoalescing() {
        let new = ScreenBuffer(size: Size(cols: 4, rows: 1))
        let red = Style(fg: .hex(0xFF0000))
        new[0, 0] = Cell("A", red)
        new[1, 0] = Cell("B", red)                          // same style as neighbour
        let s = String(decoding: TUIRenderer.renderDiff(old: nil, new: new), as: UTF8.self)
        // the red SGR is emitted once for the A+B run, not per cell
        let occurrences = s.components(separatedBy: "38;2;255;0;0").count - 1
        XCTAssertEqual(occurrences, 1)
    }
}
