import Foundation

/// Assembles the message array for a model turn: system prompt + chat history +
/// the new user message (with optional project context inlined). Provider-
/// agnostic — the Anthropic adapter splits the system message out itself.
public struct MessageBuilder: Sendable {
    public init() {}

    public func build(
        systemPrompt: String,
        projectContext: String?,
        history: [ChatMessage],
        userPrompt: String,
        images: [String] = []
    ) -> [ChatMessage] {
        var messages: [ChatMessage] = [ChatMessage(role: .system, content: systemPrompt)]
        messages.append(contentsOf: history)

        let content: String
        if let context = projectContext, !context.isEmpty {
            content = "<project_context>\n\(context)\n</project_context>\n\n\(userPrompt)"
        } else {
            content = userPrompt
        }
        messages.append(ChatMessage(role: .user, content: content, imageDataURLs: images))
        return messages
    }

    /// A follow-up user turn that feeds back the errors for self-correction.
    public func errorTurn(_ report: ErrorReport) -> ChatMessage {
        let body = """
        The app has errors. Fix the root cause with the smallest correct edit, then re-emit the \
        affected file(s). Do not restart the dev server.

        \(report.formatted())
        """
        return ChatMessage(role: .user, content: body)
    }
}
