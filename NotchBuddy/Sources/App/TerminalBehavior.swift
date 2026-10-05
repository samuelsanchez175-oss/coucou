import Foundation

/// Pure decisions for the four terminal faces, the open-notch height, and track skip.
enum TerminalBehavior {
    enum Face: Equatable {
        case idle, working, waiting
    }

    struct Reading: Equatable {
        var face: Face
        var grokMissing: Bool
    }

    /// Header, padding, two face rows, the attach row, a prompt, a status line, and the lock.
    static let face: CGFloat = 28
    static let label: CGFloat = 12
    static let compactSide: CGFloat = 28
    /// Status dot on a closed-notch blob. The menu bar has no name beside it, so it is larger than the open 6pt dot.
    static let collapsedStatusLight: CGFloat = 8
    /// How far that dot sits past the blob's bottom-right corner, so it clears the face.
    static let collapsedStatusShift: CGFloat = 5
    /// Ear beside the camera. The white blob sits in the left one. The four blobs sit in the right one.
    static let collapsedWing: CGFloat = 64
    /// Both open-notch columns use this width. The pair is centered in the card.
    static let faceColumn: CGFloat = 108
    /// Room for the name beside the 6pt status dot and its gap, with a little slack
    /// so SwiftUI does not add an ellipsis.
    static var blobNameWidth: CGFloat { faceColumn - 14 }
    static let faceColumnGap: CGFloat = 16
    static var faceGridWidth: CGFloat { faceColumn * 2 + faceColumnGap }
    /// Home page inset, the left card, and the gap before the terminal card.
    static let overviewPageInset: CGFloat = 10
    static let overviewLeftCard: CGFloat = 322
    static let overviewCardGap: CGFloat = 10

    /// Width left for the four terminal tiles after the left card.
    static func overviewRightCard(islandWidth: CGFloat) -> CGFloat {
        islandWidth - overviewPageInset * 2 - overviewLeftCard - overviewCardGap
    }
    static let overviewHeight: CGFloat = 8 + 34 + clusterHeight + 10

    /// Vertical center of the four faces, in the overview's content coordinates.
    /// This still includes the 8pt pad and 34pt header. A notched Mac subtracts
    /// that band once the header has moved into the menu bar.
    static var overviewBlobCenterY: CGFloat {
        let row = face + 2 + label
        let first = 8 + 34 + 6 + row / 2
        let second = first + row + 6
        return (first + second) / 2
    }

    /// 8pt pad plus the 34pt button row. On a notched Mac this row moves into the menu bar.
    static let menuBarHeaderBand: CGFloat = 42

    /// Controls sit halfway down the menu bar.
    static func menuBarControlCenterY(band: CGFloat) -> CGFloat {
        max(0, band) / 2
    }

    struct MenuBarWings: Equatable {
        /// Left tabs end here, at the hardware notch's left edge.
        var notchLeading: CGFloat
        /// Settings and volume begin here, at the hardware notch's right edge.
        var notchTrailing: CGFloat
    }

    /// The open drawer is centered on the notch. Tabs fill the left wing. Settings fills the right.
    static func menuBarWings(islandWidth: CGFloat, notchWidth: CGFloat) -> MenuBarWings {
        let width = max(0, islandWidth)
        let notch = min(max(0, notchWidth), width)
        let leading = (width - notch) / 2
        return MenuBarWings(notchLeading: leading, notchTrailing: leading + notch)
    }

    /// Drop the in-drawer header when it has moved onto the menu bar.
    static func drawerBodyHeight(layoutHeight: CGFloat, hasNotch: Bool) -> CGFloat {
        guard hasNotch else { return layoutHeight }
        return max(0, layoutHeight - menuBarHeaderBand)
    }

