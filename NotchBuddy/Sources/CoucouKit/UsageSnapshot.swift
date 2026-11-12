import Foundation

/// Cross-process usage snapshot shared with the Mac widget through the App Group.
/// The main app writes this file after every poll; the widget reads it in its
/// timeline provider. Codable DTO on purpose, so new services ship without
/// changing widget code.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var updatedAt: Date
    public var services: [Service]

    public init(updatedAt: Date, services: [Service]) {
        self.updatedAt = updatedAt
        self.services = services
    }

    public struct Service: Codable, Equatable, Sendable, Identifiable {
        /// Stable service id (matches the pill id and the UsageService raw value).
        public var id: String
        public var title: String
        public var brandHex: String
        public var gates: [Gate]

        public init(id: String, title: String, brandHex: String, gates: [Gate]) {
            self.id = id
            self.title = title
            self.brandHex = brandHex
            self.gates = gates
        }

        /// Smallest remaining across the service's gates, or nil when nothing is known.
        public var worstRemaining: Int? {
            gates.compactMap(\.remaining).min()
        }
    }

    public struct Gate: Codable, Equatable, Sendable, Identifiable {
        public var model: String
        public var window: String
        public var remaining: Int?
        public var replenishes: Date?
        public var savedAt: Date?

        public var id: String { "\(model)|\(window)" }

        public init(model: String, window: String, remaining: Int? = nil, replenishes: Date? = nil, savedAt: Date? = nil) {
            self.model = model
            self.window = window
            self.remaining = remaining
            self.replenishes = replenishes
            self.savedAt = savedAt
        }
    }
}

public extension UsageSnapshot {
    static let appGroupID = "group.fr.louisraille.Coucou"
    static let fileName = "usage-snapshot.json"
    /// Widget kind, used by `WidgetCenter.shared.reloadAllTimelines(ofKind:)`.
    static let widgetKind = "CoucouMacUsage"

    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    static func load() -> UsageSnapshot? {
        guard let url = containerURL(),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    func write() {
        guard let url = Self.containerURL() else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? encoder.encode(self) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

public extension UsageSnapshot {
    /// Sample payload for widget placeholders and previews.
    static let sample = UsageSnapshot(
        updatedAt: Date(),
        services: [
            Service(id: "claude", title: "Claude", brandHex: "#D97757", gates: [
                Gate(model: "Claude", window: "5 hours", remaining: 68, replenishes: Date().addingTimeInterval(3600 * 3), savedAt: Date()),
                Gate(model: "Claude", window: "Week", remaining: 82, savedAt: Date()),
            ]),
            Service(id: "grok", title: "Grok", brandHex: "#F4F4F5", gates: [
                Gate(model: "Grok", window: "2 hours", remaining: 41, replenishes: Date().addingTimeInterval(3600), savedAt: Date()),
            ]),
            Service(id: "chatgpt", title: "ChatGPT", brandHex: "#10A37F", gates: [
                Gate(model: "GPT-5", window: "5 hours", remaining: 12, replenishes: Date().addingTimeInterval(3600 * 2), savedAt: Date()),
            ]),
            Service(id: "antigravity", title: "Antigravity", brandHex: "#4285F4", gates: [
                Gate(model: "Gemini", window: "Day", remaining: 55, replenishes: Date().addingTimeInterval(3600 * 8), savedAt: Date()),
            ]),
            Service(id: "grokbot", title: "Grok Bot", brandHex: "#C8CCD6", gates: [
                Gate(model: "Grok Bot", window: "Week", remaining: 73, savedAt: Date()),
            ]),
        ]
    )
}
