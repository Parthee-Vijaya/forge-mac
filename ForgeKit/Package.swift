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
        .library(name: "ForgeKit", targets: ["ForgeKit"])
    ],
    targets: [
        .target(name: "ForgeKit"),
        .testTarget(
            name: "ForgeKitTests",
            dependencies: ["ForgeKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
