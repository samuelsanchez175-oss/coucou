import Foundation

/// One service under the home blob. The row names the model. Each ring is one real gate.
enum UsageService: String, CaseIterable, Equatable {
    case claude, grok, chatgpt, antigravity, grokbot

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .grok: return "Grok"
        case .chatgpt: return "ChatGPT"
        case .antigravity: return "Antigravity"
        case .grokbot: return "Grok Bot"
        }
    }

    /// Claude coral, Grok white, ChatGPT green, Antigravity blue, Grok Bot silver.
    var brandHex: String {
        switch self {
        case .claude: return "#D97757"
        case .grok: return "#F4F4F5"
        case .chatgpt: return "#10A37F"
        case .antigravity: return "#4285F4"
        case .grokbot: return "#C8CCD6"
        }
    }
}

/// One remaining-percent gate. A missing percent stays empty instead of copying another gate.
struct UsageGate: Equatable {
    var model: String
    var window: String
    var remaining: Int?
    /// When this gate refills. Shown as a date and a time.
    var replenishes: Date? = nil
}

/// The gates a service actually reported.
struct UsageLevels: Equatable {
    var gates: [UsageGate] = []

    var hasReading: Bool { gates.contains { $0.remaining != nil } }
}

/// One model line. Gates for that model sit beside the name.
struct UsageRow: Equatable, Identifiable {
    var model: String
    var gates: [UsageGate]
    var id: String { model }
}

/// Remaining-limit math and where the rows sit under the white blob.
enum UsageBehavior {
    static let services = [UsageService.claude, .grok, .chatgpt, .antigravity, .grokbot]
    static let ring: CGFloat = 18
    static let gap: CGFloat = 0
    /// Date on one line, time on the next. Tall enough for both at 10pt.
    static let row: CGFloat = 22
    static let header: CGFloat = 11
    /// Room for “Claude Sonnet 4.6” at 11pt. A longer name scales down, it does not ellipsize first.
    static let nameWidth: CGFloat = 82
    /// The percent sits to the right of the ring. “100%” at 10pt needs this width.
    static let percentWidth: CGFloat = 32
    /// Ring, a small gap, and the percent. The column caption starts on this group, then shifts left.
    static let meterWidth: CGFloat = 54
    /// How far “5 hours” and “Week” sit left of the meter center, toward the ring.
    static let headerNudge: CGFloat = 14
    /// How far those captions sit above the header row, clear of the rings.
    static let headerLift: CGFloat = 4
    /// Space after the percent before the refill date.
    static let dateGap: CGFloat = 6
    /// The clock, then air before the next ring. “12:00 AM” is the wide case.
    static let dateLane: CGFloat = 66
    /// Shared clocks stay in this order. A month follows only when a model has one.
    static let leadingWindows = ["5 hours", "Week"]
    static let laterWindows = ["Month"]
    /// Auto and named-model buckets stay off the home card.
    private static let hiddenWindows: Set<String> = ["Auto", "Named models"]
    /// Left inset of the rows. They sit under the blob and use the card width.
    static let stackLeading: CGFloat = 10
    /// Overview blob center, in island coordinates. Matches `ViewLayout.botX`.
    static let blobCenterX: CGFloat = 68
    static let blobDiameter: CGFloat = 58
    /// A five-hour pool resets inside this span. A later reset, up to eight days, is the week.
    private static let fiveHourSpan: TimeInterval = 6 * 60 * 60
    private static let weekSpan: TimeInterval = 8 * 24 * 60 * 60
    private static let monthSpan: TimeInterval = 40 * 24 * 60 * 60
    /// Clear space under the last model, reserved for the home player.
    static let shelfClearance: CGFloat = 34

    static var stackWidth: CGFloat { TerminalBehavior.overviewLeftCard - stackLeading - 8 }

    /// Top of the first model, just under the blob.
    static var stackTop: CGFloat {
        let centerY = TerminalBehavior.overviewBlobCenterY - TerminalBehavior.menuBarHeaderBand
        return centerY + blobDiameter / 2 + 2
    }

    static var stackHeight: CGFloat {
        header + gap + row * CGFloat(services.count) + gap * CGFloat(max(0, services.count - 1))
    }

    /// Column captions, left to right: five hours, week, then any later clock a model reported.
    static func columnWindows(_ gates: [UsageGate]) -> [String] {
        var present = Set(gates.map(\.window).filter { !$0.isEmpty })
        present.subtract(hiddenWindows)
        for window in leadingWindows { present.insert(window) }
        let preferred = leadingWindows + laterWindows
        let ordered = preferred.filter { present.contains($0) }
        let extra = present.subtracting(Set(preferred)).sorted()
        return ordered + extra
    }

