import Accelerate
import AVFoundation
import Foundation
import UniformTypeIdentifiers

struct NookEventFact: Equatable {
    var calendarID: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
}

struct NookActivityFacts: Equatable {
    var mediaTitle: String?
    var mediaArtist: String?
    var trayCount: Int
    var nextEventTitle: String?
    var bluetoothName: String?
    var bluetoothIsNews: Bool
    var batteryPercent: Int?
    var batteryCharging: Bool
    /// Watts flowing into the battery while it is charging.
    var chargingWatts: Double? = nil
    var timerEnded: Bool
    var updateAvailable: Bool = false
}

struct NookHeadline: Equatable {
    var id: String
    var text: String
    var symbol: String
}

enum NookDropChoice {
    case agent
    case pipeline
}

/// Where a file drop lands. The tray page can keep it or send it.
enum NookFileLanding: Equatable {
    /// Closed notch, or the nook widgets. Store, then the older AirDrop or stem path.
    case pipeline
    /// Tray page, anywhere except the AirDrop tile.
    case hold
    /// The AirDrop tile on the right of the tray.
    case airDrop
}

/// What a drop is allowed to do. A held file is not sent.
struct NookDropPlan: Equatable {
    var store: Bool
    var airDropStored: Bool
    var airDropOriginals: Bool
    var splitStems: Bool
    var airDropCompanions: Bool
}

struct NookColumnSpec: Equatable {
    var id: String
    var cells: Int
}

enum NookLayout {
    /// Slider 4...30 becomes a side column of 72...200 points.
    static func wingWidth(slider: Double) -> CGFloat {
        let clamped = min(30, max(4, slider))
        let t = (clamped - 4) / 26
        return 72 + CGFloat(t) * 128
    }

    /// Tray page inset. A higher slider makes the dashed tray wider.
    static func trayInset(slider: Double) -> CGFloat {
        let clamped = min(30, max(4, slider))
        let t = (clamped - 4) / 26
        return 28 - CGFloat(t) * 20
    }

    /// Split `total` across widgets by cell weight, after divider gaps.
    static func columnWidths(cells: [Int], total: CGFloat, divider: CGFloat) -> [CGFloat] {
        guard !cells.isEmpty else { return [] }
        let sum = cells.reduce(0, +)
        guard sum > 0, total > 0 else { return Array(repeating: 0, count: cells.count) }
        let gaps = CGFloat(max(0, cells.count - 1)) * divider
        let usable = max(0, total - gaps)
        return cells.map { CGFloat($0) / CGFloat(sum) * usable }
    }

    /// One cell on the nook grid. A widget keeps this many points even when neighbors are added.
    static let pointsPerCell: CGFloat = 32
    /// Nook page padding, both sides. Matches NookView's horizontal padding.
    static let nookPageInset: CGFloat = 28
    /// Nook, Tray, home, and settings stay on one line when the widget row is narrower.
    static let nookTabBarWidth: CGFloat = 280
    static let widgetDivider: CGFloat = 1

    /// Width of the widget's own controls, before the column's content padding.
    static func singleLineWidth(_ id: String) -> CGFloat {
        switch id {
        case "media": return 200
        case "calendar": return 240
        case "mirror": return 128
        case "shortcuts": return 130
        case "notes", "todos", "timer": return 120
        default: return 120
        }
    }

    /// Mirror keeps a tighter inset so the circle is not eaten by the page padding.
    static func columnPadding(_ id: String, contentPadding: CGFloat) -> CGFloat {
        let pad = max(0, contentPadding)
        return id == "mirror" ? min(pad, 8) : pad
    }

    static func minimumColumnWidth(id: String, contentPadding: CGFloat) -> CGFloat {
        singleLineWidth(id) + columnPadding(id, contentPadding: contentPadding) * 2
    }

    /// Stored cells stay put. A count below the control floor rises to that floor.
    static func fittedCells(id: String, cells: Int, contentPadding: CGFloat) -> Int {
        let needed = Int(ceil(minimumColumnWidth(id: id, contentPadding: contentPadding) / pointsPerCell))
        return max(max(1, cells), needed)
    }

    static func columnWidth(id: String, cells: Int, contentPadding: CGFloat) -> CGFloat {
        CGFloat(fittedCells(id: id, cells: cells, contentPadding: contentPadding)) * pointsPerCell
    }

    /// Open nook width. Adding a column adds only that column. An empty row still fits the tab bar.
    static func nookDrawerWidth(columns: [NookColumnSpec], dividers: Bool, contentPadding: CGFloat) -> CGFloat {
        let widths = columns.map { columnWidth(id: $0.id, cells: $0.cells, contentPadding: contentPadding) }
        let gaps = (dividers && widths.count > 1) ? CGFloat(widths.count - 1) * widgetDivider : 0
        let row = widths.reduce(0, +) + gaps
        return max(row, nookTabBarWidth) + nookPageInset
    }

    static func includeEvent(
        _ event: NookEventFact,
        now: Date,
        allowedCalendarIDs: [String]?,
        showPast: Bool,
        showAllDay: Bool,
        showMultiDay: Bool,
        daysBehind: Int,
        daysAhead: Int
    ) -> Bool {
        if let allowed = allowedCalendarIDs, !allowed.contains(event.calendarID) { return false }
        if event.isAllDay && !showAllDay { return false }
        let day: TimeInterval = 86_400
        let windowStart = now.addingTimeInterval(-Double(max(0, daysBehind)) * day)
        let windowEnd = now.addingTimeInterval(Double(max(0, daysAhead)) * day)
        if event.end < windowStart || event.start > windowEnd { return false }
        let spansDays = event.end.timeIntervalSince(event.start) > day + 60
        if spansDays && !showMultiDay { return false }
        if !showPast && event.end < now { return false }
        return true
    }

    static func headline(facts: NookActivityFacts, enabled: Set<String>, revealed: Bool) -> NookHeadline? {
        guard revealed else { return nil }
        if enabled.contains("timerEnded"), facts.timerEnded {
            return NookHeadline(id: "timerEnded", text: "Timer ended", symbol: "timer")
        }
        if enabled.contains("media"), let title = nonempty(facts.mediaTitle) {
            let artist = nonempty(facts.mediaArtist)
            let text = artist.map { "\(title) · \($0)" } ?? title
            return NookHeadline(id: "media", text: text, symbol: "music.note")
        }
        if enabled.contains("calendar"), let title = nonempty(facts.nextEventTitle) {
            return NookHeadline(id: "calendar", text: title, symbol: "calendar")
        }
        if enabled.contains("battery"), let percent = facts.batteryPercent, facts.batteryCharging || percent <= 20 {
            return NookHeadline(
                id: "battery",
                text: batteryLine(percent: percent, charging: facts.batteryCharging, watts: facts.chargingWatts),
                symbol: batterySymbol(percent: percent, charging: facts.batteryCharging)
            )
        }
        if enabled.contains("bluetooth"), facts.bluetoothIsNews, let name = nonempty(facts.bluetoothName) {
            return NookHeadline(id: "bluetooth", text: name, symbol: "dot.radiowaves.left.and.right")
        }
        if enabled.contains("update"), facts.updateAvailable {
            return NookHeadline(id: "update", text: "Update available", symbol: "arrow.down.circle")
        }
        if enabled.contains("tray"), facts.trayCount > 0 {
            let text = facts.trayCount == 1 ? "1 file in the tray" : "\(facts.trayCount) files in the tray"
            return NookHeadline(id: "tray", text: text, symbol: "tray.full")
        }
        return nil
    }

    /// Charging reads as the percentage and the watts. A low battery keeps the word battery.
    static func batteryLine(percent: Int, charging: Bool, watts: Double?) -> String {
        let shown = min(100, max(0, percent))
        if !charging { return "\(shown)% battery" }
        guard let watts, let speed = chargeSpeedText(watts) else { return "\(shown)%" }
        return "\(shown)% \(speed)"
    }

    /// Battery icon for this percentage. A bolt means power is flowing in.
    static func batterySymbol(percent: Int, charging: Bool) -> String {
        let clamped = min(100, max(0, percent))
        let level: String
        switch clamped {
        case ..<13: level = "battery.0"
        case ..<38: level = "battery.25"
        case ..<63: level = "battery.50"
        case ..<88: level = "battery.75"
        default: level = "battery.100"
        }
        return charging ? "\(level).bolt" : level
    }

    /// Signed milliamps times millivolts, only while the pack is charging.
    /// AppleSmartBattery uses a negative current when power is leaving the pack.
    /// A wrapped InstantAmperage near 65535 is not a real current.
    static func chargingWatts(milliamps: Int, millivolts: Int, charging: Bool) -> Double? {
        guard charging, millivolts > 0, milliamps != 0, abs(milliamps) <= 20_000 else { return nil }
        let amps = milliamps < 0 ? -milliamps : milliamps
        let watts = Double(amps) * Double(millivolts) / 1_000_000
        guard watts.isFinite, watts > 0, watts <= 240 else { return nil }
        return watts
    }

