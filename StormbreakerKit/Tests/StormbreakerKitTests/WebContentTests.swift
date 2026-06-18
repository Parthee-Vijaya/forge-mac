import XCTest
@testable import StormbreakerKit

final class WebContentTests: XCTestCase {
    func testExtractURLsTrimsTrailingPunctuationAndDedupes() {
        let text = "se https://github.com/johnbean393/KeyType. og igen (https://github.com/johnbean393/KeyType)"
        let urls = WebContent.extractURLs(text)
        XCTAssertEqual(urls, ["https://github.com/johnbean393/KeyType"])  // trailing . and ) trimmed, deduped
    }

    func testExtractURLsMultiple() {
        let urls = WebContent.extractURLs("a http://x.dev/p?q=1 b https://y.io")
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0], "http://x.dev/p?q=1")
    }

    func testExtractURLsNoneInPlainText() {
        XCTAssertTrue(WebContent.extractURLs("byg en tæller-app uden links").isEmpty)
    }

    func testGithubRepoParsing() {
        XCTAssertEqual(WebContent.githubRepo("https://github.com/johnbean393/KeyType")?.owner, "johnbean393")
        XCTAssertEqual(WebContent.githubRepo("https://github.com/johnbean393/KeyType")?.repo, "KeyType")
        XCTAssertEqual(WebContent.githubRepo("https://github.com/a/b.git")?.repo, "b")
        XCTAssertEqual(WebContent.githubRepo("https://github.com/a/b/tree/main/src")?.repo, "b")  // first two path parts
    }

    func testGithubRepoRejectsNonRepo() {
        XCTAssertNil(WebContent.githubRepo("https://example.com/a/b"))
        XCTAssertNil(WebContent.githubRepo("https://github.com/justanowner"))
    }

    func testStripHTML() {
        let html = "<html><head><style>.x{}</style></head><body><h1>Hej</h1><script>bad()</script><p>verden &amp; mere</p></body></html>"
        let text = WebContent.stripHTML(html)
        XCTAssertTrue(text.contains("Hej"))
        XCTAssertTrue(text.contains("verden & mere"))
        XCTAssertFalse(text.contains("bad()"))      // script dropped
        XCTAssertFalse(text.contains(".x{}"))        // style dropped
        XCTAssertFalse(text.contains("<"))           // tags stripped
    }
}
