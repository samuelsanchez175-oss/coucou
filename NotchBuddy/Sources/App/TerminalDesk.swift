import AppKit
import ApplicationServices
import Foundation

enum TerminalFace: String {
    case idle, working, waiting

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .waiting: return "Waiting"
        }
    }

    var botState: BotState {
        switch self {
        case .idle: return .idle
        case .working: return .working
        case .waiting: return .question
        }
    }
}

struct BlobShine: Equatable {
    var hex: String
    var until: Date
}

struct TerminalSlot: Identifiable, Equatable {
    var id: String
    var name: String
    var color: String
    var folder: String
    var windowID: Int?
    /// tty of the selected tab. This stays put when Terminal replaces the window id.
    var tty: String = ""
    /// Noun kept for this session. Empty until the first good title, or a name you type.
    var lockedName: String = ""
    /// grok, claude, or codex. Used the next time this color opens a window.
    var assistant: String = "grok"
}

private struct StoredTerminal: Codable {
    var id: String
    var name: String
    var folder: String
    var windowID: Int?
    var tty: String?
    var lockedName: String?
    var assistant: String?
}

/// Four fixed Terminal.app sessions, one per notch color.
@MainActor
final class TerminalDesk: ObservableObject {
    static let shared = TerminalDesk()

    @Published var slots: [TerminalSlot]
    @Published var selectedID = "green"
    @Published var draft = ""
    @Published var ghost = ""
    @Published var promptFocused = false
    @Published var faces: [String: TerminalFace] = [:]
    @Published var notes: [String: String] = [:]
    @Published var openWindows: [(id: Int, title: String)] = []
    /// Live window title Terminal gave each color. Empty until that window exists.
    @Published var titles: [String: String] = [:]
    @Published var accessibilityOff = false
    @Published var sendFailed = false
    /// Color that is asking which already-open terminal to attach to.
    @Published var askingID: String?
    /// While on, this page stays open for 20 seconds after the pointer leaves.
    @Published var pageLocked = false
    /// When the pointer left, if the page lock is holding the dock open.
    @Published var lockLeftAt: Date?
    /// Color the file drag is currently over.
    @Published var dropSlotID: String?
    /// A short color flash on a blob. The hex is the slot color, or the tool color after a claim.
    @Published var shines: [String: BlobShine] = [:]
    /// When a blob started the one-shot hop, glance, and ring.
    @Published var notices: [String: Date] = [:]

    private var loop: Task<Void, Never>?
    private var ghostTask: Task<Void, Never>?
    private var armedSlot: String?
    private var armedAt: Date?
    /// Frames from the last listing, so a press can focus the window already in that corner.
    private var rememberedCorners: [TerminalBehavior.CornerWindow] = []
    /// Sessions from the last listing that Terminal actually returned.
    private var liveSessions: [TerminalBehavior.LiveSession] = []
    private var liveListIsCurrent = false
    /// A place is moving tabs. The window id changes before the new one is saved.
    private var placeInFlight = 0
    /// Bumps when a place starts, so a listing taken during that move is not trusted to divorce a blob.
    private var placeGeneration = 0
    /// When the first Terminal window was listed. Plain shells stay claimable for startupGrace after this.
    private var firstWindowsAt: Date?
    /// Consecutive listings that omitted a saved window. One miss is not a close.
    private var marriageMisses: [String: Int] = [:]
    /// Colors whose new terminal is still being created. A second press must not start a tab too.
    private var opening: Set<String> = []
    private let defaults = UserDefaults.standard
    private let storeKey = "nook.terminals"

    private init() {
        let saved = Self.load(defaults, key: storeKey)
        slots = Self.palette.map { item in
            let prior = saved.first { $0.id == item.id }
            return TerminalSlot(
                id: item.id,
                name: prior?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? prior!.name : item.name,
                color: item.color,
                folder: prior?.folder ?? "",
                windowID: prior?.windowID,
                tty: prior?.tty ?? "",
                lockedName: prior?.lockedName ?? "",
                assistant: TerminalBehavior.launchTool(prior?.assistant ?? "grok")
            )
        }
        for slot in slots { faces[slot.id] = .idle }
    }

    static let palette: [(id: String, name: String, color: String)] = [
        ("green", "Terminal 1", "#22C55E"),
        ("orange", "Terminal 2", "#F29B38"),
        ("purple", "Terminal 3", "#7C5CFF"),
        ("red", "Terminal 4", "#F4505E"),
    ]

    var selected: TerminalSlot? { slots.first { $0.id == selectedID } ?? slots.first }

    /// The locked noun, or the title on the Terminal window, or the saved name before a window exists.
    func displayName(_ id: String) -> String {
        let slot = slots.first { $0.id == id }
        let locked = slot?.lockedName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !locked.isEmpty { return locked }
        let fallback = slot?.name ?? "Terminal"
        guard let title = titles[id] else { return fallback }
        return TerminalBehavior.adoptedName(windowTitle: title, fallback: fallback)
    }

    func start() {
        guard loop == nil else { return }
        launchCotypistIfNeeded()
        loop = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func selectGreen() { selectedID = "green" }

    /// Remember a compact-face click so opening the notch does not snap back to green.
    func armSelection(_ id: String) {
        armedSlot = id
        armedAt = Date()
    }

    func applyExpandSelection() {
        let age = armedAt.map { Date().timeIntervalSince($0) }
        selectedID = TerminalBehavior.chooseSlot(armedID: armedSlot, age: age)
        armedSlot = nil
        armedAt = nil
    }

    func select(_ id: String) { selectedID = id }

    func setName(_ id: String, _ name: String) {
        lockName(id, name)
    }

    /// Keeps this spelling on the blob until that terminal closes.
    func lockName(_ id: String, _ name: String) {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        slots[index].name = trimmed.isEmpty ? slots[index].name : trimmed
        slots[index].lockedName = trimmed
        save()
    }

    /// The assistant this color starts the next time it opens a window.
    func setAssistant(_ id: String, _ raw: String) {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return }
        let tool = TerminalBehavior.launchTool(raw)
        guard slots[index].assistant != tool else { return }
        slots[index].assistant = tool
        save()
    }

    func shine(_ id: String, hex: String) {
        shines[id] = BlobShine(hex: hex, until: Date().addingTimeInterval(1.2))
    }