    /// Watts entering the battery. `BatteryPower` is milliwatts.
    /// On this Mac it is positive while the pack is charging: 4318 mW matches
    /// 338 mA at 12695 mV. A negative sample is the same inflow with the other sign,
    /// so a charge uses the magnitude. Discharge is 0. A zero power sample falls
    /// back to current times voltage. The adapter contract and system draw are not inputs.
    static func measuredChargeWatts(
        batteryPowerMilliwatts: Int?,
        milliamps: Int?,
        millivolts: Int?,
        charging: Bool
    ) -> Double? {
        guard charging else { return 0 }
        if let batteryPowerMilliwatts, batteryPowerMilliwatts != 0 {
            let watts = abs(Double(batteryPowerMilliwatts)) / 1000
            guard watts.isFinite, watts > 0, watts <= 240 else { return nil }
            return watts
        }
        if let milliamps, let millivolts,
           let watts = chargingWatts(milliamps: milliamps, millivolts: millivolts, charging: true) {
            return watts
        }
        if batteryPowerMilliwatts == 0 { return 0 }
        return nil
    }

    /// The charging speed as it reads on the notch, such as 0W, 2.4W, or 47W.
    static func chargeSpeedText(_ watts: Double) -> String? {
        guard watts.isFinite, watts >= 0 else { return nil }
        if watts == 0 { return "0W" }
        if watts < 10 {
            let tenths = Int((watts * 10).rounded())
            if tenths >= 100 { return "10W" }
            return "\(tenths / 10).\(tenths % 10)W"
        }
        return "\(Int(watts.rounded()))W"
    }

    /// Measured watts into the pack. supplyWatts is the adapter contract and is never the charge rate.
    static func displayedSpeedWatts(charging: Bool, packWatts: Double?, supplyWatts: Double?) -> Double? {
        _ = charging
        _ = supplyWatts
        guard let packWatts, packWatts.isFinite, packWatts >= 0, packWatts <= 240 else { return nil }
        return packWatts
    }

    /// Amber under 15 watts, green through 45, and blue from a fast charge on up.
    static func chargeSpeedColorHex(watts: Double) -> String {
        guard watts.isFinite, watts > 0 else { return "#8E939C" }
        if watts < 15 { return "#F5A524" }
        if watts < 45 { return "#3DDC84" }
        return "#64D2FF"
    }

    /// A paused session does not lead the notch. Blank titles do not either.
    static func publishedMediaTitle(isPlaying: Bool, title: String?) -> String? {
        guard isPlaying else { return nil }
        return nonempty(title)
    }

    /// A status line stays inside the hardware notch. It does not add side wings.
    static func restingExtraWidth(text: String?) -> CGFloat {
        _ = text
        return 0
    }

    /// The tray icon and the count need a short wing beside the hardware notch.
    static func traySideWidth(showing: Bool) -> CGFloat {
        showing ? 56 : 0
    }

    /// Digits from a line such as "3 files in the tray". The closed notch shows that count.
    static func trayCollapsedText(_ sentence: String) -> String {
        let count = sentence.prefix { $0.isNumber }
        guard !count.isEmpty else { return sentence }
        return String(count)
    }

    /// How long the tray count stays on screen, then how long it stays away.
    static let trayNoticeOn: TimeInterval = 10
    static let trayNoticeOff: TimeInterval = 10

    /// The tray count is visible for ten seconds of every twenty.
    static func trayNoticeVisible(at time: TimeInterval) -> Bool {
        let period = trayNoticeOn + trayNoticeOff
        var remainder = time.truncatingRemainder(dividingBy: period)
        if remainder < 0 { remainder += period }
        return remainder < trayNoticeOn
    }

    /// Seconds until the tray count should next appear or disappear.
    static func trayNoticeDelay(at time: TimeInterval) -> TimeInterval {
        var into = time.truncatingRemainder(dividingBy: trayNoticeOn)
        if into < 0 { into += trayNoticeOn }
        if into == 0 { return trayNoticeOn }
        return trayNoticeOn - into
    }

    /// Horizontal center of the tray count, measured across the left wing.
    static func trayPillCenterX(side: CGFloat) -> CGFloat {
        side / 2
    }

    /// The tray count hides on its own 10 second clock, so inactivity must not swallow it.
    static func keepsTrayLineAwake(headlineID: String?) -> Bool {
        headlineID == "tray"
    }

    /// The collapsed notch stays the height of the menu bar. Volume, a track,
    /// and AirDrop sit in that strip. Extra room is added to the width.
    static func collapsedDropsBand(hudVisible: Bool, mediaPlaying: Bool) -> Bool {
        _ = (hudVisible, mediaPlaying)
        return false
    }

    /// Vertical center for anything drawn on the closed notch.
    static func collapsedAnchorY(housingCenter: CGFloat) -> CGFloat {
        housingCenter
    }

    static func activityAllowed(
        enabled: Bool,
        showInFullscreen: Bool,
        globalFullscreen: String,
        isFullscreen: Bool,
        hasNotch: Bool
    ) -> Bool {
        guard enabled else { return false }
        guard isFullscreen else { return true }
        guard showInFullscreen else { return false }
        switch globalFullscreen {
        case "never": return false
        case "always": return true
        default: return hasNotch
        }
    }

    /// Finger left is previous unless Invert is on. Natural scrolling already
    /// reports a left finger swipe as a negative delta; traditional scrolling does not.
    static func mediaSkipsToNext(deltaX: CGFloat, naturalScrolling: Bool, invert: Bool) -> Bool {
        let fingerMovedRight = naturalScrolling ? deltaX > 0 : deltaX < 0
        let next = fingerMovedRight
        return invert ? !next : next
    }

    /// Expanded nook takes the whole drop. A closed notch keeps the left side for Mochi
    /// and uses the right side for the tray pipeline.
    static func dropChoice(expanded: Bool, nookOpen: Bool, insideIsland: Bool, xFraction: Double) -> NookDropChoice {
        if expanded { return nookOpen ? .pipeline : .agent }
        if insideIsland && xFraction > 0.62 { return .pipeline }
        return .agent
    }

    struct TrayItem: Equatable, Codable, Identifiable {
        var path: String
        var name: String
        var id: String { path }
    }

    static func addToTray(_ items: [TrayItem], paths: [String], limit: Int = 20) -> [TrayItem] {
        var next = items
        for path in paths where !path.isEmpty {
            let name = URL(fileURLWithPath: path).lastPathComponent
            if let index = next.firstIndex(where: { $0.path == path }) {
                let existing = next.remove(at: index)
                next.insert(existing, at: 0)
            } else {
                next.insert(TrayItem(path: path, name: name), at: 0)
            }
        }
        if next.count > limit { next = Array(next.prefix(limit)) }
        return next
    }

    /// The AirDrop tile on the right of the tray. Wide enough for the symbol and the word.
    static let airDropTileWidth: CGFloat = 148

    /// Every file in the tray uses this rectangle. The corner stays small so the tile reads as a rectangle.
    static let trayTileCorner: CGFloat = 4

    /// The stock file-type image, in points. The settings slider stores this number.
    static func trayIconPoints(_ stored: Double) -> CGFloat {
        CGFloat(min(140, max(36, stored.rounded())))
    }

    /// Tile width for an icon. 100 points of icon is a 148-point tile.
    static func trayTileWidth(icon: CGFloat) -> CGFloat {
        max(108, icon + 48)
    }

    /// Tile height for an icon. 100 points of icon is a 156-point tile.
    static func trayTileHeight(icon: CGFloat) -> CGFloat {
        max(96, icon + 56)
    }

