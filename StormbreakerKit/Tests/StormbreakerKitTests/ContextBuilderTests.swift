import XCTest
@testable import StormbreakerKit

final class ContextBuilderTests: XCTestCase {

    private func reader(_ map: [String: String]) -> (String) async -> String? {
        { path in map[path] }
    }

    // MARK: - Helpers

    func testEstimateTokens() {
        XCTAssertEqual(ContextBuilder.estimateTokens(String(repeating: "x", count: 400)), 100)
        XCTAssertEqual(ContextBuilder.estimateTokens(""), 1)
    }

    func testPrioritizePutsTouchedThenEntryFirst() {
        let files = ["src/App.tsx", "src/main.tsx", "src/components/Foo.tsx", "src/lib/util.ts"]
        let order = ContextBuilder.prioritize(files: files, touched: ["src/components/Foo.tsx"])
        XCTAssertEqual(order.first, "src/components/Foo.tsx")           // touched wins
        XCTAssertEqual(order[1], "src/App.tsx")                         // then entry point
        XCTAssertEqual(Set(order), Set(files))                         // all included, deduped
    }

    func testPrioritizeIgnoresUnknownTouched() {
        let files = ["src/App.tsx"]
        let order = ContextBuilder.prioritize(files: files, touched: ["src/Ghost.tsx"])
        XCTAssertEqual(order, ["src/App.tsx"])
    }

    func testIsSourceAndLang() {
        XCTAssertTrue(ContextBuilder.isSource("src/App.tsx"))
        XCTAssertFalse(ContextBuilder.isSource("package.json"))
        XCTAssertEqual(ContextBuilder.lang("a.tsx"), "tsx")
        XCTAssertEqual(ContextBuilder.lang("a.css"), "css")
    }

    // MARK: - build()

    func testEmptyFilesReturnsNil() async {
        let result = await ContextBuilder().build(files: [], touched: [], read: reader([:]))
        XCTAssertNil(result)
    }

    func testIncludesTouchedFileBeforeEntry() async {
        let files = ["src/App.tsx", "src/components/Hero.tsx"]
        let map = ["src/App.tsx": "export default function App(){}",
                   "src/components/Hero.tsx": "export const Hero = () => null"]
        let out = await ContextBuilder().build(files: files, touched: ["src/components/Hero.tsx"], read: reader(map))
        let unwrapped = try? XCTUnwrap(out)
        let hero = unwrapped?.range(of: "src/components/Hero.tsx:")
        let app = unwrapped?.range(of: "src/App.tsx:\n```")
        XCTAssertNotNil(hero)
        XCTAssertNotNil(app)
        // Hero (touched) inlined before App.
        XCTAssertTrue(hero!.lowerBound < app!.lowerBound)
    }

    func testBudgetLimitsIncludedFiles() async {
        // Two ~100-token files; budget only fits one.
        let big = String(repeating: "a", count: 400)   // ~100 tokens
        let files = ["src/App.tsx", "src/Other.tsx"]
        let map = ["src/App.tsx": big, "src/Other.tsx": big]
        let out = await ContextBuilder(tokenBudget: 120).build(files: files, touched: [], read: reader(map))
        let body = out ?? ""
        // App.tsx (entry) fits; Other.tsx does not.
        XCTAssertTrue(body.contains("src/App.tsx:\n```"))
        XCTAssertFalse(body.contains("src/Other.tsx:\n```"))
    }

    func testHeadTruncatesWhenTopFileExceedsBudget() async {
        let huge = String(repeating: "z", count: 4000)   // ~1000 tokens
        let out = await ContextBuilder(tokenBudget: 50)
            .build(files: ["src/App.tsx"], touched: [], read: reader(["src/App.tsx": huge]))
        let body = try? XCTUnwrap(out)
        XCTAssertEqual(body?.contains("truncated for context budget"), true)
    }

    func testCompressesLongFileList() async {
        let files = (0..<150).map { "src/f\($0).ts" }
        let out = await ContextBuilder(maxListedFiles: 100)
            .build(files: files, touched: [], read: { _ in nil })
        XCTAssertEqual(out?.contains("and 50 more files"), true)
    }

    // Fase 3b: a pinned (@file) file is included fully even past the budget
    // (a realistic source file, well under the pinned hard ceiling).
    func testPinnedFileIncludedDespiteTinyBudget() async {
        let big = String(repeating: "x", count: 40_000)   // ~10k tokens, < maxPinnedTokens
        let files = ["src/App.tsx", "src/lib/special.ts"]
        let out = await ContextBuilder(tokenBudget: 100)
            .build(files: files, touched: [], pinned: ["src/lib/special.ts"]) { $0 == "src/lib/special.ts" ? big : "// other" }
        XCTAssertEqual(out?.contains("src/lib/special.ts:"), true)
        XCTAssertEqual(out?.contains(big), true, "pinned content included in full")
    }

    // #16: a pathologically large pin (minified bundle) is head-truncated so it
    // can't blow past num_ctx — bounded, not unbounded.
    func testHugePinnedFileIsTruncated() async {
        let huge = String(repeating: "x", count: 200_000)   // ~50k tokens, >> maxPinnedTokens (16k)
        let out = await ContextBuilder(tokenBudget: 100, maxPinnedTokens: 16_000)
            .build(files: ["src/big.ts"], touched: [], pinned: ["src/big.ts"]) { _ in huge }
        XCTAssertEqual(out?.contains("src/big.ts:"), true, "pinned file still included")
        XCTAssertEqual(out?.contains(huge), false, "a huge pin must NOT be injected in full")
        XCTAssertEqual(out?.contains("truncated for context budget"), true, "head-truncated with a note")
        XCTAssertLessThan(out?.count ?? .max, 70_000, "bounded well under the raw 200k chars")
    }

    func testPinnedHelperMatchesPathOrFilename() {
        let files = ["src/components/Header.tsx", "src/App.tsx"]
        XCTAssertEqual(ContextBuilder.pinned(from: "change @Header.tsx please", files: files), ["src/components/Header.tsx"])
        XCTAssertEqual(ContextBuilder.pinned(from: "edit @src/App.tsx", files: files), ["src/App.tsx"])
        XCTAssertTrue(ContextBuilder.pinned(from: "no mentions", files: files).isEmpty)
    }
}
