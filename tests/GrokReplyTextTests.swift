import Foundation

@main
enum GrokReplyTextTests {
    static func main() {
        let message = """
        {"output":[{"type":"reasoning","summary":[]},{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hello from Grok"}]}]}
        """.data(using: .utf8)!
        precondition(try! GrokReplyText.text(in: message) == "Hello from Grok")

        let joined = """
        {"output":[{"type":"message","content":[{"type":"output_text","text":"One"},{"type":"output_text","text":"Two"}]}]}
        """.data(using: .utf8)!
        precondition(try! GrokReplyText.text(in: joined) == "One\nTwo")

        let direct = #"{"output_text":" Shortcut "}"#.data(using: .utf8)!
        precondition(try! GrokReplyText.text(in: direct) == "Shortcut")

        let err = #"{"error":{"message":"Incorrect API key","type":"invalid_request_error"}}"#.data(using: .utf8)!
        do {
            _ = try GrokReplyText.text(in: err)
            preconditionFailure("error body should throw")
        } catch let failure as GrokReplyText.Failure {
            precondition(failure.message == "Incorrect API key")
        } catch {
            preconditionFailure("unexpected error \(error)")
        }
        precondition(GrokReplyText.apiError(in: err) == "Incorrect API key")

        let empty = #"{"output":[]}"#.data(using: .utf8)!
        do {
            _ = try GrokReplyText.text(in: empty)
            preconditionFailure("empty output should throw")
        } catch let failure as GrokReplyText.Failure {
            precondition(failure.message == "No response text.")
        } catch {
            preconditionFailure("unexpected error \(error)")
        }

        print("Grok reply text: 5 cases passed")
    }
}
