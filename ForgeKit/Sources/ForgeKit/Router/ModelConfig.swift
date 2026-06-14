import Foundation

/// Describes which model to talk to and how. The app persists/selects one of
/// these; `ModelRouter` turns it into a concrete provider.
public struct ModelConfig: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable { case ollamaNative, openAICompat, anthropic }

    public var id: String { "\(displayName)#\(modelID)" }
    public var kind: Kind
    public var baseURL: URL
    public var apiKey: String?
    public var modelID: String
    public var numCtx: Int
    public var displayName: String
    /// Smaller/local models cannot reliably produce line-replace diffs, so the
    /// skeleton uses whole-file writes everywhere; this flag lets the prompt and
    /// parser adapt later when a strong model is selected.
    public var supportsLineReplace: Bool

    public init(
        kind: Kind,
        baseURL: URL,
        apiKey: String?,
        modelID: String,
        numCtx: Int = 32_768,
        displayName: String,
        supportsLineReplace: Bool = false
    ) {
        self.kind = kind
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelID = modelID
        self.numCtx = numCtx
        self.displayName = displayName
        self.supportsLineReplace = supportsLineReplace
    }

    /// The local default: qwen2.5-coder:14b via Ollama's native API.
    public static let localDefault = ModelConfig(
        kind: .ollamaNative,
        baseURL: URL(string: "http://localhost:11434")!,
        apiKey: nil,
        modelID: "qwen2.5-coder:14b",
        numCtx: 32_768,
        displayName: "qwen2.5-coder:14b · local",
        supportsLineReplace: false
    )

    /// NVIDIA NIM (OpenAI-compatible). `model` should be a valid NIM model id.
    public static func nvidiaNIM(key: String, model: String) -> ModelConfig {
        ModelConfig(
            kind: .openAICompat,
            baseURL: URL(string: "https://integrate.api.nvidia.com/v1")!,
            apiKey: key,
            modelID: model,
            displayName: "NVIDIA NIM · cloud",
            supportsLineReplace: true
        )
    }

    public static func openAI(key: String, model: String) -> ModelConfig {
        ModelConfig(
            kind: .openAICompat,
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: key,
            modelID: model,
            displayName: "OpenAI · cloud",
            supportsLineReplace: true
        )
    }

    public static func anthropic(key: String, model: String) -> ModelConfig {
        ModelConfig(
            kind: .anthropic,
            baseURL: URL(string: "https://api.anthropic.com/v1/messages")!,
            apiKey: key,
            modelID: model,
            displayName: "Claude · cloud",
            supportsLineReplace: true
        )
    }
}
