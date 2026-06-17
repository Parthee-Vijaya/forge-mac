import XCTest
@testable import ForgeKit

final class RulesLoaderTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rules-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testReadsBothWithAIRulesLast() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try "Use Vue.".write(to: dir.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        try "Use React.".write(to: dir.appendingPathComponent("AI_RULES.md"), atomically: true, encoding: .utf8)
        let out = try XCTUnwrap(RulesLoader.read(projectRoot: dir))
        XCTAssertTrue(out.contains("Use Vue."))
        XCTAssertTrue(out.contains("Use React."))
        XCTAssertLessThan(out.range(of: "AGENTS.md")!.lowerBound, out.range(of: "AI_RULES.md")!.lowerBound,
                          "AI_RULES.md comes last so it wins ties")
    }

    func testAgentsOnly() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try "Only agents.".write(to: dir.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(RulesLoader.read(projectRoot: dir)?.contains("Only agents."), true)
    }

    func testNilWhenNoneOrEmpty() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(RulesLoader.read(projectRoot: dir))
        try "   \n".write(to: dir.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        XCTAssertNil(RulesLoader.read(projectRoot: dir), "whitespace-only is treated as empty")
    }
}
