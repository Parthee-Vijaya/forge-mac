import Foundation

/// Describes which model to talk to and how. The app discovers/selects one of
/// these; `ModelRouter` turns it into a concrete provider.
public struct ModelConfig: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable { case ollamaNative, openAICompat, anthropic }
    public enum Source: String, Sendable, Equatable { case ollama, lmStudio, cloud }

    public var id: String { "\(source.rawValue):\(modelID)" }
    public var kind: Kind
    public var source: Source
    public var baseURL: URL
    public var apiKey: String?
    public var modelID: String
    public var numCtx: Int
    public var displayName: String
    /// Smaller/local models can't reliably produce line-replace diffs, so the
    /// skeleton uses whole-file writes; this flag lets the prompt/parser adapt
    /// later when a strong model is selected.
    public var supportsLineReplace: Bool

    public init(
        kind: Kind,
        source: Source,
        baseURL: URL,
        apiKey: String?,
        modelID: String,
        numCtx: Int = 32_768,
        displayName: String,
        supportsLineReplace: Bool = false
    ) {
        self.kind = kind
        self.source = source
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelID = modelID
        self.numCtx = numCtx
        self.displayName = displayName
        self.supportsLineReplace = supportsLineReplace
    }

    /// Used until model discovery runs / if nothing else is available.
    public static let localDefault = ModelConfig.ollama(model: "qwen2.5-coder:14b")

    /// Ollama via its NATIVE /api/chat endpoint (so num_ctx is honored).
    public static func ollama(
        model: String, baseURL: URL = URL(string: "http://localhost:11434")!
    ) -> ModelConfig {
        ModelConfig(kind: .ollamaNative, source: .ollama, baseURL: baseURL,
                    apiKey: nil, modelID: model, displayName: model, supportsLineReplace: false)
    }

    /// LM Studio via its OpenAI-compatible endpoint. LM Studio manages each
    /// model's context window itself, so the OpenAI-compat path is fine here.
    public static func lmStudio(
        model: String, baseURL: URL = URL(string: "http://localhost:1234/v1")!
    ) -> ModelConfig {
        ModelConfig(kind: .openAICompat, source: .lmStudio, baseURL: baseURL,
                    apiKey: nil, modelID: model, displayName: model, supportsLineReplace: false)
    }

    public static func nvidiaNIM(key: String, model: String) -> ModelConfig {
        ModelConfig(kind: .openAICompat, source: .cloud,
                    baseURL: URL(string: "https://integrate.api.nvidia.com/v1")!,
                    apiKey: key, modelID: model, displayName: model, supportsLineReplace: true)
    }

    public static func openAI(key: String, model: String) -> ModelConfig {
        ModelConfig(kind: .openAICompat, source: .cloud,
                    baseURL: URL(string: "https://api.openai.com/v1")!,
                    apiKey: key, modelID: model, displayName: model, supportsLineReplace: true)
    }

    public static func anthropic(key: String, model: String) -> ModelConfig {
        ModelConfig(kind: .anthropic, source: .cloud,
                    baseURL: URL(string: "https://api.anthropic.com/v1/messages")!,
                    apiKey: key, modelID: model, displayName: model, supportsLineReplace: true)
    }
}
