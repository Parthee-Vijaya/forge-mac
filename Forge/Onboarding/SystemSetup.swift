import Foundation
import AppKit
import Darwin

/// Detected Mac hardware + a coding-model recommendation sized to its memory.
/// Apple-Silicon unified memory is what bounds local-model size, so we recommend
/// by total RAM.
struct HardwareInfo: Sendable {
    let ramGB: Int
    let chip: String
    var isAppleSilicon: Bool { chip.localizedCaseInsensitiveContains("apple") }

    static let current: HardwareInfo = {
        let ram = Int((ProcessInfo.processInfo.physicalMemory + (1 << 29)) / (1 << 30)) // round to GB
        return HardwareInfo(ramGB: ram, chip: Self.cpuBrand())
    }()

    private static func cpuBrand() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        let s = String(cString: buf).trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "Mac" : s
    }

    /// An Ollama coding model that fits comfortably in this Mac's memory, with a
    /// human label (approx download size). qwen2.5-coder is a strong, widely
    /// available family across sizes.
    var recommendedModel: (pull: String, label: String) {
        switch ramGB {
        case ..<9:   return ("qwen2.5-coder:3b",  "qwen2.5-coder:3b · ~2 GB")
        case 9...17: return ("qwen2.5-coder:7b",  "qwen2.5-coder:7b · ~4,7 GB")
        case 18...34: return ("qwen2.5-coder:14b", "qwen2.5-coder:14b · ~9 GB")
        default:     return ("qwen2.5-coder:32b", "qwen2.5-coder:32b · ~20 GB")
        }
    }

    var summary: String { "\(chip) · \(ramGB) GB RAM" }
}

/// What's already installed on the machine (probed once when the model step appears).
struct SetupProbe: Sendable {
    var ollama = false
    var lmStudio = false
    var homebrew = false

    static func detect() async -> SetupProbe {
        async let ollama = Shell.login("command -v ollama 2>/dev/null")
        async let brew = Shell.login("command -v brew 2>/dev/null")
        async let lms = Shell.login("command -v lms 2>/dev/null")
        let ollamaFound = !(await ollama).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let brewFound = !(await brew).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let lmsFound = !(await lms).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let lmApp = FileManager.default.fileExists(atPath: "/Applications/LM Studio.app")
        return SetupProbe(ollama: ollamaFound, lmStudio: lmApp || lmsFound, homebrew: brewFound)
    }
}

/// One-click install actions for the local runtimes. All `brew`/`ollama` specs are
/// fixed literals (no user interpolation) → no shell-injection surface.
enum SystemSetup {
    enum Target: Equatable {
        case ollama, lmStudio
        var downloadURL: URL {
            switch self {
            case .ollama:   URL(string: "https://ollama.com/download")!
            case .lmStudio: URL(string: "https://lmstudio.ai")!
            }
        }
        /// Homebrew spec: Ollama is a formula (no sudo); LM Studio is a cask.
        var brewSpec: String {
            switch self {
            case .ollama:   "ollama"
            case .lmStudio: "--cask lm-studio"
            }
        }
    }

    @MainActor static func openDownload(_ target: Target) { NSWorkspace.shared.open(target.downloadURL) }
    @MainActor static func openURL(_ string: String) { if let u = URL(string: string) { NSWorkspace.shared.open(u) } }

    /// `brew install <spec>`, streaming progress. Returns true on exit code 0.
    static func installViaBrew(_ target: Target, onLine: @escaping @MainActor (String) -> Void) async -> Bool {
        await Shell.stream("brew install \(target.brewSpec)", onLine: onLine) == 0
    }

    /// Pull an Ollama model, streaming progress.
    static func pullModel(_ name: String, onLine: @escaping @MainActor (String) -> Void) async -> Bool {
        await Shell.stream("ollama pull \(name)", onLine: onLine) == 0
    }

    /// Brew installs only the Ollama CLI (no auto-started service), so start the
    /// server detached after install so discovery on :11434 works.
    static func startOllamaServe() {
        Task.detached { _ = await Shell.login("nohup ollama serve >/dev/null 2>&1 &") }
    }
}