    /// Apple's type for this path. The tray draws that type's stock icon.
    static func trayTypeIdentifier(path: String) -> String {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return UTType.folder.identifier
        }
        let ext = URL(fileURLWithPath: path).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return UTType.data.identifier }
        return type.identifier
    }

    /// Copies are stored as `UUID-original-name`. The tray shows the original name.
    static func trayDisplayName(_ filename: String) -> String {
        let parts = filename.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 6,
              parts[0].count == 8, parts[1].count == 4, parts[2].count == 4,
              parts[3].count == 4, parts[4].count == 12 else { return filename }
        let hex = CharacterSet(charactersIn: "0123456789ABCDEFabcdef")
        let head = parts.prefix(5).joined()
        guard head.unicodeScalars.allSatisfy({ hex.contains($0) }) else { return filename }
        return parts.dropFirst(5).joined(separator: "-")
    }

    /// Finder and in-app file drags advertise one of these pasteboard types.
    /// Plain text and other drags stay click-through.
    static func claimsFileDrag(_ types: [String]) -> Bool {
        for type in types {
            if type == "public.file-url" || type == "public.url" || type == "NSFilenamesPboardType" {
                return true
            }
            if type.contains("file-url") { return true }
        }
        return false
    }

    /// The overlay takes a file drag that started in another app.
    /// A drag that starts on a tray file stays with the AirDrop tile.
    static func claimsDropHit(buttonDown: Bool, types: [String], dragBeganOutside: Bool) -> Bool {
        buttonDown && dragBeganOutside && claimsFileDrag(types)
    }

    /// Window point (origin bottom-left) to island point (origin top-left).
    static func islandLocalPoint(windowPoint: CGPoint, islandFrame: CGRect) -> CGPoint {
        CGPoint(
            x: windowPoint.x - islandFrame.minX,
            y: islandFrame.maxY - windowPoint.y
        )
    }

    /// The tile sends the file. The rest of an open tray keeps it.
    /// Before the tile has a size, a drop stays in the tray.
    static func trayLanding(trayPage: Bool, point: CGPoint, tile: CGRect) -> NookFileLanding {
        guard trayPage else { return .pipeline }
        guard tile.width > 1, tile.height > 1, tile.width <= airDropTileWidth + 24, tile.contains(point) else { return .hold }
        return .airDrop
    }

    /// A file dropped on the tray stays there. AirDrop runs only for the tile,
    /// or for the older pipeline when the tray page is not the target.
    /// A song dropped on the tile is sent, even when stem splitting is on.
    static func dropPlan(landing: NookFileLanding, route: NookStemRoute) -> NookDropPlan {
        switch landing {
        case .airDrop:
            return NookDropPlan(
                store: false,
                airDropStored: false,
                airDropOriginals: true,
                splitStems: false,
                airDropCompanions: false
            )
        case .hold:
            switch route {
            case .airDrop:
                return NookDropPlan(
                    store: true, airDropStored: false, airDropOriginals: false,
                    splitStems: false, airDropCompanions: false
                )
            case .stems:
                return NookDropPlan(
                    store: true, airDropStored: false, airDropOriginals: false,
                    splitStems: true, airDropCompanions: false
                )
            case .needsLogic, .needsAppleSilicon:
                return NookDropPlan(
                    store: true, airDropStored: false, airDropOriginals: false,
                    splitStems: false, airDropCompanions: false
                )
            }
        case .pipeline:
            switch route {
            case .airDrop:
                return NookDropPlan(
                    store: true, airDropStored: true, airDropOriginals: false,
                    splitStems: false, airDropCompanions: false
                )
            case .stems:
                return NookDropPlan(
                    store: true, airDropStored: false, airDropOriginals: false,
                    splitStems: true, airDropCompanions: true
                )
            case .needsLogic, .needsAppleSilicon:
                return NookDropPlan(
                    store: true, airDropStored: false, airDropOriginals: false,
                    splitStems: false, airDropCompanions: true
                )
            }
        }
    }

    /// A file that is already in the tray is not copied again when it is dragged inside the tray.
    static func pathsToCopy(incoming: [String], held: [String]) -> [String] {
        let kept = Set(held)
        return incoming.filter { !kept.contains($0) }
    }

    /// Two releases of the same files inside this window are one AirDrop.
    static func shouldSendAirDrop(paths: [String], previous: [String], elapsed: TimeInterval) -> Bool {
        guard !paths.isEmpty else { return false }
        if paths == previous, elapsed < 0.8 { return false }
        return true
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A song dropped on the tray can be split into stems in Logic Pro.
/// Other files stay in the tray until they are dragged onto AirDrop.
enum NookStemRoute: Equatable {
    case airDrop
    case stems
    case needsLogic
    case needsAppleSilicon
}

enum NookStemPipeline {
    /// Audio formats Logic Pro will import onto a track.
    static let songExtensions: Set<String> = [
        "wav", "wave", "aif", "aiff", "aifc", "mp3", "m4a", "caf", "aac", "sd2", "snd"
    ]

    static func isSong(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return songExtensions.contains(ext)
    }

    static func songPaths(_ paths: [String]) -> [String] {
        paths.filter(isSong)
    }

    static func otherPaths(_ paths: [String]) -> [String] {
        paths.filter { !isSong($0) }
    }

    static func songName(_ path: String) -> String {
        let base = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return base.isEmpty ? "The song" : base
    }

    /// Music takes the stem path only while the pipeline is on.
    /// A missing Logic Pro install, or a Mac that is not Apple silicon, is reported
    /// instead of sending the song to AirDrop.
    static func route(paths: [String], enabled: Bool, logicInstalled: Bool, appleSilicon: Bool) -> NookStemRoute {
        guard enabled, !songPaths(paths).isEmpty else { return .airDrop }
        guard logicInstalled else { return .needsLogic }
        guard appleSilicon else { return .needsAppleSilicon }
        return .stems
    }

    static func note(route: NookStemRoute, songName: String) -> String {
        switch route {
        case .airDrop:
            return ""
        case .stems:
            return "Splitting \(songName) into stems in Logic Pro."
        case .needsLogic:
            return "Logic Pro is not installed, so \(songName) stayed in the tray."
        case .needsAppleSilicon:
            return "Stem Splitter needs an Apple silicon Mac. \(songName) stayed in the tray."
        }
    }

    static func finishedNote(songName: String, result: String) -> String {
        switch result {
        case "ok":
            return "Stems for \(songName) are in Logic Pro. The original region is muted."
        case "disabled":
            return "Logic Pro could not select \(songName). Click the audio region, then drop the song again."
        case "offline":
            return "Logic Pro needs the internet once before it can split \(songName)."
        case "no-project":
            return "Open a project in Logic Pro, then drop \(songName) again."
        case "busy":
            return "Logic Pro is asking about the open project. Answer that, then drop \(songName) again."
        case "timeout":
            return "Logic Pro is still splitting \(songName). The stems show up in the project when it finishes."
        default:
            return "Logic Pro could not split \(songName). It is still in the tray."
        }
    }
}

/// What the blue plus on a tray file can run.
enum NookTrayPipeline: Hashable {
    case stems
    case songInfo
}

/// The corner buttons on a tray file, and what the plus asks Coucou to do.
enum NookTrayChip {
    static let removeSymbol = "xmark"
    static let pipelineSymbol = "plus"
    static let removeLabel = "Remove"
    static let pipelineLabel = "Pipelines"

    /// Red X at the top right. Blue plus sits immediately to its left.
    static func removeColorComponents() -> (Double, Double, Double) {
        (0.96, 0.27, 0.31)
    }

    static func pipelineColorComponents() -> (Double, Double, Double) {
        (0.32, 0.56, 1.0)
    }

    static func removeHint(name: String) -> String {
        "Takes \(name) out of the tray. The file on disk stays."
    }

    static func pipelineHint(name: String) -> String {
        "Runs \(name) through a pipeline. A song can be split into stems, or read for key, tempo, and energy."
    }

    static func title(_ pipeline: NookTrayPipeline) -> String {
        switch pipeline {
        case .stems: return "Split into stems"
        case .songInfo: return "Song info"
        }
    }

    static func hint(_ pipeline: NookTrayPipeline) -> String {
        switch pipeline {
        case .stems:
            return "Adds this song to the open Logic Pro project and splits it into vocals, drums, bass, and the other instruments."
        case .songInfo:
            return "Reads the key, tempo, Camelot code, and energy on this Mac. Nothing opens in a browser."
        }
    }

    /// A song can be split in Logic or read for key and tempo. Other files have no pipeline.
    static func pipelines(for path: String) -> [NookTrayPipeline] {
        NookStemPipeline.isSong(path) ? [.stems, .songInfo] : []
    }

    static func displayName(path: String) -> String {
        NookLayout.trayDisplayName(URL(fileURLWithPath: path).lastPathComponent)
    }

    static func spokenName(path: String) -> String {
        let base = URL(fileURLWithPath: displayName(path: path)).deletingPathExtension().lastPathComponent
        return base.isEmpty ? "This file" : base
    }

    /// An explicit plus press runs the chosen pipeline even when the drop switch is off.
    /// A file that is not a song only explains why.
    static func plan(
        pipeline: NookTrayPipeline?,
        path: String,
        logicInstalled: Bool,
        appleSilicon: Bool
    ) -> NookTrayPipelinePlan {
        let shown = displayName(path: path)
        guard NookStemPipeline.isSong(path) else {
            return NookTrayPipelinePlan(
                splitPath: nil,
                note: "\(shown) is not a song, so there is no pipeline for it.",
                readSongInfo: false
            )
        }
        guard let pipeline else {
            return NookTrayPipelinePlan(
                splitPath: nil,
                note: "Pick a pipeline for \(shown).",
                readSongInfo: false
            )
        }
        switch pipeline {
        case .stems:
            let route = NookStemPipeline.route(
                paths: [path],
                enabled: true,
                logicInstalled: logicInstalled,
                appleSilicon: appleSilicon
            )
            let name = spokenName(path: path)
            if route == .stems {
                return NookTrayPipelinePlan(
                    splitPath: path,
                    note: NookStemPipeline.note(route: .stems, songName: name),
                    readSongInfo: false
                )
            }
            return NookTrayPipelinePlan(
                splitPath: nil,
                note: NookStemPipeline.note(route: route, songName: name),
                readSongInfo: false
            )
        case .songInfo:
            return NookTrayPipelinePlan(
                splitPath: nil,
                note: "Reading \(shown).",
                readSongInfo: true
            )
        }
    }

    static func songInfoNote(name: String, readout: SongReadout) -> String {
        "\(name): \(readout.line)"
    }

    static func songInfoFailedNote(name: String) -> String {
        "\(name) could not be read."
    }
}

struct NookTrayPipelinePlan: Equatable {
    var splitPath: String?
    var note: String
    var readSongInfo: Bool
}

/// Tap tempo and the on-Mac reading of a song: BPM, key, Camelot, and energy.
struct SongReadout: Equatable, Sendable {
    var bpm: Int?
    var keyName: String
    var camelot: String
    var energy: Int

    var line: String {
        let tempo = bpm.map { "\($0) BPM" } ?? "BPM unavailable"
        let notes = SongFacts.scaleNotes(keyName: keyName).joined(separator: " ")
        let scale = notes.isEmpty ? "" : ", \(notes)"
        return "\(tempo), \(keyName), \(camelot)\(scale), Energy \(energy)"
    }
}

enum TapTempo {
    /// A gap longer than this starts a new count.
    static let resetAfter: TimeInterval = 2.2

    /// BPM from the latest run of taps. One tap, or a gap, has no tempo yet.
    static func bpm(tapTimes: [TimeInterval]) -> Int? {
        let ordered = tapTimes.sorted()
        guard let last = ordered.last else { return nil }
        var cluster: [TimeInterval] = [last]
        for time in ordered.dropLast().reversed() {
            guard let newest = cluster.first, newest - time <= resetAfter else { break }
            cluster.insert(time, at: 0)
            if cluster.count == 8 { break }
        }
        guard cluster.count >= 2 else { return nil }
        let intervals = zip(cluster, cluster.dropFirst()).map { $1 - $0 }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        guard average > 0.08, average < 2 else { return nil }
        let tempo = 60 / average
        guard tempo >= 40, tempo <= 240 else { return nil }
        return Int(tempo.rounded())
    }
}

enum SongFacts {
    private static let pitchNames = ["C", "D♭", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
    private static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    private static let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
    /// One hue per pitch, in Camelot order, light enough to read on the black notch.
    private static let pitchColorHex = [
        "#5CA3EB", "#EBEB5C", "#A35CEB", "#5CEB5C", "#EB5CA3", "#5CEBEB",
        "#EBA35C", "#5C5CEB", "#A3EB5C", "#EB5CEB", "#5CEBA3", "#EB5C5C"
    ]
    private static let camelotNumber = [8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1]
    private static let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    static func keyName(pitchClass: Int, minor: Bool) -> String {
        let name = pitchNames[(pitchClass % 12 + 12) % 12]
        return "\(name) \(minor ? "minor" : "major")"
    }

    static func camelot(pitchClass: Int, minor: Bool) -> String {
        let pc = (pitchClass % 12 + 12) % 12
        let majorPC = minor ? (pc + 3) % 12 : pc
        return "\(camelotNumber[majorPC])\(minor ? "A" : "B")"
    }

    /// The seven notes of the named key. Sharps and flats stay inside one scale.
    static func scaleNotes(keyName: String) -> [String] {
        let parts = keyName.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return [] }
        let tonicName = String(parts[0])
        guard let tonic = pitchClass(of: tonicName) else { return [] }
        let minor = parts[1].lowercased() == "minor"
        let names = spelling(tonicName: tonicName, pitchClass: tonic, minor: minor)
        let steps = minor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]
        return steps.map { names[(tonic + $0) % 12] }
    }

    static func noteColorHex(_ note: String) -> String {
        guard let index = pitchClass(of: note) else { return "#F5F6F8" }
        return pitchColorHex[index]
    }

    static func keyColorHex(keyName: String) -> String {
        let tonic = keyName.split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return noteColorHex(tonic)
    }

    static func pitchClass(of note: String) -> Int? {
        if let index = sharpNames.firstIndex(of: note) { return index }
        if let index = flatNames.firstIndex(of: note) { return index }
        return pitchNames.firstIndex(of: note)
    }

    private static func spelling(tonicName: String, pitchClass: Int, minor: Bool) -> [String] {
        if tonicName.contains("♯") { return sharpNames }
        if tonicName.contains("♭") { return flatNames }
        if minor {
            return [0, 2, 3, 5, 7, 10].contains(pitchClass) ? flatNames : sharpNames
        }
        if pitchClass == 0 { return pitchNames }
        return [1, 3, 5, 8, 10].contains(pitchClass) ? flatNames : sharpNames
    }

    static func energy(of samples: [Float]) -> Int {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        let rms = sqrt(sum / Float(samples.count))
        guard rms > 1e-8 else { return 0 }
        let decibels = 20 * log10(rms)
        let level = (decibels - (-42)) / ((-8) - (-42))
        return Int((min(1, max(0, level)) * 100).rounded())
    }

    /// Read a song file on this Mac. Returns nil when the file is not audio Coucou can open.
    static func read(url: URL) -> SongReadout? {
        guard NookStemPipeline.isSong(url.path) else { return nil }
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 1000, file.length > 0 else { return nil }
        let startSeconds: Double = file.length > AVAudioFramePosition(sampleRate * 30) ? 8 : 0
        let startFrame = min(file.length - 1, AVAudioFramePosition(startSeconds * sampleRate))
        let framesToRead = AVAudioFrameCount(min(Double(file.length - startFrame), 16 * sampleRate))
        guard framesToRead > AVAudioFrameCount(sampleRate),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else { return nil }
        file.framePosition = startFrame
        do { try file.read(into: buffer, frameCount: framesToRead) } catch { return nil }
        guard let samples = monoDownsampled(buffer, targetRate: 22050) else { return nil }
        return analyze(samples: samples, sampleRate: 22050)
    }

    static func analyze(samples: [Float], sampleRate: Double) -> SongReadout? {
        guard samples.count > Int(sampleRate * 2), sampleRate > 1000 else { return nil }
        let fftSize = 1024
        let hop = 256
        let log2n = vDSP_Length(10)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        var previous = [Float](repeating: 0, count: fftSize / 2)
        var flux: [Float] = []
        var chroma = [Float](repeating: 0, count: 12)
        var frame = [Float](repeating: 0, count: fftSize)
        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)

        var offset = 0
        while offset + fftSize <= samples.count {
            for index in 0..<fftSize {
                frame[index] = samples[offset + index] * window[index]
            }
            let magnitude = magnitudes(frame: frame, real: &real, imag: &imag, setup: setup, log2n: log2n)
            var fluxSum: Float = 0
            for bin in 1..<magnitude.count {
                let rise = magnitude[bin] - previous[bin]
                if rise > 0 { fluxSum += rise }
            }
            // One peak per note. Neighboring bins of a Hann window would otherwise
            // land on the next semitone and pull a major chord toward minor.
            for bin in 2..<(magnitude.count - 1) {
                let mid = magnitude[bin]
                guard mid > 1e-4, mid >= magnitude[bin - 1], mid >= magnitude[bin + 1] else { continue }
                let left = magnitude[bin - 1]
                let right = magnitude[bin + 1]
                let denominator = left - 2 * mid + right
                var delta = 0.0
                if abs(denominator) > 1e-8 {
                    delta = 0.5 * Double(left - right) / Double(denominator)
                    delta = min(0.5, max(-0.5, delta))
                }
                let frequency = (Double(bin) + delta) * sampleRate / Double(fftSize)
                guard frequency >= 55, frequency <= 4200 else { continue }
                let midi = 69.0 + 12.0 * log2(frequency / 440.0)
                var pitchClass = Int(midi.rounded()) % 12
                if pitchClass < 0 { pitchClass += 12 }
                chroma[pitchClass] += logf(1 + mid)
            }
            previous = magnitude
            flux.append(fluxSum)
            offset += hop
        }

        guard let key = musicalKey(chroma: chroma) else { return nil }
        return SongReadout(
            bpm: tempo(flux: flux, hopSeconds: Double(hop) / sampleRate),
            keyName: key.name,
            camelot: key.camelot,
            energy: energy(of: samples)
        )
    }

    private static func magnitudes(
        frame: [Float],
        real: inout [Float],
        imag: inout [Float],
        setup: FFTSetup,
        log2n: vDSP_Length
    ) -> [Float] {
        let half = frame.count / 2
        var output = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realBuffer in
            imag.withUnsafeMutableBufferPointer { imagBuffer in
                guard let realAddress = realBuffer.baseAddress, let imagAddress = imagBuffer.baseAddress else { return }
                var split = DSPSplitComplex(realp: realAddress, imagp: imagAddress)
                frame.withUnsafeBufferPointer { samples in
                    samples.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                for bin in 0..<half {
                    output[bin] = sqrt(realBuffer[bin] * realBuffer[bin] + imagBuffer[bin] * imagBuffer[bin])
                }
            }
        }
        return output
    }

    private static func tempo(flux: [Float], hopSeconds: Double) -> Int? {
        guard flux.count > 40, hopSeconds > 0 else { return nil }
        let mean = flux.reduce(0, +) / Float(flux.count)
        let centered = flux.map { $0 - mean }
        var power: Float = 0
        for value in centered { power += value * value }
        guard power > 0 else { return nil }
        let minLag = max(1, Int((60.0 / 180.0) / hopSeconds))
        let maxLag = min(centered.count / 2, Int((60.0 / 70.0) / hopSeconds))
        guard maxLag > minLag + 1 else { return nil }
        var scores = [Float](repeating: 0, count: maxLag + 1)
        var bestLag = minLag
        var best: Float = -.greatestFiniteMagnitude
        var total: Float = 0
        for lag in minLag...maxLag {
            var sum: Float = 0
            let count = centered.count - lag
            for index in 0..<count {
                sum += centered[index] * centered[index + lag]
            }
            let score = sum / Float(count)
            scores[lag] = score
            total += score
            if score > best {
                best = score
                bestLag = lag
            }
        }
        let average = total / Float(maxLag - minLag + 1)
        let overlap = Float(centered.count - bestLag)
        let coherence = (best * overlap) / power
        // A steady tone can wobble enough to beat the average and invent a tempo.
        // Real beats repeat strongly enough to clear both gates.
        guard best > average * 1.35, coherence > 0.2 else { return nil }
        var lag = Double(bestLag)
        if bestLag > minLag, bestLag < maxLag {
            let left = scores[bestLag - 1]
            let mid = scores[bestLag]
            let right = scores[bestLag + 1]
            let denominator = left - 2 * mid + right
            if abs(denominator) > 1e-5 {
                lag += Double(0.5 * (left - right) / denominator)
            }
        }
        let bpm = 60.0 / (lag * hopSeconds)
        guard bpm.isFinite, bpm >= 70, bpm <= 180 else { return nil }
        return Int(bpm.rounded())
    }

    private static func musicalKey(chroma: [Float]) -> (name: String, camelot: String)? {
        guard chroma.reduce(0, +) > 0 else { return nil }
        var best: Float = -2
        var pitchClass = 0
        var minor = false
        for isMinor in [false, true] {
            let profile = isMinor ? minorProfile : majorProfile
            for tonic in 0..<12 {
                let score = cosine(chroma, rotate(profile, by: tonic))
                if score > best {
                    best = score
                    pitchClass = tonic
                    minor = isMinor
                }
            }
        }
        return (keyName(pitchClass: pitchClass, minor: minor), camelot(pitchClass: pitchClass, minor: minor))
    }

    private static func rotate(_ profile: [Float], by tonic: Int) -> [Float] {
        (0..<12).map { profile[($0 - tonic + 12) % 12] }
    }

    private static func cosine(_ left: [Float], _ right: [Float]) -> Float {
        let leftMean = left.reduce(0, +) / Float(left.count)
        let rightMean = right.reduce(0, +) / Float(right.count)
        var dot: Float = 0
        var leftNorm: Float = 0
        var rightNorm: Float = 0
        for index in 0..<left.count {
            let x = left[index] - leftMean
            let y = right[index] - rightMean
            dot += x * y
            leftNorm += x * x
            rightNorm += y * y
        }
        guard leftNorm > 0, rightNorm > 0 else { return 0 }
        return dot / sqrt(leftNorm * rightNorm)
    }

    private static func monoDownsampled(_ buffer: AVAudioPCMBuffer, targetRate: Double) -> [Float]? {
        guard let destination = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: buffer.format, to: destination) else { return nil }
        let ratio = targetRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let output = AVAudioPCMBuffer(pcmFormat: destination, frameCapacity: capacity) else { return nil }
        var used = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if used {
                status.pointee = .endOfStream
                return nil
            }
            used = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = output.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
    }
}

