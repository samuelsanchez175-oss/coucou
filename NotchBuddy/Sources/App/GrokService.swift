import Foundation

/// Notch chat through the SpaceXAI Responses API (`https://api.x.ai/v1`).
/// The key lives in the Keychain under `xai-api-key`. Conversations stay on this Mac (`store: false`).
@MainActor
final class GrokService {
    static let shared = GrokService()

    private let endpoint = URL(string: "https://api.x.ai/v1/responses")!
    private var conversation: [[String: String]] = []

    private var model: String {
        let m = AppState.shared.grokModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? AppState.defaultGrokModel : m
    }

    func clearConversation() {
        conversation = []
    }

    func chat(query: String, context: PromptContext?, state: AppState) async {
        guard let key = KeychainStore.shared.get("xai-api-key"), !key.isEmpty else {
            await showError("Grok API key missing. Open settings.", state: state)
            return
        }

        var userText = query
        if conversation.isEmpty, let context {
            userText = contextText(context) + "\n\n" + query
        }
        conversation.append(["role": "user", "content": userText])

        var input: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
        ]
        input.append(contentsOf: conversation)

        let body: [String: Any] = [
            "model": model,
            "input": input,
            "store": false,
        ]

        do {
            let data = try await callAPI(body: body, key: key)
            let text = try GrokReplyText.text(in: data)
            conversation.append(["role": "assistant", "content": text])
            state.chatHistory.append(ChatMessage(role: .assistant, content: text))
            state.stateOverride = nil
            state.view = .prompt
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        } catch {
            conversation.removeLast()
            await showError(error.localizedDescription, state: state)
        }
    }

    private let systemPrompt = """
    You are Mochi, a personal assistant embedded in the notch of a Mac. \
    Respond in the user's language. Be thorough and complete — use as much detail as the task requires. \
    No markdown formatting (no **, no ##, no bullet dashes). Use plain text with line breaks.
    """

    private func callAPI(body: [String: Any], key: String) async throws -> Data {
        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if let message = GrokReplyText.apiError(in: data) {
                if message.localizedCaseInsensitiveContains("model") {
                    throw failure("Model not found: \(model). Pick another one in Settings.")
                }
                throw failure(message)
            }
            let raw = String(data: data, encoding: .utf8) ?? "unknown error"
            throw failure(raw)
        }
        return data
    }

    private func contextText(_ context: PromptContext) -> String {
        switch context {
        case .window(let app, let title, let url):
            var text = "Context — App: \(app), Window: \(title)"
            if let url { text += ", URL: \(url)" }
            return text
        case .file(let name, let fileURL):
            var text = "File: \(name)"
            if let fileURL, let contents = textContents(of: fileURL) {
                text += "\nFile contents:\n\(contents)"
            }
            return text
        }
    }

    private func textContents(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              data.count <= 200_000,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private func showError(_ message: String, state: AppState) async {
        state.stateOverride = .error
        state.noteMessage = message
        state.view = .note
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "Grok", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