    /// Open-notch height. `NotchClearance.expandedHeight` stays content plus the housing.
    static func expandedDrawerHeight(layoutHeight: CGFloat, occludedHeight: CGFloat, headerInMenuBar: Bool) -> CGFloat {
        let body = drawerBodyHeight(layoutHeight: layoutHeight, hasNotch: headerInMenuBar && occludedHeight > 0)
        return NotchClearance(occludedHeight: occludedHeight).expandedHeight(body)
    }

    /// Face-relative blob center. The stored layout y still includes the header row.
    static func blobCenterY(layoutY: CGFloat, headerInMenuBar: Bool) -> CGFloat {
        headerInMenuBar ? layoutY - menuBarHeaderBand : layoutY
    }

    /// How long a locked terminal page stays open after the pointer leaves.
    static let pageLockHold: TimeInterval = 20
    /// The lock icon opens across this long, ending when the hold ends.
    static let pageLockUnlock: TimeInterval = 3

    private static let attachRow: CGFloat = 22
    private static let lockRow: CGFloat = 22

    private static var clusterHeight: CGFloat {
        let row = face + 2 + label
        let grid = row + 6 + row
        return 12 + grid + 6 + attachRow + 6 + 44 + 6 + 14 + 6 + lockRow
    }

    enum BlobClick: Equatable {
        /// Open this color's window, or focus it, and tile it into its corner.
        case focus
        /// The separate Attach control asks which open terminal to wire.
        case askAttach
    }

    enum Corner: Equatable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// Point size Terminal uses when a blob opens or focuses its window.
    static let terminalFontSize = 20

    /// Terminal.app `bounds`: left, top, right, bottom. Origin is the top-left
    /// of the main display, and y grows downward.
    struct TerminalBounds: Equatable, Sendable {
        var left: Int
        var top: Int
        var right: Int
        var bottom: Int
    }

    struct SlotBinding: Equatable {
        var id: String
        var windowID: Int?
    }

    /// The Terminal window a blob opened. It lasts until that window is gone.
    struct Marriage: Equatable {
        var windowID: Int?
        var terminated: Bool
    }

    /// A blob stays on the window it opened. A window missing from a real
    /// Terminal list is terminated. A failed listing keeps the marriage, and
    /// a window the blob did not open is left alone.
    static func marriage(windowID: Int?, liveWindowIDs: [Int], listed: Bool) -> Marriage {
        guard let windowID else {
            return Marriage(windowID: nil, terminated: false)
        }
        if !listed || liveWindowIDs.contains(windowID) {
            return Marriage(windowID: windowID, terminated: false)
        }
        return Marriage(windowID: nil, terminated: true)
    }

    /// The one window already tiled into this color's corner.
    /// A window somewhere else is not claimed. Two windows in one corner are not guessed.
    /// A window another color already owns is left alone.
    static func windowInCorner(quadrant: TerminalBounds, windows: [CornerWindow], taken: Set<Int>, slack: Int = cornerSlack) -> Int? {
        let hits = windows.filter { window in
            !taken.contains(window.id) && sameFrame(window.bounds, quadrant, slack: slack)
        }
        guard hits.count == 1 else { return nil }
        return hits[0].id
    }

    private static func sameFrame(_ window: TerminalBounds, _ quadrant: TerminalBounds, slack: Int) -> Bool {
        abs(window.left - quadrant.left) <= slack
            && abs(window.top - quadrant.top) <= slack
            && abs(window.right - quadrant.right) <= slack
            && abs(window.bottom - quadrant.bottom) <= slack
    }

    struct ListedWindow: Equatable {
        var id: Int
        var title: String
        /// Present when the listing included the window frame. Nil for an older id-and-title line.
        var bounds: TerminalBounds? = nil
    }

    /// A Terminal window Coucou can recognize by the corner it was tiled into.
    struct CornerWindow: Equatable {
        var id: Int
        var bounds: TerminalBounds
    }

    /// How far a tiled window may sit from the corner Coucou gave it, in points.
    static let cornerSlack = 48