    func setFolder(_ id: String, _ folder: String) {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return }
        slots[index].folder = folder
        save()
    }

    func setWindow(_ id: String, _ windowID: Int?) {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return }
        if let windowID {
            for other in slots.indices where other != index && slots[other].windowID == windowID {
                slots[other].windowID = nil
            }
        }
        slots[index].windowID = windowID
        if let windowID, let session = liveSessions.first(where: { $0.id == windowID }), !session.tty.isEmpty {
            slots[index].tty = session.tty
        }
        if windowID == nil {
            slots[index].tty = ""
        }
        save()
    }

    /// A color that is not selected asks which open terminal to wire live.
    func beginAsk(_ id: String) {
        guard slots.contains(where: { $0.id == id }) else { return }
        askingID = id
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.overview)
        Task { await tick() }
    }

    /// The unselected Attach blob asks for the next color that has no window.
    func beginAskForFreeSlot() {
        let bindings = slots.map { TerminalBehavior.SlotBinding(id: $0.id, windowID: $0.windowID) }
        beginAsk(TerminalBehavior.attachTarget(slots: bindings, selectedID: selectedID))
    }

    func cancelAsk() { askingID = nil }

    func windowsForAsk(_ id: String) -> [TerminalBehavior.WindowChoice] {
        let taken = Set(slots.filter { $0.id != id }.compactMap(\.windowID))
        let open = openWindows.map { TerminalBehavior.WindowChoice(id: $0.id, title: $0.title) }
        return TerminalBehavior.attachChoices(open: open, takenByOthers: taken)
    }

    /// Wire this color to a terminal that is already open, then tile it into that corner.
    func attachToOpenWindow(_ id: String, _ windowID: Int) {
        setWindow(id, windowID)
        askingID = nil
        openOrFocus(id)
    }

    /// A deliberate new window. The one-shot claim must not replace this choice.
    func attachNewWindow(_ id: String) {
        setWindow(id, nil)
        askingID = nil
        openOrFocus(id)
    }

    func chooseFolder(_ id: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.message = "Folder this terminal opens in."
        if panel.runModal() == .OK, let url = panel.url {
            setFolder(id, url.path)
        }
    }

    func askForAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// True when Escape should stay in the notch: cancel an attach ask, or clear ghost text.
    func consumeEscape() -> Bool {
        if askingID != nil {
            askingID = nil
            return true
        }
        guard promptFocused, !ghost.isEmpty else { return false }
        ghost = ""
        return true
    }

    func noteDraftChanged() {
        ghostTask?.cancel()
        let prefix = draft
        guard promptFocused, !prefix.isEmpty else {
            ghost = ""
            return
        }
        ghostTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            let suggestion = CotypistLink.suggestion(after: prefix)
            await MainActor.run {
                guard let self, self.draft == prefix, self.promptFocused else { return }
                self.ghost = suggestion
            }
        }
    }

    func acceptNextWord() {
        guard !ghost.isEmpty else { return }
        let word: String
        if let space = ghost.firstIndex(of: " ") {
            word = String(ghost[...space])
        } else {
            word = ghost
        }
        draft += word
        ghost = String(ghost.dropFirst(word.count))
    }

    func acceptAll() {
        guard !ghost.isEmpty else { return }
        draft += ghost
        ghost = ""
    }

    func wakeCotypist() {
        launchCotypistIfNeeded()
        CotypistLink.wake()
        noteDraftChanged()
    }

    /// The window id to focus. A new id with the saved tty is the same terminal.
    private func resolvedWindowID(_ slot: TerminalSlot) -> Int? {
        TerminalBehavior.marriedWindow(
            savedID: slot.windowID,
            savedTTY: slot.tty,
            live: liveSessions,
            listed: liveListIsCurrent
        ).windowID
    }

    /// A click raises the married window and leaves its frame. An empty color opens one.
    /// A window that is already gone opens a new one in that corner.
    func focus(_ id: String) {
        select(id)
        guard let slot = slots.first(where: { $0.id == id }) else { return }
        guard let windowID = resolvedWindowID(slot) else {
            openOrFocus(id)
            return
        }
        Task {
            let raised = await Task.detached {
                TerminalBridge.focus(windowID)
            }.value
            guard !raised else { return }
            let still = slots.first { $0.id == id }?.windowID
            guard still == windowID || still == nil else { return }
            setWindow(id, nil)
            openOrFocus(id)
        }
    }

    func openOrFocus(_ id: String) {
        select(id)
        guard let slot = slots.first(where: { $0.id == id }) else { return }
        let folder = resolvedFolder(slot)
        var windowID = resolvedWindowID(slot)
        if windowID == nil, let quadrant = cornerFrames()[id] {
            let taken = Set(slots.compactMap(\.windowID))
            if let adopted = TerminalBehavior.windowInCorner(quadrant: quadrant, windows: rememberedCorners, taken: taken) {
                windowID = adopted
                setWindow(id, adopted)
            }
        }
        let layout = frames(including: id)
        let clicked = layout[id] ?? TerminalBehavior.TerminalBounds(left: 0, top: 25, right: 800, bottom: 500)
        let others: [(Int, TerminalBehavior.TerminalBounds)] = slots.compactMap { other in
            guard other.id != id, let wid = other.windowID, let frame = layout[other.id] else { return nil }
            return (wid, frame)
        }
        let focusID = windowID
        let creating = focusID == nil
        if creating {
            guard TerminalBehavior.startsOneWindow(inFlight: opening.contains(id)) else { return }
            opening.insert(id)
        }
        let shell = creating ? TerminalBehavior.shellProfile(id) : ""
        let tool = TerminalBehavior.launchTool(slot.assistant)
        let model = TerminalBehavior.modelArgument(tool: tool, claudeModel: AppState.shared.claudeModel, grokModel: AppState.shared.grokModel)
        beginPlace()
        Task {
            let tiled = await Task.detached { () -> (TerminalBridge.Outcome, [TerminalBridge.PlacedWindow]) in
                var outcome = TerminalBridge.openOrFocus(windowID: focusID, folder: folder, bounds: clicked, profile: shell, tool: tool, model: model)
                guard let focus = outcome.windowID else { return (outcome, []) }
                var batch = others
                batch.append((focus, clicked))
                let placed = TerminalBridge.placeMany(batch, focus: focus, profile: shell)
                if let mine = placed.first(where: { $0.requestedID == focus || $0.windowID == focus }) {
                    outcome.windowID = mine.windowID
                    if !mine.title.isEmpty { outcome.windowTitle = mine.title }
                }
                return (outcome, placed)
            }.value
            apply(id, tiled.0)
            if creating { opening.remove(id) }
            if creating, let opened = tiled.0.windowID {
                let profile = TerminalBehavior.shellProfile(id)
                let corner = clicked
                await Task.detached {
                    TerminalBridge.useShellProfile(opened, profile: profile, bounds: corner)
                }.value
            }
            notePlaced(tiled.1)
            endPlace()
        }
    }

    func togglePageLock() {
        pageLocked.toggle()
        lockLeftAt = nil
    }

    func releasePageLock() {
        pageLocked = false
        lockLeftAt = nil
    }

    /// Dropped files are typed into that color's Grok chat as attachments.
    func attachFiles(_ urls: [URL], to id: String) {
        let files: [(path: String, name: String, directory: Bool)] = urls.compactMap { url in
            let path = url.path
            guard !path.isEmpty else { return nil }
            var directory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &directory)
            guard exists else { return nil }
            return (path, url.lastPathComponent, directory.boolValue)
        }
        guard !files.isEmpty, let slot = slots.first(where: { $0.id == id }) else { return }
        select(id)
        cancelAsk()
        let folder = resolvedFolder(slot)
        let windowID = resolvedWindowID(slot)
        let layout = frames(including: id)
        let bounds = layout[id] ?? TerminalBehavior.TerminalBounds(left: 0, top: 25, right: 800, bottom: 500)
        let hadWindow = windowID != nil
        let tool = TerminalBehavior.launchTool(slot.assistant)
        let model = TerminalBehavior.modelArgument(tool: tool, claudeModel: AppState.shared.claudeModel, grokModel: AppState.shared.grokModel)
        let queries = files.map { TerminalBehavior.attachmentQuery(path: $0.path, isDirectory: $0.directory) }
        let note = TerminalBehavior.attachmentNote(names: files.map(\.name))
        notes[id] = note
        beginPlace()
        Task {
            let outcome = await Task.detached {
                TerminalBridge.attach(queries, windowID: windowID, folder: folder, bounds: bounds, tool: tool, model: model)
            }.value
            endPlace()
            apply(id, outcome)
            if !hadWindow, outcome.windowID != nil {
                reflowOpen(focus: outcome.windowID ?? 0)
            }
            if outcome.ok {
                sendFailed = false
                notes[id] = note
            } else {
                sendFailed = true
                notes[id] = "Could not attach"
                if outcome.accessibility { accessibilityOff = true }
            }
        }
    }

    func send() {
        guard let slot = selected else { return }
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let folder = resolvedFolder(slot)
        let windowID = resolvedWindowID(slot)
        let id = slot.id
        let layout = frames(including: id)
        let bounds = layout[id] ?? TerminalBehavior.TerminalBounds(left: 0, top: 25, right: 800, bottom: 500)
        let hadWindow = windowID != nil
        let tool = TerminalBehavior.launchTool(slot.assistant)
        let model = TerminalBehavior.modelArgument(tool: tool, claudeModel: AppState.shared.claudeModel, grokModel: AppState.shared.grokModel)
        beginPlace()
        Task {
            let outcome = await Task.detached {
                TerminalBridge.send(text, windowID: windowID, folder: folder, bounds: bounds, tool: tool, model: model)
            }.value
            endPlace()
            apply(id, outcome)
            if !hadWindow, outcome.windowID != nil {
                reflowOpen(focus: outcome.windowID ?? 0)
            }
            if outcome.ok {
                draft = ""
                ghost = ""
                sendFailed = false
            } else {
                sendFailed = true
                if outcome.accessibility { accessibilityOff = true }
            }
        }
    }

    // MARK: - Private

    private func beginPlace() {
        placeGeneration += 1
        placeInFlight += 1
    }

    private func endPlace() {
        placeInFlight = max(0, placeInFlight - 1)
    }

    private func tick() async {
        let ids = slots.map(\.windowID)
        let readingGeneration = placeGeneration
        let snapshot = await Task.detached {
            TerminalBridge.snapshot(windowIDs: ids)
        }.value
        let placeMoved = placeInFlight > 0 || placeGeneration != readingGeneration
        openWindows = snapshot.windows.map { ($0.id, $0.title) }
        if snapshot.listed {
            liveSessions = snapshot.windows.map { TerminalBehavior.LiveSession(id: $0.id, tty: $0.tty) }
            liveListIsCurrent = true
        }
        let ttyList = snapshot.listed ? snapshot.windows.map(\.tty) : []
        let commands = await Task.detached {
            Self.commandsByTTY(ttyList)
        }.value
        let sessions = liveSessions
        _ = cornerWindows(in: snapshot)
        let quadrants = cornerFrames()
        var nextTitles: [String: String] = [:]
        var resolved: [(windowID: Int?, tty: String, ended: Bool, originalID: Int?, droppedSession: Bool)] = []
        var freshlyClaimed: Set<String> = []
        for (index, slot) in slots.enumerated() {
            let originalID = slots[index].windowID
            let link = TerminalBehavior.marriedWindow(
                savedID: originalID,
                savedTTY: slots[index].tty,
                live: sessions,
                listed: snapshot.listed
            )
            var windowID = link.windowID
            var tty = slots[index].tty
            var ended = link.terminated
            var droppedSession = link.terminated
            if ended && placeMoved {
                ended = false
                windowID = originalID
                droppedSession = false
            }
            if ended {
                let seen = (marriageMisses[slot.id] ?? 0) + 1
                marriageMisses[slot.id] = seen
                if !TerminalBehavior.releaseMarriage(terminated: true, misses: seen) {
                    ended = false
                    windowID = originalID
                    droppedSession = false
                }
            } else {
                marriageMisses[slot.id] = 0
            }
            resolved.append((windowID, tty, ended, originalID, droppedSession))
        }
        if snapshot.listed {
            if !snapshot.windows.isEmpty, firstWindowsAt == nil {
                firstWindowsAt = Date()
            }
            let acceptPlain = firstWindowsAt.map {
                Date().timeIntervalSince($0) < TerminalBehavior.startupGrace
            } ?? true
            let open = snapshot.windows.map { window in
                let ttyName = (window.tty as NSString).lastPathComponent
                return TerminalBehavior.ListedWindow(
                    id: window.id,
                    title: window.title,
                    bounds: window.bounds,
                    tty: window.tty,
                    process: commands[ttyName] ?? ""
                )
            }
            let seated = TerminalBehavior.marriagesForCorners(
                slots: resolved.enumerated().map { index, row in
                    TerminalBehavior.CornerClaim(
                        id: slots[index].id,
                        windowID: row.windowID,
                        tty: row.windowID == nil ? "" : row.tty,
                        lockedName: slots[index].lockedName
                    )
                },
                windows: open,
                quadrants: quadrants
            )
            for index in resolved.indices {
                let was = resolved[index].windowID
                let now = seated[index].windowID
                if was != nil, now == nil {
                    resolved[index].windowID = nil
                    resolved[index].tty = ""
                    resolved[index].ended = true
                    resolved[index].droppedSession = true
                } else if was == nil, now != nil {
                    resolved[index].windowID = now
                    resolved[index].tty = seated[index].tty
                    resolved[index].ended = false
                    freshlyClaimed.insert(slots[index].id)
                    if slots[index].lockedName.isEmpty, !seated[index].lockedName.isEmpty {
                        slots[index].lockedName = seated[index].lockedName
                    }
                }
            }
            let picture = resolved.enumerated().map { index, row in
                TerminalBehavior.ClaimSlot(
                    id: slots[index].id,
                    windowID: row.windowID,
                    tty: row.windowID == nil ? "" : row.tty
                )
            }
            let freeIDs = Set(resolved.enumerated().compactMap { index, row in
                row.windowID == nil ? slots[index].id : nil
            })
            let claimed = TerminalBehavior.claimFreeWindows(
                slots: picture,
                open: open,
                freeIDs: freeIDs,
                acceptPlain: acceptPlain,
                quadrants: quadrants
            )
            for index in resolved.indices where resolved[index].windowID == nil {
                if let adopted = claimed[index].windowID {
                    resolved[index].windowID = adopted
                    resolved[index].ended = false
                    let claimedTTY = claimed[index].tty.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !claimedTTY.isEmpty { resolved[index].tty = claimedTTY }
                    freshlyClaimed.insert(slots[index].id)
                }
            }
        }
        for (index, row) in resolved.enumerated() {
            let slot = slots[index]
            var windowID = row.windowID
            var tty = row.tty
            var ended = row.ended
            let originalID = row.originalID
            if ended {
                windowID = nil
                tty = ""
                faces[slot.id] = .idle
                releaseSessionName(index)
            } else if row.droppedSession {
                releaseSessionName(index)
                if let windowID, let found = snapshot.windows.first(where: { $0.id == windowID }), !found.tty.isEmpty {
                    tty = found.tty
                }
            } else if let windowID, let found = snapshot.windows.first(where: { $0.id == windowID }), !found.tty.isEmpty {
                tty = found.tty
            }
            if slots[index].windowID != windowID || slots[index].tty != tty || slots[index].lockedName != slot.lockedName || slots[index].name != slot.name {
                slots[index].windowID = windowID
                slots[index].tty = tty
                save()
            }
            guard !ended, let windowID, let found = snapshot.windows.first(where: { $0.id == windowID }) else {
                if slots[index].windowID == nil { faces[slot.id] = .idle }
                continue
            }
            let title = TerminalBehavior.adoptedName(windowTitle: found.title, fallback: slot.name)
            nextTitles[slot.id] = title
            let ttyName = (found.tty as NSString).lastPathComponent
            let noun = TerminalBehavior.shortTitle(found.title, fallback: "")
            let restingName = Self.palette.first { $0.id == slots[index].id }?.name ?? ""
            let userNamed = slots[index].name != restingName
            let locked = TerminalBehavior.lockNoun(
                current: slots[index].lockedName,
                candidate: noun,
                sessionEnded: false,
                userNamed: userNamed
            )
            if locked != slots[index].lockedName {
                slots[index].lockedName = locked
                save()
            }
            if freshlyClaimed.contains(slot.id) {
                if let bounds = found.bounds {
                    TerminalFrameFlash.show(bounds: bounds, hex: slot.color)
                }
                if let tool = TerminalBehavior.sessionTool(title: found.title, process: commands[ttyName] ?? "") {
                    shine(slot.id, hex: TerminalBehavior.toolShineHex(tool))
                } else {
                    let profile = TerminalBehavior.shellProfile(slot.id)
                    let tinted = windowID
                    Task.detached {
                        TerminalBridge.useShellProfile(tinted, profile: profile)
                    }
                }
            }
            var raw = index < snapshot.tails.count ? snapshot.tails[index] : ""
            if windowID != originalID, raw == "missing" { raw = "" }
            let read = TerminalRead.classify(title: title, contents: raw)
            let prior = behaviorFace(faces[slot.id] ?? .idle)
            faces[slot.id] = read.face
            if TerminalBehavior.attentionFlash(previous: prior, next: behaviorFace(read.face)),
               !freshlyClaimed.contains(slot.id) {
                shine(slot.id, hex: slot.color)
                notices[slot.id] = Date()
            }
            if read.grokMissing {
                notes[slot.id] = TerminalBehavior.missingLine(for: slot.assistant)
            } else if let note = notes[slot.id], TerminalBehavior.cliIsMissing(note) {
                notes[slot.id] = nil
            }
        }
        if snapshot.listed { titles = nextTitles }
        accessibilityOff = !AXIsProcessTrusted()
        if promptFocused, !draft.isEmpty, ghost.isEmpty {
            ghost = CotypistLink.suggestion(after: draft)
        }
    }

    private func apply(_ id: String, _ outcome: TerminalBridge.Outcome) {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return }
        if let windowID = outcome.windowID {
            slots[index].windowID = windowID
            save()
        }
        if let title = outcome.windowTitle {
            titles[id] = TerminalBehavior.adoptedName(windowTitle: title, fallback: slots[index].name)
        }
        if outcome.grokMissing {
            notes[id] = TerminalBehavior.missingLine(for: slots[index].assistant)
        }
        if outcome.accessibility {
            accessibilityOff = true
        }
    }

    private func resolvedFolder(_ slot: TerminalSlot) -> String {
        let trimmed = slot.folder.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return NSHomeDirectory() }
        return trimmed
    }

    /// The four corners on this display, whether or not a window is open there.
    private func cornerFrames() -> [String: TerminalBehavior.TerminalBounds] {
        let span = screenSpan()
        return TerminalBehavior.quadrantPlacements(
            slotIDs: Self.palette.map(\.id),
            visibleLeft: span.left,
            visibleTop: span.top,
            visibleWidth: span.width,
            visibleHeight: span.height
        )
    }

    /// Windows whose frames came back with the listing. Remembers them for the next press.
    private func cornerWindows(in snapshot: TerminalBridge.Snapshot) -> [TerminalBehavior.CornerWindow] {
        guard snapshot.listed else { return rememberedCorners }
        let corners = snapshot.windows.compactMap { window -> TerminalBehavior.CornerWindow? in
            guard let bounds = window.bounds else { return nil }
            return TerminalBehavior.CornerWindow(id: window.id, bounds: bounds)
        }
        rememberedCorners = corners
        return corners
    }

    /// Frames for the windows that are open, plus the color being opened.
    private func frames(including id: String) -> [String: TerminalBehavior.TerminalBounds] {
        let span = screenSpan()
        var ids = slots.compactMap { $0.windowID == nil ? nil : $0.id }
        if !ids.contains(id) { ids.append(id) }
        return TerminalBehavior.quadrantPlacements(
            slotIDs: ids,
            visibleLeft: span.left,
            visibleTop: span.top,
            visibleWidth: span.width,
            visibleHeight: span.height
        )
    }

    /// Move every open window into its own corner. Focus 0 leaves the front window alone.
    private func reflowOpen(focus: Int) {
        let span = screenSpan()
        let ids = slots.compactMap { $0.windowID == nil ? nil : $0.id }
        let layout = TerminalBehavior.quadrantPlacements(
            slotIDs: ids,
            visibleLeft: span.left,
            visibleTop: span.top,
            visibleWidth: span.width,
            visibleHeight: span.height
        )
        let batch: [(Int, TerminalBehavior.TerminalBounds)] = slots.compactMap { slot in
            guard let wid = slot.windowID, let frame = layout[slot.id] else { return nil }
            return (wid, frame)
        }
        guard !batch.isEmpty else { return }
        beginPlace()
        Task {
            let placed = await Task.detached {
                TerminalBridge.placeMany(batch, focus: focus)
            }.value
            notePlaced(placed)
            endPlace()
        }
    }

    /// Keep each blob married to the window that actually received its corner.
    /// Moving a tab out of a set gives that session a new window id.
    private func notePlaced(_ placed: [TerminalBridge.PlacedWindow]) {
        var changed = false
        for item in placed {
            guard let index = slots.firstIndex(where: { $0.windowID == item.requestedID || $0.windowID == item.windowID }) else { continue }
            if slots[index].windowID != item.windowID {
                slots[index].windowID = item.windowID
                changed = true
            }
            if !item.title.isEmpty {
                titles[slots[index].id] = TerminalBehavior.adoptedName(windowTitle: item.title, fallback: slots[index].name)
            }
        }
        if changed { save() }
    }

    private func adopt(_ names: [Int: String]) {
        for (wid, title) in names {
            guard let slot = slots.first(where: { $0.windowID == wid }) else { continue }
            titles[slot.id] = TerminalBehavior.adoptedName(windowTitle: title, fallback: slot.name)
        }
    }

    /// Usable area of the notched display, in Terminal's top-left bounds space.
    private func screenSpan() -> (left: Int, top: Int, width: Int, height: Int) {
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        let screen = notched ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return (0, 25, 1280, 800) }
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? screen
        let primaryHeight = Int(primary.frame.height.rounded())
        let visible = screen.visibleFrame
        return (
            Int(visible.minX.rounded()),
            primaryHeight - Int(visible.maxY.rounded()),
            Int(visible.width.rounded()),
            Int(visible.height.rounded())
        )
    }

    /// The next session can take a new noun. The resting label is the color's own name.
    private func releaseSessionName(_ index: Int) {
        let id = slots[index].id
        slots[index].lockedName = TerminalBehavior.lockNoun(
            current: slots[index].lockedName,
            candidate: "",
            sessionEnded: true
        )
        if let resting = Self.palette.first(where: { $0.id == id })?.name {
            slots[index].name = resting
        }
    }

    private func behaviorFace(_ face: TerminalFace) -> TerminalBehavior.Face {
        switch face {
        case .idle: return .idle
        case .working: return .working
        case .waiting: return .waiting
        }
    }

    /// Processes on the listed ttys, so a shell title can still show Xcode, Grok, or Claude.
    /// A full process list can stall, so this asks only for those ttys and gives up quickly.
    nonisolated private static func commandsByTTY(_ ttys: [String]) -> [String: String] {
        let names = Array(Set(ttys.map { ($0 as NSString).lastPathComponent }.filter { !$0.isEmpty && $0 != "??" && $0 != "-" }))
        guard !names.isEmpty else { return [:] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        var args = ["-o", "tty=,command="]
        for name in names {
            args.append("-t")
            args.append(name)
        }
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return [:]
        }
        let deadline = Date().addingTimeInterval(0.4)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return [:]
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [:] }
        var map: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }
            let tty = String(parts[0])
            if tty == "??" || tty == "-" { continue }
            map[tty, default: ""] += " " + parts[1]
        }
        return map
    }

    private func launchCotypistIfNeeded() {
        let id = "app.cotypist.Cotypist"
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == id }) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Cotypist.app"))
    }

    private func save() {
        let stored = slots.map {
            StoredTerminal(
                id: $0.id,
                name: $0.name,
                folder: $0.folder,
                windowID: $0.windowID,
                tty: $0.tty.isEmpty ? nil : $0.tty,
                lockedName: $0.lockedName.isEmpty ? nil : $0.lockedName,
                assistant: TerminalBehavior.launchTool($0.assistant)
            )
        }
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: storeKey)
        }
    }

    private static func load(_ defaults: UserDefaults, key: String) -> [StoredTerminal] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([StoredTerminal].self, from: data) else { return [] }
        return stored
    }
}

