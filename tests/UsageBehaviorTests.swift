import Foundation

/// IslandTypes stores this on a task. The real cases live with the blob.
enum EyeShape: String, Equatable {
    case round
}

@main
enum UsageBehaviorTests {
    static func main() {
        testOrderAndColors()
        testClaudeKeepsBothWindows()
        testGrokWeeklyRemaining()
        testChatGPTWindows()
        testAntigravityWindows()
        testGrokbotGates()
        testNumberAndArc()
        testStackSitsUnderTheBlob()
        testRingsAreInTheLeftCard()
        testColumnsReadLeftToRight()
        print("Usage behavior: 10 cases passed")
    }

    static func testOrderAndColors() {
        precondition(UsageBehavior.services.map(\.title) == ["Claude", "Grok", "ChatGPT", "Antigravity", "Grok Bot"])
        precondition(UsageBehavior.services.map(\.brandHex) == ["#D97757", "#F4F4F5", "#10A37F", "#4285F4", "#C8CCD6"])
    }

    static func testClaudeKeepsBothWindows() {
        let both = """
        {"five_hour":{"utilization":95},"seven_day":{"utilization":29},"extra_usage":{"utilization":100},"seven_day_opus":null}
        """
        let levels = UsageBehavior.parseClaude(Data(both.utf8), model: "Claude Sonnet 4.6")
        precondition(remaining(levels, "Claude Sonnet 4.6", "5 hours") == 5, "the five-hour window stays its own ring")
        precondition(remaining(levels, "Claude Sonnet 4.6", "Week") == 71, "the weekly window stays its own ring")
        precondition(levels.gates.count == 2, "extra usage and an empty model week are not rings")
        let weekly = #"{"five_hour":null,"seven_day":{"utilization":29}}"#
        let weekOnly = UsageBehavior.parseClaude(Data(weekly.utf8))
        precondition(weekOnly.gates.count == 1)
        precondition(remaining(weekOnly, "Claude", "Week") == 71)
        precondition(!weekOnly.gates.contains { $0.window == "5 hours" })
        let opus = #"{"five_hour":{"utilization":95},"seven_day":{"utilization":29},"seven_day_opus":{"utilization":10},"seven_day_sonnet":{"utilization":40}}"#
        let models = UsageBehavior.parseClaude(Data(opus.utf8), model: "Claude Sonnet 4.6")
        precondition(remaining(models, "Opus", "Week") == 90)
        precondition(remaining(models, "Sonnet", "Week") == 60)
        precondition(models.gates.count == 4)
        let empty = UsageBehavior.parseClaude(Data("{}".utf8))
        precondition(empty.gates.isEmpty)
    }

