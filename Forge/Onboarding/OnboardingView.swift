import SwiftUI
import AppKit
import ForgeKit

/// First-run wizard: name → location → model → cloud key → GitHub → Vercel →
/// memory → AI_RULES → done. Writes Preferences + Keychain on finish.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    @State private var step = 0
    @State private var cloudKey = ""
    @State private var discovered: [ModelConfig] = []
    @State private var discovering = false
    @State private var githubLine = "Tjekker…"
    @State private var vercelLine = "Tjekker…"
    // Local-runtime setup (model step)
    @State private var probe = SetupProbe()
    @State private var installingTarget: SystemSetup.Target?
    @State private var installLog = ""
    @State private var pulling = false
    @State private var pullLog = ""

    private let lastStep = 9
    private let optionalSteps: Set<Int> = [4, 5, 6]

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            ScrollView {
                content($model)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32).padding(.vertical, 28)
            }
            Divider().overlay(Theme.border)
            footer
        }
        .frame(minWidth: 1040, minHeight: 680)
        .background(Theme.canvas)
        .preferredColorScheme(model.colorScheme)
        .task(id: step) { await onStepAppear($model) }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 9) {
            Circle().fill(Theme.accent).frame(width: 9, height: 9)
            Text("Forge").font(Theme.wordmark(16)).foregroundStyle(Theme.ink)
            Spacer()
            Text("Trin \(min(step + 1, lastStep)) / \(lastStep)")
                .font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Tilbage") { step -= 1 }.buttonStyle(.plain).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            if optionalSteps.contains(step) {
                Button("Spring over") { step += 1 }.buttonStyle(.plain).foregroundStyle(Theme.inkFaint)
            }
            if step == lastStep {
                Button("Nej tak — byg løs") { finish(startTour: false) }
                    .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                primaryButton("Ja tak — vis mig rundt") { finish(startTour: true) }
            } else {
                primaryButton("Næste") { step += 1 }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func primaryButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Theme.accent, in: Capsule())
    }

    // MARK: - Steps

    @ViewBuilder
    private func content(_ model: Bindable<AppModel>) -> some View {
        switch step {
        case 0:
            stepShell("Velkommen til Forge", "Beskriv en app, og se den blive bygget — live. Lad os sætte dig op (et minut).") {
                Toggle(isOn: model.preferences.learningMode) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Jeg er ny til at kode")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                        Text("Slå learning mode til: Forge forklarer hvad der sker undervejs, har en ordbog over fagudtryk, og guider dig gennem build, fejl, kode og deployment til GitHub.")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch).tint(Theme.accent)
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.border))
            }
        case 1:
            stepShell("Hvad skal vi kalde dig?", "Bruges i appen og fortæller agenten hvem den hjælper.") {
                textField("Dit navn", model.preferences.userName)
            }
        case 2:
            stepShell("Hvor skal dine projekter ligge?", "Standard er app-mappen. Vælg en anden hvis du vil have dem et bestemt sted.") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(model.wrappedValue.preferences.projectsRoot.isEmpty
                             ? "Standard (Application Support/Forge)"
                             : model.wrappedValue.preferences.projectsRoot)
                            .font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Theme.inkSoft)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Vælg mappe…") { pickFolder(model) }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                    }
                    .padding(12).overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.border))
                    if !model.wrappedValue.preferences.projectsRoot.isEmpty {
                        Button("Nulstil til standard") { model.wrappedValue.preferences.projectsRoot = "" }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                    }
                }
            }
        case 3:
            stepShell("Kør Forge lokalt — gratis og privat",
                      "Forge bruger en AI-model til at skrive koden. En lokal model kører på din egen Mac — gratis, offline og privat. Jeg har fundet den bedste til din hardware.") {
                localModelStep(model)
            }
        case 4:
            stepShell("Eller brug en cloud-model (API-nøgle)",
                      "Ingen stærk lokal model? Brug en cloud-model i stedet. Det kræver en API-nøgle fra udbyderens konsol — ikke dit ChatGPT/Claude/Gemini-abonnement (API'et er separat og afregnes pr. brug). Google Gemini har et gratis niveau. Kan springes over.") {
                cloudStep(model)
            }
        case 5:
            stepShell("GitHub", "Bruges til at pushe genererede apps. Du kan springe over og gøre det senere.") {
                VStack(alignment: .leading, spacing: 10) {
                    statusRow(githubLine)
                    textField("GitHub-bruger/org (owner)", model.preferences.githubOwner)
                }
            }
        case 6:
            stepShell("Vercel (valgfri)", "Bruges til at deploye. Spring over hvis du ikke deployer endnu.") {
                VStack(alignment: .leading, spacing: 10) {
                    statusRow(vercelLine)
                    textField("Vercel team/scope (valgfri)", model.preferences.vercelScope)
                }
            }
        case 7:
            stepShell("Global memory", "Hvad skal Forge altid huske om dig? Injiceres i hver tur (fx “TypeScript strict, minimale deps, dansk UI-tekst”).") {
                editor(model.preferences.memory, height: 150)
            }
        case 8:
            stepShell("Standard projekt-regler (AI_RULES.md)", "Hvert nyt projekt får denne fil — den styrer agenten og følger med koden ved deploy.") {
                editor(model.preferences.rulesTemplate, height: 200)
            }
        default:
            stepShell("Alt klar, \(model.wrappedValue.preferences.userName.isEmpty ? "kom i gang" : model.wrappedValue.preferences.userName)! 🎉",
                      "Du kan ændre alt senere i Indstillinger (⌘,).") {
                summary(model)
                tourOffer
            }
        }
    }

    /// First-run offer for the guided tour, shown on the final onboarding step.
    /// "Ja tak" / "Nej tak" live in the footer; this card explains the choice and
    /// makes clear the tour is always available later.
    private var tourOffer: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Vil du have en hurtig rundvisning?")
                    .font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ink)
                Text("Jeg fremhæver og forklarer hvert trin — hvor du beskriver din app, vælger teknologi, og finder ordbogen. Du kan altid starte den senere via “Start tutorial” i sidebaren.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.radiusM))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1))
    }

    private func stepShell<Inner: View>(_ title: String, _ subtitle: String, @ViewBuilder _ inner: () -> Inner) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.inkSoft)
            }
            inner()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textField(_ placeholder: String, _ binding: Binding<String>) -> some View {
        TextField(placeholder, text: binding)
            .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(Theme.ink).tint(Theme.accent)
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.border))
    }

    private func editor(_ binding: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: binding)
            .font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.ink).tint(Theme.accent)
            .scrollContentBackground(.hidden).padding(8).frame(height: height)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.border))
    }

    private func statusRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(text.contains("Logget ind") || text.contains("som ") ? Theme.positive : Theme.inkFaint)
                .frame(width: 7, height: 7)
            Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.inkSoft)
        }
    }

    // MARK: - Local model step (install + recommend + discovered list)

    private func localModelStep(_ model: Bindable<AppModel>) -> some View {
        let hw = HardwareInfo.current
        let rec = hw.recommendedModel
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "cpu").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Din Mac: \(hw.summary)").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                    Text("Anbefalet lokal model: \(rec.label)").font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.radiusM))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.accent.opacity(0.3)))

            runtimeCard(title: "Ollama", subtitle: "Letvægts og hurtig — kører som baggrundstjeneste. Bedst til at starte.",
                        installed: probe.ollama, target: .ollama, showPull: true, rec: rec, model: model)
            runtimeCard(title: "LM Studio", subtitle: "App med grafisk model-bibliotek, hvis du vil browse og hente modeller visuelt.",
                        installed: probe.lmStudio, target: .lmStudio, showPull: false, rec: rec, model: model)

            Divider().overlay(Theme.border)
            HStack {
                Text("Fundne modeller").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Button("Opdatér") { Task { probe = await SetupProbe.detect(); await loadModels(model) } }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent)
            }
            modelList(model)
        }
    }

    private func runtimeCard(title: String, subtitle: String, installed: Bool,
                             target: SystemSetup.Target, showPull: Bool,
                             rec: (pull: String, label: String), model: Bindable<AppModel>) -> some View {
        let busy = installingTarget != nil || pulling
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(installed ? Theme.positive : Theme.inkFaint).frame(width: 7, height: 7)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(installed ? "installeret" : "ikke fundet").font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                Spacer(minLength: 0)
            }
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if !installed {
                HStack(spacing: 8) {
                    smallButton("Hent \(title)", filled: true) { SystemSetup.openDownload(target) }
                    if probe.homebrew {
                        smallButton("Installér via Homebrew", filled: false) { Task { await installBrew(target, model) } }
                            .disabled(busy)
                    }
                }
                if target == .lmStudio, probe.homebrew {
                    Text("Homebrew-installation kan bede om din adgangskode.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.inkFaint)
                }
            } else if showPull {
                smallButton("Hent anbefalet model: \(rec.pull)", filled: true) { Task { await pull(rec.pull, model) } }
                    .disabled(busy)
            }
            if installingTarget == target { progressRow("Installerer \(title)…", installLog) }
            if pulling, target == .ollama { progressRow("Henter \(rec.pull)…", pullLog) }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.border))
    }

    private func smallButton(_ title: String, filled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium))
                .foregroundStyle(filled ? Theme.onAccent : Theme.accent)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(filled ? Theme.accent : Theme.accent.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func progressRow(_ label: String, _ log: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ink)
                if !log.isEmpty {
                    Text(log).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.inkFaint)
                        .lineLimit(1).truncationMode(.head)
                }
            }
        }
        .padding(.top, 2)
    }

    @MainActor private func installBrew(_ target: SystemSetup.Target, _ model: Bindable<AppModel>) async {
        installingTarget = target; installLog = "starter…"
        let ok = await SystemSetup.installViaBrew(target) { installLog = $0 }
        if ok, target == .ollama { SystemSetup.startOllamaServe() }
        installingTarget = nil
        probe = await SetupProbe.detect()
        try? await Task.sleep(for: .seconds(1))   // give `ollama serve` a moment to bind :11434
        await loadModels(model)
    }

    @MainActor private func pull(_ name: String, _ model: Bindable<AppModel>) async {
        pulling = true; pullLog = "starter…"
        let ok = await SystemSetup.pullModel(name) { pullLog = $0 }
        pulling = false
        if ok { await loadModels(model) }
    }

    private func modelList(_ model: Bindable<AppModel>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if discovering {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Finder modeller…").foregroundStyle(Theme.inkSoft) }
            } else if discovered.isEmpty {
                Text("Ingen lokale modeller fundet. Start Ollama eller LM Studio og prøv igen.")
                    .font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                Button("Prøv igen") { Task { await loadModels(model) } }.buttonStyle(.plain).foregroundStyle(Theme.accent)
            } else {
                ForEach(discovered) { config in
                    Button { model.wrappedValue.preferences.defaultModelID = config.id } label: {
                        HStack(spacing: 8) {
                            Circle().fill(dotColor(config.source)).frame(width: 7, height: 7)
                            Text(config.displayName).font(.system(size: 13)).foregroundStyle(Theme.ink)
                            Text(sourceLabel(config.source)).font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                            Spacer()
                            if model.wrappedValue.preferences.defaultModelID == config.id {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(model.wrappedValue.preferences.defaultModelID == config.id ? Theme.fill : .clear,
                                    in: RoundedRectangle(cornerRadius: Theme.radiusM))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.border))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func cloudStep(_ model: Bindable<AppModel>) -> some View {
        let provider = model.wrappedValue.preferences.cloudProvider.isEmpty
            ? "gemini" : model.wrappedValue.preferences.cloudProvider
        return VStack(alignment: .leading, spacing: 10) {
            Picker("Provider", selection: model.preferences.cloudProvider) {
                Text("Google Gemini (gratis niveau)").tag("gemini")
                Text("OpenAI").tag("openai")
                Text("Anthropic").tag("anthropic")
                Text("NVIDIA NIM").tag("nvidiaNIM")
            }
            .pickerStyle(.menu).labelsHidden()
            Button {
                SystemSetup.openURL(Self.getKeyURL(provider))
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "key").font(.system(size: 11))
                    Text("Hent en API-nøgle hos \(Self.providerName(provider)) →").font(.system(size: 12, weight: .medium))
                }.foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            textField("Model-id (valgfri — fx \(Self.modelHint(provider)))", model.preferences.cloudModel)
            SecureField("API-nøgle", text: $cloudKey)
                .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(Theme.ink).tint(Theme.accent)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.border))
            Text("Nøglen gemmes sikkert i Keychain — aldrig i klartekst.")
                .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
        }
    }

    static func getKeyURL(_ provider: String) -> String {
        switch provider {
        case "openai":    "https://platform.openai.com/api-keys"
        case "anthropic": "https://console.anthropic.com/settings/keys"
        case "gemini":    "https://aistudio.google.com/app/apikey"
        default:          "https://build.nvidia.com/"
        }
    }
    static func providerName(_ provider: String) -> String {
        switch provider {
        case "openai": "OpenAI"; case "anthropic": "Anthropic"
        case "gemini": "Google AI Studio"; default: "NVIDIA"
        }
    }
    static func modelHint(_ provider: String) -> String {
        switch provider {
        case "openai": "gpt-4o"; case "anthropic": "claude-sonnet-4-6"
        case "gemini": "gemini-2.0-flash"; default: "nvidia/llama-3.1-nemotron-70b-instruct"
        }
    }

    private func summary(_ model: Bindable<AppModel>) -> some View {
        let p = model.wrappedValue.preferences
        return VStack(alignment: .leading, spacing: 6) {
            summaryRow("Navn", p.userName.isEmpty ? "—" : p.userName)
            summaryRow("Placering", p.projectsRoot.isEmpty ? "Standard" : p.projectsRoot)
            summaryRow("Model", p.defaultModelID.isEmpty ? "Lokal (auto)" : p.defaultModelID)
            summaryRow("Cloud", cloudKey.isEmpty ? "Sprunget over" : "\(p.cloudProvider.isEmpty ? "nvidiaNIM" : p.cloudProvider)")
            summaryRow("GitHub", p.githubOwner.isEmpty ? "—" : p.githubOwner)
            summaryRow("Vercel", p.vercelScope.isEmpty ? "—" : p.vercelScope)
            summaryRow("Memory", p.memory.isEmpty ? "—" : "\(p.memory.prefix(40))…")
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.inkFaint).frame(width: 80, alignment: .leading)
            Text(value).font(.system(size: 12.5)).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
        }
    }

    // MARK: - Actions

    private func onStepAppear(_ model: Bindable<AppModel>) async {
        if step == 1, model.wrappedValue.preferences.userName.isEmpty {
            model.wrappedValue.preferences.userName = NSFullUserName()
        }
        if step == 3 {
            probe = await SetupProbe.detect()
            await loadModels(model)
        }
        if step == 5 {
            let login = await Shell.login("gh api user --jq .login 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
            githubLine = login.isEmpty ? "Ikke logget ind (kør `gh auth login` i Terminal)" : "Logget ind som \(login)"
            if model.wrappedValue.preferences.githubOwner.isEmpty, !login.isEmpty {
                model.wrappedValue.preferences.githubOwner = login
            }
        }
        if step == 6 {
            let who = await Shell.login("vercel whoami 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
            let line = who.split(separator: "\n").last.map(String.init) ?? ""
            vercelLine = line.isEmpty ? "Ikke logget ind (kør `vercel login`)" : "Logget ind som \(line)"
        }
    }

    private func loadModels(_ model: Bindable<AppModel>) async {
        discovering = true
        discovered = await ModelDiscovery.discoverLocal()
        discovering = false
        if model.wrappedValue.preferences.defaultModelID.isEmpty, !discovered.isEmpty {
            model.wrappedValue.preferences.defaultModelID = AppModel.preferredDefault(discovered).id
        }
    }

    private func pickFolder(_ model: Bindable<AppModel>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Vælg"
        if panel.runModal() == .OK, let url = panel.url {
            model.wrappedValue.preferences.projectsRoot = url.path
        }
    }

    private func finish(startTour: Bool = false) {
        let key = cloudKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            KeychainStore.set(key, account: KeychainStore.cloudKeyAccount)
            if model.preferences.cloudProvider.isEmpty { model.preferences.cloudProvider = "nvidiaNIM" }
        }
        model.completeOnboarding()
        // Launch the guided spotlight tour on the start screen if the user opted
        // in. Either way the tour stays available later via "Start tutorial".
        if startTour { model.startTutorial() }
    }

    private func dotColor(_ source: ModelConfig.Source) -> Color {
        switch source {
        case .ollama: Theme.positive
        case .lmStudio: Color.purple
        case .cloud: Color.blue
        }
    }
    private func sourceLabel(_ source: ModelConfig.Source) -> String {
        switch source {
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        case .cloud: "Cloud"
        }
    }
}