    /// One answer from Terminal. `listed` is false when the text is not a
    /// window list. An empty list is still listed: the windows are gone.
    struct WindowListing: Equatable {
        var windows: [ListedWindow]
        var tails: [String]
        var listed: Bool
    }

    /// Split `id`, a real tab, and the window title. A line that is not that
    /// shape means the listing was not read, so it must not look like every
    /// window closed. Terminal's `tab` class stringifies as the word "tab".
    static func parseSnapshot(_ text: String, slotCount: Int) -> WindowListing {
        let parts = text.components(separatedBy: "\u{1e}")
        var windows: [ListedWindow] = []
        var unread = 0
        let listing = parts.first ?? ""
        for line in listing.split(whereSeparator: \.isNewline) {
            let bits = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let id = Int(bits.first ?? "") else {
                unread += 1
                continue
            }
            let title: String
            var bounds: TerminalBounds?
            if bits.count >= 6,
               let left = Int(bits[1]), let top = Int(bits[2]),
               let right = Int(bits[3]), let bottom = Int(bits[4]) {
                bounds = TerminalBounds(left: left, top: top, right: right, bottom: bottom)
                title = bits.dropFirst(5).joined(separator: "\t")
            } else if bits.count > 1 {
                title = bits.dropFirst().joined(separator: "\t")
            } else {
                unread += 1
                continue
            }
            windows.append(ListedWindow(id: id, title: title.isEmpty ? "Terminal" : title, bounds: bounds))
        }
        var tails = parts.dropFirst().map { String($0) }
        if tails.count < slotCount {
            tails.append(contentsOf: Array(repeating: "", count: slotCount - tails.count))
        }
        return WindowListing(
            windows: windows,
            tails: Array(tails.prefix(slotCount)),
            listed: unread == 0
        )
    }

    struct WindowChoice: Equatable, Identifiable {
        var id: Int
        var title: String
    }

    /// Every color opens or focuses its own window. The Attach control asks.
    static func blobClick(slotID _: String, selectedID _: String) -> BlobClick {
        .focus
    }

    /// Green is the top left, yellow the top right, purple the bottom left, red the bottom right.
    static func corner(slotID: String) -> Corner {
        switch slotID {
        case "orange", "yellow": return .topRight
        case "purple": return .bottomLeft
        case "red": return .bottomRight
        default: return .topLeft
        }
    }

    static func cornerPhrase(_ slotID: String) -> String {
        switch corner(slotID: slotID) {
        case .topLeft: return "top left"
        case .topRight: return "top right"
        case .bottomLeft: return "bottom left"
        case .bottomRight: return "bottom right"
        }
    }

    /// True while a locked terminal page should ignore the pointer leaving.
    /// The hold starts when `leftAt` is set and ends `pageLockHold` seconds later.
    static func holdsPageOpen(locked: Bool, onPage: Bool, leftAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard locked, onPage, let leftAt else { return false }
        return now - leftAt < pageLockHold
    }

    /// True when the 20 second hold has finished and the lock should open.
    static func shouldReleasePageLock(locked: Bool, onPage: Bool, leftAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard locked, onPage, let leftAt else { return false }
        return now - leftAt >= pageLockHold
    }

    /// 0 is a closed lock. 1 is an open lock.
    /// The change runs across the last 3 seconds of the hold.
    static func lockOpenAmount(locked: Bool, leftAt: TimeInterval?, now: TimeInterval) -> Double {
        guard locked else { return 1 }
        guard let leftAt else { return 0 }
        let elapsed = now - leftAt
        let start = pageLockHold - pageLockUnlock
        if elapsed <= start { return 0 }
        if elapsed >= pageLockHold { return 1 }
        return (elapsed - start) / pageLockUnlock
    }

    struct BlobFrame: Equatable {
        var id: String
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat

        func contains(_ x: CGFloat, _ y: CGFloat) -> Bool {
            x >= self.x && x < self.x + width && y >= self.y && y < self.y + height
        }
    }

