import SwiftUI
import AppKit
import ForgeKit

/// Root app state and the glue between the SwiftUI UI and the ForgeKit engine.
@MainActor
@Observable
final class AppModel {
    struct UIMessage: Identifiable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        var text: String
        var files: [String] = []
    }

    enum PreviewWidth: CaseIterable {
        case full, tablet, phone
        var maxWidth: CGFloat? {
            switch self {
            case .full: nil
            case .tablet: 834
            case .phone: 414
            }
        }
        var icon: String {
            switch self {
            case .full: "rectangle"
            case .tablet: "ipad"
            case .phone: "iphone"
            }
        }
    }

    // Chat
    var messages: [UIMessage] = []
    var draft: String = ""
    var isBusy: Bool = false
    var statusText: String = "Ready."

    // Layout: the preview pane only appears once the first build has started.
    var hasStarted: Bool = false

    // Preview
    var previewURL: URL?
    var phase: AgentState = .idle
    var previewWidth: PreviewWidth = .full
    var reloadToken: Int = 0

    // Diagnostics
    var serverLog: [LogLine] = []
    var jsErrors: [RuntimeIssue] = []
    var showConsole: Bool = false

    // Model selection
    var availableModels: [ModelConfig] = []
    var selectedModelID: String = ""

    // ForgeKit handles (Sendable; safe to use from off-main tasks).
    @ObservationIgnored nonisolated let workspace: ProjectWorkspace
    @ObservationIgnored nonisolated let devServer: DevServerManager
    @ObservationIgnored nonisolated let processLayer: ForgeProcessLayer
    @ObservationIgnored nonisolated let errorCollector: ErrorCollector
    @ObservationIgnored private var templateInstalled = false
    @ObservationIgnored private var logTask: Task<Void, Never>?

    init() {
        let root = AppModel.projectRoot()
        let workspace = ProjectWorkspace(root: root)
        let devServer = DevServerManager(workspace: workspace)
        self.workspace = workspace
        self.devServer = devServer
        self.processLayer = ForgeProcessLayer(workspace: workspace, devServer: devServer)
        self.errorCollector = ErrorCollector(devServer: devServer)

        self.availableModels = [.localDefault]
        self.selectedModelID = ModelConfig.localDefault.id

        startLogStream()
        Task { await refreshModels() }
    }

    static func projectRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Forge/project", isDirectory: true)
    }

    var selectedModel: ModelConfig {
        availableModels.first { $0.id == selectedModelID } ?? .localDefault
    }

    /// Re-discover local models (Ollama + LM Studio) plus the optional cloud
    /// model. Called at launch and from the picker's Refresh button.
    func refreshModels() async {
        var models = await ModelDiscovery.discoverLocal()
        let env = ProcessInfo.processInfo.environment
        if let key = env["FORGE_CLOUD_API_KEY"], !key.isEmpty {
            let cloud = env["FORGE_CLOUD_MODEL"] ?? "nvidia/llama-3.1-nemotron-70b-instruct"
            models.append(.nvidiaNIM(key: key, model: cloud))
        }
        if models.isEmpty { models = [.localDefault] }
        availableModels = models
        if !models.contains(where: { $0.id == selectedModelID }) {
            selectedModelID = Self.preferredDefault(models).id
        }
    }

    static func preferredDefault(_ models: [ModelConfig]) -> ModelConfig {
        models.first { $0.modelID.lowercased().contains("coder") }
            ?? models.first { $0.source == .ollama }
            ?? models.first ?? .localDefault
    }

    // MARK: - Chat submission

    func submit() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isBusy else { return }
        draft = ""
        hasStarted = true
        let history = chatHistory()
        messages.append(UIMessage(role: .user, text: prompt))
        messages.append(UIMessage(role: .assistant, text: ""))
        let assistantIndex = messages.count - 1
        isBusy = true

        Task {
            await runAgent(prompt: prompt, history: history, assistantIndex: assistantIndex)
            isBusy = false
            statusText = Self.statusText(for: phase)
        }
    }

    private func runAgent(prompt: String, history: [ChatMessage], assistantIndex: Int) async {
        if !templateInstalled {
            do {
                try await TemplateInstaller().install(into: workspace)
                templateInstalled = true
            } catch {
                appendAssistant(assistantIndex, "Could not scaffold the project: \(error)")
                return
            }
        }
        await errorCollector.reset()

        let config = selectedModel
        let deps = AgentLoop.Dependencies(
            provider: ModelRouter.provider(for: config),
            options: ModelRouter.options(for: config),
            process: processLayer,
            projectContext: { [workspace] in await AppModel.buildContext(workspace) },
            collectErrors: { [errorCollector] in await errorCollector.collect() },
            onTurnStart: { [errorCollector] in await errorCollector.reset() },
            settleDelay: .seconds(2),
            maxRepairAttempts: 3)

        for await event in AgentLoop(deps).run(userPrompt: prompt, history: history) {
            switch event {
            case .assistantText(let text):
                appendAssistant(assistantIndex, text)
            case .state(let state):
                phase = state
                statusText = Self.statusText(for: state)
            case .fileWriting(let path):
                statusText = "Writing \(path)…"
            case .fileWritten(let path):
                addFile(path, to: assistantIndex)
            case .previewReady(let url):
                previewURL = url
            }
        }
    }

    func handleRuntimeIssue(_ issue: RuntimeIssue) {
        jsErrors.append(issue)
        if jsErrors.count > 200 { jsErrors.removeFirst(jsErrors.count - 200) }
        let collector = errorCollector
        Task { await collector.submit([issue]) }
    }

    func reloadPreview() { reloadToken += 1 }

    func openInBrowser() {
        if let url = previewURL { NSWorkspace.shared.open(url) }
    }

    func shutdown() async {
        logTask?.cancel()
        await devServer.shutdown()
    }

    // MARK: - Helpers

    private func appendAssistant(_ index: Int, _ text: String) {
        guard messages.indices.contains(index) else { return }
        messages[index].text += text
    }

    private func addFile(_ path: String, to index: Int) {
        guard messages.indices.contains(index) else { return }
        if !messages[index].files.contains(path) { messages[index].files.append(path) }
    }

    private func chatHistory() -> [ChatMessage] {
        messages.map { ChatMessage(role: $0.role == .user ? .user : .assistant, content: $0.text) }
    }

    nonisolated static func buildContext(_ workspace: ProjectWorkspace) async -> String? {
        let files = await workspace.fileMap()
        guard !files.isEmpty else { return nil }
        var context = "Project files:\n" + files.map { "- \($0)" }.joined(separator: "\n")
        if let app = try? await workspace.readFile("src/App.tsx") {
            context += "\n\nCurrent src/App.tsx:\n```tsx\n\(app)\n```"
        }
        return context
    }

    private func startLogStream() {
        let devServer = self.devServer
        logTask = Task { [weak self] in
            for await event in await devServer.events() {
                guard let self else { break }
                switch event {
                case .log(let line):
                    self.serverLog.append(line)
                    if self.serverLog.count > 500 { self.serverLog.removeFirst(self.serverLog.count - 500) }
                case .ready(let url):
                    self.previewURL = url
                case .phase, .exited:
                    break
                }
            }
        }
    }

    static func statusText(for state: AgentState) -> String {
        switch state {
        case .idle: "Ready."
        case .building: "Thinking & writing code…"
        case .applying: "Installing & starting…"
        case .awaitingHMR: "Applying changes…"
        case .collectingErrors: "Checking for errors…"
        case .repairing(let attempt): "Fixing errors (attempt \(attempt))…"
        case .clean: "Done."
        case .failed(let reason): "Stopped: \(reason)"
        }
    }
}
