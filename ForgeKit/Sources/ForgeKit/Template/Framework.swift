import Foundation

/// The frontend framework a project is scaffolded with. All three are Vite-based,
/// so the dev server, ready-detection and `npm run dev` / `vite build` flow are
/// identical — only the template files and the system-prompt guidance differ.
public enum Framework: String, Sendable, CaseIterable {
    case react, svelte, vue

    public init(id: String) { self = Framework(rawValue: id) ?? .react }

    public var displayName: String {
        switch self {
        case .react: "React"
        case .svelte: "Svelte"
        case .vue: "Vue"
        }
    }

    public var template: ProjectTemplate {
        switch self {
        case .react: .viteReactTailwind
        case .svelte: .viteSvelteTailwind
        case .vue: .viteVueTailwind
        }
    }
}
