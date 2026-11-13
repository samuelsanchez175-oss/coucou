import SwiftUI
import WidgetKit

// Mac widget: shows what is left of each AI plan. The main Mac app writes a
// snapshot into the App Group container after every poll; this widget reads
// that snapshot. See `UsageSnapshot` in CoucouKit for the on-disk shape.

@main
struct CoucouMacWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
    }
}

// MARK: - Timeline

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
    let placeholder: Bool
}

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .sample, placeholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snap = UsageSnapshot.load()
        completion(UsageEntry(date: .now, snapshot: snap ?? .sample, placeholder: snap == nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let snap = UsageSnapshot.load()
        let entry = UsageEntry(date: .now, snapshot: snap ?? UsageSnapshot(updatedAt: .now, services: []),
                               placeholder: snap == nil)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

// MARK: - Widget configuration

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: UsageSnapshot.widgetKind, provider: UsageTimelineProvider()) { entry in
            UsageView(entry: entry)
                .containerBackground(for: .widget) { Color.black.opacity(0.85) }
        }
        .configurationDisplayName("AI Usage")
        .description("How much of each AI plan you have left.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct UsageView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallView(snapshot: entry.snapshot, placeholder: entry.placeholder)
        case .systemMedium:
            GridView(snapshot: entry.snapshot, placeholder: entry.placeholder, maxRows: 4, compact: true)
        default:
            GridView(snapshot: entry.snapshot, placeholder: entry.placeholder, maxRows: 8, compact: false)
        }
    }
}

// MARK: - Column picking

/// Pick up to two window strings to use as grid columns: the two most common
/// windows across services, ordered shortest first.
private func pickColumns(_ snapshot: UsageSnapshot) -> [String] {
    var counts: [String: Int] = [:]
    for service in snapshot.services {
        for gate in service.gates {
            counts[gate.window, default: 0] += 1
        }
    }
    let sorted = counts.sorted { (a, b) in
        if a.value != b.value { return a.value > b.value }
        return windowRank(a.key) < windowRank(b.key)
    }
    let top = Array(sorted.prefix(2))
    return top.sorted { windowRank($0.key) < windowRank($1.key) }.map(\.key)
}

/// Rough ordering so "5 hours" lands left of "Week".
private func windowRank(_ w: String) -> Int {
    let lower = w.lowercased()
    if lower.contains("minute") { return 0 }
    if lower.contains("hour") { return 1 }
    if lower.contains("day") { return 2 }
    if lower.contains("week") { return 3 }
    if lower.contains("month") { return 4 }
    return 5
}

// MARK: - Small (lowest)

private struct SmallView: View {
    let snapshot: UsageSnapshot
    let placeholder: Bool

    private var worst: (service: UsageSnapshot.Service, gate: UsageSnapshot.Gate)? {
        var picked: (UsageSnapshot.Service, UsageSnapshot.Gate)?
        for service in snapshot.services {
            for gate in service.gates where gate.remaining != nil {
                let current = picked?.1.remaining ?? Int.max
                if (gate.remaining ?? Int.max) < current {
                    picked = (service, gate)
                }
            }
        }
        return picked.map { (service: $0.0, gate: $0.1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Lowest")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let worst {
                Text(worst.service.title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                MeterRing(remaining: worst.gate.remaining ?? 0, hex: worst.service.brandHex)
                    .frame(width: 60, height: 60)
                Text("\(worst.gate.window) · \(worst.gate.remaining ?? 0)%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("No data")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .foregroundStyle(.white)
        .redacted(reason: placeholder ? .placeholder : [])
    }
}

// MARK: - Grid (Medium + Large)

private struct GridView: View {
    let snapshot: UsageSnapshot
    let placeholder: Bool
    let maxRows: Int
    let compact: Bool

    var body: some View {
        let cols = pickColumns(snapshot)
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HeaderRow(cols: cols, compact: compact)
            if snapshot.services.isEmpty {
                Text("No data yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(snapshot.services.prefix(maxRows)) { service in
                ServiceRow(service: service, cols: cols, compact: compact)
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 10 : 12)
        .foregroundStyle(.white)
        .redacted(reason: placeholder ? .placeholder : [])
    }
}

private struct HeaderRow: View {
    let cols: [String]
    let compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            Spacer()
                .frame(width: nameColumnWidth(compact: compact))
            ForEach(cols, id: \.self) { col in
                Text(col)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            // Keep space empty when fewer than two columns are known.
            ForEach(0..<(2 - cols.count), id: \.self) { _ in
                Spacer().frame(maxWidth: .infinity)
            }
        }
    }
}

private struct ServiceRow: View {
    let service: UsageSnapshot.Service
    let cols: [String]
    let compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: service.brandHex))
                    .frame(width: 7, height: 7)
                Text(service.title)
                    .font(compact ? .caption : .footnote.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .frame(width: nameColumnWidth(compact: compact), alignment: .leading)

            ForEach(cols, id: \.self) { col in
                GateCell(gate: service.gates.first { $0.window == col }, hex: service.brandHex, compact: compact)
                    .frame(maxWidth: .infinity)
            }
            ForEach(0..<(2 - cols.count), id: \.self) { _ in
                Spacer().frame(maxWidth: .infinity)
            }
        }
    }
}

private struct GateCell: View {
    let gate: UsageSnapshot.Gate?
    let hex: String
    let compact: Bool

    var body: some View {
        if let gate, let remaining = gate.remaining {
            HStack(spacing: 6) {
                MeterRing(remaining: remaining, hex: hex)
                    .frame(width: compact ? 26 : 32, height: compact ? 26 : 32)
                if !compact, let replenishes = gate.replenishes {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(replenishes, format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(replenishes, format: .dateTime.hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        } else {
            Text("—")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private func nameColumnWidth(compact: Bool) -> CGFloat {
    compact ? 76 : 92
}

// MARK: - Bits

private struct MeterRing: View {
    let remaining: Int
    let hex: String
    var body: some View {
        let pct = max(0, min(100, remaining))
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 3)
            Circle().trim(from: 0, to: CGFloat(Double(pct) / 100.0))
                .stroke(Color(hex: hex), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(pct)%")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}