// MARK: - Player presentation

/// The three launcher tiles. Music uses its app icon. Spotify is the wave circle.
/// YouTube is the white tile with the red play shape, never a letter.
enum NookMediaPlatform: String, Equatable {
    case music, spotify, youtube

    static let launcher: [NookMediaPlatform] = [.music, .spotify, .youtube]

    var mark: String {
        switch self {
        case .music: return "app-icon"
        case .spotify: return "wave-circle"
        case .youtube: return "play-tile"
        }
    }

    var bundleIDs: [String] {
        switch self {
        case .music:
            return ["com.apple.Music"]
        case .spotify:
            return ["com.spotify.client"]
        case .youtube:
            return [
                "com.google.Chrome.app.agimnkijcaahngcdmfeangaknmldooml",
                "com.google.ios.youtube",
            ]
        }
    }

    var appPaths: [String] {
        switch self {
        case .music:
            return ["/System/Applications/Music.app"]
        case .spotify:
            return ["/Applications/Spotify.app", NSHomeDirectory() + "/Applications/Spotify.app"]
        case .youtube:
            return ["/Applications/YouTube.app", NSHomeDirectory() + "/Applications/YouTube.app"]
        }
    }

    var webURL: URL? {
        switch self {
        case .music: return nil
        case .spotify: return URL(string: "https://open.spotify.com")
        case .youtube: return URL(string: "https://www.youtube.com")
        }
    }