    /// The four faces in the right-hand card, in island coordinates (origin top-left).
    /// `contentTop` is the top of the page content, under the camera housing.
    static func blobFrames(islandWidth: CGFloat, contentTop: CGFloat, headerInContent: Bool = true) -> [BlobFrame] {
        let inset: CGFloat = 10
        let leftCard: CGFloat = 322
        let gap: CGFloat = 10
        let clusterPadX: CGFloat = 8
        let gridTop = contentTop + (headerInContent ? menuBarHeaderBand : 0) + 6
        let rightX = inset + leftCard + gap
        let rightWidth = max(0, islandWidth - inset * 2 - leftCard - gap)
        let innerX = rightX + clusterPadX
        let innerWidth = max(0, rightWidth - clusterPadX * 2)
        let columnGap: CGFloat = 8
        let columnWidth = max(0, (innerWidth - columnGap) / 2)
        let rowHeight = face + 2 + label
        let rowGap: CGFloat = 6
        let rows = [["green", "orange"], ["purple", "red"]]
        var frames: [BlobFrame] = []
        for (row, ids) in rows.enumerated() {
            for (column, id) in ids.enumerated() {
                frames.append(BlobFrame(
                    id: id,
                    x: innerX + CGFloat(column) * (columnWidth + columnGap),
                    y: gridTop + CGFloat(row) * (rowHeight + rowGap),
                    width: columnWidth,
                    height: rowHeight
                ))
            }
        }
        return frames
    }

    /// The color under a drop, or nil when the pointer is not on a face.
    static func blobSlot(x: CGFloat, y: CGFloat, islandWidth: CGFloat, contentTop: CGFloat, headerInContent: Bool = true) -> String? {
        blobFrames(islandWidth: islandWidth, contentTop: contentTop, headerInContent: headerInContent).first { $0.contains(x, y) }?.id
    }

    /// What to type so Grok attaches this path. Hidden files need the `!` picker.
    static func attachmentQuery(path: String, isDirectory: Bool) -> String {
        var text = path
        if isDirectory && !text.hasSuffix("/") { text += "/" }
        let hidden = text.split(separator: "/", omittingEmptySubsequences: false).contains { part in
            part.hasPrefix(".") && part != "." && part != ".."
        }
        return (hidden ? "@!" : "@") + text
    }

    static func attachmentNote(names: [String]) -> String {
        if names.count == 1, let name = names.first, !name.isEmpty {
            return "Attached \(name)"
        }
        return "Attached \(names.count) files"
    }

    struct CollapsedBlobCenters: Equatable {
        var whiteX: CGFloat
        var facesX: CGFloat
    }

    /// Centers of the white blob and the four-blob grid, in a closed island.
    /// Both sit in the ears, outside the camera housing.
    static func collapsedBlobCenters(islandWidth: CGFloat, notchWidth: CGFloat) -> CollapsedBlobCenters {
        let width = max(0, islandWidth)
        let notch = min(max(0, notchWidth), width)
        let leading = (width - notch) / 2
        let inset = collapsedWing / 2
        return CollapsedBlobCenters(
            whiteX: max(inset, leading - inset),
            facesX: min(max(inset, width - inset), leading + notch + inset)
        )
    }

    /// Each open color keeps its own corner. Empty corners stay empty.
    /// A single window does not grow to fill the screen.
    static func quadrantPlacements(
        slotIDs: [String],
        visibleLeft: Int,
        visibleTop: Int,
        visibleWidth: Int,
        visibleHeight: Int
    ) -> [String: TerminalBounds] {
        var frames: [String: TerminalBounds] = [:]
        var seen = Set<String>()
        for id in slotIDs where seen.insert(id).inserted {
            frames[id] = quadrantBounds(
                slotID: id,
                visibleLeft: visibleLeft,
                visibleTop: visibleTop,
                visibleWidth: visibleWidth,
                visibleHeight: visibleHeight
            )
        }
        return frames
    }

