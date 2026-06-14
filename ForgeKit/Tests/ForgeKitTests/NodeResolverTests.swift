import XCTest
@testable import ForgeKit

final class NodeResolverTests: XCTestCase {
    func testResolvesNodeAndNpmOnThisMachine() throws {
        let resolver = NodeResolver()
        let node = try resolver.resolve(.node)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: node.path))

        let npm = try resolver.resolve(.npm)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: npm.path))

        let binDir = try resolver.nodeBinDirectory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: binDir.path))
    }

    func testSearchDirectoriesAreDeduplicatedAndAbsolute() {
        let dirs = NodeResolver().searchDirectories().map(\.path)
        XCTAssertEqual(Set(dirs).count, dirs.count, "search directories should be unique")
        XCTAssertTrue(dirs.allSatisfy { $0.hasPrefix("/") })
    }
}