    static func columnWidth(_ window: String) -> CGFloat {
        switch window {
        case "5 hours", "Week": return meterWidth + dateLane
        default: return meterWidth + dateLane
        }
    }

    /// A refill such as Oct 16, 3:24 PM. A dash, a missing date, or a reset already past stays blank.
    static func replenishReading(remaining: Int?, at date: Date?, now: Date = Date(), timeZone: TimeZone = .current) -> (day: String, time: String)? {
        guard remaining != nil, let date, date.timeIntervalSince(now) > -120 else { return nil }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = timeZone
        day.dateFormat = "MMM d"
        let clock = DateFormatter()
        clock.locale = day.locale
        clock.timeZone = timeZone
        clock.dateFormat = "h:mm a"
        return (day.string(from: date), clock.string(from: date))
    }

    static func replenishLabel(remaining: Int?, at date: Date?, now: Date = Date(), timeZone: TimeZone = .current) -> String? {
        guard let reading = replenishReading(remaining: remaining, at: date, now: now, timeZone: timeZone) else { return nil }
        return "\(reading.day), \(reading.time)"
    }

    /// The ring for one column. Five hours and week stay in place when that model has no such gate.
    /// A later clock is absent, so the row does not invent a dash for someone else's meter.
    static func placed(row: UsageRow, window: String) -> UsageGate? {
        if let gate = row.gates.first(where: { $0.window == window }) { return gate }
        guard leadingWindows.contains(window) else { return nil }
        return UsageGate(model: row.model, window: window, remaining: nil)
    }

    static func rows(service: UsageService, levels: UsageLevels) -> [UsageRow] {
        if levels.gates.isEmpty {
            return [UsageRow(model: service.title, gates: [UsageGate(model: service.title, window: "", remaining: nil)])]
        }
        var order: [String] = []
        var grouped: [String: [UsageGate]] = [:]
        for gate in levels.gates {
            if grouped[gate.model] == nil { order.append(gate.model) }
            grouped[gate.model, default: []].append(gate)
        }
        return order.map { UsageRow(model: $0, gates: grouped[$0] ?? []) }
    }

    static func number(_ remaining: Int?) -> String {
        guard let remaining else { return "—" }
        return "\(remaining)%"
    }

    /// 1 fills the ring. An unknown reading draws only the track.
    static func fraction(_ remaining: Int?) -> Double {
        guard let remaining else { return 0 }
        return min(1, max(0, Double(remaining) / 100))
    }

    static func detail(service: UsageService, gate: UsageGate) -> String {
        let name = gate.model.isEmpty ? service.title : gate.model
        if gate.window.isEmpty { return "\(name), no reading yet" }
        guard let remaining = gate.remaining else { return "\(name), \(gate.window), no reading yet" }
        if let when = replenishLabel(remaining: remaining, at: gate.replenishes) {
            return "\(name), \(gate.window), \(remaining)% left, refills \(when)"
        }
        return "\(name), \(gate.window), \(remaining)% left"
    }

    /// A saved model id, shown in plain words. Unknown ids keep their own words.
    static func displayModel(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let known = TerminalBehavior.modelTitle(trimmed)
        if known != trimmed && known != "Keys" { return known }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("gpt-") {
            let rest = trimmed.dropFirst(4)
            let parts = rest.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
            let version = parts.first.map(String.init) ?? ""
            let tail = parts.count > 1 ? capitalized(String(parts[1])) : ""
            return tail.isEmpty ? "GPT-\(version)" : "GPT-\(version) \(tail)"
        }
        if trimmed.contains("-") || trimmed.contains("_") {
            return trimmed.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { capitalized(String($0)) }.joined(separator: " ")
        }
        return trimmed
    }

    /// Utilization is the percent already used. Five-hour and weekly stay separate. Extra usage is ignored.
    static func parseClaude(_ data: Data, model: String = "Claude") -> UsageLevels {
        guard let root = json(data) else { return UsageLevels() }
        var gates: [UsageGate] = []
        append(&gates, model: model, window: "5 hours", used: field(root["five_hour"], key: "utilization"), replenishes: resetInstant(root["five_hour"]))
        append(&gates, model: model, window: "Week", used: field(root["seven_day"], key: "utilization"), replenishes: resetInstant(root["seven_day"]))
        let modelWeeks = [("seven_day_opus", "Opus"), ("seven_day_sonnet", "Sonnet"), ("seven_day_haiku", "Haiku")]
        for (key, name) in modelWeeks {
            append(&gates, model: name, window: "Week", used: field(root[key], key: "utilization"), replenishes: resetInstant(root[key]))
        }
        return UsageLevels(gates: gates)
    }