    static func testGrokWeeklyRemaining() {
        let body = #"{"config":{"creditUsagePercent":4,"productUsage":[{"product":"GrokBuild","usagePercent":4}]}}"#
        let levels = UsageBehavior.parseGrok(Data(body.utf8), model: "Grok 4.7")
        precondition(levels.gates.count == 1, "the product meter is the same weekly reading")
        precondition(remaining(levels, "Grok 4.7", "Week") == 96)
        precondition(!levels.gates.contains { $0.window == "5 hours" }, "one weekly reading is not copied into the five-hour ring")
        let split = #"{"config":{"creditUsagePercent":4,"productUsage":[{"product":"GrokBuild","usagePercent":4},{"product":"Other","usagePercent":20}]}}"#
        let extra = UsageBehavior.parseGrok(Data(split.utf8))
        precondition(remaining(extra, "Grok", "Week") == 96)
        precondition(remaining(extra, "Other", "Week") == 80)
        let empty = UsageBehavior.parseGrok(Data(#"{"config":{}}"#.utf8))
        precondition(empty.gates.isEmpty)
        let when = iso("2026-10-14T03:00:00Z")
        let utc = TimeZone(secondsFromGMT: 0)!
        let period = #"{"config":{"creditUsagePercent":9,"billingPeriodEnd":"2026-10-20T15:55:14.449664+00:00","productUsage":[{"product":"GrokBuild","usagePercent":9}]}}"#
        let billed = UsageBehavior.parseGrok(Data(period.utf8), model: "Grok 4.7")
        precondition(billed.gates.count == 1, "a matching product meter is not a second ring")
        let billedWeek = billed.gates.first
        precondition(UsageBehavior.replenishLabel(remaining: billedWeek?.remaining, at: billedWeek?.replenishes, now: when, timeZone: utc) == "Oct 20, 3:55 PM")
        let currentOnly = #"{"config":{"creditUsagePercent":9,"currentPeriod":{"end":"2026-10-20T15:55:14.449664+00:00"}}}"#
        let fromCurrent = UsageBehavior.parseGrok(Data(currentOnly.utf8), model: "Grok 4.7")
        let currentWeek = fromCurrent.gates.first
        precondition(UsageBehavior.replenishLabel(remaining: currentWeek?.remaining, at: currentWeek?.replenishes, now: when, timeZone: utc) == "Oct 20, 3:55 PM")
    }

    static func testChatGPTWindows() {
        let live = """
        {"rate_limit":{"primary_window":{"used_percent":42,"limit_window_seconds":18000},"secondary_window":{"used_percent":22,"limit_window_seconds":604800}},"model_usage":{"gpt-6-astra":{"available":true}},"additional_rate_limits":{"later":{"used_percent":10,"limit_window_seconds":2592000}},"code_review_rate_limit":null}
        """
        let levels = UsageBehavior.parseChatGPT(Data(live.utf8))
        precondition(remaining(levels, "GPT-6 Astra", "5 hours") == 58)
        precondition(remaining(levels, "GPT-6 Astra", "Week") == 78)
        precondition(remaining(levels, "GPT-6 Astra", "Month") == 90, "a third quota window stays its own ring")
        precondition(levels.gates.count == 3, "a model with no percent does not invent a ring")
        let snapshot = #"{"payload":{"rate_limits":{"primary":{"used_percent":0},"secondary":{"used_percent":10}}}}"#
        let saved = UsageBehavior.parseChatGPT(Data(snapshot.utf8))
        precondition(remaining(saved, "ChatGPT", "5 hours") == 100)
        precondition(remaining(saved, "ChatGPT", "Week") == 90)
        let empty = UsageBehavior.parseChatGPT(Data("{}".utf8))
        precondition(empty.gates.isEmpty)
        let now = iso("2026-10-14T03:00:00Z")
        let utc = TimeZone(secondsFromGMT: 0)!
        let stamped = """
        {"rate_limit":{"primary_window":{"used_percent":82,"limit_window_seconds":18000,"reset_at":1791950524},"secondary_window":{"used_percent":28,"limit_window_seconds":604800,"reset_after_seconds":500000}},"model_usage":{"gpt-6-astra":{"available":true}}}
        """
        let dated = UsageBehavior.parseChatGPT(Data(stamped.utf8), now: now)
        let primary = dated.gates.first { $0.window == "5 hours" }
        let secondary = dated.gates.first { $0.window == "Week" }
        precondition(UsageBehavior.replenishLabel(remaining: primary?.remaining, at: primary?.replenishes, now: now, timeZone: utc) == "Oct 14, 4:02 AM")
        precondition(UsageBehavior.replenishLabel(remaining: secondary?.remaining, at: secondary?.replenishes, now: now, timeZone: utc) == "Oct 19, 9:53 PM")
        precondition(UsageBehavior.replenishLabel(remaining: saved.gates.first?.remaining, at: saved.gates.first?.replenishes, now: now, timeZone: utc) == nil)
    }

    static func testAntigravityWindows() {
        let full = """
        {"userStatus":{"cascadeModelConfigData":{"clientModelConfigs":[
          {"label":"Gemini 3.8 Flash","quotaInfo":{"remainingFraction":1,"resetTime":"2026-10-14T05:42:49Z"}},
          {"label":"Claude Sonnet","quotaInfo":{"resetTime":"2026-10-16T16:58:29Z"}}
        ]}}}
        """
        let now = iso("2026-10-14T00:56:21Z")
        let flash = UsageBehavior.parseAntigravity(Data(full.utf8), now: now)
        precondition(remaining(flash, "Gemini 3.8 Flash", "5 hours") == 100)
        precondition(flash.gates.count == 1, "a reset with no fraction is not a ring")
        let tight = """
        {"userStatus":{"cascadeModelConfigData":{"clientModelConfigs":[
          {"label":"Gemini Flash","quotaInfo":{"remainingFraction":1,"resetTime":"2026-10-14T04:00:00Z"}},
          {"label":"Gemini Pro","quotaInfo":{"remainingFraction":0.4,"resetTime":"2026-10-20T00:00:00Z"}}
        ]}}}
        """
        let split = UsageBehavior.parseAntigravity(Data(tight.utf8), now: now)
        precondition(remaining(split, "Gemini Flash", "5 hours") == 100)
        precondition(remaining(split, "Gemini Pro", "Week") == 40)
        let twins = """
        {"userStatus":{"cascadeModelConfigData":{"clientModelConfigs":[
          {"label":"Gemini Flash","quotaInfo":{"remainingFraction":1,"resetTime":"2026-10-14T04:00:00Z"}},
          {"label":"Gemini Pro","quotaInfo":{"remainingFraction":0.4,"resetTime":"2026-10-14T05:00:00Z"}}
        ]}}}
        """
        let tighter = UsageBehavior.parseAntigravity(Data(twins.utf8), now: now)
        precondition(remaining(tighter, "Gemini Flash", "5 hours") == 100)
        precondition(remaining(tighter, "Gemini Pro", "5 hours") == 40, "each model keeps its own gate")
        let unknown = """
        {"userStatus":{"cascadeModelConfigData":{"clientModelConfigs":[
          {"label":"Gemini Flash","quotaInfo":{"remainingFraction":0.4}}
        ]}}}
        """
        let unlabeled = UsageBehavior.parseAntigravity(Data(unknown.utf8), now: now)
        precondition(unlabeled.gates.isEmpty, "a fraction with no window is not copied into a ring")
        let empty = UsageBehavior.parseAntigravity(Data(#"{"userStatus":{}}"#.utf8), now: now)
        precondition(empty.gates.isEmpty)
    }

    static func testGrokbotGates() {
        let now = iso("2026-10-14T00:00:00Z")
        let start = Int(iso("2026-10-01T00:00:00Z").timeIntervalSince1970 * 1000)
        let end = Int(iso("2026-10-31T00:00:00Z").timeIntervalSince1970 * 1000)
        let status = #"{"usagePercent":100,"nextResetTimestampUtc":"2026-10-16T15:24:00Z","grokPlanLabel":"hidden"}"#
        let period = """
        {"billingCycleStart":"\(start)","billingCycleEnd":"\(end)","planUsage":{"autoPercentUsed":100,"apiPercentUsed":0,"totalPercentUsed":62}}
        """
        let levels = UsageBehavior.parseGrokbot(status: Data(status.utf8), period: Data(period.utf8), now: now)
        precondition(remaining(levels, "Grok Bot", "Week") == 0)
        precondition(remaining(levels, "Grok Bot", "Auto") == 0)
        precondition(remaining(levels, "Grok Bot", "Named models") == 100)
        precondition(levels.gates.count == 3, "the period total and the plan name are not extra rings")
        let weekGate = levels.gates.first { $0.window == "Week" }
        let utc = TimeZone(secondsFromGMT: 0)!
        precondition(UsageBehavior.replenishLabel(remaining: weekGate?.remaining, at: weekGate?.replenishes, now: now, timeZone: utc) == "Oct 16, 3:24 PM")
        precondition(!levels.gates.contains { $0.model.contains("hidden") })
        let missing = UsageBehavior.parseGrokbot(status: Data("{}".utf8), period: Data("{}".utf8), now: now)
        precondition(missing.gates.isEmpty)
        let rows = UsageBehavior.rows(service: .grokbot, levels: missing)
        precondition(rows.count == 1)
        precondition(rows[0].model == "Grok Bot")
        precondition(rows[0].gates.first?.remaining == nil)
    }

    private static func remaining(_ levels: UsageLevels, _ model: String, _ window: String) -> Int? {
        levels.gates.first { $0.model == model && $0.window == window }?.remaining
    }

    private static func iso(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)!
    }

    static func testNumberAndArc() {
        precondition(UsageBehavior.displayModel("gpt-6-astra") == "GPT-6 Astra")
        precondition(UsageBehavior.displayModel("grok-4.7") == "Grok 4.7")
        precondition(UsageBehavior.displayModel("claude-sonnet-4-6") == "Claude Sonnet 4.6")
        precondition(UsageBehavior.number(nil) == "—")
        precondition(UsageBehavior.number(5) == "5%")
        precondition(UsageBehavior.number(100) == "100%")
        precondition(UsageBehavior.fraction(nil) == 0)
        precondition(UsageBehavior.fraction(100) == 1)
        precondition(UsageBehavior.fraction(5) == 0.05)
        let five = UsageGate(model: "Claude Sonnet 4.6", window: "5 hours", remaining: 5)
        precondition(UsageBehavior.detail(service: .claude, gate: five) == "Claude Sonnet 4.6, 5 hours, 5% left")
        let missing = UsageGate(model: "Grok 4.7", window: "Week", remaining: nil)
        precondition(UsageBehavior.detail(service: .grok, gate: missing) == "Grok 4.7, Week, no reading yet")
        let unread = UsageGate(model: "Grok Bot", window: "", remaining: nil)
        precondition(UsageBehavior.detail(service: .grokbot, gate: unread) == "Grok Bot, no reading yet")
    }

    static func testStackSitsUnderTheBlob() {
        let blobCenterY = TerminalBehavior.overviewBlobCenterY - TerminalBehavior.menuBarHeaderBand
        let blobBottom = blobCenterY + UsageBehavior.blobDiameter / 2
        precondition(UsageBehavior.stackTop >= blobBottom + 2, "the rings start under the blob")
        precondition(UsageBehavior.stackLeading >= 0)
        precondition(UsageBehavior.stackLeading + UsageBehavior.stackWidth <= TerminalBehavior.overviewLeftCard)
        let body = TerminalBehavior.drawerBodyHeight(layoutHeight: TerminalBehavior.overviewHeight, hasNotch: true)
        // The pull pill keeps 12pt under the page, and the shelf is the bottom 34pt of what remains.
        let shelfTop = body - 12 - UsageBehavior.shelfClearance
        precondition(
            UsageBehavior.stackTop + UsageBehavior.stackHeight + 8 <= shelfTop,
            "five model rows stay above the audio shelf"
        )
        precondition(UsageBehavior.services.count == 5)
        precondition(UsageBehavior.ring >= 16)
        precondition(UsageBehavior.headerNudge >= 12, "the hour and week captions sit further left")
        precondition(UsageBehavior.headerLift >= 4, "the hour and week captions sit above the rings")
    }

    static func testRingsAreInTheLeftCard() {
        let source = try! String(contentsOfFile: "NotchBuddy/Sources/App/IslandViewContent.swift", encoding: .utf8)
        guard let overview = source.range(of: "struct OverviewView"),
              let cluster = source.range(of: "TerminalClusterView()") else {
            preconditionFailure("overview layout moved")
        }
        let left = source[overview.lowerBound..<cluster.lowerBound]
        precondition(left.contains("UsageRingStack"), "the rings are not under the blob")
        precondition(!source[cluster.lowerBound...].prefix(400).contains("UsageRingStack"), "the rings are not in the terminal card")
        guard let stack = source.range(of: "struct UsageRingStack") else {
            preconditionFailure("usage rings moved")
        }
        let body = source[stack.lowerBound...].prefix(1600)
        precondition(body.contains("row.model"), "each row names the model")
        precondition(body.contains("gate.window"), "each gate keeps its own caption")
    }

    static func testColumnsReadLeftToRight() {
        let gates = [
            UsageGate(model: "Grok Bot", window: "Named models", remaining: 100),
            UsageGate(model: "Grok Bot", window: "Auto", remaining: 0),
            UsageGate(model: "Claude Sonnet 4.6", window: "Week", remaining: 70),
            UsageGate(model: "Claude Sonnet 4.6", window: "5 hours", remaining: 0),
        ]
        precondition(UsageBehavior.columnWindows(gates) == ["5 hours", "Week"])
        let grok = UsageRow(model: "Grok 4.7", gates: [UsageGate(model: "Grok 4.7", window: "Week", remaining: 92)])
        precondition(UsageBehavior.placed(row: grok, window: "5 hours")?.remaining == nil)
        precondition(UsageBehavior.placed(row: grok, window: "Week")?.remaining == 92)
        precondition(UsageBehavior.placed(row: grok, window: "Auto") == nil)
        let rowWidth = 6 + 2 + UsageBehavior.nameWidth + 2 + UsageBehavior.columnWidth("5 hours") + 2 + UsageBehavior.columnWidth("Week")
        precondition(rowWidth <= UsageBehavior.stackWidth, "name, five hours, and week fit the card")
        precondition(UsageBehavior.columnWidth("5 hours") > 76, "the five-hour column has room beside the ring")
        precondition(UsageBehavior.dateGap >= 4, "the refill date sits clear of the percent")
        let spent = #"{"five_hour":{"utilization":100,"resets_at":"2026-10-14T03:00:00Z"}}"#
        let claude = UsageBehavior.parseClaude(Data(spent.utf8), model: "Claude Sonnet 4.6")
        let five = claude.gates.first { $0.window == "5 hours" }
        let zone = TimeZone(secondsFromGMT: 0)!
        let morning = iso("2026-10-13T12:00:00Z")
        precondition(five?.remaining == 0)
        precondition(UsageBehavior.replenishLabel(remaining: five?.remaining, at: five?.replenishes, now: morning, timeZone: zone) == "Oct 14, 3:00 AM")
        precondition(UsageBehavior.replenishLabel(remaining: 70, at: five?.replenishes, now: morning, timeZone: zone) == "Oct 14, 3:00 AM")
        precondition(UsageBehavior.replenishLabel(remaining: nil, at: five?.replenishes, now: morning, timeZone: zone) == nil)
        precondition(UsageBehavior.replenishLabel(remaining: 0, at: nil) == nil)
        precondition(UsageBehavior.replenishLabel(remaining: 10, at: five?.replenishes, now: iso("2026-10-15T00:00:00Z"), timeZone: zone) == nil)
        let fractional = #"{"five_hour":{"utilization":14,"resets_at":"2026-10-14T08:09:59.626411+00:00"},"seven_day":{"utilization":31,"resets_at":"2026-10-19T03:59:59.626438+00:00"}}"#
        let live = UsageBehavior.parseClaude(Data(fractional.utf8), model: "Claude Sonnet 4.6")
        let liveNow = iso("2026-10-14T03:00:00Z")
        let hour = live.gates.first { $0.window == "5 hours" }
        let week = live.gates.first { $0.window == "Week" }
        precondition(UsageBehavior.replenishLabel(remaining: hour?.remaining, at: hour?.replenishes, now: liveNow, timeZone: zone) == "Oct 14, 8:09 AM")
        precondition(UsageBehavior.replenishLabel(remaining: week?.remaining, at: week?.replenishes, now: liveNow, timeZone: zone) == "Oct 19, 3:59 AM")
        let bare = #"{"five_hour":{"utilization":0,"resets_at":null},"seven_day":{"utilization":30}}"#
        let undated = UsageBehavior.parseClaude(Data(bare.utf8))
        let bareHour = undated.gates.first { $0.window == "5 hours" }
        let bareWeek = undated.gates.first { $0.window == "Week" }
        precondition(UsageBehavior.replenishLabel(remaining: bareHour?.remaining, at: bareHour?.replenishes, now: liveNow, timeZone: zone) == nil)
        precondition(UsageBehavior.replenishLabel(remaining: bareWeek?.remaining, at: bareWeek?.replenishes, now: liveNow, timeZone: zone) == nil)
    }
}