    var sourceName: String {
        switch self {
        case .music: return "music"
        case .spotify: return "spotify"
        case .youtube: return "youtube"
        }
    }

    var title: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        case .youtube: return "YouTube"
        }
    }
}

struct NookPlaybackFacts: Equatable {
    var title: String
    var artist: String
    var bundleID: String
    var displayName: String
    var rate: Double
    var position: Double
    var duration: Double
}

struct NookPlaybackCard: Equatable {
    var title: String
    var artist: String
    var platform: NookMediaPlatform?
    var playing: Bool
    var transportSymbol: String
}

/// Where a click on the playing name goes.
enum PlayingReveal: Equatable {
    /// Bring this app's window forward.
    case application(String)
    /// Focus the browser tab that has the video, then bring that browser forward.
    case browser(String)
}

enum NookPlayback {
    static func platform(bundleID: String, displayName: String) -> NookMediaPlatform? {
        let bundle = bundleID.lowercased()
        let name = displayName.lowercased()
        if bundle == "com.apple.music" || name == "music" || name == "apple music" {
            return .music
        }
        if bundle == "com.spotify.client" || name == "spotify" {
            return .spotify
        }
        if bundle.contains("youtube") || name.contains("youtube") {
            return .youtube
        }
        return nil
    }

    /// Music and Spotify open that app. Chrome and Safari open the tab with the video.
    /// A Chrome app window, such as the YouTube app, opens that window.
    /// Nothing opens when the source is blank.
    static func revealTarget(bundleID: String, displayName: String) -> PlayingReveal? {
        let id = bundleID.lowercased()
        let name = displayName.lowercased()
        if id.isEmpty && name.isEmpty { return nil }
        if id.contains(".chrome.app.") {
            return .application(bundleID)
        }
        if id == "com.apple.safari" || name == "safari" {
            return .browser("Safari")
        }
        if id == "com.google.chrome" || name == "google chrome" || name.contains("youtube") || id.contains("chrome") {
            return .browser("Google Chrome")
        }
        if id == "com.apple.music" || name == "music" || name == "apple music" {
            return .application(bundleID.isEmpty ? "com.apple.Music" : bundleID)
        }
        if id == "com.spotify.client" || name == "spotify" {
            return .application(bundleID.isEmpty ? "com.spotify.client" : bundleID)
        }
        if bundleID.isEmpty { return nil }
        return .application(bundleID)
    }

