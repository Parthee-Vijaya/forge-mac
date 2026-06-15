import Foundation
import ForgeKit

// ─────────────────────────────────────────────────────────────────────────────
// Forge dogfood harness
//
// Drives the REAL ForgeKit AgentLoop (same provider, process layer, artifact
// parser, executor, and self-correction loop the app uses) against a local
// model — but headless and fully instrumented. Every state transition, every
// error report the repair loop sees, per-phase timing, token usage, and the
// model's reasoning are logged so we can see exactly WHERE a real build breaks.
//
//   swift run dogfood "<prompt>" [modelID]
//
// Output (stdout) is meant to be teed to a log. The generated project, the full
// reasoning, and the assistant transcript are saved under ~/forge-dogfood-runs/.
// ─────────────────────────────────────────────────────────────────────────────

let args = CommandLine.arguments
let defaultPrompt = """
Build a kanban board with three columns: "To Do", "In Progress", and "Done". \
I can add a card to a column by typing a title and pressing Enter, move a card \
left or right between columns with arrow buttons on the card, and delete a card \
with an × button. Persist all cards in localStorage so they survive a reload. \
Clean, modern look.
"""
let prompt = args.count > 1 && !args[1].isEmpty ? args[1] : defaultPrompt
let modelID = args.count > 2 && !args[2].isEmpty ? args[2] : "qwen/qwen3.6-35b-a3b"
let framework = Framework(id: args.count > 3 ? args[3] : "react")
let entryFile = framework.template.modelEntryFile

let startedAt = Date()
func elapsed() -> String { String(format: "%6.1fs", Date().timeIntervalSince(startedAt)) }
/// Live, timestamped line to stdout (teed to the run log by the caller).
func note(_ s: String) {
    print("[\(elapsed())] \(s)")
    fflush(stdout)
}

// Stable, inspectable run directory.
let runStamp = Int(startedAt.timeIntervalSince1970)
let runDir = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent("forge-dogfood-runs/run-\(runStamp)")
let projectDir = runDir.appendingPathComponent("project")
try? FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

note("Forge dogfood — model=\(modelID)  framework=\(framework.displayName)")
note("run dir: \(runDir.path)")
note("prompt: \(prompt)")
note(String(repeating: "─", count: 78))

let workspace = ProjectWorkspace(root: projectDir)
try await TemplateInstaller().install(framework.template, into: workspace)
note("scaffolded \(framework.displayName)+Vite+Tailwind template (entry: \(entryFile))")

let devServer = DevServerManager(workspace: workspace)
let processLayer = ForgeProcessLayer(workspace: workspace, devServer: devServer)
let collector = ErrorCollector(devServer: devServer)
let config = ModelConfig.lmStudio(model: modelID)

// Capture every error report the self-correction loop acts on — the key signal
// for "is the loop misdiagnosing, or seeing the real failure?".
nonisolated(unsafe) var collectCount = 0
let deps = AgentLoop.Dependencies(
    provider: ModelRouter.provider(for: config),
    options: ModelRouter.options(for: config),
    process: processLayer,
    projectContext: { [workspace] in
        let files = await workspace.fileMap()
        return await ContextBuilder().build(files: files, touched: []) { try? await workspace.readFile($0) }
    },
    collectErrors: {
        let report = await collector.collect()
        collectCount += 1
        if report.isClean {
            note("◆ collectErrors #\(collectCount): CLEAN ✅")
        } else {
            let body = report.formatted()
            note("◆ collectErrors #\(collectCount): NOT clean  sig=[\(report.signature.prefix(60))]")
            note("  ┌─ ERROR REPORT the loop will try to fix ─────────────")
            for line in body.split(separator: "\n", omittingEmptySubsequences: false).prefix(40) {
                note("  │ \(line)")
            }
            note("  └──────────────────────────────────────────────────────")
        }
        return report
    },
    onTurnStart: { await collector.reset() },
    readFile: { [workspace] path in try? await workspace.readFile(path) },
    settleDelay: .seconds(2),
    maxRepairAttempts: 3)

// ── consume the event stream ────────────────────────────────────────────────
var reachedClean = false
var lastFailure: String?
var previewURL: URL?
var filesWritten: [String] = []
var assistantTranscript = ""
var reasoningBuffer = ""
var reasoningTotal = 0
var reasoningTick = 0
var turnTokens = 0
var lastStateAt = Date()

@MainActor func stateLine(_ label: String) {
    let dt = Date().timeIntervalSince(lastStateAt)
    lastStateAt = Date()
    note(String(format: "STATE → %@  (+%.1fs in previous phase)", label, dt))
}

