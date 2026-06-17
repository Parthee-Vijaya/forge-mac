import XCTest
@testable import ForgeKit

/// Covers the pure, side-effect-free helpers. The process-driven methods
/// (status/publish/push/...) are exercised manually against a real repo — they
/// need git/gh + network, so they're out of scope for unit tests.
final class GitServiceTests: XCTestCase {

    // MARK: parseAheadBehind

    func testParseAheadBehindTabSeparated() {
        // `git rev-list --left-right --count @{u}...HEAD` → "behind\tahead"
        let (behind, ahead) = GitService.parseAheadBehind("2\t5")
        XCTAssertEqual(behind, 2)
        XCTAssertEqual(ahead, 5)
    }

    func testParseAheadBehindSpaceSeparated() {
        let (behind, ahead) = GitService.parseAheadBehind("0 3\n")
        XCTAssertEqual(behind, 0)
        XCTAssertEqual(ahead, 3)
    }

    func testParseAheadBehindMalformedIsZero() {
        // No upstream → git writes to stderr; we must not crash or misreport.
        XCTAssertEqual(GitService.parseAheadBehind("fatal: no upstream").behind, 0)
        XCTAssertEqual(GitService.parseAheadBehind("fatal: no upstream").ahead, 0)
        XCTAssertEqual(GitService.parseAheadBehind("").ahead, 0)
        XCTAssertEqual(GitService.parseAheadBehind("7").ahead, 0)
    }

    // MARK: slug

    func testSlugBasic() {
        XCTAssertEqual(GitService.slug("Add login screen"), "add-login-screen")
    }

    func testSlugCollapsesAndTrimsPunctuation() {
        XCTAssertEqual(GitService.slug("  Fix: the (weird) bug!! "), "fix-the-weird-bug")
    }

    func testSlugDanishCharsAndEmptyFallback() {
        // Danish letters are .isLetter → kept (branch names allow them).
        XCTAssertEqual(GitService.slug("Tilføj forside"), "tilføj-forside")
        XCTAssertEqual(GitService.slug("!!!"), "change")
        XCTAssertEqual(GitService.slug(""), "change")
    }

    func testSlugCapsLength() {
        let long = String(repeating: "a", count: 100)
        XCTAssertLessThanOrEqual(GitService.slug(long).count, 40)
    }

    // MARK: firstURL

    func testFirstURLFindsGhOutput() {
        let out = "✓ Created repository Parthee-Vijaya/foo on GitHub\nhttps://github.com/Parthee-Vijaya/foo\n"
        XCTAssertEqual(GitService.firstURL(out), "https://github.com/Parthee-Vijaya/foo")
    }

    func testFirstURLNilWhenAbsent() {
        XCTAssertNil(GitService.firstURL("nothing here"))
    }

    // MARK: ownerRepo

    func testOwnerRepoHTTPS() {
        let r = GitService.ownerRepo("https://github.com/Parthee-Vijaya/forge-mac.git")
        XCTAssertEqual(r?.owner, "Parthee-Vijaya")
        XCTAssertEqual(r?.repo, "forge-mac")
    }

    func testOwnerRepoSSH() {
        let r = GitService.ownerRepo("git@github.com:Parthee-Vijaya/forge-mac.git")
        XCTAssertEqual(r?.owner, "Parthee-Vijaya")
        XCTAssertEqual(r?.repo, "forge-mac")
    }

    func testOwnerRepoNoSuffix() {
        let r = GitService.ownerRepo("https://github.com/foo/bar")
        XCTAssertEqual(r?.owner, "foo")
        XCTAssertEqual(r?.repo, "bar")
    }

    // MARK: GitStatus convenience

    func testGitStatusDerivedFields() {
        var st = GitStatus.none
        XCTAssertFalse(st.hasRemote)
        st.remoteURL = "git@github.com:Parthee-Vijaya/forge-mac.git"
        XCTAssertTrue(st.hasRemote)
        XCTAssertEqual(st.owner, "Parthee-Vijaya")
        XCTAssertEqual(st.repoName, "forge-mac")
    }
}
