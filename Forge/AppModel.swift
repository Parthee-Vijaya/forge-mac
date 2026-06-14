import SwiftUI
import AppKit
import ForgeKit

/// Root app state and the glue between the SwiftUI UI and the ForgeKit engine.
@MainActor
@Observable
final class AppModel {
    struct UIMessage: Identifiable, Codable {
        enum Role: String, Codable { case user, assistant }
        var id = UUID()
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

    enum RightPaneMode { case preview, code }

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
    var rightPaneMode: RightPaneMode = .preview

    // Code view
    var projectFiles: [String] = []
    var selectedFile: String?
    var editorText: String = ""
    var editorDirty: Bool = false

    // Diagnostics
    var serverLog: [LogLine] = []
    var jsErrors: [RuntimeIssue] = []
    var showConsole: Bool = false

    // Model selection
    var availableModels: [ModelConfig] = []
    var selectedModelID: String = ""

    // ForgeKit handles (Sendable; safe to use from off-main tasks).
    // Projects
    var projects: [Project] = []
    var currentProject: Project

    @ObservationIgnored private(set) var workspace: ProjectWorkspace
    @ObservationIgnored private(set) var devServer: DevServerManager
    @ObservationIgnored private(set) var processLayer: ForgeProcessLayer
    @ObservationIgnored private(set) var errorCollector: ErrorCollector
    @ObservationIgnored private var templateInstalled = false
    @ObservationIgnored private var logTask: Task<Void, Never>?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var lastLoadedText = ""

    init() {
        var loaded = ProjectStore.loadProjects()
        if loaded.isEmpty {
            let project = ProjectStore.makeProject(name: "Untitled")
            ProjectStore.saveProjects([project])
            loaded = [project]
        }
        let current = loaded[0]
        self.projects = loaded
        self.currentProject = current

        let workspace = ProjectWorkspace(root: ProjectStore.dir(for: current))
        let devServer = DevServerManager(workspace: workspace)
        self.workspace = workspace
        self.devServer = devServer
        self.processLayer = ForgeProcessLayer(workspace: workspace, devServer: devServer)
        self.errorCollector = ErrorCollector(devServer: devServer)

        self.availableModels = [.localDefault]
        self.selectedModelID = ModelConfig.localDefault.id

        self.messages = ProjectStore.loadChat(for: current)
        self.hasStarted = !messages.isEmpty
        self.templateInstalled = ProjectStore.hasBuiltApp(current)

        startLogStream()
        let resume = templateInstalled && !messages.isEmpty
        let devServerRef = devServer
        Task {
            await refreshModels()
            if resume { try? await devServerRef.start() }
        }
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

    // MARK: - Projects

    func newProject() {
        guard !isBusy else { return }
        persistCurrentChat()
        let project = ProjectStore.makeProject(name: "Untitled")
        projects.insert(project, at: 0)
        ProjectStore.saveProjects(projects)
        activate(project, freshState: true)
    }

    func switchTo(_ project: Project) {
        guard !isBusy, project.id != currentProject.id else { return }
        persistCurrentChat()
        activate(project, freshState: false)
    }

    func deleteProject(_ project: Project) {
        guard !isBusy else { return }
        projects.removeAll { $0.id == project.id }
        ProjectStore.deleteDir(for: project)
        if projects.isEmpty {
            projects = [ProjectStore.makeProject(name: "Untitled")]
        }
        ProjectStore.saveProjects(projects)
        if currentProject.id == project.id {
            activate(projects[0], freshState: false)
        }
    }

    private func activate(_ project: Project, freshState: Bool) {
        let previous = devServer
        Task { await previous.shutdown() }

        currentProject = project
        installHandles(for: project)

        previewURL = nil
        phase = .idle
        rightPaneMode = .preview
        selectedFile = nil
        editorText = ""
        projectFiles = []
        serverLog = []
        jsErrors = []
        statusText = "Ready."
        messages = freshState ? [] : ProjectStore.loadChat(for: project)
        templateInstalled = ProjectStore.hasBuiltApp(project)
        hasStarted = !messages.isEmpty

        if templateInstalled && !messages.isEmpty {
            let devServerRef = devServer
            Task { try? await devServerRef.start() }
        }
    }

    private func installHandles(for project: Project) {
        let workspace = ProjectWorkspace(root: ProjectStore.dir(for: project))
        self.workspace = workspace
        self.devServer = DevServerManager(workspace: workspace)
        self.processLayer = ForgeProcessLayer(workspace: workspace, devServer: devServer)
        self.errorCollector = ErrorCollector(devServer: devServer)
        startLogStream()
    }

    private func persistCurrentChat() {
        ProjectStore.saveChat(messages, for: currentProject)
        currentProject.updatedAt = Date()
        if let index = projects.firstIndex(where: { $0.id == currentProject.id }) {
            projects[index] = currentProject
        }
        ProjectStore.saveProjects(projects)
    }

    private func renameCurrent(to name: String) {
        currentProject.name = name
        if let index = projects.firstIndex(where: { $0.id == currentProject.id }) {
            projects[index] = currentProject
        }
        ProjectStore.saveProjects(projects)
    }

    static func projectName(from prompt: String) -> String {
        let trimmed = prompt.split(separator: " ").prefix(6).joined(separator: " ")
        return String(trimmed.prefix(42))
    }

    // MARK: - Code view

    func enterCodeMode() {
        rightPaneMode = .code
        Task {
            await refreshFiles()
            if selectedFile == nil {
                let entry = projectFiles.first { $0 == "src/App.tsx" } ?? projectFiles.first
                if let entry { await openFile(entry) }
            }
        }
    }

    func refreshFiles() async {
        projectFiles = await workspace.fileMap()
    }

    func openFile(_ path: String) async {
        autosaveTask?.cancel()
        guard let text = try? await workspace.readFile(path) else { return }
        editorText = text
        lastLoadedText = text
        selectedFile = path
        editorDirty = false
    }

    /// Debounced autosave: writing the file lets Vite HMR refresh the preview.
    func onEditorChange() {
        guard editorText != lastLoadedText else { return }
        editorDirty = true
        autosaveTask?.cancel()
        let path = selectedFile
        let text = editorText
        autosaveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let path else { return }
            try? await workspace.writeFile(path, contents: text)
            lastLoadedText = text
            editorDirty = false
        }
    }

    func saveNow() async {
        autosaveTask?.cancel()
        guard let path = selectedFile else { return }
        try? await workspace.writeFile(path, contents: editorText)
        lastLoadedText = editorText
        editorDirty = false
    }

    // MARK: - Chat submission

    func submit() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isBusy else { return }
        if messages.isEmpty { renameCurrent(to: Self.projectName(from: prompt)) }
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
        await refreshFiles()
        persistCurrentChat()
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
        logTask?.cancel()
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
