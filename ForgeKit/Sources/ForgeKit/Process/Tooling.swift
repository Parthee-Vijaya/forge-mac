import Foundation

/// The package manager used to install dependencies and run scripts in a
/// generated project. The skeleton defaults to npm; pnpm/bun are wired for
/// future use (all three accept `install` and `run dev`).
public enum PackageManager: String, Sendable, CaseIterable {
    case npm
    case pnpm
    case bun

    /// The Node tool to resolve on PATH for this package manager.
    public var tool: NodeResolver.Tool {
        switch self {
        case .npm: .npm
        case .pnpm: .pnpm
        case .bun: .bun
        }
    }

    /// Arguments for a clean dependency install.
    public var installArgs: [String] { ["install"] }

    /// Arguments to start the dev server (the `dev` script in package.json).
    public var devArgs: [String] { ["run", "dev"] }
}
