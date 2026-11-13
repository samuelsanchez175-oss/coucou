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

    /// Every location the snapshot may live at, in read order. The app writes
    /// to all writable ones; the widget reads the newest existing file. Both
    /// paths exist so adhoc / local-dev builds work even when the App Group
    /// container is not resolvable.
    static func candidateURLs() -> [URL] {
        var urls: [URL] = []
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            urls.append(group.appendingPathComponent(fileName))
        }
        // The widget runs sandboxed, so `urls(for: .applicationSupportDirectory …)`
        // returns its OWN container. Resolve the real user home through getpwuid
        // so a Developer-ID dev build with a temp-exception entitlement can
        // reach the snapshot the main app writes to ~/Library/Application Support.
        if let realHome = realUserHome() {
            urls.append(URL(fileURLWithPath: realHome)
                .appendingPathComponent("Library/Application Support/Coucou", isDirectory: true)
                .appendingPathComponent(fileName))
        }
        return urls
    }

    private static func realUserHome() -> String? {
        guard let pw = getpwuid(getuid()) else { return nil }
        return String(cString: pw.pointee.pw_dir)
    }

    static func containerURL() -> URL? { candidateURLs().first }

    static func load() -> UsageSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        // Return the newest readable snapshot across all candidate locations.
        var newest: (date: Date, snapshot: UsageSnapshot)?
        for url in candidateURLs() {
            guard let data = try? Data(contentsOf: url),
                  let snap = try? decoder.decode(UsageSnapshot.self, from: data) else { continue }
            if newest == nil || snap.updatedAt > newest!.date {
                newest = (snap.updatedAt, snap)
            }
        }
        return newest?.snapshot
    }

    func write() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        // Write to every candidate location so whichever one the widget's
        // sandbox can reach has a fresh snapshot.
        for url in Self.candidateURLs() {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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
