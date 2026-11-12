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
        // The main app calls `WidgetCenter.reloadAllTimelines` after every save,
        // so this 15-minute refresh is only a safety net.
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
            MediumView(snapshot: entry.snapshot, placeholder: entry.placeholder)
        default:
            LargeView(snapshot: entry.snapshot, placeholder: entry.placeholder)
        }
    }
}

// MARK: - Small

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

// MARK: - Medium

private struct MediumView: View {
    let snapshot: UsageSnapshot
    let placeholder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI Usage")
                .font(.caption)
                .foregroundStyle(.secondary)
            if snapshot.services.isEmpty {
                Text("No data yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(snapshot.services.prefix(5)) { service in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: service.brandHex))
                        .frame(width: 8, height: 8)
                    Text(service.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(service.worstRemaining.map { "\($0)%" } ?? "—")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(remainingColor(service.worstRemaining))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .foregroundStyle(.white)
        .redacted(reason: placeholder ? .placeholder : [])
    }
}

// MARK: - Large

private struct LargeView: View {
    let snapshot: UsageSnapshot
    let placeholder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI Usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.updatedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if snapshot.services.isEmpty {
                Text("Open Coucou once to pull your limits.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(snapshot.services) { service in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: service.brandHex))
                            .frame(width: 8, height: 8)
                        Text(service.title)
                            .font(.subheadline.weight(.semibold))
                    }
                    ForEach(service.gates) { gate in
                        HStack {
                            Text(gate.window)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let remaining = gate.remaining {
                                Text("\(remaining)%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(remainingColor(remaining))
                            } else {
                                Text("—")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .foregroundStyle(.white)
        .redacted(reason: placeholder ? .placeholder : [])
    }
}

// MARK: - Bits

private struct MeterRing: View {
    let remaining: Int
    let hex: String
    var body: some View {
        let pct = max(0, min(100, remaining))
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 6)
            Circle().trim(from: 0, to: CGFloat(Double(pct) / 100.0))
                .stroke(Color(hex: hex), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(pct)%")
                .font(.caption.monospacedDigit())
        }
    }
}

private func remainingColor(_ remaining: Int?) -> Color {
    guard let remaining else { return .secondary }
    if remaining < 15 { return .red }
    if remaining < 40 { return .orange }
    return .white
}