    /// The pose of the little cuddler for this terminal.
    /// Idle rests. A new response works. A question asks.
    static func cuddlerState(for face: Face) -> BotState {
        switch face {
        case .idle: return .idle
        case .working: return .working
        case .waiting: return .question
        }
    }

    /// Where one color sits when all four windows are open.
    static func quadrantBounds(
        slotID: String,
        visibleLeft: Int,
        visibleTop: Int,
        visibleWidth: Int,
        visibleHeight: Int
    ) -> TerminalBounds {
        var ids = ["green", "orange", "purple", "red"]
        if !ids.contains(slotID) { ids.append(slotID) }
        let frames = tiledFrames(
            slotIDs: ids,
            visibleLeft: visibleLeft,
            visibleTop: visibleTop,
            visibleWidth: visibleWidth,
            visibleHeight: visibleHeight
        )
        if let frame = frames[slotID] { return frame }
        return TerminalBounds(
            left: visibleLeft,
            top: visibleTop,
            right: visibleLeft + max(0, visibleWidth),
            bottom: visibleTop + max(0, visibleHeight)
        )
    }

    /// How open windows would share the screen if they grew into empty corners.
    /// Opening a blob does not use this. `quadrantPlacements` keeps each color
    /// in its own corner. One window takes all of it here. Two split it in half.
    /// Three give the whole side to the color that is alone, and split the other side.
    /// Four meet at the corners.
    static func tiledFrames(
        slotIDs: [String],
        visibleLeft: Int,
        visibleTop: Int,
        visibleWidth: Int,
        visibleHeight: Int
    ) -> [String: TerminalBounds] {
        let width = max(0, visibleWidth)
        let height = max(0, visibleHeight)
        var seen = Set<String>()
        let unique = slotIDs.filter { seen.insert($0).inserted }
        let leftIDs = unique.filter { isLeft($0) }
        let rightIDs = unique.filter { !isLeft($0) }
        let midX = width / 2
        let midY = height / 2
        let rightWidth = width - midX
        let bottomHeight = height - midY
        var frames: [String: TerminalBounds] = [:]

        func fill(_ ids: [String], _ x: Int, _ w: Int) {
            let tops = ids.filter { isTop($0) }
            let bottoms = ids.filter { !isTop($0) }
            if !tops.isEmpty && !bottoms.isEmpty {
                for id in tops {
                    frames[id] = TerminalBounds(
                        left: x, top: visibleTop, right: x + w, bottom: visibleTop + midY
                    )
                }
                for id in bottoms {
                    frames[id] = TerminalBounds(
                        left: x,
                        top: visibleTop + midY,
                        right: x + w,
                        bottom: visibleTop + midY + bottomHeight
                    )
                }
            } else {
                for id in ids {
                    frames[id] = TerminalBounds(
                        left: x, top: visibleTop, right: x + w, bottom: visibleTop + height
                    )
                }
            }
        }

        if !leftIDs.isEmpty && !rightIDs.isEmpty {
            fill(leftIDs, visibleLeft, midX)
            fill(rightIDs, visibleLeft + midX, rightWidth)
        } else if !leftIDs.isEmpty {
            fill(leftIDs, visibleLeft, width)
        } else {
            fill(rightIDs, visibleLeft, width)
        }
        return frames
    }

    private static func isLeft(_ slotID: String) -> Bool {
        switch corner(slotID: slotID) {
        case .topLeft, .bottomLeft: return true
        case .topRight, .bottomRight: return false
        }
    }

    private static func isTop(_ slotID: String) -> Bool {
        switch corner(slotID: slotID) {
        case .topLeft, .topRight: return true
        case .bottomLeft, .bottomRight: return false
        }
    }

