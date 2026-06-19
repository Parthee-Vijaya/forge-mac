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

    // MARK: - SSRF guard (H2)

    func testSSRFBlocksInternalTargets() {
        for u in ["http://169.254.169.254/latest/meta-data/",   // cloud metadata
                  "http://localhost:3000", "http://127.0.0.1/x", "http://127.1/x",
                  "https://[::1]/", "http://10.0.0.5", "http://192.168.1.1",
                  "http://172.16.4.4", "http://100.100.100.100",   // Tailscale CGNAT
                  "http://0.0.0.0", "http://server.local", "http://db.internal",
                  "ftp://example.com/x", "file:///etc/passwd"] {   // non-http(s) too
            XCTAssertTrue(WebContent.isBlockedURL(u), "should block: \(u)")
        }
    }

    func testSSRFAllowsPublicTargets() {
        for u in ["https://github.com/x/y", "https://api.duckduckgo.com/?q=swift",
                  "http://93.184.216.34/", "https://example.com"] {   // example.com public IP literal
            XCTAssertFalse(WebContent.isBlockedURL(u), "should allow: \(u)")
        }
    }

    func testSSRFIPv4RangeMath() {
        XCTAssertTrue(WebContent.isBlockedIPv4(WebContent.parseIPv4("169.254.169.254")!))
        XCTAssertTrue(WebContent.isBlockedIPv4(WebContent.parseIPv4("10.255.255.255")!))
        XCTAssertFalse(WebContent.isBlockedIPv4(WebContent.parseIPv4("8.8.8.8")!))
        XCTAssertFalse(WebContent.isBlockedIPv4(WebContent.parseIPv4("172.32.0.1")!))   // just outside 172.16/12
        XCTAssertTrue(WebContent.isBlockedIPv4(WebContent.parseIPv4("172.31.255.255")!))
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

    func testDecodeDDGRedirect() {
        XCTAssertEqual(WebContent.decodeDDGRedirect("//duckduckgo.com/l/?uddg=https%3A%2F%2Fa.com%2Fb&rut=x"),
                       "https://a.com/b")
        XCTAssertEqual(WebContent.decodeDDGRedirect("//example.com/p"), "https://example.com/p")  // protocol-relative
        XCTAssertEqual(WebContent.decodeDDGRedirect("https://direct.com"), "https://direct.com")  // already absolute
    }

    // DDG lite markup: result-link anchors (href before class, single quotes, &amp;) + result-snippet <td>.
    func testParseSearchResults() {
        let html = """
        <a rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Freactrouter.com%2Fdocs&amp;rut=z" class='result-link'>React Router Docs</a>
        <td class='result-snippet'>The official React Router documentation.</td>
        <a rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com&amp;rut=y" class='result-link'>Example &amp; Co</a>
        <td class='result-snippet'>An example &amp; more.</td>
        """
        let results = WebContent.parseSearchResults(html, max: 5)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].title, "React Router Docs")
        XCTAssertEqual(results[0].url, "https://reactrouter.com/docs")    // uddg-decoded
        XCTAssertTrue(results[0].snippet.contains("official"))
        XCTAssertEqual(results[1].url, "https://example.com")
        XCTAssertTrue(results[1].snippet.contains("&"), "HTML entity decoded in snippet")
    }

    // Ads/“more info” links are interleaved — they must be dropped WITHOUT shifting
    // the real result's snippet.
    func testParseSearchResultsSkipsAdsAndKeepsAlignment() {
        let html = """
        <a href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fduckduckgo.com%2Fy.js%3Fad_domain%3Dudemy.com&amp;rut=1" class='result-link'>Sponsored Course</a>
        <a rel="nofollow" class="result-link">more info</a>
        <td class='result-snippet'>Ad snippet.</td>
        <a href="//duckduckgo.com/l/?uddg=https%3A%2F%2Freal.com%2Fa&amp;rut=2" class='result-link'>Real Result</a>
        <td class='result-snippet'>Real snippet here.</td>
        """
        let results = WebContent.parseSearchResults(html, max: 5)
        XCTAssertEqual(results.count, 1, "ad + 'more info' dropped")
        XCTAssertEqual(results[0].url, "https://real.com/a")
        XCTAssertTrue(results[0].snippet.contains("Real snippet"), "snippet stayed aligned with the real result")
    }

    func testParseSearchResultsEmptyOnUnknownMarkup() {
        XCTAssertTrue(WebContent.parseSearchResults("<html><body>no results here</body></html>", max: 5).isEmpty)
    }
}