    /// The home card draws the thumbnail under the blob only when a title exists.
    static func showsHomeAudio(title: String?) -> Bool {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty
    }

    /// A title replaces the launcher, including while paused.
    /// Pause shows only while the audio or video is moving.
    static func card(_ facts: NookPlaybackFacts) -> NookPlaybackCard? {
        let title = facts.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let playing = facts.rate > 0.05
        let artist = facts.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return NookPlaybackCard(
            title: title,
            artist: artist,
            platform: platform(bundleID: facts.bundleID, displayName: facts.displayName),
            playing: playing,
            transportSymbol: playing ? "pause.fill" : "play.fill"
        )
    }

    /// "system" follows whichever app is playing. Music and Spotify stay on that app.
    static func accepts(platform: NookMediaPlatform?, preference: String) -> Bool {
        switch preference {
        case "music": return platform == .music
        case "spotify": return platform == .spotify
        default: return true
        }
    }

    /// Chrome keeps a background audio or video session on the closed notch.
    /// MediaRemote often reports that session as stopped while the tab is still
    /// the current player. A paused Music or YouTube app stays on the faces.
    /// A blank title never replaces the faces.
    static func showsOnClosedNotch(bundleID: String, displayName: String, title: String?, playing: Bool) -> Bool {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return false }
        if playing { return true }
        let id = bundleID.lowercased()
        let name = displayName.lowercased()
        if id.contains(".chrome.app.") { return false }
        return id == "com.google.chrome" || name == "google chrome"
    }

    /// Center of the closed-notch player, on the right where the faces sit.
    static func closedShelfCenterX(islandWidth: CGFloat, contentWidth: CGFloat) -> CGFloat {
        let width = max(36, contentWidth)
        let rightInset: CGFloat = 16
        return max(width / 2, islandWidth - rightInset - width / 2)
    }

    /// Right wing for the 18pt play button, with air around it.
    static let mediaWing: CGFloat = 36

    /// The closed notch grows this wing when a track or video is on it.
    /// The same width is added on the left so the housing stays centered.
    static func mediaWingWidth(showing: Bool) -> CGFloat {
        showing ? mediaWing : 0
    }

    /// Center of the play button, in the right wing.
    static func mediaShelfCenterX(islandWidth: CGFloat, wing: CGFloat) -> CGFloat {
        let span = max(36, wing)
        return max(span / 2, islandWidth - span / 2)
    }

    /// Camera span inside an island that stays centered on the housing.
    static func housingEdges(islandWidth: CGFloat, notchWidth: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        let island = max(0, islandWidth)
        let notch = min(island, max(0, notchWidth))
        let leading = (island - notch) / 2
        return (leading, leading + notch)
    }

    /// The play button. The app icon and the waveform are not on the closed notch.
    static let shelfContentWidth: CGFloat = 18

    /// The closed notch shows the play button only. The song or video name stays off.
    static func mediaTitlePlacement(islandWidth: CGFloat, notchWidth: CGFloat) -> (centerX: CGFloat, maxWidth: CGFloat) {
        _ = (islandWidth, notchWidth)
        return (0, 0)
    }

    /// Chrome often leaves the rate at zero while the tab is still sending audio.
    static func waveIsMoving(reportedPlaying: Bool, outputRunning: Bool) -> Bool {
        reportedPlaying || outputRunning
    }

    /// Seven bars. A moving phase rises and falls. A resting phase stays short.
    static func barHeights(phase: Double, moving: Bool, count: Int = 7) -> [CGFloat] {
        let bars = max(1, count)
        if !moving {
            return Array(repeating: 0.22, count: bars)
        }
        return (0..<bars).map { index in
            let shift = Double(index) * 0.9
            let wave = abs(sin(phase + shift))
            return CGFloat(0.28 + 0.72 * wave)
        }
    }

    /// A dark cover still reads on the black notch. The brightest channel reaches 0.78.
    static func waveTint(red: Double, green: Double, blue: Double) -> (Double, Double, Double) {
        var channels = [
            min(1, max(0, red)),
            min(1, max(0, green)),
            min(1, max(0, blue))
        ]
        let peak = channels.max() ?? 0
        let target = 0.78
        if peak < 0.001 {
            return (target, target, target)
        }
        if peak < target {
            let scale = target / peak
            channels = channels.map { min(1, $0 * scale) }
        }
        return (channels[0], channels[1], channels[2])
    }
}

enum NookPictureInPictureKind: Equatable {
    /// Ask this browser to float the video.
    case browser(String)
    /// Float the album art. The session has a picture, not a browser video.
    case artwork
    case unavailable
}

struct NookPictureInPictureClick: Equatable {
    var x: Double
    var y: Double
}

enum NookPictureInPictureOutcome: Equatable, Sendable {
    case entered
    case exited
    case failed
    /// The browser is on another desktop. Show its video here instead of switching desktops.
    case mirror(windowID: UInt32, left: Double, top: Double, right: Double, bottom: Double)
}

enum NookPictureInPicture {
    /// Chrome and Safari can float the video. Music and Spotify float the album art.
    static func kind(bundleID: String, displayName: String, hasTitle: Bool) -> NookPictureInPictureKind {
        guard hasTitle else { return .unavailable }
        let id = bundleID.lowercased()
        let name = displayName.lowercased()
        if id == "com.apple.safari" || name == "safari" {
            return .browser("Safari")
        }
        if id == "com.google.chrome" || name == "google chrome" || id.contains("chrome") || name.contains("youtube") {
            return .browser("Google Chrome")
        }
        return .artwork
    }

    /// A point inside the page, below the window title and in the upper part of the video.
    static func click(left: Double, top: Double, right: Double, bottom: Double) -> NookPictureInPictureClick? {
        let width = right - left
        let height = bottom - top
        guard width >= 80, height >= 80 else { return nil }
        let y = top + min(360, height - 40)
        guard y > top, y < bottom else { return nil }
        return NookPictureInPictureClick(x: (left + right) / 2, y: y)
    }

    static func outcome(_ raw: String) -> NookPictureInPictureOutcome {
        let text = raw.lowercased()
        // "entered" alone is a leftover mark. Only the live picture element counts.
        if text.contains("in-pip") { return .entered }
        if text.contains("exited") { return .exited }
        return .failed
    }

    /// A floating picture is ready only when the page owns one and that window is on screen.
    static func pictureReady(read: String, pictureOnScreen: Bool) -> Bool {
        outcome(read) == .entered && pictureOnScreen
    }

    /// Where the button puts a new picture. Another desktop is mirrored onto this one.
    enum PictureRoute: Equatable {
        case enterHere
        case mirrorHere
    }

    static func route(browserOnThisDesktop: Bool) -> PictureRoute {
        browserOnThisDesktop ? .enterHere : .mirrorHere
    }

    /// Where a press lands. A picture on another desktop is shown here.
    enum PicturePlace: Equatable {
        case enterHere
        case raiseHere
        case mirrorHere
    }

    static func place(step: Step, browserOnThisDesktop: Bool, pictureOnThisDesktop: Bool) -> PicturePlace? {
        switch step {
        case .enterWithoutLeaving:
            return browserOnThisDesktop ? .enterHere : .mirrorHere
        case .showExisting:
            return pictureOnThisDesktop ? .raiseHere : .mirrorHere
        case .exitWithoutLeaving, .unavailable:
            return nil
        }
    }

    /// One press, one action. A second event from the same click is ignored.
    static func acceptsPress(secondsSinceLast: Double) -> Bool {
        secondsSinceLast >= 0.35
    }

    /// The notch is out of the way when it no longer covers the spot.
    static func notchIsClear(cover: ScreenRect?, x: Double, y: Double) -> Bool {
        guard let cover else { return true }
        return !cover.contains(x, y)
    }

    /// What the same press does next. A miss waits, then clicks again.
    enum PressMove: Equatable {
        case click
        case wait
        case stop
    }

    static let clicksPerPress = 6

    static func nextPress(read: String, clicksSent: Int, pollsSinceClick: Int) -> PressMove {
        switch outcome(read) {
        case .entered, .exited:
            return .stop
        case .failed, .mirror:
            break
        }
        if clicksSent >= clicksPerPress { return .stop }
        if clicksSent == 0 || pollsSinceClick >= 3 { return .click }
        return .wait
    }

