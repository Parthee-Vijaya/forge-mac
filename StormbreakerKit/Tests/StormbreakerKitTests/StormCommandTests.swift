import XCTest
@testable import StormbreakerKit

final class StormCommandTests: XCTestCase {
    func testParseFrontmatterAndBody() {
        let md = """
        ---
        description: Review the diff
        mode: plan
        ---
        Review these changes for bugs:
        $ARGUMENTS
        """
        let c = StormCommand.parse(md, id: "review", origin: .project)
        XCTAssertEqual(c?.id, "review")
        XCTAssertEqual(c?.description, "Review the diff")
        XCTAssertEqual(c?.mode, .plan)
        XCTAssertEqual(c?.template.contains("$ARGUMENTS"), true)
    }

    func testParseNilWhenBodyEmpty() {
        XCTAssertNil(StormCommand.parse("---\ndescription: x\n---\n", id: "x", origin: .global))
    }

    func testExpandArguments() async {
        let c = StormCommand(id: "greet", template: "Say hi to $ARGUMENTS now")
        let out = await c.expand(arguments: "Bob", runShell: { _ in nil }, readFile: { _ in nil })
        XCTAssertEqual(out, "Say hi to Bob now")
    }

    func testExpandShellInlinesStdout() async {
        let c = StormCommand(id: "x", template: "Diff:\n!`git diff`\nfix it")
        let out = await c.expand(
            arguments: "",
            runShell: { cmd in cmd == "git diff" ? "- old\n+ new" : nil },
            readFile: { _ in nil })
        XCTAssertTrue(out.contains("- old\n+ new"))
        XCTAssertFalse(out.contains("!`git diff`"))
    }

    func testExpandShellSkipNoteWhenDenied() async {
        let c = StormCommand(id: "x", template: "out: !`rm -rf /`")
        let out = await c.expand(arguments: "", runShell: { _ in nil }, readFile: { _ in nil })
        XCTAssertTrue(out.contains("sprang kommandoen over"), out)
    }

    func testExpandFileInlinesContents() async {
        let c = StormCommand(id: "x", template: "Edit @src/App.tsx please")
        let out = await c.expand(
            arguments: "",
            runShell: { _ in nil },
            readFile: { path in path == "src/App.tsx" ? "export const x = 1" : nil })
        XCTAssertTrue(out.contains("src/App.tsx:"))
        XCTAssertTrue(out.contains("export const x = 1"))
    }

    func testExpandFileLeavesUnknownTokenLiteral() async {
        // @handle that isn't a readable file stays literal (not every @ is a file).
        let c = StormCommand(id: "x", template: "ping @nobody")
        let out = await c.expand(arguments: "", runShell: { _ in nil }, readFile: { _ in nil })
        XCTAssertEqual(out, "ping @nobody")
    }

    func testCommandStoreLoadsProjectCommands() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cmd-\(UUID().uuidString)")
        let dir = root.appendingPathComponent(".forge/commands")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "---\ndescription: ship it\n---\nDeploy $ARGUMENTS".write(
            to: dir.appendingPathComponent("ship.md"), atomically: true, encoding: .utf8)

        let cmds = CommandStore.load(projectRoot: root)
        let ship = CommandStore.find("ship", in: cmds)
        XCTAssertEqual(ship?.description, "ship it")
        XCTAssertEqual(ship?.origin, .project)
        XCTAssertNil(CommandStore.find("nope", in: cmds))
    }
}
