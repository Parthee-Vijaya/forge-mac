import XCTest
import ForgeKit
@testable import Forge

/// Unit tests for AppModel's pure, static decision helpers — the bits of app
/// logic that don't need a running UI. These are the functions that decide a
/// project's name, which model is the default, how the token pill reads, etc.
/// Keeping them honest here means a refactor that breaks the rules (e.g. stops
/// preferring qwen3.6) fails CI instead of shipping.
@MainActor
final class AppModelLogicTests: XCTestCase {

    // MARK: preferredDefault — qwen3.6 wins, then any qwen, then first, then localDefault

    func testPreferredDefaultPrefersQwen36() {
        let models = [
            ModelConfig.lmStudio(model: "nemotron-super-49b"),
            ModelConfig.ollama(model: "qwen2.5-coder:32b"),
            ModelConfig.lmStudio(model: "qwen/qwen3.6-35b-a3b"),
        ]
        XCTAssertEqual(AppModel.preferredDefault(models).modelID, "qwen/qwen3.6-35b-a3b")
    }

    func testPreferredDefaultFallsBackToAnyQwen() {
        let models = [
            ModelConfig.lmStudio(model: "nemotron-super-49b"),
            ModelConfig.ollama(model: "qwen2.5-coder:14b"),
        ]
        XCTAssertEqual(AppModel.preferredDefault(models).modelID, "qwen2.5-coder:14b")
    }

    func testPreferredDefaultFallsBackToFirst() {
        let models = [ModelConfig.lmStudio(model: "mistral-small")]
        XCTAssertEqual(AppModel.preferredDefault(models).modelID, "mistral-small")
    }

    func testPreferredDefaultEmptyIsLocalDefault() {
        XCTAssertEqual(AppModel.preferredDefault([]), .localDefault)
    }

    // MARK: isStaleModelID — the retired qwen2.5-coder default must not stick

    func testStaleModelIDs() {
        XCTAssertTrue(AppModel.isStaleModelID("qwen2.5-coder:32b"))
        XCTAssertTrue(AppModel.isStaleModelID("some-CODER-model"))
        XCTAssertFalse(AppModel.isStaleModelID("qwen/qwen3.6-35b-a3b"))
        XCTAssertFalse(AppModel.isStaleModelID("nemotron-super-49b"))
    }

    // MARK: projectName — strip lead-ins, cut at separators, capitalize, cap length

    func testProjectNameStripsDanishLeadIn() {
        XCTAssertEqual(AppModel.projectName(from: "byg mig en todo-app"), "Todo-app")
    }

    func testProjectNameStripsEnglishLeadIn() {
        XCTAssertEqual(AppModel.projectName(from: "build a weather dashboard"), "Weather dashboard")
    }

    func testProjectNameCutsAtSeparator() {
        XCTAssertEqual(AppModel.projectName(from: "en kanban-board med drag and drop"), "Kanban-board")
    }

    func testProjectNameCapitalizesFirstLetter() {
        XCTAssertEqual(AppModel.projectName(from: "portfolio site"), "Portfolio site")
    }

    func testProjectNameEmptyIsUntitled() {
        XCTAssertEqual(AppModel.projectName(from: "   "), "Untitled")
    }

    func testProjectNameCapsAtFiveWords() {
        let name = AppModel.projectName(from: "one two three four five six seven")
        XCTAssertEqual(name, "One two three four five")
    }

    // MARK: repoName — strip .git, take last path/scp component

    func testRepoNameFromHTTPSURL() {
        XCTAssertEqual(AppModel.repoName(from: "https://github.com/Parthee-Vijaya/forge-mac.git"), "forge-mac")
    }

    func testRepoNameFromSCPURL() {
        XCTAssertEqual(AppModel.repoName(from: "git@github.com:Parthee-Vijaya/forge-mac.git"), "forge-mac")
    }

    func testRepoNameWithoutGitSuffix() {
        XCTAssertEqual(AppModel.repoName(from: "https://github.com/foo/bar"), "bar")
    }

    func testRepoNameEmptyIsRepo() {
        XCTAssertEqual(AppModel.repoName(from: ""), "repo")
    }

    // MARK: formatTokens — compact pill text

    func testFormatTokens() {
        XCTAssertEqual(AppModel.formatTokens(0), "0")
        XCTAssertEqual(AppModel.formatTokens(999), "999")
        XCTAssertEqual(AppModel.formatTokens(1_500), "1.5k")
        XCTAssertEqual(AppModel.formatTokens(2_400_000), "2.4M")
    }

    // MARK: statusText — agent state → human label

    func testStatusText() {
        XCTAssertEqual(AppModel.statusText(for: .idle), "Ready.")
        XCTAssertEqual(AppModel.statusText(for: .clean), "Done.")
        XCTAssertEqual(AppModel.statusText(for: .repairing(attempt: 2)), "Fixing errors (attempt 2)…")
        XCTAssertEqual(AppModel.statusText(for: .failed("boom")), "Stopped: boom")
    }

    // MARK: recentTouched — newest-first, de-duplicated, capped at 8

    func testRecentTouchedDedupesNewestFirst() {
        let messages = [
            AppModel.UIMessage(role: .user, text: "make it"),
            AppModel.UIMessage(role: .assistant, text: "ok", files: ["App.tsx", "index.css"]),
            AppModel.UIMessage(role: .assistant, text: "tweak", files: ["App.tsx", "Button.tsx"]),
        ]
        // Walks messages newest-first: Button.tsx + App.tsx from the last turn,
        // then index.css from the earlier one (App.tsx already seen → skipped).
        XCTAssertEqual(AppModel.recentTouched(from: messages), ["Button.tsx", "App.tsx", "index.css"])
    }

    func testRecentTouchedIgnoresUserFiles() {
        let messages = [
            AppModel.UIMessage(role: .user, text: "here", files: ["pasted.png"]),
            AppModel.UIMessage(role: .assistant, text: "done", files: ["App.tsx"]),
        ]
        XCTAssertEqual(AppModel.recentTouched(from: messages), ["App.tsx"])
    }

    func testRecentTouchedCapsAcrossMessages() {
        // The cap is checked at message boundaries: once accumulated files reach
        // ≥8 it stops walking older turns. Ten single-file turns → first 8 (newest).
        let messages = (0..<10).map {
            AppModel.UIMessage(role: .assistant, text: "turn \($0)", files: ["f\($0).tsx"])
        }
        let touched = AppModel.recentTouched(from: messages)
        XCTAssertEqual(touched.count, 8)
        XCTAssertEqual(touched.first, "f9.tsx")   // newest turn first
    }
}
