// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ForgeKit",
    platforms: [
        // Pure Foundation engine — broad compatibility so it builds under the
        // Command Line Tools toolchain, independent of the macOS-26 app target.
        .macOS(.v14)
    ],
    products: [
        .library(name: "ForgeKit", targets: ["ForgeKit"]),
        // B18: a stdio MCP server that exposes a project's files to external agents.
        .executable(name: "forge-mcp", targets: ["forge-mcp"]),
        // The `forge` CLI: drives the real AgentLoop from a terminal.
        .executable(name: "forge", targets: ["forge"])
    ],
    targets: [
        .target(name: "ForgeKit"),
        .executableTarget(name: "forge-mcp"),
        .executableTarget(name: "forge", dependencies: ["ForgeKit"]),
        .testTarget(
            name: "ForgeKitTests",
            dependencies: ["ForgeKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
