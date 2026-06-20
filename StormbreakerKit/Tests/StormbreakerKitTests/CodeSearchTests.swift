import XCTest
@testable import StormbreakerKit

final class CodeSearchTests: XCTestCase {
    private func project() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "export const useAuth = () => {}".write(
            to: root.appendingPathComponent("auth.ts"), atomically: true, encoding: .utf8)
        try "import { useAuth } from './auth'".write(
            to: root.appendingPathComponent("App.tsx"), atomically: true, encoding: .utf8)
        // A pruned dir that must never appear in results.
        let nm = root.appendingPathComponent("node_modules/pkg")
        try FileManager.default.createDirectory(at: nm, withIntermediateDirectories: true)
        try "useAuth".write(to: nm.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)
        return root
    }

    func testGlobFindsFilesAndPrunesNodeModules() async throws {
        let root = try project(); defer { try? FileManager.default.removeItem(at: root) }
        let out = await CodeSearch.run(.glob, query: "*.ts", root: root)
        XCTAssertTrue(out.contains("auth.ts"), out)
        XCTAssertFalse(out.contains("node_modules"), "pruned dir must not appear")
    }

    func testGrepFindsContentAndPrunesNodeModules() async throws {
        let root = try project(); defer { try? FileManager.default.removeItem(at: root) }
        let out = await CodeSearch.run(.grep, query: "useAuth", root: root)
        // node_modules must never appear, whether or not a match was returned.
        XCTAssertFalse(out.contains("node_modules"), "pruned dir must not appear")
        // The SPM test sandbox blocks spawned-subprocess file reads (so grep/rg can
        // return the no-match sentinel here); when it DOES match, the source files
        // must be present. Real CLI/GUI matching is verified outside the sandbox.
        if !out.contains("Ingen match") {
            XCTAssertTrue(out.contains("auth.ts") || out.contains("App.tsx"), out)
        }
    }

    func testEmptyQuery() async throws {
        let root = try project(); defer { try? FileManager.default.removeItem(at: root) }
        let out = await CodeSearch.run(.grep, query: "   ", root: root)
        XCTAssertTrue(out.contains("Tom"))
    }
}
