import Foundation

/// Maps a `ModelConfig` to a concrete `ChatModel` provider and the matching
/// generation options. The one place that knows about provider kinds.
public enum ModelRouter {
    public static func provider(for config: ModelConfig) -> any ChatModel {
        switch config.kind {
        case .ollamaNative:
            OllamaNativeProvider(baseURL: config.baseURL, modelID: config.modelID)
        case .openAICompat:
            OpenAICompatProvider(baseURL: config.baseURL, apiKey: config.apiKey,
                                 modelID: config.modelID, extraHeaders: config.extraHeaders)
        case .anthropic:
            AnthropicProvider(apiKey: config.apiKey ?? "", modelID: config.modelID)
        }
    }

    public static func options(for config: ModelConfig) -> GenerationOptions {
        // 16k output so ambitious single-shot apps (charts, multiple views) don't get
        // truncated mid-file; 8k was too low and produced "unexpected end of file".
        GenerationOptions(temperature: 0.2, numCtx: config.numCtx, maxTokens: 16_384)
    }
}