    /// The name Terminal put on the window. A blank title keeps the fallback.
    static func adoptedName(windowTitle: String, fallback: String) -> String {
        let trimmed = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// Two or three whole words from the terminal's own title. The line stops
    /// before it would be wider than the blob column, so the name is not cut off.
    static func shortTitle(_ windowTitle: String, fallback: String) -> String {
        let words = titleWords(windowTitle)
        let chosen = words.isEmpty ? titleWords(fallback) : words
        if chosen.isEmpty { return "Terminal" }
        return wordsThatFit(chosen, maxWidth: blobNameWidth)
    }

    /// Width of a 10pt semibold label, in points. Used to keep the blob name whole.
    static func labelWidth(_ text: String) -> CGFloat {
        text.reduce(CGFloat(0)) { total, character in
            total + (labelGlyphWidth[character] ?? 7.5)
        }
    }

    private static func wordsThatFit(_ words: [String], maxWidth: CGFloat) -> String {
        var kept: [String] = []
        for word in words.prefix(3) {
            let next = (kept + [word]).joined(separator: " ")
            if labelWidth(next) > maxWidth, !kept.isEmpty { break }
            kept.append(word)
        }
        return kept.joined(separator: " ")
    }

    /// Measured widths of SF Pro 10pt semibold. A missing glyph uses a wide stand-in.
    private static let labelGlyphWidth: [Character: CGFloat] = [
        "a": 5.87, "b": 6.49, "c": 5.89, "d": 6.49, "e": 6.02, "f": 4.03, "g": 6.44,
        "h": 6.28, "i": 2.84, "j": 2.84, "k": 5.92, "l": 2.91, "m": 9.21, "n": 6.23,
        "o": 6.21, "p": 6.45, "q": 6.45, "r": 4.27, "s": 5.62, "t": 4.06, "u": 6.23,
        "v": 5.80, "w": 8.32, "x": 5.72, "y": 5.89, "z": 5.68,
        "A": 7.23, "B": 6.92, "C": 7.44, "D": 7.51, "E": 6.24, "F": 6.00, "G": 7.67,
        "H": 7.80, "I": 3.11, "J": 5.90, "K": 7.02, "L": 5.97, "M": 9.06, "N": 7.70,
        "O": 7.93, "P": 6.71, "Q": 7.93, "R": 6.91, "S": 6.73, "T": 6.62, "U": 7.64,
        "V": 7.16, "W": 10.06, "X": 7.23, "Y": 7.00, "Z": 6.82,
        "0": 6.76, "1": 5.06, "2": 6.40, "3": 6.65, "4": 6.83, "5": 6.58, "6": 6.78,
        "7": 6.03, "8": 6.85, "9": 6.78, " ": 2.78, "-": 4.91,
    ]

    /// Idle is orange and slow. A new response is blue and quicker.
    /// A question is purple and the fastest.
    static func statusPhrase(for face: Face) -> String {
        switch face {
        case .idle: return "Idle"
        case .working: return "New response available"
        case .waiting: return "Needs your input"
        }
    }

    static func statusColorHex(for face: Face) -> String {
        switch face {
        case .idle: return "#FF9F1C"
        case .working: return "#3D8BFF"
        case .waiting: return "#C084FC"
        }
    }

    static func heartbeatBPM(for face: Face) -> Double {
        switch face {
        case .idle: return 52
        case .working: return 88
        case .waiting: return 126
        }
    }

    /// Lub-dub brightness from 0 at rest to 1 at the first beat.
    static func heartbeatLevel(seconds: Double, bpm: Double) -> Double {
        guard bpm > 1 else { return 0 }
        let period = 60.0 / bpm
        var cycle = seconds.truncatingRemainder(dividingBy: period) / period
        if cycle < 0 { cycle += 1 }
        func pulse(_ center: Double, _ amp: Double) -> Double {
            let distance = abs(cycle - center)
            let width = 0.05
            if distance >= width { return 0 }
            let rise = 1 - distance / width
            return amp * rise * rise
        }
        return min(1, max(pulse(0.08, 1), pulse(0.20, 0.7)))
    }

    /// Placeholder length. The face itself truncates to the column width.
    static func promptName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = 42
        guard trimmed.count > limit else { return trimmed }
        let head = String(trimmed.prefix(limit - 1)).trimmingCharacters(in: .whitespaces)
        return head + "…"
    }

