// swift-tools-version: 6.2
import PackageDescription

// A dev/QA harness that drives the real StormbreakerKit AgentLoop headlessly against a
// local model, logging every phase so we can see *where* the build loop breaks.
// Kept in a separate package so the shipping StormbreakerKit library stays pristine.
let package = Package(
    name: "dogfood",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../StormbreakerKit")
    ],
    targets: [
        .executableTarget(
            name: "dogfood",
            dependencies: [.product(name: "StormbreakerKit", package: "StormbreakerKit")]
        )
    ],
    swiftLanguageModes: [.v6]
)
