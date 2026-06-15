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
        .executable(name: "forge-mcp", targets: ["forge-mcp"])
    ],
    targets: [
        .target(name: "ForgeKit"),
        .executableTarget(name: "forge-mcp"),
        .testTarget(
            name: "ForgeKitTests",
            dependencies: ["ForgeKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
