import XCTest
@testable import StormbreakerKit

/// ReviewAgent parser tests (agentic-SDLC borrow). The model output format is pinned
/// here so the reviewer stays robust to list markers, info-vs-actionable, and noise.
final class ReviewAgentTests: XCTestCase {

    func testParseFindingsAndSummary() {
        let out = """
        warn :: a11y :: src/App.tsx :: knappen mangler aria-label
        critical :: correctness :: src/App.tsx :: nulstil-knappen mangler
        SUMMARY :: et par ting at rette
        """
        let r = ReviewAgent.parse(out)
        XCTAssertEqual(r.findings.count, 2)
        XCTAssertEqual(r.findings[0].severity, .warn)
        XCTAssertEqual(r.findings[0].category, "a11y")
        XCTAssertEqual(r.findings[0].file, "src/App.tsx")
        XCTAssertEqual(r.findings[1].severity, .critical)
        XCTAssertEqual(r.summary, "et par ting at rette")
        XCTAssertFalse(r.isClean)
        XCTAssertEqual(r.actionable.count, 2)
    }

    func testCleanReport() {
        let r = ReviewAgent.parse("SUMMARY :: Ser godt ud.")
        XCTAssertTrue(r.findings.isEmpty)
        XCTAssertTrue(r.isClean)
        XCTAssertEqual(r.summary, "Ser godt ud.")
    }

    func testLenientMarkersDashFileAndInfoNotActionable() {
        let out = """
        - warn :: security :: - :: undgå dangerouslySetInnerHTML
        * info :: correctness :: src/x.tsx :: lille note
        en linje uden skilletegn — ignoreres
        """
        let r = ReviewAgent.parse(out)
        XCTAssertEqual(r.findings.count, 2)
        XCTAssertNil(r.findings[0].file)              // "-" → nil
        XCTAssertEqual(r.findings[1].severity, .info)
        XCTAssertEqual(r.actionable.count, 1)         // only the warn counts as actionable
    }

    func testFixPromptIncludesActionableFindings() {
        let r = ReviewAgent.parse("""
        critical :: correctness :: src/App.tsx :: mangler nulstil-knap
        info :: a11y :: - :: lille ting
        """)
        let p = ReviewAgent.fixPrompt(for: r)
        XCTAssertTrue(p.contains("mangler nulstil-knap"))
        XCTAssertTrue(p.contains("src/App.tsx"))
        XCTAssertFalse(p.contains("lille ting"))      // info isn't auto-fixed
    }
}
