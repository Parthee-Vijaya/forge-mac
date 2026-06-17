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
    /// Extra HTTP headers for OpenAI-compatible requests — e.g. OpenRouter's
    /// optional `HTTP-Referer`/`X-Title` attribution headers. Empty for most.
    public var extraHeaders: [String: String]

    public init(
        kind: Kind,
        source: Source,
        baseURL: URL,
        apiKey: String?,
        modelID: String,
        numCtx: Int = 32_768,
        displayName: String,
        supportsLineReplace: Bool = false,
        extraHeaders: [String: String] = [:]
    ) {
        self.kind = kind
        self.source = source
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelID = modelID
        self.numCtx = numCtx
        self.displayName = displayName
        self.supportsLineReplace = supportsLineReplace
        self.extraHeaders = extraHeaders
    }

    /// Used until model discovery runs / if nothing else is available.
    public static let localDefault = ModelConfig.lmStudio(model: "qwen/qwen3.6-35b-a3b")

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

    /// Google Gemini via its OpenAI-compatible endpoint (has a free API tier), so
    /// it rides the existing OpenAICompatProvider — no new provider class needed.
    public static func gemini(key: String, model: String) -> ModelConfig {
        ModelConfig(kind: .openAICompat, source: .cloud,
                    baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/")!,
                    apiKey: key, modelID: model, displayName: model, supportsLineReplace: true)
    }

    /// OpenRouter — a single OpenAI-compatible gateway to many models (OpenAI,
    /// Anthropic, Google, Llama, …). Model ids are namespaced, e.g. `openai/gpt-4o`
    /// or `anthropic/claude-sonnet-4`. `HTTP-Referer`/`X-Title` are optional
    /// attribution headers OpenRouter surfaces on its dashboard/rankings.
    public static func openRouter(key: String, model: String) -> ModelConfig {
        ModelConfig(kind: .openAICompat, source: .cloud,
                    baseURL: URL(string: "https://openrouter.ai/api/v1")!,
                    apiKey: key, modelID: model, displayName: model, supportsLineReplace: true,
                    extraHeaders: [
                        "HTTP-Referer": "https://github.com/Parthee-Vijaya/forge-mac",
                        "X-Title": "Forge",
                    ])
    }

    /// Estimated USD cost of a call. Local models are free (0). For cloud models we
    /// look up a known price by model id; unknown cloud models return nil → the UI
    /// shows "—" rather than guessing.
    public func cost(promptTokens: Int, completionTokens: Int) -> Double? {
        if source != .cloud { return 0 }
        guard let (inputPerM, outputPerM) = Self.pricePerMTok(for: modelID) else { return nil }
        return Double(promptTokens) / 1_000_000 * inputPerM
             + Double(completionTokens) / 1_000_000 * outputPerM
    }

    /// Approximate USD price per 1M tokens (input, output) for known cloud models.
    /// Matched by substring so OpenRouter's namespaced ids (`openai/gpt-4o`) resolve,
    /// and any `:free` model is free. Conservative table — unknown → nil ("—").
    static func pricePerMTok(for modelID: String) -> (Double, Double)? {
        let id = modelID.lowercased()
        let table: [(String, (Double, Double))] = [
            (":free", (0, 0)),
            ("gpt-4o-mini", (0.15, 0.60)),
            ("gpt-4o", (2.50, 10.00)),
            ("gpt-4.1-mini", (0.40, 1.60)),
            ("gpt-4.1", (2.00, 8.00)),
            ("o4-mini", (1.10, 4.40)),
            ("claude-3-5-haiku", (0.80, 4.00)),
            ("claude-haiku", (0.80, 4.00)),
            ("claude-3-5-sonnet", (3.00, 15.00)),
            ("claude-sonnet", (3.00, 15.00)),
            ("claude-opus", (15.00, 75.00)),
            ("gemini-2.0-flash", (0.10, 0.40)),
            ("gemini-1.5-flash", (0.075, 0.30)),
            ("gemini-flash", (0.10, 0.40)),
            ("gemini-1.5-pro", (1.25, 5.00)),
            ("gemini-pro", (1.25, 5.00)),
        ]
        for (key, price) in table where id.contains(key) { return price }
        return nil
    }
}
