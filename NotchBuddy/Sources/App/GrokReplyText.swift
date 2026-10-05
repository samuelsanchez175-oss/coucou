import Foundation

/// Pulls the assistant text out of a SpaceXAI Responses API body.
enum GrokReplyText {
    struct Failure: Error, Equatable, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Error string from a non-success body, when the API sent one.
    static func apiError(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let err = json["error"] as? [String: Any] {
            let message = (err["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty { return message }
        }
        if let err = json["error"] as? String {
            let message = err.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty { return message }
        }
        return nil
    }

    static func text(in data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(message: "Unexpected API response.")
        }
        if let message = apiError(in: data) {
            throw Failure(message: message)
        }
        if let direct = json["output_text"] as? String {
            let trimmed = direct.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        var parts: [String] = []
        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                if let content = item["content"] as? [[String: Any]] {
                    for block in content where isTextBlock(block) {
                        if let text = block["text"] as? String {
                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty { parts.append(trimmed) }
                        }
                    }
                }
            }
        }

        let joined = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if joined.isEmpty {
            throw Failure(message: "No response text.")
        }
        return joined
    }

    private static func isTextBlock(_ block: [String: Any]) -> Bool {
        guard let type = block["type"] as? String else { return false }
        return type == "output_text" || type == "text"
    }
}
