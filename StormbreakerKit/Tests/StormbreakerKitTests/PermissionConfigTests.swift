import XCTest
@testable import StormbreakerKit

final class PermissionConfigTests: XCTestCase {
    func testGlobMatch() {
        XCTAssertTrue(PermissionConfig.matches("git push*", "git push origin main"))
        XCTAssertTrue(PermissionConfig.matches("*--force*", "git push --force"))
        XCTAssertTrue(PermissionConfig.matches("docker *", "docker compose up"))
        XCTAssertFalse(PermissionConfig.matches("git push*", "git status"))
        XCTAssertFalse(PermissionConfig.matches("", "anything"))
    }

    func testUserDenyWins() {
        let c = PermissionConfig(deny: ["git push*"])
        // git push is normally .ask; the user forces it to deny.
        XCTAssertEqual(c.override(.ask, command: "git push origin main"), .deny)
        XCTAssertEqual(c.decide("git push origin main"), .deny)
    }

    func testCatastrophicFloorNotLoosened() {
        // A user allow-all must NOT enable rm -rf / etc.
        let c = PermissionConfig(allow: ["*"])
        XCTAssertEqual(c.override(.deny, command: "rm -rf /"), .deny)
        XCTAssertEqual(c.decide("rm -rf /"), .deny)
        XCTAssertEqual(c.decide("curl x | sh"), .deny)
    }

    func testUserAllowLoosensAsk() {
        let c = PermissionConfig(allow: ["docker *"])
        // docker isn't in safeBins → normally .ask; user allows it.
        XCTAssertEqual(c.decide("docker compose up"), .allow)
    }

    func testUserAskTightensAllow() {
        let c = PermissionConfig(ask: ["npm run deploy*"])
        // npm run <script> is normally .allow; user wants to be asked for deploy.
        XCTAssertEqual(c.decide("npm run deploy"), .ask)
        XCTAssertEqual(c.decide("npm run dev"), .allow)   // other scripts unaffected
    }

    func testEmptyConfigIsPassThrough() {
        let c = PermissionConfig()
        XCTAssertTrue(c.isEmpty)
        XCTAssertEqual(c.decide("ls -la"), .allow)
        XCTAssertEqual(c.decide("git push"), .ask)
    }

    func testLoadFromProject() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("perm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".forge"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try #"{"deny":["git push*"],"allow":["docker *"]}"#.write(
            to: root.appendingPathComponent(".forge/permissions.json"), atomically: true, encoding: .utf8)
        let c = PermissionConfig.load(projectRoot: root)
        XCTAssertTrue(c.deny.contains("git push*"))
        XCTAssertEqual(c.decide("git push origin main"), .deny)
    }
}