note("starting AgentLoop.run …")
for await event in AgentLoop(deps).run(userPrompt: prompt, history: []) {
    switch event {
    case .state(let s):
        switch s {
        case .idle: stateLine("idle")
        case .planning: stateLine("planning")
        case .planReady: stateLine("planReady")
        case .building: stateLine("building (streaming model output)")
        case .applying: stateLine("applying actions (install / write / start)")
        case .awaitingHMR: stateLine("awaitingHMR (letting it settle)")
        case .collectingErrors: stateLine("collectingErrors")
        case .repairing(let n): stateLine("REPAIRING attempt \(n) 🔧")
        case .clean: stateLine("CLEAN ✅"); reachedClean = true
        case .failed(let why):
            stateLine("FAILED ❌")
            lastFailure = why
            note("  failure reason:\n\(why.prefix(800))")
        }
    case .fileWriting(let path):
        note("  ✎ writing \(path) …")
    case .fileWritten(let path):
        filesWritten.append(path)
        note("  ✓ wrote \(path)")
    case .fileChunk:
        break  // streamed into the editor in the app; ignore here
    case .previewReady(let url):
        previewURL = url
        note("  🌐 preview ready: \(url.absoluteString)")
    case .assistantText(let t):
        assistantTranscript += t
    case .reasoning(let r):
        reasoningBuffer += r
        reasoningTotal += r.count
        // Print a compact heartbeat every ~1500 chars so a runaway "thinking"
        // phase (e.g. counting line numbers) is visible without flooding.
        if reasoningTotal / 1500 > reasoningTick {
            reasoningTick = reasoningTotal / 1500
            let tail = reasoningBuffer.suffix(140).replacingOccurrences(of: "\n", with: " ")
            note("  …thinking (\(reasoningTotal) chars) …\(tail)")
        }
    case .usage(let pt, let ct):
        turnTokens += pt + ct
        note("  📊 usage: prompt=\(pt) completion=\(ct) (running total \(turnTokens))")
    }
}

// ── settle the dev server + final verification ───────────────────────────────
note(String(repeating: "─", count: 78))
note("loop finished. reachedClean=\(reachedClean) failure=\(lastFailure ?? "none")")
note("files written (\(filesWritten.count)): \(Set(filesWritten).sorted().joined(separator: ", "))")
note("reasoning total: \(reasoningTotal) chars   completion+prompt tokens: \(turnTokens)")

if let url = previewURL {
    note("probing preview \(url.absoluteString) …")
    do {
        let (data, response) = try await URLSession.shared.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        let html = String(decoding: data, as: UTF8.self)
        note("  HTTP \(code), \(data.count) bytes, has #root=\(html.contains("id=\"root\""))")
    } catch {
        note("  preview probe FAILED: \(error)")
    }
} else {
    note("no preview URL — pipeline never reached a running server")
}

// Save artifacts for inspection.
try? assistantTranscript.write(to: runDir.appendingPathComponent("assistant.md"), atomically: true, encoding: .utf8)
try? reasoningBuffer.write(to: runDir.appendingPathComponent("reasoning.txt"), atomically: true, encoding: .utf8)
if let app = try? await workspace.readFile(entryFile) {
    note(String(repeating: "─", count: 78))
    note("FINAL \(entryFile) (\(app.count) chars):")
    for line in app.split(separator: "\n", omittingEmptySubsequences: false).prefix(80) {
        print("    \(line)")
    }
}

// ── tsc-gate self-test (FORGE_GATE_SELFTEST=1) ───────────────────────────────
// Proves the production path ErrorCollector.collect() → DevServerManager.typeCheck()
// → real tsc → ErrorClassifier actually catches a type error the dev-server
// settle reports as "clean". Injects a real error, re-collects, then restores.
if ProcessInfo.processInfo.environment["FORGE_GATE_SELFTEST"] == "1",
   let original = try? await workspace.readFile(entryFile) {
    note(String(repeating: "─", count: 78))
    note("TYPE-GATE SELF-TEST (\(entryFile))")
    let before = await collector.collect()
    note("  baseline collect() on the generated app: clean=\(before.isClean)")
    // A real TYPE error (not a parse error): for .vue/.svelte it must live inside
    // the <script> block, so inject before the first </script>; .tsx is plain TS.
    let probe = "\nconst _forgeGateProbe: number = \"this is a string, not a number\"\n"
    let broken: String
    if let r = original.range(of: "</script>") {
        broken = original.replacingCharacters(in: r, with: probe + "</script>")
    } else {
        broken = original + "\n" + probe
    }
    try? await workspace.writeFile(entryFile, contents: broken)
    note("  injected a deliberate type error (number = string) …")
    let after = await collector.collect()
    if after.isClean {
        note("  ❌ GATE FAILED: collect() still reports clean — type error NOT caught")
    } else {
        note("  ✅ GATE WORKS: collect() now reports the type error the esbuild settle missed:")
        for line in after.formatted().split(separator: "\n").prefix(5) { note("     \(line)") }
    }
    try? await workspace.writeFile(entryFile, contents: original)  // restore
    note("  restored \(entryFile)")
}

await devServer.shutdown()
note("dev server shut down. run dir: \(runDir.path)")
note("DONE in \(elapsed())")