    /// Grok reports one weekly credit meter. A different product percent is its own gate.
    static func parseGrok(_ data: Data, model: String = "Grok") -> UsageLevels {
        guard let root = json(data) else { return UsageLevels() }
        let config = root["config"] as? [String: Any] ?? root
        var gates: [UsageGate] = []
        append(&gates, model: model, window: "Week", used: field(config, key: "creditUsagePercent"), replenishes: grokReset(config))
        for product in config["productUsage"] as? [[String: Any]] ?? [] {
            guard let used = field(product, key: "usagePercent") else { continue }
            let left = remaining(usedPercent: used)
            if gates.contains(where: { $0.window == "Week" && $0.remaining == left }) { continue }
            append(&gates, model: productName(product["product"] as? String), window: "Week", used: used)
        }
        return UsageLevels(gates: gates)
    }

    /// The primary window is five hours. The secondary window is the week. A longer quota is its own gate.
    static func parseChatGPT(_ data: Data, now: Date = Date()) -> UsageLevels {
        guard let root = json(data) else { return UsageLevels() }
        let rate = (root["rate_limit"] as? [String: Any])
            ?? ((root["payload"] as? [String: Any])?["rate_limits"] as? [String: Any])
        guard let rate else { return UsageLevels() }
        let model = chatModel(root)
        var gates: [UsageGate] = []
        appendChat(&gates, model: model, value: rate["primary_window"] ?? rate["primary"], fallback: "5 hours", now: now)
        appendChat(&gates, model: model, value: rate["secondary_window"] ?? rate["secondary"], fallback: "Week", now: now)
        if let extra = (root["additional_rate_limits"] ?? rate["additional_rate_limits"]) as? [String: Any] {
            for key in extra.keys.sorted() {
                appendChat(&gates, model: model, value: extra[key], fallback: nil, now: now)
            }
        }
        return UsageLevels(gates: gates)
    }

    /// Each model with a remaining fraction and a reset is its own gate. A reset alone is skipped.
    static func parseAntigravity(_ data: Data, now: Date = Date()) -> UsageLevels {
        guard let root = json(data),
              let status = root["userStatus"] as? [String: Any],
              let data = status["cascadeModelConfigData"] as? [String: Any],
              let configs = data["clientModelConfigs"] as? [[String: Any]] else { return UsageLevels() }
        var gates: [UsageGate] = []
        for config in configs {
            guard let quota = config["quotaInfo"] as? [String: Any],
                  let raw = field(quota, key: "remainingFraction"),
                  let reset = instant(quota["resetTime"]),
                  let window = windowTitle(until: reset, now: now) else { continue }
            gates.append(UsageGate(model: configModel(config), window: window, remaining: remaining(fraction: raw), replenishes: reset))
        }
        return UsageLevels(gates: gates)
    }

    /// The weekly allowance, the Auto bucket, and named models. A plan label is not a gate.
    static func parseGrokbot(status: Data, period: Data = Data(), now: Date = Date()) -> UsageLevels {
        var gates: [UsageGate] = []
        if let root = json(status), let used = field(root, key: "usagePercent") {
            let reset = instant(root["nextResetTimestampUtc"])
            let window = reset.flatMap { windowTitle(until: $0, now: now) }
            if let window {
                append(&gates, model: "Grok Bot", window: window, used: used, replenishes: reset)
            }
        }
        if let root = json(period), let plan = root["planUsage"] as? [String: Any] {
            append(&gates, model: "Grok Bot", window: "Auto", used: field(plan, key: "autoPercentUsed"))
            append(&gates, model: "Grok Bot", window: "Named models", used: field(plan, key: "apiPercentUsed"))
        }
        return UsageLevels(gates: gates)
    }

    static func remaining(usedPercent: Double) -> Int {
        let used = min(100, max(0, usedPercent))
        return Int((100 - used).rounded())
    }