    /// Several spots in the page, so one press can land if the first spot misses.
    static func clickSpots(
        primary: NookPictureInPictureClick,
        windowLeft: Double,
        windowTop: Double,
        windowRight: Double,
        windowBottom: Double
    ) -> [NookPictureInPictureClick] {
        let shifts: [(Double, Double)] = [(0, 0), (0, 72), (48, 36), (-48, 108), (0, 144), (72, 72)]
        let margin = 8.0
        var spots: [NookPictureInPictureClick] = []
        for (dx, dy) in shifts {
            let x = primary.x + dx
            let y = primary.y + dy
            guard x > windowLeft + margin, x < windowRight - margin,
                  y > windowTop + margin, y < windowBottom - margin else { continue }
            if spots.contains(where: { abs($0.x - x) < 1 && abs($0.y - y) < 1 }) { continue }
            spots.append(NookPictureInPictureClick(x: x, y: y))
        }
        return spots
    }

    /// A window Coucou can see, including one on another desktop.
    struct ListedWindow: Equatable {
        var id: UInt32
        var owner: String
        var width: Double
        var height: Double
        var onScreen: Bool
        var layer: Int
    }

    /// The floating picture on another desktop, not the full browser window.
    static func offscreenPicture(
        among windows: [ListedWindow],
        browserWidth: Double,
        browserHeight: Double
    ) -> ListedWindow? {
        let pictures = windows.filter { window in
            (window.owner == "Google Chrome" || window.owner == "Safari")
                && !window.onScreen
                && isPictureWindow(
                    width: window.width,
                    height: window.height,
                    browserWidth: browserWidth,
                    browserHeight: browserHeight
                )
        }
        let floating = pictures.filter { $0.layer > 0 && $0.layer < 25 }
        let pool = floating.isEmpty ? pictures : floating
        return pool.max { $0.width * $0.height < $1.width * $1.height }
    }

    /// An existing picture is mirrored whole. The video already left the page.
    static func pictureCrop(width: Double, height: Double) -> ScreenRect {
        ScreenRect(left: 0, top: 0, right: width, bottom: height)
    }

    /// Screen recording is asked once. A refusal does not open Settings again.
    enum CaptureAsk: Equatable {
        case allowed
        case ask
        case skip
    }

    static func captureAsk(alreadyAllowed: Bool, alreadyAsked: Bool) -> CaptureAsk {
        if alreadyAllowed { return .allowed }
        if alreadyAsked { return .skip }
        return .ask
    }

    /// The video's area inside the browser window, in that window's top-left points.
    /// A hidden page with no rectangle uses the page under the toolbar.
    static func mirrorCrop(frame: VideoFrame, windowWidth: Double, windowHeight: Double) -> ScreenRect? {
        guard windowWidth >= 80, windowHeight >= 80 else { return nil }
        if frameIsLaidOut(frame) {
            let x = min(max(0, frame.left), windowWidth - 80)
            let y = min(max(0, frame.top), windowHeight - 80)
            let width = min(frame.width, windowWidth - x)
            let height = min(frame.height, windowHeight - y)
            guard width >= 80, height >= 80 else { return nil }
            return ScreenRect(left: x, top: y, right: x + width, bottom: y + height)
        }
        let top = 92.0
        guard top + 80 < windowHeight else { return nil }
        return ScreenRect(left: 0, top: top, right: windowWidth, bottom: windowHeight)
    }

    /// What the button does. A picture that is already floating stays on this desktop.
    enum Step: Equatable {
        case enterWithoutLeaving
        case showExisting
        case exitWithoutLeaving
        case unavailable
    }

    struct VideoFrame: Equatable {
        var state: String
        var left: Double
        var top: Double
        var width: Double
        var height: Double
        var screenX: Double
        var screenY: Double
    }

    static func step(buttonIsOn: Bool, videoState: String) -> Step {
        if buttonIsOn {
            return videoState == "in" ? .exitWithoutLeaving : .unavailable
        }
        if videoState == "in" { return .showExisting }
        if videoState == "play" || videoState == "have" { return .enterWithoutLeaving }
        return .unavailable
    }

    /// A video that is actually playing beats one that is only present.
    static func prefersPlayingVideo(_ candidate: String, over current: String) -> Bool {
        videoRank(candidate) < videoRank(current)
    }

    private static func videoRank(_ state: String) -> Int {
        switch state {
        case "play": return 0
        case "in": return 1
        case "have": return 2
        default: return 3
        }
    }

    static func parseVideo(_ raw: String) -> VideoFrame? {
        let parts = raw.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" }).map(String.init)
        guard parts.count >= 7,
              let left = Double(parts[1]),
              let top = Double(parts[2]),
              let width = Double(parts[3]),
              let height = Double(parts[4]),
              let screenX = Double(parts[5]),
              let screenY = Double(parts[6]) else { return nil }
        let state = parts[0]
        guard state == "in" || state == "play" || state == "have" else { return nil }
        return VideoFrame(
            state: state, left: left, top: top, width: width, height: height,
            screenX: screenX, screenY: screenY
        )
    }

    /// A rectangle in the same top-left coordinates as a browser window.
    struct ScreenRect: Equatable {
        var left: Double
        var top: Double
        var right: Double
        var bottom: Double

        func contains(_ x: Double, _ y: Double) -> Bool {
            x >= left && x < right && y >= top && y < bottom
        }
    }

    /// The page has laid the video out. A hidden tab reports a zero rectangle.
    static func frameIsLaidOut(_ frame: VideoFrame) -> Bool {
        frame.width >= 40 && frame.height >= 40
    }

    /// The page token from the frame script. Hidden pages reject picture-in-picture.
    static func pageIsVisible(_ raw: String) -> Bool {
        raw.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" }).contains("visible")
    }

    /// Center of the playing video, kept inside the browser window.
    /// When the notch covers that spot, the press moves below the notch.
    /// If the notch covers the whole video, the original spot is kept and the notch lets the press through.
    static func videoClick(
        _ frame: VideoFrame,
        windowLeft: Double,
        windowTop: Double,
        windowRight: Double,
        windowBottom: Double,
        coveredBy: ScreenRect? = nil
    ) -> NookPictureInPictureClick? {
        let margin = 8.0
        func insideWindow(_ x: Double, _ y: Double) -> Bool {
            x > windowLeft + margin && x < windowRight - margin && y > windowTop + margin && y < windowBottom - margin
        }
        func clear(_ x: Double, _ y: Double) -> Bool {
            guard let coveredBy else { return true }
            return !coveredBy.contains(x, y)
        }
        var spots: [(Double, Double)] = []
        if frameIsLaidOut(frame) {
            let originX = frame.screenX + frame.left
            let originY = frame.screenY + frame.top
            let centerX = originX + frame.width / 2
            spots.append((centerX, originY + min(frame.height / 2, 280)))
            if let coveredBy {
                let below = coveredBy.bottom + 24
                if below > originY + margin, below < originY + frame.height - margin {
                    spots.append((centerX, below))
                }
            }
            spots.append((centerX, originY + frame.height * 0.72))
        }
        var kept: NookPictureInPictureClick?
        for (x, y) in spots where insideWindow(x, y) {
            if kept == nil { kept = NookPictureInPictureClick(x: x, y: y) }
            if clear(x, y) { return NookPictureInPictureClick(x: x, y: y) }
        }
        if var fallback = click(left: windowLeft, top: windowTop, right: windowRight, bottom: windowBottom) {
            if let coveredBy, coveredBy.contains(fallback.x, fallback.y) {
                let pushed = coveredBy.bottom + 24
                if pushed < windowBottom - margin, !coveredBy.contains(fallback.x, pushed) {
                    fallback = NookPictureInPictureClick(x: fallback.x, y: pushed)
                } else if let kept {
                    return kept
                }
            }
            if insideWindow(fallback.x, fallback.y), clear(fallback.x, fallback.y) { return fallback }
        }
        return kept
    }

    /// The floating picture is smaller than the browser window it came from.
    static func isPictureWindow(width: Double, height: Double, browserWidth: Double, browserHeight: Double) -> Bool {
        guard width >= 200, height >= 120 else { return false }
        if browserWidth > 0, width * height >= browserWidth * browserHeight * 0.9 { return false }
        return true
    }

    /// Keep checking until the picture has opened or the wait is used up.
    static func keepWaiting(read: String, tries: Int, limit: Int) -> Bool {
        let done = outcome(read)
        if done == .entered || done == .exited { return false }
        return tries < limit
    }

    static func buttonSymbol(active: Bool) -> String {
        active ? "pip.exit" : "pip.enter"
    }

    static func buttonLabel(active: Bool) -> String {
        active ? "Exit picture in picture" : "Picture in picture"
    }

    static func buttonHelp(active: Bool) -> String {
        active
            ? "Puts the video back in its window."
            : "Floats the playing picture above your other windows."
    }

