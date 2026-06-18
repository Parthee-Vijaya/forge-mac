import XCTest
@testable import StormbreakerKit

final class ViteReadyDetectorTests: XCTestCase {
    private let detector = ViteReadyDetector()

    func testParsesPlainLocalLine() {
        let url = detector.detect(in: "  ➜  Local:   http://localhost:5173/")
        XCTAssertEqual(url?.absoluteString, "http://localhost:5173")
        XCTAssertEqual(url?.port, 5173)
    }

    func testParsesNonDefaultPort() {
        let url = detector.detect(in: "Local: http://127.0.0.1:5180/")
        XCTAssertEqual(url?.port, 5180)
        XCTAssertEqual(url?.host, "127.0.0.1")
    }

    func testStripsANSIBeforeMatching() {
        let ansi = "\u{1B}[32m  ➜  \u{1B}[1mLocal\u{1B}[22m:   \u{1B}[36mhttp://localhost:5173/\u{1B}[39m"
        XCTAssertEqual(detector.detect(in: ansi)?.port, 5173)
    }

    func testIgnoresUnrelatedLines() {
        XCTAssertNil(detector.detect(in: "  ➜  Network: use --host to expose"))
        XCTAssertNil(detector.detect(in: "VITE v6.0.0  ready in 320 ms"))
        XCTAssertNil(detector.detect(in: ""))
    }
}