    private static func append(_ gates: inout [UsageGate], model: String, window: String, used: Double?, replenishes: Date? = nil) {
        guard let used else { return }
        let gate = UsageGate(model: model, window: window, remaining: remaining(usedPercent: used), replenishes: replenishes)
        if gates.contains(where: { $0.model == gate.model && $0.window == gate.window && $0.remaining == gate.remaining }) {
            return
        }
        gates.append(gate)
    }

    private static func appendChat(_ gates: inout [UsageGate], model: String, value: Any?, fallback: String?, now: Date) {
        guard let used = field(value, key: "used_percent") else { return }
        let seconds = field(value, key: "limit_window_seconds")
        let window: String
        if let seconds, let title = windowTitle(seconds: seconds) {
            window = title
        } else if seconds == nil, let fallback {
            window = fallback
        } else {
            return
        }
        append(&gates, model: model, window: window, used: used, replenishes: resetInstant(value, now: now))
    }

    /// A reset instant from a usage window. Relative seconds count from now.
    private static func resetInstant(_ value: Any?, now: Date = Date()) -> Date? {
        guard let box = value as? [String: Any] else { return instant(value) }
        if let date = instant(box["resets_at"] ?? box["reset_at"] ?? box["resetAt"]) { return date }
        if let seconds = field(box, key: "reset_after_seconds") ?? field(box, key: "reset_after"), seconds > 0 {
            return now.addingTimeInterval(seconds)
        }
        return nil
    }

    /// The end of Grok's billing period, when the weekly credits refill.
    private static func grokReset(_ config: [String: Any]) -> Date? {
        let period = config["billingPeriod"] as? [String: Any]
        let current = config["currentPeriod"] as? [String: Any]
        return instant(
            period?["end"]
                ?? period?["endTimestamp"]
                ?? period?["endDate"]
                ?? period?["resets_at"]
                ?? config["billingPeriodEnd"]
                ?? current?["end"]
                ?? config["resets_at"]
        )
    }

    private static func chatModel(_ root: [String: Any]) -> String {
        guard let usage = root["model_usage"] as? [String: Any], !usage.isEmpty else { return "ChatGPT" }
        let names = usage.keys.sorted().map { displayModel($0) }.filter { !$0.isEmpty }
        if names.isEmpty { return "ChatGPT" }
        if names.count == 1 { return names[0] }
        return names.prefix(3).joined(separator: ", ")
    }

    private static func productName(_ raw: String?) -> String {
        switch raw {
        case "GrokBuild": return "Grok"
        case let name? where !name.isEmpty && name.count <= 24 && !name.contains("@"): return name
        default: return "Grok"
        }
    }

    private static func configModel(_ config: [String: Any]) -> String {
        for key in ["label", "displayName", "modelName"] {
            guard let text = config[key] as? String else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.count > 40 || trimmed.contains("@") { continue }
            return trimmed
        }
        return "Antigravity"
    }

    private static func capitalized(_ text: String) -> String {
        let words = text.split(separator: "-").map { word -> String in
            guard let first = word.first else { return String(word) }
            return first.uppercased() + word.dropFirst()
        }
        return words.joined(separator: " ")
    }

    /// Inside six hours is the five-hour pool. Later, through eight days, is the week. Through forty days is the month.
    private static func windowTitle(until reset: Date, now: Date) -> String? {
        let delta = reset.timeIntervalSince(now)
        guard delta >= 0 else { return nil }
        return windowTitle(seconds: delta)
    }

    private static func windowTitle(seconds: Double) -> String? {
        guard seconds > 0 else { return nil }
        if seconds <= fiveHourSpan { return "5 hours" }
        if seconds <= weekSpan { return "Week" }
        if seconds <= monthSpan { return "Month" }
        return nil
    }

    private static func remaining(fraction: Double) -> Int {
        if fraction > 1 {
            return remaining(usedPercent: 100 - min(100, fraction))
        }
        return Int((min(1, max(0, fraction)) * 100).rounded())
    }

    private static func instant(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return date(seconds: number.doubleValue)
        }
        guard let text = value as? String else { return nil }
        if let number = Double(text) { return date(seconds: number) }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    private static func date(seconds: Double) -> Date? {
        guard seconds.isFinite, seconds > 1_000_000_000 else { return nil }
        let unix = seconds > 1_000_000_000_000 ? seconds / 1000 : seconds
        return Date(timeIntervalSince1970: unix)
    }

    private static func json(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func field(_ object: Any?, key: String) -> Double? {
        guard let dict = object as? [String: Any], let number = dict[key] as? NSNumber else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }
}