    /// Installed on the page, then fired by one real click. A scripted call is rejected.
    /// The largest video is the one playing, not a small preview.
    static func hookScript() -> String {
        "(function(){if(window.__coucouPipHook)return 'hooked';window.__coucouPip='';window.__coucouPipHook=true;var pip=function(e){if(!e.isTrusted)return;var vids=[].slice.call(document.querySelectorAll('video'));var v=null,area=-1;for(var i=0;i<vids.length;i++){var box=vids[i].getBoundingClientRect();var size=box.width*box.height;if(size<1&&vids[i].videoWidth){size=vids[i].videoWidth*vids[i].videoHeight;}if(size>area){v=vids[i];area=size;}}if(!v){window.__coucouPip='no-video';return;}if(document.pictureInPictureElement){document.exitPictureInPicture();window.__coucouPip='exited';window.__coucouPipHook=false;pip.drop();return;}v.requestPictureInPicture().then(function(){window.__coucouPip='entered';window.__coucouPipHook=false;pip.drop();}).catch(function(err){window.__coucouPip='err-'+(err&&err.name||'fail');});e.preventDefault();e.stopPropagation();};pip.drop=function(){document.removeEventListener('pointerdown',pip,true);};document.addEventListener('pointerdown',pip,true);return 'hooked';})()"
    }

    /// State plus the video rectangle and the page origin, in one line.
    static func videoFrameScript() -> String {
        "(function(){var vids=[].slice.call(document.querySelectorAll('video'));var best=null,area=0;for(var i=0;i<vids.length;i++){var box=vids[i].getBoundingClientRect();var size=box.width*box.height;if(size>area){best=vids[i];area=size;}}if(!best)return 'none';var r=best.getBoundingClientRect();var mark=document.pictureInPictureElement?'in':(!best.paused?'play':'have');return mark+' '+Math.round(r.left)+' '+Math.round(r.top)+' '+Math.round(r.width)+' '+Math.round(r.height)+' '+Math.round(window.screenX)+' '+Math.round(window.screenY)+' '+document.visibilityState;})()"
    }

    static func readScript() -> String {
        "(function(){return (document.pictureInPictureElement?'in-pip ':'not-pip ')+(window.__coucouPip||'');})()"
    }

    static func videoStateScript() -> String {
        "(function(){var v=document.querySelector('video');if(!v)return 'none';if(document.pictureInPictureElement)return 'in';if(!v.paused)return 'play';return 'have';})()"
    }
}

/// Which lens a discovered camera is.
enum MirrorLens: Equatable {
    case builtInWide
    case deskView
    case external
    case continuity
}

/// The facing a camera reports. A MacBook's FaceTime camera reports none.
enum MirrorFacing: Equatable {
    case front
    case back
    case unspecified
}

/// A camera Coucou might show in the Mirror circle.
struct MirrorDevice: Equatable {
    var id: String
    /// The lens faces the person at the Mac.
    var front: Bool
    /// The Mac's own wide camera, not a phone or a desk view.
    var builtIn: Bool
}

/// Whether a Mirror start is still the request the person wants.
struct MirrorSessionPlan: Equatable {
    var generation: Int
    var wantsRunning: Bool
}

/// The Mirror circle turns the front camera on, and the next press turns it off.
enum MirrorBehavior {
    enum Action: Equatable {
        case start
        case stop
    }

    /// A press follows the request, including a start that has not reached the screen yet.
    static func press(wantsRunning: Bool) -> Action {
        wantsRunning ? .stop : .start
    }

    static func advance(_ plan: MirrorSessionPlan, _ action: Action) -> MirrorSessionPlan {
        MirrorSessionPlan(generation: plan.generation + 1, wantsRunning: action == .start)
    }

    /// The camera stays on only when this start is still the latest request.
    static func shouldStayOn(plan: MirrorSessionPlan, startedGeneration: Int) -> Bool {
        plan.wantsRunning && plan.generation == startedGeneration
    }

    /// A built-in wide camera still faces the person when the Mac reports no facing.
    /// Desk View and a rear camera stay out.
    static func listedDevice(id: String, lens: MirrorLens, facing: MirrorFacing) -> MirrorDevice {
        let builtIn = lens == .builtInWide
        let front = lens != .deskView && facing != .back && (facing == .front || lens == .builtInWide)
        return MirrorDevice(id: id, front: front, builtIn: builtIn)
    }

    static func lens(for deviceType: AVCaptureDevice.DeviceType) -> MirrorLens {
        switch deviceType {
        case .builtInWideAngleCamera: return .builtInWide
        case .deskViewCamera: return .deskView
        case .continuityCamera: return .continuity
        default: return .external
        }
    }

    static func facing(for position: AVCaptureDevice.Position) -> MirrorFacing {
        switch position {
        case .front: return .front
        case .back: return .back
        default: return .unspecified
        }
    }

    /// Built-in front camera first. Any other front camera next. Never a rear camera.
    static func frontCameraID(_ devices: [MirrorDevice]) -> String? {
        if let match = devices.first(where: { $0.front && $0.builtIn }) { return match.id }
        if let match = devices.first(where: { $0.front }) { return match.id }
        return nil
    }

    static func visibleTitle(asking: Bool = false, denied: Bool, missing: Bool) -> String {
        if asking { return "Allow camera access" }
        if denied { return "Camera is off" }
        if missing { return "No front camera" }
        return "Mirror"
    }

    static func accessibilityTitle(asking: Bool = false, wantsRunning: Bool, denied: Bool, missing: Bool) -> String {
        if asking { return "Allow camera access" }
        if denied { return "Camera is off" }
        if missing { return "No front camera" }
        return wantsRunning ? "Turn off Mirror" : "Mirror"
    }

    static func help(asking: Bool = false, wantsRunning: Bool, denied: Bool, missing: Bool) -> String {
        if asking { return "macOS is asking to use the camera. Choose Allow." }
        if denied { return "Camera access is off. Turn it on in System Settings." }
        if missing { return "This Mac has no front camera Coucou can show." }
        if wantsRunning { return "Turns the front camera off." }
        return "Shows the front camera in this circle. Press again to turn it off."
    }

    /// An undecided camera has to ask. A blocked camera will not ask again.
    static func prompt(for access: MirrorAccess) -> MirrorPrompt {
        switch access {
        case .authorized: return .startCamera
        case .notDetermined: return .ask
        case .denied: return .openSettings
        }
    }

    /// The Allow prompt only appears while Coucou is a normal app. Every other step stays in the menu bar.
    static func activation(for prompt: MirrorPrompt) -> MirrorActivation {
        switch prompt {
        case .ask: return .regular
        case .startCamera, .openSettings: return .accessory
        }
    }

    static let cameraSettingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Camera")!

    /// macOS only shows Allow after Coucou has been a normal app for a moment.
    static func askDelay(for activation: MirrorActivation) -> TimeInterval {
        activation == .regular ? 0.5 : 0
    }

    /// A refused ask opens Camera settings. An allowed ask starts the camera.
    static func afterAsk(granted: Bool) -> MirrorPrompt {
        granted ? .startCamera : .openSettings
    }

    /// The circle keeps saying it is asking when macOS opens Settings instead of the prompt.
    static func keepsAsk(_ prompt: MirrorPrompt) -> Bool {
        switch prompt {
        case .ask, .openSettings: return true
        case .startCamera: return false
        }
    }
}

enum MirrorAccess: Equatable {
    case authorized
    case notDetermined
    case denied
}

enum MirrorPrompt: Equatable {
    case startCamera
    case ask
    case openSettings
}

enum MirrorActivation: Equatable {
    case regular
    case accessory
}

/// One now-playing line from the system reader.
struct NowPlayingWire: Equatable {
    var title: String
    var artist: String
    var bundleID: String
    var displayName: String
    var playing: Bool
    var position: Double
    var duration: Double
    var artworkPath: String?
    var artworkStamp: Int
}

enum NowPlayingWireLine {
    /// A stopped Chrome session stays a real session. A blank or broken line does not.
    static func decode(_ line: String) -> NowPlayingWire? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              flag(object["ok"]) else { return nil }
        let title = text(object["title"])
        guard let title else { return nil }
        let rate = number(object["rate"])
        let art = text(object["art"])
        return NowPlayingWire(
            title: title,
            artist: text(object["artist"]) ?? "",
            bundleID: text(object["bundle"]) ?? "",
            displayName: text(object["name"]) ?? "",
            playing: flag(object["playing"]) || rate > 0.05,
            position: number(object["position"]),
            duration: number(object["duration"]),
            artworkPath: art,
            artworkStamp: Int(number(object["stamp"]))
        )
    }

    private static func text(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return trimmed
    }

    private static func flag(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return false
    }

    private static func number(_ value: Any?) -> Double {
        let number: Double
        if let value = value as? NSNumber {
            number = value.doubleValue
        } else if let value = value as? Double {
            number = value
        } else {
            number = 0
        }
        if number.isNaN || number < 0 { return 0 }
        return number
    }
}
