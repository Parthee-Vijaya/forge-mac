import XCTest
@testable import StormbreakerKit

final class DependencyCacheTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("storm-depcache-test-\(UUID().uuidString)")
        let cacheRoot = tmp.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        DependencyCache.rootOverrideForTesting = cacheRoot
    }

    override func tearDownWithError() throws {
        DependencyCache.rootOverrideForTesting = nil
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeProject(_ name: String, packageJSON: String, withNodeModules: Bool) throws -> URL {
        let root = tmp.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try packageJSON.write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        if withNodeModules {
            let dep = root.appendingPathComponent("node_modules/dep")
            try FileManager.default.createDirectory(at: dep, withIntermediateDirectories: true)
            try "module.exports = 1".write(to: dep.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)
        }
        return root
    }

    /// populate(A) then restore(B) with the SAME package.json clones node_modules in;
    /// a project with a DIFFERENT package.json is a cache miss.
    func testPopulateThenRestoreClonesAcrossProjects() throws {
        let pkg = #"{"name":"x","dependencies":{"dep":"1.0.0"}}"#
        let a = try makeProject("a", packageJSON: pkg, withNodeModules: true)
        DependencyCache.populate(from: a)

        let b = try makeProject("b", packageJSON: pkg, withNodeModules: false)
        XCTAssertTrue(DependencyCache.restore(into: b), "same package.json → cache hit")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: b.appendingPathComponent("node_modules/dep/index.js").path),
            "node_modules cloned into project B")

        let c = try makeProject("c", packageJSON: #"{"name":"y"}"#, withNodeModules: false)
        XCTAssertFalse(DependencyCache.restore(into: c), "different package.json → cache miss")
    }

    /// restore is a no-op when node_modules already exists (don't clobber an install).
    func testRestoreSkipsWhenNodeModulesPresent() throws {
        let pkg = #"{"name":"x","dependencies":{"dep":"1.0.0"}}"#
        let a = try makeProject("a", packageJSON: pkg, withNodeModules: true)
        DependencyCache.populate(from: a)
        // B already has node_modules → restore must not touch it.
        let b = try makeProject("b", packageJSON: pkg, withNodeModules: true)
        XCTAssertFalse(DependencyCache.restore(into: b))
    }
}
