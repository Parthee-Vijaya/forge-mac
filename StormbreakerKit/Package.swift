// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StormbreakerKit",
    platforms: [
        // Pure Foundation engine — broad compatibility so it builds under the
        // Command Line Tools toolchain, independent of the macOS-26 app target.
        .macOS(.v14)
    ],
    products: [
        .library(name: "StormbreakerKit", targets: ["StormbreakerKit"]),
        // B18: a stdio MCP server that exposes a project's files to external agents.
        .executable(name: "storm-mcp", targets: ["storm-mcp"]),
        // The `storm` CLI: drives the real AgentLoop from a terminal.
        .executable(name: "storm", targets: ["storm"])
    ],
    targets: [
        .target(name: "StormbreakerKit"),
        .executableTarget(name: "storm-mcp", dependencies: ["StormbreakerKit"]),
        .executableTarget(name: "storm", dependencies: ["StormbreakerKit"]),
        .testTarget(
            name: "StormbreakerKitTests",
            dependencies: ["StormbreakerKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
