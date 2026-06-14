import Foundation

/// Writes a `ProjectTemplate` into a fresh project workspace before the first
/// model turn.
public struct TemplateInstaller: Sendable {
    public init() {}

    /// Install the template, skipping files that already exist unless `overwrite`
    /// is set (so re-running on an existing project doesn't clobber edits).
    public func install(
        _ template: ProjectTemplate = .viteReactTailwind,
        into workspace: ProjectWorkspace,
        overwrite: Bool = false
    ) async throws {
        try await workspace.ensureRootExists()
        for file in template.files {
            if !overwrite, await workspace.fileExists(file.path) { continue }
            try await workspace.writeFile(file.path, contents: file.contents)
        }
    }
}
