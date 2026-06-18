import XCTest
@testable import StormbreakerKit

/// Live network tests for the agent web tool — hits DuckDuckGo + GitHub for real.
/// Gated behind STORM_RUN_INTEGRATION=1 so the normal suite stays offline/fast.
final class WebContentLiveTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["STORM_RUN_INTEGRATION"] == "1",
            "set STORM_RUN_INTEGRATION=1 for live web tests")
    }

    func testSearchReturnsRealResults() async throws {
        let out = await WebContent.search("react router v7 useNavigate", maxResults: 5)
        let text = try XCTUnwrap(out, "search returned nil — endpoint blocked or markup changed")
        XCTAssertTrue(text.contains("http"), "results should include URLs:\n\(text)")
        XCTAssertTrue(text.contains("1."), "results should be numbered:\n\(text)")
        XCTAssertFalse(text.contains("ad_domain"), "ads should be filtered out")
    }

    func testFetchGitHubRepoReadme() async throws {
        let out = await WebContent.fetch("https://github.com/johnbean393/KeyType")
        let text = try XCTUnwrap(out)
        XCTAssertTrue(text.lowercased().contains("autocomplete"), "should read the real README:\n\(text.prefix(200))")
    }
}