    /// The unselected Attach blob binds the selected color when that color has
    /// no window, otherwise the first free color, otherwise the selected color.
    static func attachTarget(slots: [SlotBinding], selectedID: String) -> String {
        if slots.first(where: { $0.id == selectedID })?.windowID == nil {
            return selectedID
        }
        if let free = slots.first(where: { $0.windowID == nil }) {
            return free.id
        }
        return selectedID
    }

    /// Open terminals this blob can wire. Windows already on another color stay
    /// available, after the free ones, so a choice can move the wire.
    static func attachChoices(open: [WindowChoice], takenByOthers: Set<Int>) -> [WindowChoice] {
        let free = open.filter { !takenByOthers.contains($0.id) }
        let taken = open.filter { takenByOthers.contains($0.id) }
        return free + taken
    }

    static func choiceTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Terminal" : trimmed
    }

    /// Blank terminal text still has a status when the window title carries it.
    /// Grok's prompt box is on screen during a response and during a quiet prompt,
    /// so that chrome is not a status. The title is. A real shell prompt or a
    /// password prompt in the text still wins over the title.
    static func classify(title: String, contents: String) -> Reading {
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "missing" || isGrokChrome(trimmed) {
            return Reading(face: face(inTitle: title), grokMissing: false)
        }
        let screen = classify(trimmed)
        if screen.face == .idle || screen.face == .waiting || screen.grokMissing {
            return screen
        }
        let titled = face(inTitle: title)
        if titled != .idle {
            return Reading(face: titled, grokMissing: false)
        }
        return screen
    }

    /// The blob keeps its color while idle. A response lights it blue.
    /// A question lights it purple.
    static func blobLightHex(slotHex: String, face: Face) -> String {
        switch face {
        case .idle: return slotHex
        case .working, .waiting: return statusColorHex(for: face)
        }
    }

    /// The composer frame Grok leaves on screen. It does not say whether a response is waiting.
    private static func isGrokChrome(_ text: String) -> Bool {
        if text.localizedCaseInsensitiveContains("shift+tab") { return true }
        return text.contains("❯") && text.localizedCaseInsensitiveContains("grok")
    }

    static func classify(_ raw: String) -> Reading {
        if raw.isEmpty || raw == "missing" { return Reading(face: .idle, grokMissing: false) }
        let lines = raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let last = lines.last else { return Reading(face: .idle, grokMissing: false) }
        let lower = last.lowercased()
        if lower == "grok cli not found" { return Reading(face: .idle, grokMissing: true) }
        if lower.contains("password:") || lower.contains("[y/n]") || lower.contains("(yes/no)") || lower.contains("yes/no") {
            return Reading(face: .waiting, grokMissing: false)
        }
        if isShellPrompt(last) {
            return Reading(face: .idle, grokMissing: false)
        }
        return Reading(face: .working, grokMissing: false)
    }

    /// Grok writes its activity into the window title. The tab text is often blank.
    private static func face(inTitle title: String) -> Face {
        let segments = title
            .components(separatedBy: " — ")
            .flatMap { $0.components(separatedBy: " - ") }
            .map { activitySegment($0) }
            .filter { !$0.isEmpty }
        var working = false
        for segment in segments {
            if isInputRequest(segment) { return .waiting }
            if segment == "waiting for your next prompt" || segment.hasPrefix("waiting for your next prompt") {
                continue
            }
            if isBusy(segment) { working = true }
        }
        if working { return .working }
        let spinning = title.unicodeScalars.contains { $0.value >= 0x2800 && $0.value <= 0x28FF }
        return spinning ? .working : .idle
    }

    private static func activitySegment(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let scalar = text.unicodeScalars.first, scalar.value >= 0x2800 && scalar.value <= 0x28FF {
            text = String(text.unicodeScalars.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.lowercased()
    }

    private static func isInputRequest(_ segment: String) -> Bool {
        segment == "action required" || segment.hasPrefix("action required")
            || segment == "approval required" || segment.hasPrefix("approval required")
            || segment == "needs your input" || segment.hasPrefix("needs your input")
    }

    private static func isBusy(_ segment: String) -> Bool {
        if segment == "running" || segment.hasPrefix("running:") || segment.hasPrefix("running ") { return true }
        if segment == "waiting for response" || segment.hasPrefix("waiting for response") { return true }
        let heads = ["thinking", "responding", "compacting", "retrying", "searching"]
        return heads.contains { segment == $0 || segment.hasPrefix($0 + " ") || segment.hasPrefix($0 + ":") }
    }

    /// A shell prompt ends in % or $. A progress line such as "45%" does not.
    private static func isShellPrompt(_ line: String) -> Bool {
        guard let mark = line.last, mark == "%" || mark == "$" else { return false }
        if line.count == 1 { return true }
        let previous = line[line.index(line.endIndex, offsetBy: -2)]
        if mark == "%" && (previous.isNumber || previous == ")" || previous == "]") { return false }
        return true
    }

    /// Words worth showing under a blob. Skips the account name, the shell, and the size.
    private static func titleWords(_ raw: String) -> [String] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let chunks = text.components(separatedBy: " — ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isNoiseChunk($0) && !isSizeToken($0) }
        guard !chunks.isEmpty else { return [] }
        var body = chunks
        if body.count >= 2 && !body[0].contains(" ") && !body[0].contains("-") {
            body.removeFirst()
        }
        let phrases = body.flatMap { $0.components(separatedBy: " - ") }
        var best: [String] = []
        var bestScore = -1
        for phrase in phrases {
            let words = phraseWords(phrase)
            let score = words.reduce(0) { $0 + ($1.count) }
            if score > bestScore {
                bestScore = score
                best = words
            }
        }
        let status: Set<String> = ["thinking", "waiting", "compacting", "responding", "searching", "working", "running"]
        let skipped = best.drop(while: { status.contains($0.lowercased()) })
        let chosen = skipped.isEmpty ? best : Array(skipped)
        return chosen
    }

    private static func isNoiseChunk(_ chunk: String) -> Bool {
        let lower = chunk.lowercased()
        if isSizeToken(chunk) { return true }
        if ["zsh", "-zsh", "bash", "-bash", "sh", "-sh", "fish", "terminal"].contains(lower) { return true }
        if lower.contains("▸") { return true }
        return false
    }

    private static func isSizeToken(_ text: String) -> Bool {
        let parts = text.split { $0 == "×" || $0 == "x" || $0 == "X" || $0.isWhitespace }
        guard parts.count == 2 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    private static func phraseWords(_ phrase: String) -> [String] {
        phrase.split(whereSeparator: \.isWhitespace).compactMap { raw in
            let word = String(raw).trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
            if word.isEmpty || isSpinner(word) || isSizeToken(word) { return nil }
            let lower = word.lowercased()
            if ["zsh", "bash", "sh", "fish"].contains(lower) { return nil }
            return word
        }
    }

    private static func isSpinner(_ word: String) -> Bool {
        let scalars = word.unicodeScalars
        if scalars.isEmpty { return true }
        return scalars.allSatisfy { scalar in
            let value = scalar.value
            if value >= 0x2800 && value <= 0x28FF { return true }
            return !CharacterSet.alphanumerics.contains(scalar)
        }
    }

    /// A face click in the last moment wins. Anything older, or no click, selects green.
    static func chooseSlot(armedID: String?, age: TimeInterval?) -> String {
        guard let armedID, let age, age >= 0, age < 0.4 else { return "green" }
        return armedID
    }
}