/// A one-time colored edge on the Terminal window Coucou just claimed.
@MainActor
enum TerminalFrameFlash {
    private static var panels: [NSPanel] = []

    static func show(bounds: TerminalBehavior.TerminalBounds, hex: String) {
        let screen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        let height = screen?.frame.height ?? 0
        let width = CGFloat(bounds.right - bounds.left)
        let frameHeight = CGFloat(bounds.bottom - bounds.top)
        guard width > 2, frameHeight > 2 else { return }
        let rect = NSRect(
            x: CGFloat(bounds.left),
            y: height - CGFloat(bounds.bottom),
            width: width,
            height: frameHeight
        )
        let panel = NSPanel(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let stroke = NSView(frame: NSRect(origin: .zero, size: rect.size))
        stroke.wantsLayer = true
        let ink = nsColor(hex)
        stroke.layer?.backgroundColor = ink.withAlphaComponent(0.16).cgColor
        stroke.layer?.borderColor = ink.cgColor
        stroke.layer?.borderWidth = 5
        stroke.layer?.cornerRadius = 12
        panel.contentView = stroke
        panel.orderFrontRegardless()
        panels.append(panel)
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            panel.orderOut(nil)
            panels.removeAll { $0 === panel }
        }
    }

    private static func nsColor(_ hex: String) -> NSColor {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        Scanner(string: cleaned).scanHexInt64(&value)
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum TerminalRead {
    static func classify(_ raw: String) -> (face: TerminalFace, grokMissing: Bool) {
        mapped(TerminalBehavior.classify(raw))
    }

    static func classify(title: String, contents: String) -> (face: TerminalFace, grokMissing: Bool) {
        mapped(TerminalBehavior.classify(title: title, contents: contents))
    }

    private static func mapped(_ reading: TerminalBehavior.Reading) -> (face: TerminalFace, grokMissing: Bool) {
        let face: TerminalFace
        switch reading.face {
        case .idle: face = .idle
        case .working: face = .working
        case .waiting: face = .waiting
        }
        return (face, reading.grokMissing)
    }
}

enum TerminalBridge {
    struct Outcome: Sendable {
        var ok: Bool
        var windowID: Int?
        var grokMissing: Bool
        var accessibility: Bool
        var windowTitle: String?
    }

    /// The window that received the corner. `requestedID` is the id we asked for.
    /// Moving a tab out of a set replaces it with `windowID`.
    struct PlacedWindow: Sendable {
        var requestedID: Int
        var windowID: Int
        var title: String
    }

    struct Snapshot: Sendable {
        var windows: [(id: Int, title: String, bounds: TerminalBehavior.TerminalBounds?, tty: String)]
        var tails: [String]
        /// False when Terminal did not answer. An empty list while Terminal is running is still true.
        var listed: Bool
    }

    nonisolated static func snapshot(windowIDs: [Int?]) -> Snapshot {
        let script = """
        on run argv
          set sep to character id 30
          set field to character id 9
          set AppleScript's text item delimiters to sep
          set windowLines to {}
          set tails to {}
          if application "Terminal" is not running then return sep
          tell application "Terminal"
            repeat with w in windows
              try
                set widText to (id of w) as text
                if widText is not "" then
                  set ttyName to ""
                  try
                    set ttyName to tty of selected tab of w
                  end try
                  set leftEdge to ""
                  set topEdge to ""
                  set rightEdge to ""
                  set bottomEdge to ""
                  try
                    set frameBox to bounds of w
                    set leftEdge to item 1 of frameBox as text
                    set topEdge to item 2 of frameBox as text
                    set rightEdge to item 3 of frameBox as text
                    set bottomEdge to item 4 of frameBox as text
                  end try
                  set wname to "Terminal"
                  try
                    set wname to name of w
                  end try
                  set end of windowLines to widText & field & leftEdge & field & topEdge & field & rightEdge & field & bottomEdge & field & ttyName & field & wname
                end if
              end try
            end repeat
            repeat with widText in argv
              if widText is "" then
                set end of tails to ""
              else
                set blob to ""
                try
                  set blob to contents of selected tab of window id (widText as integer)
                  if (count of blob) > 500 then set blob to text -500 thru -1 of blob
                end try
                set end of tails to blob
              end if
            end repeat
          end tell
          set AppleScript's text item delimiters to linefeed
          set listing to windowLines as text
          set AppleScript's text item delimiters to sep
          return listing & sep & (tails as text)
        end run
        """
        let args = windowIDs.map { $0.map(String.init) ?? "" }
        guard let text = OSAScript.run(script, args: args), !text.isEmpty else {
            return Snapshot(windows: [], tails: Array(repeating: "", count: windowIDs.count), listed: false)
        }
        let parsed = TerminalBehavior.parseSnapshot(text, slotCount: windowIDs.count)
        return Snapshot(
            windows: parsed.windows.map { ($0.id, $0.title, $0.bounds, $0.tty) },
            tails: parsed.tails,
            listed: parsed.listed
        )
    }

    nonisolated static func openOrFocus(windowID: Int?, folder: String, bounds: TerminalBehavior.TerminalBounds, profile: String = "", tool: String = "grok", model: String = "") -> Outcome {
        if let windowID, let placed = place(windowID, bounds) {
            return Outcome(
                ok: true,
                windowID: placed.windowID,
                grokMissing: false,
                accessibility: false,
                windowTitle: placed.title
            )
        }
        return openNew(folder: folder, bounds: bounds, profile: profile, tool: tool, model: model)
    }

    nonisolated static func send(_ text: String, windowID: Int?, folder: String, bounds: TerminalBehavior.TerminalBounds, tool: String = "grok", model: String = "") -> Outcome {
        var target = windowID
        var openedTitle: String?
        if target == nil || !focus(target!) {
            let opened = openNew(folder: folder, bounds: bounds, tool: tool, model: model)
            guard opened.ok, let id = opened.windowID else { return opened }
            target = id
            openedTitle = opened.windowTitle
        }
        guard let target else {
            return Outcome(ok: false, windowID: nil, grokMissing: false, accessibility: !AXIsProcessTrusted(), windowTitle: nil)
        }
        let script = """
        on run argv
          set wid to item 1 of argv as integer
          set promptText to item 2 of argv
          tell application "Terminal"
            if not (exists window id wid) then return "missing"
            set index of window id wid to 1
            activate
          end tell
          tell application "System Events"
            tell process "Terminal"
              set frontmost to true
              keystroke promptText
              key code 36
            end tell
          end tell
          return "ok"
        end run
        """
        let reply = OSAScript.run(script, args: [String(target), text]) ?? ""
        if reply == "ok" {
            return Outcome(ok: true, windowID: target, grokMissing: false, accessibility: false, windowTitle: openedTitle)
        }
        return Outcome(ok: false, windowID: target, grokMissing: false, accessibility: !AXIsProcessTrusted(), windowTitle: openedTitle)
    }

    /// Type each `@path` into the Grok chat, accept the file picker, then send.
    nonisolated static func attach(_ queries: [String], windowID: Int?, folder: String, bounds: TerminalBehavior.TerminalBounds, tool: String = "grok", model: String = "") -> Outcome {
        guard !queries.isEmpty else {
            return Outcome(ok: false, windowID: windowID, grokMissing: false, accessibility: false, windowTitle: nil)
        }
        var target = windowID
        var openedTitle: String?
        if target == nil || !focus(target!) {
            let opened = openNew(folder: folder, bounds: bounds, tool: tool, model: model)
            guard opened.ok, let id = opened.windowID else { return opened }
            target = id
            openedTitle = opened.windowTitle
        }
        guard let target else {
            return Outcome(ok: false, windowID: nil, grokMissing: false, accessibility: !AXIsProcessTrusted(), windowTitle: nil)
        }
        var args = [String(target)]
        args.append(contentsOf: queries)
        let script = """
        on run argv
          set wid to item 1 of argv as integer
          tell application "Terminal"
            if not (exists window id wid) then return "missing"
            set index of window id wid to 1
            activate
          end tell
          tell application "System Events"
            tell process "Terminal"
              set frontmost to true
              repeat with i from 2 to (count of argv)
                keystroke item i of argv
                delay 0.4
                key code 48
                delay 0.15
              end repeat
              key code 36
            end tell
          end tell
          return "ok"
        end run
        """
        let reply = OSAScript.run(script, args: args) ?? ""
        if reply == "ok" {
            return Outcome(ok: true, windowID: target, grokMissing: false, accessibility: false, windowTitle: openedTitle)
        }
        return Outcome(ok: false, windowID: target, grokMissing: false, accessibility: !AXIsProcessTrusted(), windowTitle: openedTitle)
    }

    /// Frames of every Terminal window, taken before a new session can join one as a tab.
    nonisolated private static let rememberWindowFrames = """
        set savedIDs to {}
        set savedL to {}
        set savedT to {}
        set savedR to {}
        set savedB to {}
        repeat with w in windows
          try
            set end of savedIDs to id of w
            set frameBox to bounds of w
            set end of savedL to item 1 of frameBox
            set end of savedT to item 2 of frameBox
            set end of savedR to item 3 of frameBox
            set end of savedB to item 4 of frameBox
          end try
        end repeat
        """

    /// Puts back every window except the ones just placed. Joining a tab resizes the window it lands on.
    nonisolated private static let restoreOtherWindowFrames = """
        repeat with i from 1 to (number of items in savedIDs)
          set sid to item i of savedIDs
          if sid is not in keptIDs then
            try
              set bounds of window id sid to {item i of savedL, item i of savedT, item i of savedR, item i of savedB}
            end try
          end if
        end repeat
        """

    /// With "Prefer tabs" set to Always, a new Terminal window joins the front window's tab set.
    /// Setting bounds then slides every tab. This pulls the front tab out first. The menu item
    /// is disabled when that window is already on its own.
    nonisolated private static let moveTabToOwnWindow = """
        set didMove to false
        tell application "System Events"
          tell process "Terminal"
            set frontmost to true
            try
              set moveItem to menu item "Move Tab to New Window" of menu "Window" of menu bar 1
              if enabled of moveItem then
                click moveItem
                set didMove to true
              end if
            end try
          end tell
        end tell
        if didMove then delay 0.2
        """

    /// Bring this window forward and snap it to its corner.
    /// After a tab leaves its set, the corner is applied to the new window.
    nonisolated private static func place(_ windowID: Int, _ bounds: TerminalBehavior.TerminalBounds) -> PlacedWindow? {
        let script = """
        on run argv
          set wid to item 1 of argv as integer
          set requested to wid
          set leftEdge to item 2 of argv as integer
          set topEdge to item 3 of argv as integer
          set rightEdge to item 4 of argv as integer
          set bottomEdge to item 5 of argv as integer
          if application "Terminal" is not running then return "no"
          tell application "Terminal"
            if not (exists window id wid) then return "no"
            set theTTY to ""
            try
              set theTTY to tty of selected tab of window id wid
            end try
            \(rememberWindowFrames)
            set index of window id wid to 1
            try
              set font size of current settings of selected tab of window id wid to \(TerminalBehavior.terminalFontSize)
            end try
            \(moveTabToOwnWindow)
            set placedWindow to window id wid
            if didMove then
              try
                set placedWindow to window 1
              end try
            end if
            if theTTY is not "" then
              repeat with candidate in windows
                try
                  if tty of selected tab of candidate is theTTY then set placedWindow to candidate
                end try
              end repeat
            end if
            set bounds of placedWindow to {leftEdge, topEdge, rightEdge, bottomEdge}
            try
              set wid to id of placedWindow
            end try
            set keptIDs to {wid}
            \(restoreOtherWindowFrames)
            activate
            set wname to name of placedWindow
          end tell
          return "yes" & character id 31 & (wid as text) & character id 31 & wname
        end run
        """
        let reply = OSAScript.run(script, args: [
            String(windowID),
            String(bounds.left),
            String(bounds.top),
            String(bounds.right),
            String(bounds.bottom),
        ]) ?? ""
        guard reply.hasPrefix("yes") else { return nil }
        let parts = reply.components(separatedBy: "\u{1f}")
        let resolved = parts.count > 1 ? Int(parts[1]) ?? windowID : windowID
        let title = parts.count > 2 ? parts[2] : ""
        return PlacedWindow(requestedID: windowID, windowID: resolved, title: title)
    }

    /// Snap every listed window into its corner, then optionally bring one forward.
    /// Each result names the window that owns the session after a tab is pulled out.
    nonisolated static func placeMany(_ windows: [(Int, TerminalBehavior.TerminalBounds)], focus: Int, profile: String = "") -> [PlacedWindow] {
        guard !windows.isEmpty else { return [] }
        var args = [String(focus), profile]
        for (id, bounds) in windows {
            args.append(contentsOf: [
                String(id),
                String(bounds.left),
                String(bounds.top),
                String(bounds.right),
                String(bounds.bottom),
            ])
        }
        let script = """
        on run argv
          set focusID to item 1 of argv as integer
          set profileName to item 2 of argv
          set focusTarget to focusID
          set names to {}
          set placedIDs to {}
          set i to 3
          tell application "Terminal"
            \(rememberWindowFrames)
            repeat while (i + 4) is less than or equal to (count of argv)
              set wid to item i of argv as integer
              set requested to wid
              set leftEdge to item (i + 1) of argv as integer
              set topEdge to item (i + 2) of argv as integer
              set rightEdge to item (i + 3) of argv as integer
              set bottomEdge to item (i + 4) of argv as integer
              try
                if exists window id wid then
                  set theTTY to ""
                  try
                    set theTTY to tty of selected tab of window id wid
                  end try
                  set index of window id wid to 1
                  try
                    set font size of current settings of selected tab of window id wid to \(TerminalBehavior.terminalFontSize)
                  end try
                  \(moveTabToOwnWindow)
                  set placedWindow to window id wid
                  if didMove then
                    try
                      set placedWindow to window 1
                    end try
                  end if
                  if theTTY is not "" then
                    repeat with candidate in windows
                      try
                        if tty of selected tab of candidate is theTTY then set placedWindow to candidate
                      end try
                    end repeat
                  end if
                  set bounds of placedWindow to {leftEdge, topEdge, rightEdge, bottomEdge}
                  if requested is focusID then
                    \(Self.profileCommands(for: "placedWindow"))
                    try
                      set font size of current settings of selected tab of placedWindow to \(TerminalBehavior.terminalFontSize)
                    end try
                    set bounds of placedWindow to {leftEdge, topEdge, rightEdge, bottomEdge}
                  end if
                  try
                    set wid to id of placedWindow
                  end try
                  if requested is focusID then set focusTarget to wid
                  set end of placedIDs to wid
                  set end of names to (requested as text) & character id 31 & (wid as text) & character id 31 & (name of placedWindow)
                end if
              end try
              set i to i + 5
            end repeat
            set keptIDs to placedIDs
            \(restoreOtherWindowFrames)
            if focusTarget is not 0 then
              try
                if exists window id focusTarget then
                  set index of window id focusTarget to 1
                  activate
                end if
              end try
            end if
          end tell
          set AppleScript's text item delimiters to character id 30
          return names as text
        end run
        """
        let reply = OSAScript.run(script, args: args) ?? ""
        var placed: [PlacedWindow] = []
        for record in reply.components(separatedBy: "\u{1e}") where !record.isEmpty {
            let parts = record.components(separatedBy: "\u{1f}")
            guard let requested = Int(parts.first ?? "") else { continue }
            let resolved = parts.count > 1 ? Int(parts[1]) ?? requested : requested
            let title = parts.count > 2 ? parts[2] : ""
            placed.append(PlacedWindow(requestedID: requested, windowID: resolved, title: title))
        }
        return placed
    }

    /// Grass, Man Page, Violet, or Red Sands, applied to the window that is already on its own.
    /// An empty name leaves the window alone. Violet is created from Grass the first time.
    nonisolated private static func profileCommands(for windowVar: String) -> String {
        let background = TerminalBehavior.violetBackground
        let text = TerminalBehavior.violetText
        return """
            if profileName is not "" then
              if profileName is "Violet" then
                if not (exists settings set "Violet") then
                  try
                    duplicate settings set "Grass" to end of settings sets with properties {name:"Violet"}
                    set background color of settings set "Violet" to {\(background.red), \(background.green), \(background.blue)}
                    set normal text color of settings set "Violet" to {\(text.red), \(text.green), \(text.blue)}
                    set bold text color of settings set "Violet" to {\(text.red), \(text.green), \(text.blue)}
                    set cursor color of settings set "Violet" to {\(text.red), \(text.green), \(text.blue)}
                  end try
                end if
              end if
              try
                set current settings of selected tab of \(windowVar) to settings set profileName
              end try
            end if
        """
    }

    /// A plain shell takes Grass, Man Page, Violet, or Red Sands. Tool windows stay as they are.
    /// Violet is created from Grass the first time a purple shell needs it.
    nonisolated static func useShellProfile(_ windowID: Int, profile: String, bounds: TerminalBehavior.TerminalBounds? = nil) {
        let background = TerminalBehavior.violetBackground
        let text = TerminalBehavior.violetText
        var args = [String(windowID), profile]
        if let bounds {
            args.append(contentsOf: [
                String(bounds.left),
                String(bounds.top),
                String(bounds.right),
                String(bounds.bottom),
            ])
        }
        let script = """
        on run argv
          set wid to item 1 of argv as integer
          set profileName to item 2 of argv
          if application "Terminal" is not running then return "no"
          tell application "Terminal"
            if not (exists window id wid) then return "no"
            if profileName is "Violet" then
              if not (exists settings set "Violet") then
                try
                  duplicate settings set "Grass" to end of settings sets with properties {name:"Violet"}
                  set background color of settings set "Violet" to {\(background.red), \(background.green), \(background.blue)}
                  set normal text color of settings set "Violet" to {\(text.red), \(text.green), \(text.blue)}
                  set bold text color of settings set "Violet" to {\(text.red), \(text.green), \(text.blue)}
                  set cursor color of settings set "Violet" to {\(text.red), \(text.green), \(text.blue)}
                end try
              end if
            end if
            try
              set current settings of selected tab of window id wid to settings set profileName
            end try
            if (count of argv) > 2 then
              set keptWindow to window id wid
              try
                set font size of current settings of selected tab of keptWindow to \(TerminalBehavior.terminalFontSize)
              end try
              set leftEdge to item 3 of argv as integer
              set topEdge to item 4 of argv as integer
              set rightEdge to item 5 of argv as integer
              set bottomEdge to item 6 of argv as integer
              set bounds of keptWindow to {leftEdge, topEdge, rightEdge, bottomEdge}
            end if
          end tell
          return "yes"
        end run
        """
        _ = OSAScript.run(script, args: args)
    }

    nonisolated static func focus(_ windowID: Int) -> Bool {
        let script = """
        on run argv
          set wid to item 1 of argv as integer
          if application "Terminal" is not running then return "no"
          tell application "Terminal"
            if not (exists window id wid) then return "no"
            set miniaturized of window id wid to false
            set index of window id wid to 1
            activate
          end tell
          return "yes"
        end run
        """
        let raised = OSAScript.run(script, args: [String(windowID)]) == "yes"
        if raised {
            DispatchQueue.main.async {
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal")
                    .first?
                    .activate(options: [.activateIgnoringOtherApps])
            }
        }
        return raised
    }

    nonisolated private static func openNew(folder: String, bounds: TerminalBehavior.TerminalBounds, profile: String = "", tool: String = "grok", model: String = "") -> Outcome {
        let executable = TerminalBehavior.launchTool(tool)
        let missingNote = TerminalBehavior.missingLine(for: executable)
        let modelID = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let script = """
        on run argv
          set folderPath to item 1 of argv
          set leftEdge to item 2 of argv as integer
          set topEdge to item 3 of argv as integer
          set rightEdge to item 4 of argv as integer
          set bottomEdge to item 5 of argv as integer
          set profileName to item 6 of argv
          set toolName to item 7 of argv
          set missingLine to item 8 of argv
          set modelID to item 9 of argv
          set shellLine to toolName
          if modelID is not "" then set shellLine to toolName & " --model " & quoted form of modelID
          set cmd to "export PATH=\\"$HOME/.grok/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\\"; cd " & quoted form of folderPath & " && if command -v " & toolName & " >/dev/null 2>&1; then exec " & shellLine & "; else echo " & quoted form of missingLine & "; fi"
          tell application "Terminal"
            \(rememberWindowFrames)
            activate
            set theTab to do script cmd
            set theTTY to tty of theTab
            set font size of current settings of theTab to \(TerminalBehavior.terminalFontSize)
            set theWindow to missing value
            repeat with i from 1 to (count of windows)
              try
                if tty of selected tab of window i is theTTY then set theWindow to window i
              end try
            end repeat
            if theWindow is missing value then return "no-window"
            set index of theWindow to 1
            \(moveTabToOwnWindow)
            set theWindow to missing value
            repeat with i from 1 to (count of windows)
              try
                if tty of selected tab of window i is theTTY then set theWindow to window i
              end try
            end repeat
            if theWindow is missing value then return "no-window"
            set bounds of theWindow to {leftEdge, topEdge, rightEdge, bottomEdge}
            \(Self.profileCommands(for: "theWindow"))
            try
              set font size of current settings of selected tab of theWindow to \(TerminalBehavior.terminalFontSize)
            end try
            set bounds of theWindow to {leftEdge, topEdge, rightEdge, bottomEdge}
            try
              set wid to id of theWindow
            on error
              return "no-window"
            end try
            if wid is missing value then return "no-window"
            set keptIDs to {wid}
            \(restoreOtherWindowFrames)
            set wname to name of theWindow
            delay 0.3
            set blob to ""
            try
              set blob to contents of theTab
            end try
          end tell
          set status to "ok"
          if blob contains "CLI not found" then set status to "missing-grok"
          return (wid as text) & character id 31 & status & character id 31 & wname
        end run
        """
        let reply = OSAScript.run(script, args: [
            folder,
            String(bounds.left),
            String(bounds.top),
            String(bounds.right),
            String(bounds.bottom),
            profile,
            executable,
            missingNote,
            modelID,
        ]) ?? ""
        let bits = reply.components(separatedBy: "\u{1f}")
        guard let id = Int(bits.first ?? "") else {
            return Outcome(ok: false, windowID: nil, grokMissing: false, accessibility: false, windowTitle: nil)
        }
        let missing = bits.dropFirst().first == "missing-grok"
        let title = bits.count > 2 ? bits[2] : nil
        return Outcome(ok: true, windowID: id, grokMissing: missing, accessibility: false, windowTitle: title)
    }
}

enum CotypistLink {
    nonisolated static func wake() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: 50, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 50, keyDown: false)
        down?.flags = .maskControl
        up?.flags = .maskControl
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    nonisolated static func suggestion(after prefix: String) -> String {
        guard !prefix.isEmpty, AXIsProcessTrusted() else { return "" }
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "app.cotypist.Cotypist" }) else {
            return ""
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var found = ""
        walk(element, depth: 0, prefix: prefix, found: &found)
        return found
    }

    nonisolated private static func walk(_ element: AXUIElement, depth: Int, prefix: String, found: inout String) {
        if depth > 5 || !found.isEmpty { return }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        let list = children as? [AXUIElement] ?? []
        for child in list.prefix(40) {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &value)
            if let text = value as? String {
                let cleaned = text.replacingOccurrences(of: "\n", with: " ")
                if cleaned.hasPrefix(prefix), cleaned.count > prefix.count, cleaned.count < 240 {
                    let suffix = String(cleaned.dropFirst(prefix.count))
                    if !suffix.lowercased().contains("password") {
                        found = suffix
                        return
                    }
                }
            }
            walk(child, depth: depth + 1, prefix: prefix, found: &found)
            if !found.isEmpty { return }
        }
    }
}

enum OSAScript {
    nonisolated static func run(_ script: String, args: [String]) -> String? {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("coucou-\(UUID().uuidString).scpt")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [url.path] + args
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
