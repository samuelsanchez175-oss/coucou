import AppKit
import CoreAudio
import Darwin
import EventKit
import Foundation
import IOBluetooth
import IOKit
import IOKit.ps
import os

struct NookTodo: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var done: Bool
}

/// Live facts for the notch: now playing, calendar, battery, Bluetooth, and the file tray.
@MainActor
final class NookBoard: ObservableObject {
    static let shared = NookBoard()

    @Published var mediaTitle: String?
    @Published var mediaArtist: String?
    @Published var playingSource: String?
    /// True only while audio or video is moving. A pause keeps the player, with Play.
    @Published var mediaIsPlaying = false
    /// The app is sending audio even when Now Playing leaves the rate at zero.
    @Published var mediaOutputRunning = false
    /// Right wing of the closed notch while a video's waveform is showing. The left matches it.
    @Published var mediaWing: CGFloat = 0
    /// music, spotify, or youtube when the session belongs to that app.
    @Published var mediaPlatform: String?
    @Published var mediaBundleID = ""
    @Published var mediaDisplayName = ""
    @Published var artworkPath: String?
    @Published var artworkToken = 0
    @Published var mediaPosition: Double = 0
    @Published var mediaDuration: Double = 0
    /// Last title that actually played. Stays after the session clears so Play can resume it.
    @Published var lastTrack: NookLayout.NookLastTrack?
    @Published var events: [NookEventFact] = []
    /// True when an event is inside 15 minutes, or a timer the user started has reached zero.
    @Published var lampMarked = false
    /// Day to show when the Nook opens for that event. Nil when the lamp is only a timer.
    @Published var lampEventDay: Date?
    @Published var soonEvent: NookEventFact?
    @Published var lampHint = "Opens the Nook."
    @Published var calendarDenied = false
    @Published var batteryPercent: Int?
    @Published var batteryCharging = false
    @Published var batteryWatts: Double?
    /// Charger wattage while the adapter is connected. Nil on battery power.
    @Published var supplyWatts: Double?
    @Published var bluetoothName: String?
    @Published var tray: [NookLayout.TrayItem] = []
    @Published var showsTray = false
    @Published var dropWing = false
    @Published var dropHighlight = false
    /// The pointer is over the AirDrop tile, from the computer or from a tray file.
    @Published var airDropHighlight = false
    /// Island-local frame of the AirDrop tile. Empty until the tray page has laid out.
    @Published var airDropTileFrame: CGRect = .zero
    @Published var airDropNote: String?
    /// Key, tempo, Camelot, and energy from the plus button. Nil for other tray notes.
    @Published var songFacts: SongReadout?
    @Published var songFactsName = ""
    @Published var headline: NookHeadline?
    @Published var restingExtra: CGFloat = 0
    /// Left-wing width for the tray count. Zero while that line is hidden.
    @Published var trayWing: CGFloat = 0
    @Published var noteText = ""
    /// Rich text for the same note. Empty after a code edit changes the words.
    @Published var noteRTF = Data()
    /// Rich text is the default. Code colors headings, emphasis, inline code, and comments.
    @Published var noteMode: NookNoteMode = .rich
    @Published var todos: [NookTodo] = []
    @Published var timerMinutes = 5
    @Published var timerRemaining: TimeInterval?
    @Published var timerEnded = false
    @Published var shortcutCatalog: [NookShortcut] = []
    /// Running, a failed run, or a failed load. Empty when there is nothing to say.
    @Published var shortcutNote = ""
    @Published var quickAppCatalog: [NookQuickApp] = []
    /// A failed load or a failed open. Empty when there is nothing to say.
    @Published var quickAppNote = ""
    /// Bundle id of the Quick App opened last. Empty until one opens.
    @Published var lastQuickAppID = ""
    @Published var nookVisible = false {
        didSet {
            if !nookVisible { quickAppsLoaded = false }
        }
    }
    /// True while the pointer is inside the notch shape. Drives the media peek.
    @Published var pointerOnNotch = false

    private let defaults = UserDefaults.standard
    private var loop: Task<Void, Never>?
    /// Charge-rate samples. Separate from the notch tick so a slow calendar
    /// or media refresh cannot leave the wattage stale for more than 10 seconds.
    private var batteryLoop: Task<Void, Never>?
    private var tickCount = 0
    private var askedCalendar = false
    private var shortcutsLoaded = false
    private var quickAppsLoaded = false
    private var shortcutRun: Task<Void, Never>?
    private var pointerInside = false
    private var revealed = true
    private var lastInteraction = Date()
    private var lastCandidateKey = ""
    private var lastBluetoothKey: String?
    private var bluetoothIsNews = false
    private var timerEnd: Date?
    private var artworkStamp = 0
    private var mediaUsesRemote = false
    private var updateAvailable = false
    /// Last release that answered. A failed check leaves this as it was.
    @Published private(set) var offeredVersion: String?
    @Published private(set) var releasePage: String?
    @Published private(set) var updateChecking = false
    @Published private(set) var updateChecked = false
    /// True while Coucou.zip is downloading.
    @Published private(set) var updateDownloading = false
    /// The prompt after a check. Update is offered only when a zip is saved.
    @Published var updatePrompt: UpdatePromptState?
    private var updateGeneration = 0
    private var updateTask: Task<Void, Never>?
    private var persistReady = false
    private var lastAirDropPaths: [String] = []
    private var lastAirDropAt = Date.distantPast
    private var trayNoticeTask: Task<Void, Never>?
    /// The open note field. Formatting buttons use it while the menu has focus.
    weak var noteView: NookNoteNSTextView?
    private var savedSelection = NSRange(location: 0, length: 0)
    private var droppedDoneTodos = false

    private init() {
        loadPersisted()
        persistReady = true
        if droppedDoneTodos { saveTodos() }
    }

    func start() {
        guard loop == nil else { return }
        checkForUpdate()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            NowPlayingBridge.stop()
        }
        NotificationCenter.default.addObserver(
            forName: .nookChromeChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        }
        startBatteryClock()
        loop = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func notePointer(_ inside: Bool) {
        if pointerOnNotch != inside { pointerOnNotch = inside }
        if inside == pointerInside {
            if inside { lastInteraction = Date() }
            return
        }
        pointerInside = inside
        if inside {
            lastInteraction = Date()
            if NookPreferences.shared.quickPeek { revealed = true }
        }
        publish()
    }

    func receiveDrop(_ urls: [URL], landing: NookFileLanding = .pipeline) {
        let incoming = urls.map(\.path)
        let route = NookStemPipeline.route(
            paths: incoming,
            enabled: NookPreferences.shared.splitSongsIntoStems,
            logicInstalled: LogicStemSplitter.installed(),
            appleSilicon: LogicStemSplitter.appleSilicon()
        )
        let plan = NookLayout.dropPlan(landing: landing, route: route)
        let held = tray.map(\.path)
        let fresh = NookLayout.pathsToCopy(incoming: incoming, held: held)
        func park() -> [URL] {
            let already = urls.filter { held.contains($0.path) }
            let made = fresh.map { copyIntoTray(URL(fileURLWithPath: $0)) }
            return already + made
        }
        var stored: [URL] = []
        if plan.store {
            stored = park()
            tray = NookLayout.addToTray(tray, paths: stored.map(\.path))
            saveTray()
        }
        showsTray = true
        dropWing = false
        dropHighlight = false
        airDropHighlight = false

        if plan.airDropOriginals {
            if !airDrop(urls) {
                let parked = park()
                tray = NookLayout.addToTray(tray, paths: parked.map(\.path))
                saveTray()
            }
        }

        let storedPaths = stored.map(\.path)
        let songs = NookStemPipeline.songPaths(plan.store ? storedPaths : incoming)
        let others = NookStemPipeline.otherPaths(plan.store ? storedPaths : incoming).map { URL(fileURLWithPath: $0) }
        if plan.airDropStored {
            airDrop(stored)
        }
        if plan.airDropCompanions, !others.isEmpty {
            airDrop(others)
        }
        if plan.splitStems, let songPath = songs.first {
            let name = NookStemPipeline.songName(songPath)
            var note = NookStemPipeline.note(route: .stems, songName: name)
            if songs.count > 1 {
                note = "Splitting \(name) into stems in Logic Pro. Drop the other songs one at a time."
            }
            showTrayNote(note)
            Task.detached {
                let result = LogicStemSplitter.split(path: songPath)
                await NookBoard.shared.finishStemSplit(songName: name, result: result)
            }
        } else if !plan.airDropOriginals, route == .needsLogic || route == .needsAppleSilicon {
            let name = songs.isEmpty ? "The song" : NookStemPipeline.songName(songs[0])
            showTrayNote(NookStemPipeline.note(route: route, songName: name))
        }
        revealed = true
        lastInteraction = Date()
        publish()
    }

    func finishStemSplit(songName: String, result: String) {
        showTrayNote(NookStemPipeline.finishedNote(songName: songName, result: result))
        publish()
    }

    func removeFromTray(_ item: NookLayout.TrayItem) {
        tray.removeAll { $0.path == item.path }
        saveTray()
        publish()
    }

    /// The blue plus. Stem splitting and song info run for this one file.
    /// A file that is not a song only explains why.
    func runTrayPipeline(_ pipeline: NookTrayPipeline?, on item: NookLayout.TrayItem) {
        let plan = NookTrayChip.plan(
            pipeline: pipeline,
            path: item.path,
            logicInstalled: LogicStemSplitter.installed(),
            appleSilicon: LogicStemSplitter.appleSilicon()
        )
        showTrayNote(plan.note)
        revealed = true
        lastInteraction = Date()
        publish()
        if let path = plan.splitPath {
            let name = NookTrayChip.spokenName(path: path)
            Task.detached {
                let result = LogicStemSplitter.split(path: path)
                await NookBoard.shared.finishStemSplit(songName: name, result: result)
            }
        }
        if plan.readSongInfo {
            let path = item.path
            let name = NookTrayChip.displayName(path: path)
            Task.detached {
                let readout = SongFacts.read(url: URL(fileURLWithPath: path))
                await NookBoard.shared.finishSongInfo(name: name, readout: readout)
            }
        }
    }

    func finishSongInfo(name: String, readout: SongReadout?) {
        if let readout {
            showTrayNote(NookTrayChip.songInfoNote(name: name, readout: readout), facts: readout, name: name)
        } else {
            showTrayNote(NookTrayChip.songInfoFailedNote(name: name))
        }
        publish()
    }

    private func showTrayNote(_ text: String?, facts: SongReadout? = nil, name: String = "") {
        airDropNote = text
        songFacts = facts
        songFactsName = name
    }

    @discardableResult
    func airDrop(_ urls: [URL]) -> Bool {
        let paths = urls.map(\.path)
        let now = Date()
        guard NookLayout.shouldSendAirDrop(
            paths: paths,
            previous: lastAirDropPaths,
            elapsed: now.timeIntervalSince(lastAirDropAt)
        ) else { return true }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            showTrayNote("AirDrop isn't available. The file is still in the tray.")
            return false
        }
        lastAirDropPaths = paths
        lastAirDropAt = now
        showTrayNote(nil)
        service.perform(withItems: urls)
        return true
    }

    func togglePlayback() {
        let remote = mediaUsesRemote
        let source = playingSource
        guard remote || source != nil else { return }
        mediaIsPlaying.toggle()
        Task.detached {
            if remote {
                SystemNowPlaying.toggle()
            } else if let source {
                NowPlayingProbe.pause(source: source)
            }
        }
    }

    func pausePlaying() {
        guard mediaIsPlaying else { return }
        togglePlayback()
    }

    func skip(next: Bool) {
        let remote = mediaUsesRemote
        let source = playingSource
        guard remote || source != nil else { return }
        Task.detached {
            if remote {
                SystemNowPlaying.skip(next: next)
            } else if let source {
                NowPlayingProbe.skip(source: source, next: next)
            }
        }
    }

    func seek(to seconds: Double) {
        guard mediaDuration > 0 else { return }
        let remote = mediaUsesRemote
        let source = playingSource
        guard remote || source != nil else { return }
        let clamped = min(max(0, seconds), mediaDuration)
        mediaPosition = clamped
        Task.detached {
            if remote {
                SystemNowPlaying.seek(to: clamped)
            } else if let source {
                NowPlayingProbe.seek(source: source, seconds: clamped)
            }
        }
    }

    /// Open the app that is playing, or the browser tab that has the video.
    func showPlayingSource() {
        let target = NookPlayback.revealTarget(bundleID: mediaBundleID, displayName: mediaDisplayName)
        switch target {
        case .browser(let application):
            BrowserPictureInPicture.showPlaying(application: application)
        case .application(let bundleID):
            if bundleID == "com.spotify.client",
               NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
                return
            }
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                running.activate(options: [.activateIgnoringOtherApps])
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
        case nil:
            break
        }
    }

    func resumeLast() {
        guard let lastTrack, let action = NookLayout.resume(lastTrack) else { return }
        switch action {
        case .remote:
            Task.detached { SystemNowPlaying.toggle() }
        case .player(let source, let bundleID):
            if bundleID.isEmpty || !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
                Task.detached { NowPlayingProbe.pause(source: source) }
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.open(url)
            } else {
                Task.detached { NowPlayingProbe.pause(source: source) }
            }
        case .open(let bundleID):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Ask macOS for Calendar access. Coucou comes forward first, because a menu-bar app never gets the prompt.
    func askForCalendar() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        let access: CalendarAccess = status == .fullAccess ? .full : (status == .notDetermined ? .notDetermined : .denied)
        let ask = CalendarBehavior.ask(for: access)
        guard ask == .prompt else {
            await refreshCalendar()
            return true
        }
        if CalendarBehavior.clearsPreviousAnswer(access) {
            let bundleID = Bundle.main.bundleIdentifier ?? "fr.louisraille.NotchBuddy"
            let reset = Process()
            reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            reset.arguments = ["reset", "Calendar", bundleID]
            reset.standardOutput = Pipe()
            reset.standardError = Pipe()
            try? reset.run()
            reset.waitUntilExit()
        }
        let activation = CalendarBehavior.activation(for: ask)
        if activation == .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        let delay = MirrorBehavior.askDelay(for: activation)
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        let granted = (try? await EKEventStore().requestFullAccessToEvents()) ?? false
        let follow = CalendarBehavior.afterAsk(granted: granted)
        NSApp.setActivationPolicy(.accessory)
        switch follow {
        case .showEvents:
            calendarDenied = false
            await refreshCalendar()
            return true
        case .openSettings:
            calendarDenied = true
            NSWorkspace.shared.open(CalendarBehavior.settingsURL)
            return false
        case .prompt:
            calendarDenied = true
            return false
        }
    }

    func openCalendarEvent(_ event: NookEventFact) {
        guard let url = NookLayout.calendarShowURL(start: event.start) else { return }
        NSWorkspace.shared.open(url)
    }

    func openApp(_ name: String) {
        let platform: NookMediaPlatform
        switch name {
        case "Music": platform = .music
        case "Spotify": platform = .spotify
        default: platform = .youtube
        }
        if let url = NookMediaApps.launchURL(for: platform) {
            NSWorkspace.shared.open(url)
        } else if let web = platform.webURL {
            NSWorkspace.shared.open(web)
        }
    }

    func startTimer() {
        let minutes = min(180, max(1, timerMinutes))
        timerEnd = Date().addingTimeInterval(Double(minutes) * 60)
        timerRemaining = Double(minutes) * 60
        timerEnded = false
        revealed = true
        lastInteraction = Date()
        publish()
    }

    func dismissTimer() {
        timerEnd = nil
        timerRemaining = nil
        timerEnded = false
        publish()
    }

    func addTodo(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.insert(NookTodo(id: UUID(), title: trimmed, done: false), at: 0)
        saveTodos()
    }

    func finishTodo(_ id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }), !todos[index].done else { return }
        todos[index].done = true
        saveTodos()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            todos.removeAll { $0.id == id && $0.done }
            saveTodos()
        }
    }

    func setNoteMode(_ mode: NookNoteMode) {
        guard mode != noteMode else { return }
        if let view = noteView, noteMode == .rich {
            noteText = view.string
            let length = (view.string as NSString).length
            if let data = view.rtf(from: NSRange(location: 0, length: length)) {
                noteRTF = data
            }
        }
        noteMode = mode
        if let view = noteView {
            view.renderedMode = nil
            renderNote(in: view)
        }
        saveNote()
    }

    func toggleNoteBold() { toggleNoteTrait(.boldFontMask) }
    func toggleNoteItalic() { toggleNoteTrait(.italicFontMask) }

    func toggleNoteUnderline() {
        guard noteMode == .rich, let view = noteView, let storage = view.textStorage else { return }
        let range = activeNoteRange(in: view)
        guard range.length > 0 else { return }
        var fullyUnderlined = true
        storage.enumerateAttribute(.underlineStyle, in: range) { value, _, _ in
            let style = (value as? Int) ?? (value as? NSNumber)?.intValue ?? 0
            if style == 0 { fullyUnderlined = false }
        }
        let next = fullyUnderlined ? 0 : NSUnderlineStyle.single.rawValue
        storage.beginEditing()
        storage.addAttribute(.underlineStyle, value: next, range: range)
        storage.endEditing()
        noteEdited(in: view)
    }

    func noteSelectionChanged(in view: NSTextView) {
        savedSelection = view.selectedRange()
    }

    func noteEdited(in view: NookNoteNSTextView) {
        guard !view.suppressChange else { return }
        let plain = view.string
        if noteMode == .code {
            if !noteRTF.isEmpty {
                let stored = NSAttributedString(rtf: noteRTF, documentAttributes: nil)?.string
                if stored != plain { noteRTF = Data() }
            }
            noteText = plain
            let selected = view.selectedRange()
            view.suppressChange = true
            paintCode(in: view, selection: selected)
            view.suppressChange = false
        } else {
            noteText = plain
            let length = (plain as NSString).length
            noteRTF = view.rtf(from: NSRange(location: 0, length: length)) ?? Data()
        }
        view.renderedMode = noteMode
        view.renderedRTF = noteRTF
        saveNote()
    }

    /// Shows the saved note. Skips a field the person is typing in when the words already match.
    func renderNote(in view: NookNoteNSTextView) {
        noteView = view
        let editing = view.window?.firstResponder === view
        if view.renderedMode == noteMode && view.string == noteText {
            if editing || view.renderedRTF == noteRTF { return }
        }
        let selected = view.selectedRange()
        view.suppressChange = true
        if noteMode == .code {
            paintCode(in: view, selection: selected)
        } else {
            paintRich(in: view, selection: selected)
        }
        view.renderedMode = noteMode
        view.renderedRTF = noteRTF
        view.suppressChange = false
    }

    func exportNote(_ format: NookNoteExport) {
        if let view = noteView {
            noteText = view.string
            if noteMode == .rich {
                let length = (view.string as NSString).length
                if let data = view.rtf(from: NSRange(location: 0, length: length)) {
                    noteRTF = data
                }
            }
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Coucou/notes", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(NookNotes.exportFilename(format))
            switch format {
            case .plain, .markdown:
                let body = NookNotes.exportText(mode: noteMode, plain: noteText, format: format) ?? ""
                try body.write(to: url, atomically: true, encoding: .utf8)
            case .richText:
                try exportRTF().write(to: url, options: .atomic)
            }
            saveNote()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            return
        }
    }

    func saveNote() {
        guard persistReady else { return }
        defaults.set(noteText, forKey: "nook.noteText")
        defaults.set(noteRTF, forKey: "nook.noteRTF")
        defaults.set(noteMode.rawValue, forKey: "nook.noteMode")
    }

    private func toggleNoteTrait(_ trait: NSFontTraitMask) {
        guard noteMode == .rich, let view = noteView, let storage = view.textStorage else { return }
        let range = activeNoteRange(in: view)
        guard range.length > 0 else { return }
        let manager = NSFontManager.shared
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let current = (value as? NSFont) ?? NSFont.systemFont(ofSize: 13, weight: .medium)
            let hasTrait = manager.traits(of: current).contains(trait)
            let next = hasTrait
                ? manager.convert(current, toNotHaveTrait: trait)
                : manager.convert(current, toHaveTrait: trait)
            storage.addAttribute(.font, value: next, range: subrange)
        }
        storage.endEditing()
        noteEdited(in: view)
    }

    private func activeNoteRange(in view: NSTextView) -> NSRange {
        let live = view.selectedRange()
        if live.length > 0 { return live }
        let length = (view.string as NSString).length
        guard savedSelection.location <= length else { return NSRange(location: length, length: 0) }
        let available = length - savedSelection.location
        return NSRange(location: savedSelection.location, length: min(savedSelection.length, available))
    }

    private func paintCode(in view: NookNoteNSTextView, selection: NSRange) {
        if view.string != noteText { view.string = noteText }
        guard let storage = view.textStorage else { return }
        let base = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let baseColor = NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
        storage.beginEditing()
        let full = NSRange(location: 0, length: storage.length)
        if full.length > 0 {
            storage.setAttributes([.font: base, .foregroundColor: baseColor], range: full)
        }
        let order: [NookNoteSpan.Kind] = [.heading, .emphasis, .comment, .code]
        let spans = NookNotes.highlight(view.string)
        for kind in order {
            for span in spans where span.kind == kind {
                guard span.end > span.start else { continue }
                let range = NSRange(location: span.start, length: span.end - span.start)
                guard NSMaxRange(range) <= storage.length else { continue }
                storage.addAttributes(codeAttributes(kind), range: range)
            }
        }
        storage.endEditing()
        view.typingAttributes = [.font: base, .foregroundColor: baseColor]
        view.setSelectedRange(clampedNoteRange(selection, length: storage.length))
    }

    private func paintRich(in view: NookNoteNSTextView, selection: NSRange) {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let color = NSColor(srgbRed: 0.96, green: 0.965, blue: 0.973, alpha: 1)
        if !noteRTF.isEmpty,
           let stored = NSAttributedString(rtf: noteRTF, documentAttributes: nil),
           stored.string == noteText {
            view.textStorage?.setAttributedString(stored)
        } else {
            let plain = NSAttributedString(string: noteText, attributes: [
                .font: font,
                .foregroundColor: color
            ])
            view.textStorage?.setAttributedString(plain)
        }
        view.typingAttributes = [.font: font, .foregroundColor: color]
        let length = view.textStorage?.length ?? (view.string as NSString).length
        view.setSelectedRange(clampedNoteRange(selection, length: length))
    }

    private func codeAttributes(_ kind: NookNoteSpan.Kind) -> [NSAttributedString.Key: Any] {
        let size: CGFloat = 12
        switch kind {
        case .heading:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold),
                .foregroundColor: NSColor(srgbRed: 0.98, green: 0.78, blue: 0.42, alpha: 1)
            ]
        case .emphasis:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: size, weight: .bold),
                .foregroundColor: NSColor(srgbRed: 0.80, green: 0.72, blue: 0.98, alpha: 1)
            ]
        case .code:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium),
                .foregroundColor: NSColor(srgbRed: 0.45, green: 0.88, blue: 0.74, alpha: 1)
            ]
        case .comment:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: size, weight: .regular),
                .foregroundColor: NSColor(srgbRed: 0.67, green: 0.72, blue: 0.78, alpha: 1)
            ]
        }
    }

    private func clampedNoteRange(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        let span = min(max(0, range.length), length - location)
        return NSRange(location: location, length: span)
    }

    /// Rich text for TextEdit: keep bold, italic, and underline, and drop the light notch color.
    private func exportRTF() -> Data {
        let source: NSAttributedString
        if noteMode == .rich, let view = noteView {
            source = view.attributedString()
        } else if !noteRTF.isEmpty,
                  let stored = NSAttributedString(rtf: noteRTF, documentAttributes: nil),
                  stored.string == noteText {
            source = stored
        } else {
            source = NSAttributedString(string: noteText, attributes: [
                .font: NSFont.systemFont(ofSize: 13)
            ])
        }
        let copy = NSMutableAttributedString(attributedString: source)
        let full = NSRange(location: 0, length: copy.length)
        if full.length > 0 {
            copy.removeAttribute(.foregroundColor, range: full)
            if copy.attribute(.font, at: 0, effectiveRange: nil) == nil {
                copy.addAttribute(.font, value: NSFont.systemFont(ofSize: 13), range: full)
            }
        }
        return copy.rtf(from: full) ?? Data(noteText.utf8)
    }

    func loadShortcutsIfNeeded() async {
        guard nookVisible else {
            shortcutsLoaded = false
            return
        }
        guard !shortcutsLoaded else { return }
        let enabled = NookPreferences.shared.widgets.contains { $0.id == "shortcuts" && $0.enabled }
        guard enabled else { return }
        shortcutsLoaded = true
        await refreshShortcutCatalog()
    }

    func refreshShortcutCatalog() async {
        let load = await Task.detached { ShortcutProbe.catalog() }.value
        shortcutCatalog = load.shortcuts
        if load.failed {
            shortcutNote = NookShortcuts.loadFailed
            return
        }
        if shortcutNote == NookShortcuts.loadFailed { shortcutNote = "" }
        let prefs = NookPreferences.shared
        let kept = NookShortcuts.keptPicks(prefs.shortcutPicks, catalog: load.shortcuts)
        if kept != prefs.shortcutPicks { prefs.setShortcutPicks(kept) }
    }

    func runShortcut(_ shortcut: NookShortcut) {
        shortcutRun?.cancel()
        shortcutNote = NookShortcuts.runningNote(shortcut.name)
        let identifier = shortcut.identifier
        let name = shortcut.name
        shortcutRun = Task {
            let code = await Task.detached { ShortcutProbe.run(identifier) }.value
            guard !Task.isCancelled else { return }
            shortcutNote = NookShortcuts.finishedNote(name: name, exitCode: code)
        }
    }

    /// One scan each time the nook opens with Quick Apps on. Refresh and the picker scan on their own.
    func loadQuickAppsIfNeeded() async {
        guard nookVisible else {
            quickAppsLoaded = false
            return
        }
        guard !quickAppsLoaded else { return }
        let enabled = NookPreferences.shared.widgets.contains { $0.id == "quickApps" && $0.enabled }
        guard enabled else { return }
        quickAppsLoaded = true
        await refreshQuickAppCatalog()
    }

    func refreshQuickAppCatalog() async {
        let load = await Task.detached { QuickAppProbe.catalog() }.value
        quickAppCatalog = load.apps
        if load.failed {
            quickAppNote = NookQuickApps.loadFailed
            return
        }
        if quickAppNote == NookQuickApps.loadFailed { quickAppNote = "" }
        let prefs = NookPreferences.shared
        let kept = NookQuickApps.keptPicks(prefs.quickAppPicks, catalog: load.apps)
        if kept != prefs.quickAppPicks { prefs.setQuickAppPicks(kept) }
    }

    func openQuickApp(_ app: NookQuickApp) {
        let missed = "\(app.name) could not be opened."
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID),
              NSWorkspace.shared.open(url) else {
            quickAppNote = missed
            return
        }
        if quickAppNote == missed { quickAppNote = "" }
        guard lastQuickAppID != app.bundleID else { return }
        lastQuickAppID = app.bundleID
        defaults.set(app.bundleID, forKey: "nook.lastQuickApp")
    }

    /// Reads the pack power every 10 seconds. The two-second notch tick also
    /// reads it, so a quiet tick stays faster than this clock.
    private func startBatteryClock() {
        guard batteryLoop == nil else { return }
        batteryLoop = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.readBattery()
                self.publish()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    // MARK: - Tick

    private func tick() async {
        readBattery()
        advanceTimer()
        if tickCount % 4 == 0 { readBluetooth() }
        await refreshMedia()
        if tickCount % 15 == 0 || (nookVisible && events.isEmpty && !askedCalendar) {
            await refreshCalendar()
        }
        if nookVisible {
            await loadShortcutsIfNeeded()
            await loadQuickAppsIfNeeded()
        }
        tickCount += 1
        publish()
    }

    private func refreshMedia() async {
        let prefs = NookPreferences.shared
        let mediaOn = prefs.widgets.contains { $0.id == "media" && $0.enabled }
            || prefs.activities.contains { $0.id == "media" && $0.enabled }
        guard mediaOn else {
            clearMedia()
            return
        }
        let source = prefs.mediaSource
        let snap = await Task.detached(priority: .utility) { NowPlayingProbe.read(source: source) }.value
        if let snap {
            let outputting = AudioOutputProbe.bundleIsOutputting(snap.bundleID)
            let artChanged = snap.artworkStamp != artworkStamp || snap.artworkPath != artworkPath
            artworkStamp = snap.artworkStamp
            mediaTitle = snap.title
            mediaArtist = snap.artist
            playingSource = snap.source
            mediaIsPlaying = snap.playing
            mediaOutputRunning = outputting
            mediaUsesRemote = snap.usesRemote
            mediaPlatform = NookPlayback.platform(bundleID: snap.bundleID, displayName: snap.displayName)?.rawValue
            mediaBundleID = snap.bundleID
            mediaDisplayName = snap.displayName
            artworkPath = snap.artworkPath
            mediaPosition = snap.position
            mediaDuration = snap.duration
            if artChanged { artworkToken += 1 }
            rememberTrack(
                title: snap.title,
                artist: snap.artist,
                source: snap.source,
                usesRemote: snap.usesRemote,
                bundleID: snap.bundleID
            )
        } else {
            clearMedia()
        }
    }

    private func rememberTrack(title: String, artist: String, source: String, usesRemote: Bool, bundleID: String) {
        guard let track = NookLayout.rememberedTrack(
            title: title,
            artist: artist,
            source: source,
            usesRemote: usesRemote,
            bundleID: bundleID
        ) else { return }
        guard track != lastTrack else { return }
        lastTrack = track
        saveLastTrack()
    }

    private func clearMedia() {
        mediaTitle = nil
        mediaArtist = nil
        playingSource = nil
        mediaIsPlaying = false
        mediaOutputRunning = false
        mediaUsesRemote = false
        mediaPlatform = nil
        mediaBundleID = ""
        mediaDisplayName = ""
        mediaPosition = 0
        mediaDuration = 0
        artworkStamp = 0
        if artworkPath != nil {
            artworkPath = nil
            artworkToken += 1
        }
    }

    private func refreshCalendar() async {
        let prefs = NookPreferences.shared
        let wanted = prefs.widgets.contains { $0.id == "calendar" && $0.enabled }
            || prefs.activities.contains { $0.id == "calendar" && $0.enabled }
        guard wanted else {
            events = []
            return
        }
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess else {
            calendarDenied = true
            events = []
            askedCalendar = true
            return
        }
        calendarDenied = false
        askedCalendar = true
        let store = EKEventStore()
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let end = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .prefix(200)
            .map { event in
                let raw = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return NookEventFact(
                    calendarID: event.calendar?.calendarIdentifier ?? "",
                    title: raw.isEmpty ? "Untitled event" : raw,
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay
                )
            }
            .sorted { $0.start < $1.start }
    }

    private func readBattery() {
        guard let reading = BatteryProbe.read() else { return }
        if reading.percent != batteryPercent { batteryPercent = reading.percent }
        if reading.charging != batteryCharging { batteryCharging = reading.charging }
        if reading.watts != batteryWatts { batteryWatts = reading.watts }
        if reading.supply != supplyWatts { supplyWatts = reading.supply }
    }

    private func readBluetooth() {
        let names = BluetoothProbe.connectedNames().sorted()
        let key = names.joined(separator: "|")
        if lastBluetoothKey == nil {
            lastBluetoothKey = key
            bluetoothName = names.first
            return
        }
        if key != lastBluetoothKey {
            lastBluetoothKey = key
            bluetoothIsNews = true
            bluetoothName = names.first ?? "Bluetooth disconnected"
            revealed = true
            lastInteraction = Date()
        } else if bluetoothName == nil {
            bluetoothName = names.first
        }
    }

    private func advanceTimer() {
        guard let timerEnd else { return }
        let left = timerEnd.timeIntervalSinceNow
        if left <= 0 {
            self.timerEnd = nil
            timerRemaining = nil
            timerEnded = true
            revealed = true
            lastInteraction = Date()
        } else {
            timerRemaining = left
        }
    }

    /// One look at the published release. The notch tick only reads what this stored.
    func checkForUpdate() {
        updateGeneration += 1
        let generation = updateGeneration
        updateTask?.cancel()
        updateChecking = true
        updateTask = Task { @MainActor [weak self] in
            let offer = await ReleaseProbe.latest()
            guard let self, generation == self.updateGeneration else { return }
            if let offer {
                self.offeredVersion = offer.version
                self.releasePage = offer.page
            }
            self.updateChecking = false
            self.updateChecked = true
            self.updateTask = nil
            self.publish()
        }
    }

    func openReleasePage() {
        let page = releasePage ?? LiveActivityBehavior.releasesPage
        guard let url = URL(string: page), url.scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }

    /// Finds a newer GitHub release and downloads Coucou.zip. It does not replace Coucou.
    func lookForUpdate() {
        guard !updateChecking, !updateDownloading else { return }
        updateGeneration += 1
        let generation = updateGeneration
        updateTask?.cancel()
        updateChecking = true
        updateTask = Task { @MainActor [weak self] in
            let offer = await ReleaseProbe.latest()
            guard let self, generation == self.updateGeneration else { return }
            if let offer {
                self.offeredVersion = offer.version
                self.releasePage = offer.page
            }
            self.updateChecking = false
            self.updateChecked = true
            self.publish()
            let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            let saved = offer.flatMap { self.stagedZipURL(version: $0.version) }
            let savedFileExists = saved.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            switch LiveActivityBehavior.lookup(
                installed: installed, offer: offer, savedFileExists: savedFileExists
            ) {
            case .current:
                self.sayUpdate("This is the latest version.")
            case .missingZip(let version):
                self.sayUpdate("Version \(version) is available, and Coucou could not find the download.")
            case .ask(let version):
                guard let saved else { return }
                self.updateDownloading = true
                self.askToApply(version: version, zip: saved)
                self.updateDownloading = false
            case .download(let version, let url):
                guard let dest = self.stagedZipURL(version: version) else { return }
                self.updateDownloading = true
                let ok = await ReleaseProbe.downloadZip(from: url, to: dest)
                guard generation == self.updateGeneration else { return }
                guard ok else {
                    self.updateDownloading = false
                    self.sayUpdate("Coucou could not download the update.")
                    return
                }
                self.keepOnly(version: version)
                self.askToApply(version: version, zip: dest)
                self.updateDownloading = false
            }
            self.updateTask = nil
        }
    }

    /// The download is already on disk. Showing this prompt does not replace Coucou.
    private var pendingUpdateZip: URL?
    private var pendingUpdateVersion: String?

    private func askToApply(version: String, zip: URL) {
        pendingUpdateZip = zip
        pendingUpdateVersion = version
        updatePrompt = UpdatePromptState(
            title: "Version \(version) is downloaded.",
            detail: "This download is the original GitHub release. Your Coucou on this Mac is different. Update asks Grok to compare them and does not replace Coucou. Save for later keeps the download.",
            zipReady: true
        )
        NotificationCenter.default.post(name: .showUpdatePrompt, object: nil)
    }

    /// Update asks Grok to compare the download with the local tree. Save for later leaves the download on disk.
    func answerUpdatePrompt(_ choice: LiveActivityBehavior.UpdatePromptChoice) {
        let zip = pendingUpdateZip
        let version = pendingUpdateVersion
        updatePrompt = nil
        pendingUpdateZip = nil
        pendingUpdateVersion = nil
        updateDownloading = false
        guard LiveActivityBehavior.asksGrok(choice), let zip, let version else { return }
        guard LiveActivityBehavior.installsDownloadedApp(choice) == false else { return }
        reviewDownloadedUpdate(version: version, zip: zip)
    }

    func dismissUpdatePrompt() {
        updatePrompt = nil
        pendingUpdateZip = nil
        pendingUpdateVersion = nil
        updateDownloading = false
    }

    /// Opens Grok on the local tree. The downloaded zip is named in the brief and is not installed.
    private func reviewDownloadedUpdate(version: String, zip: URL) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let repo = LiveActivityBehavior.localTree(home: home)
        let grok = LiveActivityBehavior.grokExecutable(home: home)
        guard fm.fileExists(atPath: repo.appendingPathComponent(".git").path) else {
            sayUpdate("Coucou could not find the local version. The download was not installed.")
            return
        }
        guard fm.fileExists(atPath: grok.path) else {
            sayUpdate("Coucou could not find Grok. The download was not installed.")
            return
        }
        let brief = LiveActivityBehavior.reviewBrief(version: version, zipPath: zip.path)
        let note = zip.deletingLastPathComponent().appendingPathComponent("Coucou-\(version)-review.txt")
        try? brief.write(to: note, atomically: true, encoding: .utf8)
        let command = LiveActivityBehavior.reviewCommand(repo: repo.path, grok: grok.path, brief: brief)
        guard openGrokReview(command) else {
            sayUpdate("Coucou could not open Grok. The download was not installed.")
            return
        }
        sayUpdate("Grok is comparing version \(version) with your local Coucou. Coucou was not replaced.")
    }

    /// A new Terminal window. Other windows are left where they are.
    private func openGrokReview(_ command: String) -> Bool {
        let script = """
        on run argv
          set cmd to item 1 of argv
          tell application "Terminal"
            do script cmd
          end tell
          return "ok"
        end run
        """
        return OSAScript.run(script, args: [command]) == "ok"
    }

    private func stagedZipURL(version: String) -> URL? {
        guard !version.isEmpty, version.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent("Coucou", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
            .appendingPathComponent("Coucou-\(version).zip")
    }

    private func keepOnly(version: String) {
        guard let folder = stagedZipURL(version: version)?.deletingLastPathComponent(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        let keep = "Coucou-\(version).zip"
        for name in names where name.hasPrefix("Coucou-") && name.hasSuffix(".zip") && name != keep {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private func sayUpdate(_ message: String) {
        pendingUpdateZip = nil
        pendingUpdateVersion = nil
        updatePrompt = UpdatePromptState(title: message, detail: "", zipReady: false)
        NotificationCenter.default.post(name: .showUpdatePrompt, object: nil)
    }

    private func publish() {
        let prefs = NookPreferences.shared
        let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        updateAvailable = LiveActivityBehavior.updateIsAvailable(installed: installed, offered: offeredVersion)
        considerHide(prefs)
        let facts = NookActivityFacts(
            mediaTitle: NookLayout.publishedMediaTitle(isPlaying: mediaIsPlaying, title: mediaTitle),
            mediaArtist: mediaArtist,
            trayCount: tray.count,
            nextEventTitle: nextEventTitle(prefs),
            bluetoothName: bluetoothName,
            bluetoothIsNews: bluetoothIsNews,
            batteryPercent: batteryPercent,
            batteryCharging: batteryCharging,
            chargingWatts: batteryWatts,
            timerEnded: timerEnded,
            updateAvailable: updateAvailable
        )
        let enabled = enabledActivities(prefs)
        let candidate = NookLayout.headline(facts: facts, enabled: enabled, revealed: true)
        let key = candidate.map { "\($0.id):\($0.text)" } ?? ""
        if key != lastCandidateKey {
            let previous = lastCandidateKey
            lastCandidateKey = key
            if !key.isEmpty && (previous.isEmpty || prefs.unhideAutomatically || (candidate?.id == "media" && prefs.showSongChange)) {
                revealed = true
                lastInteraction = Date()
            }
        }
        let shown = activitiesShown(prefs) && revealed
        let line = NookLayout.headline(facts: facts, enabled: enabled, revealed: shown)
        if line != headline { headline = line }
        refreshLamp(prefs)
        let extra: CGFloat
        if dropWing {
            extra = NookLayout.wingWidth(slider: prefs.dropAreaWidth)
        } else if let line {
            extra = NookLayout.restingExtraWidth(text: line.text)
        } else {
            extra = 0
        }
        if extra != restingExtra { restingExtra = extra }
        let showShelf = NookPlayback.showsWaveOnClosedNotch(
            bundleID: mediaBundleID,
            displayName: mediaDisplayName,
            title: mediaTitle,
            playing: mediaIsPlaying,
            outputRunning: mediaOutputRunning
        )
        let wing = NookPlayback.mediaWingWidth(showing: showShelf)
        if wing != mediaWing { mediaWing = wing }
        let now = ProcessInfo.processInfo.systemUptime
        let trayShown = line?.id == "tray" && !dropWing && NookLayout.trayNoticeVisible(at: now)
        let traySide = NookLayout.traySideWidth(showing: trayShown)
        if traySide != trayWing { trayWing = traySide }
        scheduleTrayNotice(at: now)
    }

    /// Wakes when the tray count should show or hide. The two-second tick is too coarse.
    private func scheduleTrayNotice(at now: TimeInterval) {
        trayNoticeTask?.cancel()
        trayNoticeTask = nil
        guard headline?.id == "tray", !dropWing else { return }
        let wait = max(0, NookLayout.trayNoticeDelay(at: now))
        let nanos = UInt64((wait * 1_000_000_000).rounded())
        trayNoticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            self?.publish()
        }
    }

    /// The drop wing and the activity line read this width. Settings flips those
    /// flags without waiting for the two-second tick.
    func refreshChrome() {
        publish()
    }

    private func considerHide(_ prefs: NookPreferences) {
        let timeout = prefs.inactivityTimeout
        guard timeout > 0, !pointerInside else { return }
        guard Date().timeIntervalSince(lastInteraction) > timeout else { return }
        if revealed {
            if NookLayout.keepsTrayLineAwake(headlineID: headline?.id) { return }
            revealed = false
            bluetoothIsNews = false
        }
    }

    private func activitiesShown(_ prefs: NookPreferences) -> Bool {
        guard prefs.liveActivitiesEnabled else { return false }
        if prefs.hideActivitiesOnNoNotch && !AppState.shared.hasNotch { return false }
        return true
    }

    private func enabledActivities(_ prefs: NookPreferences) -> Set<String> {
        let fullscreen = frontIsFullscreen
        let hasNotch = AppState.shared.hasNotch
        return Set(prefs.activities.compactMap { item in
            NookLayout.activityAllowed(
                enabled: item.enabled,
                showInFullscreen: item.showInFullscreen,
                globalFullscreen: prefs.showInFullscreen,
                isFullscreen: fullscreen,
                hasNotch: hasNotch
            ) ? item.id : nil
        })
    }

    private var frontIsFullscreen: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.frame.maxY - screen.visibleFrame.maxY < 1
    }

    private func nextEventTitle(_ prefs: NookPreferences) -> String? {
        let now = Date()
        return events.first { event in
            NookLayout.includeEvent(
                event,
                now: now,
                allowedCalendarIDs: prefs.enabledCalendarIDs,
                showPast: prefs.showPastEvents,
                showAllDay: prefs.showAllDayEvents,
                showMultiDay: prefs.showMultiDayEvents,
                daysBehind: Int(prefs.daysBehind),
                daysAhead: Int(prefs.daysAhead)
            ) && event.end >= now
        }?.title
    }

    private func copyIntoTray(_ url: URL) -> URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Coucou/tray", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let dest = folder.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return url
        }
    }

    private func loadPersisted() {
        if let text = defaults.string(forKey: "nook.noteText") { noteText = text }
        if let data = defaults.data(forKey: "nook.noteRTF") { noteRTF = data }
        if defaults.string(forKey: "nook.noteMode") == NookNoteMode.code.rawValue {
            noteMode = .code
        }
        if let data = defaults.data(forKey: "nook.todos"),
           let saved = try? JSONDecoder().decode([NookTodo].self, from: data) {
            let open = saved.filter { !$0.done }
            todos = open
            droppedDoneTodos = open.count != saved.count
        }
        if let data = defaults.data(forKey: "nook.lastTrack"),
           let saved = try? JSONDecoder().decode(NookLayout.NookLastTrack.self, from: data) {
            lastTrack = saved
        }
        lastQuickAppID = defaults.string(forKey: "nook.lastQuickApp") ?? ""
        if let data = defaults.data(forKey: "nook.trayFiles"),
           let saved = try? JSONDecoder().decode([NookLayout.TrayItem].self, from: data) {
            tray = saved.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    private func saveTray() {
        guard persistReady else { return }
        if let data = try? JSONEncoder().encode(tray) {
            defaults.set(data, forKey: "nook.trayFiles")
        }
    }

    private func saveTodos() {
        guard persistReady else { return }
        if let data = try? JSONEncoder().encode(todos) {
            defaults.set(data, forKey: "nook.todos")
        }
    }

    private func saveLastTrack() {
        guard persistReady else { return }
        if let lastTrack, let data = try? JSONEncoder().encode(lastTrack) {
            defaults.set(data, forKey: "nook.lastTrack")
        }
    }

    private func refreshLamp(_ prefs: NookPreferences) {
        let now = Date()
        let visible = events.filter { event in
            NookLayout.includeEvent(
                event,
                now: now,
                allowedCalendarIDs: prefs.enabledCalendarIDs,
                showPast: prefs.showPastEvents,
                showAllDay: prefs.showAllDayEvents,
                showMultiDay: prefs.showMultiDayEvents,
                daysBehind: Int(prefs.daysBehind),
                daysAhead: Int(prefs.daysAhead)
            )
        }
        let soon = NookLayout.soonEvent(now: now, events: visible)
        let marked = NookLayout.lampMarked(timerEnded: timerEnded, soon: soon)
        if marked != lampMarked { lampMarked = marked }
        if soon != soonEvent { soonEvent = soon }
        let day = soon.map { Calendar.current.startOfDay(for: $0.start) }
        if day != lampEventDay { lampEventDay = day }
        let hint = NookLayout.lampHint(timerEnded: timerEnded, eventTitle: soon?.title)
        if hint != lampHint { lampHint = hint }
    }
}

// MARK: - Probes

/// True when this app, or one of its helpers, is sending audio to a device.
enum AudioOutputProbe {
    nonisolated static func bundleIsOutputting(_ bundleID: String) -> Bool {
        let wanted = bundleID.lowercased()
        guard !wanted.isEmpty else { return false }
        for object in processObjects() where isRunningOutput(object) {
            let id = bundleIdentifier(object).lowercased()
            if id == wanted || id.hasPrefix(wanted + ".") { return true }
        }
        return false
    }

    private nonisolated static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids
    }

    private nonisolated static func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }

    private nonisolated static func bundleIdentifier(_ object: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var raw: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &raw) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let raw else { return "" }
        return raw.takeRetainedValue() as String
    }
}

/// Seven levels, 0…1, from the sound coming out of the speakers.
/// The tap stays unmuted, so playback is not silenced.
final class PlaybackWave: @unchecked Sendable {
    static let shared = PlaybackWave()

    private let lock = OSAllocatedUnfairLock(initialState: [Float](repeating: 0, count: 7))
    private let queue = DispatchQueue(label: "coucou.playback-wave", qos: .userInteractive)
    private var hold = [Float](repeating: 0, count: 7)
    private var next = [Float](repeating: 0, count: 7)
    private var ceiling: Float = 0.05
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioDeviceID(0)
    private var ioProc: AudioDeviceIOProcID?
    private var running = false
    private var starting = false
    private var attempts = 0
    private var generation = 0

    var levels: [Float] { lock.withLock { $0 } }

    func start() {
        guard !running, !starting else { return }
        starting = true
        let token = generation
        if attempts == 0 {
            FileManager.default.createFile(atPath: Self.statusPath, contents: Data())
        }
        attempts += 1
        note("attempt \(attempts)")
        guard let outputUID = Self.defaultOutputUID(), !outputUID.isEmpty else {
            note("output missing")
            finishStart(ok: false, token: token)
            return
        }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [AudioObjectID]())
        description.name = "Coucou"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        let tapUID = description.uuid.uuidString
        var created = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &created)
        note("tap \(tapStatus) id \(created)")
        guard tapStatus == noErr, created != kAudioObjectUnknown else {
            finishStart(ok: false, token: token)
            return
        }
        tapID = created
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Coucou",
            kAudioAggregateDeviceUIDKey: "fr.louisraille.NotchBuddy.wave.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: 1
                ]
            ]
        ]
        var aggregateDevice = AudioDeviceID(0)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateDevice)
        note("aggregate \(aggregateStatus) id \(aggregateDevice)")
        guard aggregateStatus == noErr, aggregateDevice != 0 else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
            finishStart(ok: false, token: token)
            return
        }
        aggregateID = aggregateDevice
        noteFormat(aggregateDevice)
        var proc: AudioDeviceIOProcID?
        let made = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateDevice, queue) { [weak self] _, input, _, output, _ in
            self?.ingest(input, and: output)
        }
        note("ioproc \(made)")
        guard made == noErr, let proc else {
            stopHardware()
            finishStart(ok: false, token: token)
            return
        }
        ioProc = proc
        let started = AudioDeviceStart(aggregateDevice, proc)
        note("deviceStart \(started)")
        guard started == noErr else {
            stopHardware()
            finishStart(ok: false, token: token)
            return
        }
        running = true
        attempts = 0
        finishStart(ok: true, token: token)
    }

    /// A denied tap prompt returns before the shelf can try again.
    private func finishStart(ok: Bool, token: Int) {
        starting = false
        guard !ok, token == generation, attempts < 4 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.generation == token else { return }
            self.start()
        }
    }

    func stop() {
        generation += 1
        attempts = 0
        stopHardware()
        hold = [Float](repeating: 0, count: 7)
        ceiling = 0.05
        lock.withLock { $0 = [Float](repeating: 0, count: 7) }
    }

    private func stopHardware() {
        running = false
        if aggregateID != 0, let proc = ioProc {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        ioProc = nil
        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    /// The loudest buffer is the tap. A silent microphone stream does not flatten the bars.
    /// The tap can arrive on either side of the aggregate, so both sides are read.
    private func ingest(_ input: UnsafePointer<AudioBufferList>, and output: UnsafeMutablePointer<AudioBufferList>) {
        let first = loudest(input)
        let second = loudest(UnsafePointer(output))
        let chosen: (UnsafeMutablePointer<Float>, Int, Int)?
        switch (first, second) {
        case let (a?, b?) where b.peak > a.peak:
            chosen = (b.pointer, b.frames, b.channels)
        case let (a?, _):
            chosen = (a.pointer, a.frames, a.channels)
        case let (nil, b?):
            chosen = (b.pointer, b.frames, b.channels)
        default:
            chosen = nil
        }
        guard let chosen else { return }
        fold(chosen.0, frames: chosen.1, channels: chosen.2)
    }

    private struct Slice {
        var pointer: UnsafeMutablePointer<Float>
        var frames: Int
        var channels: Int
        var peak: Float
    }

    private func loudest(_ list: UnsafePointer<AudioBufferList>) -> Slice? {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        var best: Slice?
        for buffer in buffers {
            guard let raw = buffer.mData, buffer.mNumberChannels > 0 else { continue }
            let channels = Int(buffer.mNumberChannels)
            let floats = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let frames = floats / channels
            guard frames > 7 else { continue }
            let pointer = raw.assumingMemoryBound(to: Float.self)
            var peak: Float = 0
            let step = max(1, frames / 48)
            var frame = 0
            while frame < frames {
                let base = frame * channels
                var sample = abs(pointer[base])
                if channels > 1 { sample = max(sample, abs(pointer[base + 1])) }
                if sample > peak { peak = sample }
                frame += step
            }
            if peak >= (best?.peak ?? -1) {
                best = Slice(pointer: pointer, frames: frames, channels: channels, peak: peak)
            }
        }
        return best
    }

    private func fold(_ pointer: UnsafeMutablePointer<Float>, frames: Int, channels: Int) {
        let chunk = frames / 7
        guard chunk > 0 else { return }
        for bar in 0..<7 {
            let start = bar * chunk
            let end = bar == 6 ? frames : start + chunk
            var peak: Float = 0
            let step = max(1, (end - start) / 32)
            var frame = start
            while frame < end {
                let base = frame * channels
                var sample = abs(pointer[base])
                if channels > 1 { sample = max(sample, abs(pointer[base + 1])) }
                if sample > peak { peak = sample }
                frame += step
            }
            let previous = hold[bar]
            hold[bar] = peak > previous ? peak : previous * 0.84
        }
        let local = hold.max() ?? 0
        ceiling = max(local, ceiling * 0.992)
        let scale = max(ceiling, 0.02)
        for bar in 0..<7 {
            next[bar] = min(1, hold[bar] / scale)
        }
        let published = next
        lock.withLock { $0 = published }
    }

    private static let statusPath = "/tmp/coucou-wave-status.txt"

    private func note(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: Self.statusPath) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: Self.statusPath, contents: data)
        }
    }

    private func noteFormat(_ device: AudioDeviceID) {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &format)
        note(String(
            format: "format %d rate %.0f ch %u bits %u flags %u",
            status,
            format.mSampleRate,
            format.mChannelsPerFrame,
            format.mBitsPerChannel,
            format.mFormatFlags
        ))
    }

    private static func defaultOutputUID() -> String? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr, device != 0 else {
            return nil
        }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var raw: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &raw) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let raw else { return nil }
        return raw.takeRetainedValue() as String
    }
}

enum NowPlayingProbe {
    struct Snap: Sendable {
        var title: String
        var artist: String
        var source: String
        var artworkPath: String?
        var position: Double
        var duration: Double
        var playing: Bool
        var usesRemote: Bool
        var artworkStamp: Int
        var bundleID: String
        var displayName: String
    }

    nonisolated static func read(source: String) -> Snap? {
        if let remote = SystemNowPlaying.current() {
            let platform = NookPlayback.platform(bundleID: remote.bundleID, displayName: remote.displayName)
            if NookPlayback.accepts(platform: platform, preference: source) {
                return remote
            }
        }
        let order: [String]
        switch source {
        case "music": order = ["music"]
        case "spotify": order = ["spotify"]
        default: order = ["spotify", "music"]
        }
        for name in order {
            if let snap = readOne(name) { return snap }
        }
        return nil
    }

    nonisolated static func pause(source: String) {
        let app = source == "spotify" ? "Spotify" : "Music"
        _ = run("if application \"\(app)\" is running then tell application \"\(app)\" to playpause")
    }

    nonisolated static func skip(source: String, next: Bool) {
        let app = source == "spotify" ? "Spotify" : "Music"
        let command = next ? "next track" : "previous track"
        _ = run("if application \"\(app)\" is running then tell application \"\(app)\" to \(command)")
    }

    nonisolated static func seek(source: String, seconds: Double) {
        let app = source == "spotify" ? "Spotify" : "Music"
        let value = String(format: "%.2f", max(0, seconds))
        _ = run("if application \"\(app)\" is running then tell application \"\(app)\" to set player position to \(value)")
    }

    nonisolated private static func readOne(_ source: String) -> Snap? {
        let artPath = "/tmp/coucou-now-playing.jpg"
        if source == "spotify" {
            let script = """
            if application "Spotify" is running then
              tell application "Spotify"
                if player state is playing or player state is paused then
                  return (name of current track) & tab & (artist of current track) & tab & (artwork url of current track) & tab & (player position as text) & tab & ((duration of current track) / 1000 as text) & tab & (player state as text)
                end if
              end tell
            end if
            """
            guard let text = run(script) else { return nil }
            let parts = text.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let title = clean(parts.first) else { return nil }
            let artist = clean(parts.dropFirst().first) ?? ""
            let art = parts.count > 2 ? clean(parts[2]) : nil
            let path = art.flatMap { download($0, to: artPath) }
            let position = seconds(parts.count > 3 ? parts[3] : nil)
            let duration = seconds(parts.count > 4 ? parts[4] : nil)
            let playing = (parts.count > 5 ? parts[5] : "playing").lowercased().contains("playing")
            let stamp = path.flatMap { fileStamp($0) } ?? 0
            return Snap(title: title, artist: artist, source: "spotify", artworkPath: path, position: position, duration: duration, playing: playing, usesRemote: false, artworkStamp: stamp, bundleID: "com.spotify.client", displayName: "Spotify")
        }
        let script = """
        if application "Music" is running then
          tell application "Music"
            if player state is playing or player state is paused then
              set outPath to "\(artPath)"
              do shell script "rm -f " & quoted form of outPath
              try
                set artData to raw data of artwork 1 of current track
                set fileRef to open for access POSIX file outPath with write permission
                set eof fileRef to 0
                write artData to fileRef
                close access fileRef
              end try
              return (name of current track) & tab & (artist of current track) & tab & (player position as text) & tab & (duration of current track as text) & tab & (player state as text)
            end if
          end tell
        end if
        """
        guard let text = run(script) else { return nil }
        let parts = text.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard let title = clean(parts.first) else { return nil }
        let artist = clean(parts.dropFirst().first) ?? ""
        let exists = FileManager.default.fileExists(atPath: artPath)
        let position = seconds(parts.count > 2 ? parts[2] : nil)
        let duration = seconds(parts.count > 3 ? parts[3] : nil)
        let playing = (parts.count > 4 ? parts[4] : "playing").lowercased().contains("playing")
        let path = exists ? artPath : nil
        return Snap(title: title, artist: artist, source: "music", artworkPath: path, position: position, duration: duration, playing: playing, usesRemote: false, artworkStamp: path.flatMap { fileStamp($0) } ?? 0, bundleID: "com.apple.Music", displayName: "Music")
    }

    nonisolated private static func fileStamp(_ path: String) -> Int {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else { return 0 }
        return size.intValue
    }

    nonisolated private static func download(_ urlString: String, to path: String) -> String? {
        guard let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var body: Data?
        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            body = data
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 1.5)
        guard let body, !body.isEmpty else { return nil }
        do {
            try body.write(to: URL(fileURLWithPath: path))
            return path
        } catch {
            return nil
        }
    }

    nonisolated private static func seconds(_ value: String?) -> Double {
        guard let value else { return 0 }
        let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        if number.isNaN || number < 0 { return 0 }
        return number
    }

    nonisolated private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "missing value" { return nil }
        return trimmed
    }

    nonisolated private static func run(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if text?.isEmpty == true { return nil }
        return text
    }
}

/// Reads the system now-playing session, including Chrome, through the
/// Swift process macOS already allows to see that session.
enum NowPlayingBridge {
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var process: Process?
        var input: FileHandle?
        var buffer = Data()
        var latest: NowPlayingWire?
        var latestAt = Date.distantPast
        var misses = 0
        var started = false

        func current() -> NowPlayingWire? {
            lock.lock()
            defer { lock.unlock() }
            guard let latest, Date().timeIntervalSince(latestAt) < 8 else { return nil }
            return latest
        }

        func isRunning() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if process == nil { return started }
            return process?.isRunning ?? false
        }

        func append(_ data: Data) {
            lock.lock()
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.prefix(upTo: newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                let line = String(data: lineData, encoding: .utf8) ?? ""
                if let wire = NowPlayingWireLine.decode(line) {
                    latest = wire
                    latestAt = Date()
                    misses = 0
                } else if line.contains("\"ok\":false") {
                    misses += 1
                    if misses >= 3 { latest = nil }
                }
            }
            lock.unlock()
        }
    }

    private nonisolated(unsafe) static let box = Box()

    private static let script: String = {
        let encoded = "aW1wb3J0IERhcndpbgppbXBvcnQgRm91bmRhdGlvbgoKbGV0IGZyYW1ld29ya1BhdGggPSAiL1N5c3RlbS9MaWJyYXJ5L1ByaXZhdGVGcmFtZXdvcmtzL01lZGlhUmVtb3RlLmZyYW1ld29yay9NZWRpYVJlbW90ZSIKbGV0IGFydEZpbGUgPSAiL3RtcC9jb3Vjb3Utbm93LXBsYXlpbmcuanBnIgoKZnVuYyBzeW1ib2w8VD4oXyBoYW5kbGU6IFVuc2FmZU11dGFibGVSYXdQb2ludGVyLCBfIG5hbWU6IFN0cmluZykgLT4gVD8gewogICAgZ3VhcmQgbGV0IHJhdyA9IGRsc3ltKGhhbmRsZSwgbmFtZSkgZWxzZSB7IHJldHVybiBuaWwgfQogICAgcmV0dXJuIHVuc2FmZUJpdENhc3QocmF3LCB0bzogVC5zZWxmKQp9CgpmdW5jIHN0cmluZ0tleShfIGhhbmRsZTogVW5zYWZlTXV0YWJsZVJhd1BvaW50ZXIsIF8gbmFtZTogU3RyaW5nKSAtPiBTdHJpbmcgewogICAgZ3VhcmQgbGV0IHJhdyA9IGRsc3ltKGhhbmRsZSwgbmFtZSkgZWxzZSB7IHJldHVybiBuYW1lIH0KICAgIHJldHVybiByYXcubG9hZChhczogQ0ZTdHJpbmc/LnNlbGYpLm1hcCB7ICQwIGFzIFN0cmluZyB9ID8/IG5hbWUKfQoKZnVuYyBlbWl0KF8gb2JqZWN0OiBbU3RyaW5nOiBBbnldKSB7CiAgICBndWFyZCBsZXQgZGF0YSA9IHRyeT8gSlNPTlNlcmlhbGl6YXRpb24uZGF0YSh3aXRoSlNPTk9iamVjdDogb2JqZWN0KSwKICAgICAgICAgIGxldCBsaW5lID0gU3RyaW5nKGRhdGE6IGRhdGEsIGVuY29kaW5nOiAudXRmOCkgZWxzZSB7CiAgICAgICAgcHJpbnQoIntcIm9rXCI6ZmFsc2V9IikKICAgICAgICBmZmx1c2goc3Rkb3V0KQogICAgICAgIHJldHVybgogICAgfQogICAgcHJpbnQobGluZSkKICAgIGZmbHVzaChzdGRvdXQpCn0KCmd1YXJkIGxldCBoYW5kbGUgPSBkbG9wZW4oZnJhbWV3b3JrUGF0aCwgUlRMRF9OT1cpIGVsc2UgewogICAgd2hpbGUgdHJ1ZSB7CiAgICAgICAgZW1pdChbIm9rIjogZmFsc2VdKQogICAgICAgIFRocmVhZC5zbGVlcChmb3JUaW1lSW50ZXJ2YWw6IDEpCiAgICB9Cn0KCnR5cGVhbGlhcyBJbmZvRm4gPSBAY29udmVudGlvbihjKSAoRGlzcGF0Y2hRdWV1ZSwgQGVzY2FwaW5nIEBjb252ZW50aW9uKGJsb2NrKSAoQ0ZEaWN0aW9uYXJ5PykgLT4gVm9pZCkgLT4gVm9pZAp0eXBlYWxpYXMgQm9vbEZuID0gQGNvbnZlbnRpb24oYykgKERpc3BhdGNoUXVldWUsIEBlc2NhcGluZyBAY29udmVudGlvbihibG9jaykgKEJvb2wpIC0+IFZvaWQpIC0+IFZvaWQKdHlwZWFsaWFzIFBJREZuID0gQGNvbnZlbnRpb24oYykgKERpc3BhdGNoUXVldWUsIEBlc2NhcGluZyBAY29udmVudGlvbihibG9jaykgKEludDMyKSAtPiBWb2lkKSAtPiBWb2lkCnR5cGVhbGlhcyBDbGllbnRzRm4gPSBAY29udmVudGlvbihjKSAoRGlzcGF0Y2hRdWV1ZSwgQGVzY2FwaW5nIEBjb252ZW50aW9uKGJsb2NrKSAoQ0ZBcnJheT8pIC0+IFZvaWQpIC0+IFZvaWQKdHlwZWFsaWFzIFRleHRGbiA9IEBjb252ZW50aW9uKGMpIChBbnlPYmplY3QpIC0+IENGU3RyaW5nPwp0eXBlYWxpYXMgUGlkT2ZGbiA9IEBjb252ZW50aW9uKGMpIChBbnlPYmplY3QpIC0+IEludDMyCnR5cGVhbGlhcyBTZW5kRm4gPSBAY29udmVudGlvbihjKSAoVUludDMyLCBDRkRpY3Rpb25hcnk/KSAtPiBCb29sCnR5cGVhbGlhcyBTZWVrRm4gPSBAY29udmVudGlvbihjKSAoRG91YmxlKSAtPiBWb2lkCgpsZXQgZ2V0SW5mbzogSW5mb0ZuPyA9IHN5bWJvbChoYW5kbGUsICJNUk1lZGlhUmVtb3RlR2V0Tm93UGxheWluZ0luZm8iKQpsZXQgaXNQbGF5aW5nRm46IEJvb2xGbj8gPSBzeW1ib2woaGFuZGxlLCAiTVJNZWRpYVJlbW90ZUdldE5vd1BsYXlpbmdBcHBsaWNhdGlvbklzUGxheWluZyIpCmxldCBnZXRQSUQ6IFBJREZuPyA9IHN5bWJvbChoYW5kbGUsICJNUk1lZGlhUmVtb3RlR2V0Tm93UGxheWluZ0FwcGxpY2F0aW9uUElEIikKbGV0IGdldENsaWVudHM6IENsaWVudHNGbj8gPSBzeW1ib2woaGFuZGxlLCAiTVJNZWRpYVJlbW90ZUdldE5vd1BsYXlpbmdDbGllbnRzIikKbGV0IGJ1bmRsZU9mOiBUZXh0Rm4/ID0gc3ltYm9sKGhhbmRsZSwgIk1STm93UGxheWluZ0NsaWVudEdldEJ1bmRsZUlkZW50aWZpZXIiKQpsZXQgbmFtZU9mOiBUZXh0Rm4/ID0gc3ltYm9sKGhhbmRsZSwgIk1STm93UGxheWluZ0NsaWVudEdldERpc3BsYXlOYW1lIikKbGV0IHBpZE9mOiBQaWRPZkZuPyA9IHN5bWJvbChoYW5kbGUsICJNUk5vd1BsYXlpbmdDbGllbnRHZXRQcm9jZXNzSWRlbnRpZmllciIpCmxldCBzZW5kQ29tbWFuZDogU2VuZEZuPyA9IHN5bWJvbChoYW5kbGUsICJNUk1lZGlhUmVtb3RlU2VuZENvbW1hbmQiKQpsZXQgc2Vla1RvOiBTZWVrRm4/ID0gc3ltYm9sKGhhbmRsZSwgIk1STWVkaWFSZW1vdGVTZXRFbGFwc2VkVGltZSIpCmxldCBxdWV1ZSA9IERpc3BhdGNoUXVldWUobGFiZWw6ICJjb3Vjb3Uubm93cGxheWluZyIpCgpmdW5jIGhhbmRsZUNvbW1hbmQoXyBsaW5lOiBTdHJpbmcpIHsKICAgIGxldCBwYXJ0cyA9IGxpbmUuc3BsaXQoc2VwYXJhdG9yOiAiICIpCiAgICBsZXQgdmVyYiA9IHBhcnRzLmZpcnN0Lm1hcChTdHJpbmcuaW5pdCkgPz8gIiIKICAgIHN3aXRjaCB2ZXJiIHsKICAgIGNhc2UgInRvZ2dsZSI6CiAgICAgICAgXyA9IHNlbmRDb21tYW5kPygyLCBuaWwpCiAgICBjYXNlICJuZXh0IjoKICAgICAgICBfID0gc2VuZENvbW1hbmQ/KDQsIG5pbCkKICAgIGNhc2UgInByZXYiOgogICAgICAgIF8gPSBzZW5kQ29tbWFuZD8oNSwgbmlsKQogICAgY2FzZSAic2VlayI6CiAgICAgICAgaWYgcGFydHMuY291bnQgPiAxLCBsZXQgc2Vjb25kcyA9IERvdWJsZShwYXJ0c1sxXSkgewogICAgICAgICAgICBzZWVrVG8/KG1heCgwLCBzZWNvbmRzKSkKICAgICAgICB9CiAgICBkZWZhdWx0OgogICAgICAgIGJyZWFrCiAgICB9Cn0KCkRpc3BhdGNoUXVldWUuZ2xvYmFsKHFvczogLnV0aWxpdHkpLmFzeW5jIHsKICAgIHdoaWxlIGxldCBsaW5lID0gcmVhZExpbmUoc3RyaXBwaW5nTmV3bGluZTogdHJ1ZSkgewogICAgICAgIGhhbmRsZUNvbW1hbmQobGluZSkKICAgIH0KfQoKZnVuYyB0ZXh0KF8gdmFsdWU6IEFueT8pIC0+IFN0cmluZyB7CiAgICBndWFyZCBsZXQgcmF3ID0gdmFsdWUgYXM/IFN0cmluZyBlbHNlIHsgcmV0dXJuICIiIH0KICAgIHJldHVybiByYXcudHJpbW1pbmdDaGFyYWN0ZXJzKGluOiAud2hpdGVzcGFjZXNBbmROZXdsaW5lcykKfQoKZnVuYyBudW1iZXIoXyB2YWx1ZTogQW55PykgLT4gRG91YmxlIHsKICAgIGxldCBudW1iZXI6IERvdWJsZQogICAgaWYgbGV0IHZhbHVlID0gdmFsdWUgYXM/IE5TTnVtYmVyIHsKICAgICAgICBudW1iZXIgPSB2YWx1ZS5kb3VibGVWYWx1ZQogICAgfSBlbHNlIGlmIGxldCB2YWx1ZSA9IHZhbHVlIGFzPyBEb3VibGUgewogICAgICAgIG51bWJlciA9IHZhbHVlCiAgICB9IGVsc2UgewogICAgICAgIG51bWJlciA9IDAKICAgIH0KICAgIGlmIG51bWJlci5pc05hTiB8fCBudW1iZXIgPCAwIHsgcmV0dXJuIDAgfQogICAgcmV0dXJuIG51bWJlcgp9CgpmdW5jIHNuYXBzaG90KCkgewogICAgbGV0IHdhaXQgPSBEaXNwYXRjaFNlbWFwaG9yZSh2YWx1ZTogMCkKICAgIHZhciBpbmZvOiBOU0RpY3Rpb25hcnk/CiAgICBnZXRJbmZvPyhxdWV1ZSkgeyBkaWN0IGluCiAgICAgICAgaW5mbyA9IGRpY3QubWFwIHsgJDAgYXMgTlNEaWN0aW9uYXJ5IH0KICAgICAgICB3YWl0LnNpZ25hbCgpCiAgICB9CiAgICBndWFyZCBnZXRJbmZvICE9IG5pbCwgd2FpdC53YWl0KHRpbWVvdXQ6IC5ub3coKSArIDAuOCkgPT0gLnN1Y2Nlc3MsIGxldCBpbmZvIGVsc2UgewogICAgICAgIGVtaXQoWyJvayI6IGZhbHNlXSkKICAgICAgICByZXR1cm4KICAgIH0KICAgIGxldCB0aXRsZSA9IHRleHQoaW5mb1tzdHJpbmdLZXkoaGFuZGxlLCAia01STWVkaWFSZW1vdGVOb3dQbGF5aW5nSW5mb1RpdGxlIildKQogICAgZ3VhcmQgIXRpdGxlLmlzRW1wdHkgZWxzZSB7CiAgICAgICAgZW1pdChbIm9rIjogZmFsc2VdKQogICAgICAgIHJldHVybgogICAgfQogICAgdmFyIHBsYXlpbmcgPSBmYWxzZQogICAgaXNQbGF5aW5nRm4/KHF1ZXVlKSB7IHZhbHVlIGluCiAgICAgICAgcGxheWluZyA9IHZhbHVlCiAgICAgICAgd2FpdC5zaWduYWwoKQogICAgfQogICAgaWYgaXNQbGF5aW5nRm4gIT0gbmlsIHsgXyA9IHdhaXQud2FpdCh0aW1lb3V0OiAubm93KCkgKyAwLjQpIH0KICAgIHZhciBwaWQ6IEludDMyID0gMAogICAgZ2V0UElEPyhxdWV1ZSkgeyB2YWx1ZSBpbgogICAgICAgIHBpZCA9IHZhbHVlCiAgICAgICAgd2FpdC5zaWduYWwoKQogICAgfQogICAgaWYgZ2V0UElEICE9IG5pbCB7IF8gPSB3YWl0LndhaXQodGltZW91dDogLm5vdygpICsgMC40KSB9CiAgICB2YXIgYnVuZGxlID0gIiIKICAgIHZhciBuYW1lID0gIiIKICAgIGdldENsaWVudHM/KHF1ZXVlKSB7IGFycmF5IGluCiAgICAgICAgbGV0IGl0ZW1zID0gKGFycmF5IGFzPyBbQW55XSkgPz8gW10KICAgICAgICB2YXIgZmFsbGJhY2tCdW5kbGUgPSAiIgogICAgICAgIHZhciBmYWxsYmFja05hbWUgPSAiIgogICAgICAgIGZvciBpdGVtIGluIGl0ZW1zIHsKICAgICAgICAgICAgbGV0IG9iaiA9IGl0ZW0gYXMgQW55T2JqZWN0CiAgICAgICAgICAgIGxldCBpdGVtQnVuZGxlID0gYnVuZGxlT2Y/KG9iaikubWFwIHsgJDAgYXMgU3RyaW5nIH0gPz8gIiIKICAgICAgICAgICAgbGV0IGl0ZW1OYW1lID0gbmFtZU9mPyhvYmopLm1hcCB7ICQwIGFzIFN0cmluZyB9ID8/ICIiCiAgICAgICAgICAgIGxldCBpdGVtUElEID0gcGlkT2Y/KG9iaikgPz8gMAogICAgICAgICAgICBpZiBmYWxsYmFja0J1bmRsZS5pc0VtcHR5IHsKICAgICAgICAgICAgICAgIGZhbGxiYWNrQnVuZGxlID0gaXRlbUJ1bmRsZQogICAgICAgICAgICAgICAgZmFsbGJhY2tOYW1lID0gaXRlbU5hbWUKICAgICAgICAgICAgfQogICAgICAgICAgICBpZiBwaWQgIT0gMCAmJiBpdGVtUElEID09IHBpZCB7CiAgICAgICAgICAgICAgICBidW5kbGUgPSBpdGVtQnVuZGxlCiAgICAgICAgICAgICAgICBuYW1lID0gaXRlbU5hbWUKICAgICAgICAgICAgICAgIGJyZWFrCiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgaWYgYnVuZGxlLmlzRW1wdHkgewogICAgICAgICAgICBidW5kbGUgPSBmYWxsYmFja0J1bmRsZQogICAgICAgICAgICBuYW1lID0gZmFsbGJhY2tOYW1lCiAgICAgICAgfQogICAgICAgIHdhaXQuc2lnbmFsKCkKICAgIH0KICAgIGlmIGdldENsaWVudHMgIT0gbmlsIHsgXyA9IHdhaXQud2FpdCh0aW1lb3V0OiAubm93KCkgKyAwLjQpIH0KICAgIHZhciBwb3NpdGlvbiA9IG51bWJlcihpbmZvW3N0cmluZ0tleShoYW5kbGUsICJrTVJNZWRpYVJlbW90ZU5vd1BsYXlpbmdJbmZvRWxhcHNlZFRpbWUiKV0pCiAgICB2YXIgZHVyYXRpb24gPSBudW1iZXIoaW5mb1tzdHJpbmdLZXkoaGFuZGxlLCAia01STWVkaWFSZW1vdGVOb3dQbGF5aW5nSW5mb0R1cmF0aW9uIildKQogICAgaWYgZHVyYXRpb24gPiAxMDBfMDAwIHsgZHVyYXRpb24gLz0gMTAwMCB9CiAgICBpZiBwb3NpdGlvbiA+IDEwMF8wMDAgeyBwb3NpdGlvbiAvPSAxMDAwIH0KICAgIGxldCByYXRlID0gbnVtYmVyKGluZm9bc3RyaW5nS2V5KGhhbmRsZSwgImtNUk1lZGlhUmVtb3RlTm93UGxheWluZ0luZm9QbGF5YmFja1JhdGUiKV0pCiAgICB2YXIgYXJ0ID0gIiIKICAgIHZhciBzdGFtcCA9IDAKICAgIGxldCBhcnR3b3JrVmFsdWUgPSBpbmZvW3N0cmluZ0tleShoYW5kbGUsICJrTVJNZWRpYVJlbW90ZU5vd1BsYXlpbmdJbmZvQXJ0d29ya0RhdGEiKV0KICAgIGxldCBieXRlczogRGF0YT8KICAgIGlmIGxldCBkYXRhID0gYXJ0d29ya1ZhbHVlIGFzPyBEYXRhIHsKICAgICAgICBieXRlcyA9IGRhdGEKICAgIH0gZWxzZSBpZiBsZXQgZGF0YSA9IGFydHdvcmtWYWx1ZSBhcz8gTlNEYXRhIHsKICAgICAgICBieXRlcyA9IGRhdGEgYXMgRGF0YQogICAgfSBlbHNlIHsKICAgICAgICBieXRlcyA9IG5pbAogICAgfQogICAgaWYgbGV0IGJ5dGVzLCAhYnl0ZXMuaXNFbXB0eSB7CiAgICAgICAgdHJ5PyBieXRlcy53cml0ZSh0bzogVVJMKGZpbGVVUkxXaXRoUGF0aDogYXJ0RmlsZSksIG9wdGlvbnM6IC5hdG9taWMpCiAgICAgICAgYXJ0ID0gYXJ0RmlsZQogICAgICAgIHN0YW1wID0gYnl0ZXMuY291bnQKICAgIH0KICAgIGVtaXQoWwogICAgICAgICJvayI6IHRydWUsCiAgICAgICAgImJ1bmRsZSI6IGJ1bmRsZSwKICAgICAgICAibmFtZSI6IG5hbWUsCiAgICAgICAgInRpdGxlIjogdGl0bGUsCiAgICAgICAgImFydGlzdCI6IHRleHQoaW5mb1tzdHJpbmdLZXkoaGFuZGxlLCAia01STWVkaWFSZW1vdGVOb3dQbGF5aW5nSW5mb0FydGlzdCIpXSksCiAgICAgICAgInBsYXlpbmciOiBwbGF5aW5nLAogICAgICAgICJyYXRlIjogcmF0ZSwKICAgICAgICAicG9zaXRpb24iOiBwb3NpdGlvbiwKICAgICAgICAiZHVyYXRpb24iOiBkdXJhdGlvbiwKICAgICAgICAiYXJ0IjogYXJ0LAogICAgICAgICJzdGFtcCI6IHN0YW1wCiAgICBdKQp9Cgp3aGlsZSB0cnVlIHsKICAgIHNuYXBzaG90KCkKICAgIFRocmVhZC5zbGVlcChmb3JUaW1lSW50ZXJ2YWw6IDEpCn0K"
        guard let data = Data(base64Encoded: encoded),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return "" }
        return text
    }()

    nonisolated static func latest() -> NowPlayingWire? {
        if let snap = box.current() { return snap }
        startIfNeeded()
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let snap = box.current() { return snap }
            if !box.isRunning() { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return box.current()
    }

    nonisolated static func command(_ line: String) {
        startIfNeeded()
        box.lock.lock()
        let input = box.input
        box.lock.unlock()
        guard let input else { return }
        let text = line.hasSuffix("\n") ? line : line + "\n"
        try? input.write(contentsOf: Data(text.utf8))
    }

    nonisolated static func stop() {
        box.lock.lock()
        let process = box.process
        box.process = nil
        box.input = nil
        box.started = false
        box.lock.unlock()
        process?.terminate()
    }

    nonisolated private static func startIfNeeded() {
        box.lock.lock()
        if let process = box.process, process.isRunning {
            box.lock.unlock()
            return
        }
        if box.started, box.process == nil {
            box.lock.unlock()
            return
        }
        box.started = true
        box.process = nil
        box.input = nil
        box.lock.unlock()
        endPreviousHelpers()
        guard !script.isEmpty else {
            box.lock.lock()
            box.started = false
            box.lock.unlock()
            return
        }
        let url = URL(fileURLWithPath: "/tmp/coucou-now-playing-helper.swift")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = [url.path]
            let output = Pipe()
            let input = Pipe()
            process.standardOutput = output
            process.standardInput = input
            let errPath = "/tmp/coucou-now-playing-helper.log"
            FileManager.default.createFile(atPath: errPath, contents: nil)
            if let err = FileHandle(forWritingAtPath: errPath) {
                process.standardError = err
            }
            try process.run()
            try? String(process.processIdentifier).write(
                to: URL(fileURLWithPath: "/tmp/coucou-now-playing.pid"),
                atomically: true,
                encoding: .utf8
            )
            box.lock.lock()
            box.process = process
            box.input = input.fileHandleForWriting
            box.lock.unlock()
            let handle = output.fileHandleForReading
            Thread.detachNewThread {
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    box.append(chunk)
                }
            }
        } catch {
            box.lock.lock()
            box.started = false
            box.lock.unlock()
        }
    }

    private static func endPreviousHelpers() {
        let pidURL = URL(fileURLWithPath: "/tmp/coucou-now-playing.pid")
        guard let text = try? String(contentsOf: pidURL, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0,
              pid != ProcessInfo.processInfo.processIdentifier else { return }
        kill(pid, SIGTERM)
    }
}


/// Now Playing for whichever app is actually playing, including video.
/// Play, pause, skip, and seek use the same session.
enum SystemNowPlaying {
    private final class Slot: @unchecked Sendable {
        var info: NSDictionary?
        var playing = false
        var pid: Int32 = 0
        var bundleID = ""
        var displayName = ""
    }

    private nonisolated(unsafe) static var inProcessMisses = 0
    private nonisolated(unsafe) static var usingBridge = false

    /// In-process MediaRemote is empty for this app. A system Swift reader
    /// still sees Chrome, so the notch follows that reader after two misses.
    nonisolated static func current() -> NowPlayingProbe.Snap? {
        if inProcessMisses < 2, let snap = inProcessSnapshot() {
            inProcessMisses = 0
            usingBridge = false
            return snap
        }
        if inProcessMisses < 2 { inProcessMisses += 1 }
        guard let wire = NowPlayingBridge.latest() else { return nil }
        usingBridge = true
        let platform = NookPlayback.platform(bundleID: wire.bundleID, displayName: wire.displayName)
        return NowPlayingProbe.Snap(
            title: wire.title,
            artist: wire.artist,
            source: platform?.sourceName ?? "system",
            artworkPath: wire.artworkPath,
            position: wire.position,
            duration: wire.duration,
            playing: wire.playing,
            usesRemote: true,
            artworkStamp: wire.artworkStamp,
            bundleID: wire.bundleID,
            displayName: wire.displayName.isEmpty ? (platform?.rawValue ?? "") : wire.displayName
        )
    }

    nonisolated static func inProcessSnapshot() -> NowPlayingProbe.Snap? {
        guard let handle = framework() else { return nil }
        registerIfNeeded(handle)
        let slot = Slot()
        let queue = Thread.isMainThread ? DispatchQueue.global(qos: .utility) : DispatchQueue.main
        guard fill(slot, handle: handle, queue: queue) else { return nil }
        if slot.info == nil {
            let again = Slot()
            if fill(again, handle: handle, queue: queue), again.info != nil {
                slot.info = again.info
                slot.playing = again.playing
                slot.pid = again.pid
                slot.bundleID = again.bundleID
                slot.displayName = again.displayName
            }
        }
        guard let info = slot.info else { return nil }

        let title = text(info[stringKey(handle, "kMRMediaRemoteNowPlayingInfoTitle")])
        guard let title else { return nil }
        let artist = text(info[stringKey(handle, "kMRMediaRemoteNowPlayingInfoArtist")]) ?? ""
        var position = number(info[stringKey(handle, "kMRMediaRemoteNowPlayingInfoElapsedTime")])
        var duration = number(info[stringKey(handle, "kMRMediaRemoteNowPlayingInfoDuration")])
        if duration > 100_000 { duration /= 1000 }
        if position > 100_000 { position /= 1000 }
        let rate = number(info[stringKey(handle, "kMRMediaRemoteNowPlayingInfoPlaybackRate")])
        let playing = slot.playing || rate > 0.05
        let art = artwork(info[stringKey(handle, "kMRMediaRemoteNowPlayingInfoArtworkData")])
        if slot.bundleID.isEmpty, slot.pid != 0,
           let app = NSRunningApplication(processIdentifier: slot.pid) {
            slot.bundleID = app.bundleIdentifier ?? ""
            if slot.displayName.isEmpty { slot.displayName = app.localizedName ?? "" }
        }
        let platform = NookPlayback.platform(bundleID: slot.bundleID, displayName: slot.displayName)
        return NowPlayingProbe.Snap(
            title: title,
            artist: artist,
            source: platform?.sourceName ?? "system",
            artworkPath: art?.path,
            position: position,
            duration: duration,
            playing: playing,
            usesRemote: true,
            artworkStamp: art?.stamp ?? 0,
            bundleID: slot.bundleID,
            displayName: slot.displayName.isEmpty ? (platform?.rawValue ?? "") : slot.displayName
        )
    }

    nonisolated static func toggle() {
        if usingBridge {
            NowPlayingBridge.command("toggle")
            return
        }
        send(2)
    }
    nonisolated static func skip(next: Bool) {
        if usingBridge {
            NowPlayingBridge.command(next ? "next" : "prev")
            return
        }
        send(next ? 4 : 5)
    }
    nonisolated static func seek(to seconds: Double) {
        if usingBridge {
            NowPlayingBridge.command("seek \(max(0, seconds))")
            return
        }
        guard let handle = framework() else { return }
        typealias SeekFn = @convention(c) (Double) -> Void
        let seek: SeekFn? = symbol(handle, "MRMediaRemoteSetElapsedTime")
        seek?(max(0, seconds))
    }

    private static func send(_ command: UInt32) {
        guard let handle = framework() else { return }
        typealias SendFn = @convention(c) (UInt32, CFDictionary?) -> Bool
        let send: SendFn? = symbol(handle, "MRMediaRemoteSendCommand")
        _ = send?(command, nil)
    }

    private static func fill(_ slot: Slot, handle: UnsafeMutableRawPointer, queue: DispatchQueue) -> Bool {
        typealias InfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
        typealias BoolFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
        typealias PIDFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
        typealias ClientsFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFArray?) -> Void) -> Void
        typealias TextFn = @convention(c) (AnyObject) -> CFString?
        typealias PidOfFn = @convention(c) (AnyObject) -> Int32

        let getInfo: InfoFn? = symbol(handle, "MRMediaRemoteGetNowPlayingInfo")
        let isPlaying: BoolFn? = symbol(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
        let getPID: PIDFn? = symbol(handle, "MRMediaRemoteGetNowPlayingApplicationPID")
        let getClients: ClientsFn? = symbol(handle, "MRMediaRemoteGetNowPlayingClients")
        let bundleOf: TextFn? = symbol(handle, "MRNowPlayingClientGetBundleIdentifier")
        let nameOf: TextFn? = symbol(handle, "MRNowPlayingClientGetDisplayName")
        let pidOf: PidOfFn? = symbol(handle, "MRNowPlayingClientGetProcessIdentifier")
        guard getInfo != nil else { return false }

        let wait = DispatchSemaphore(value: 0)
        getInfo?(queue) { dict in
            slot.info = dict.map { $0 as NSDictionary }
            wait.signal()
        }
        guard wait.wait(timeout: .now() + 0.6) == .success else { return false }

        isPlaying?(queue) { playing in
            slot.playing = playing
            wait.signal()
        }
        if isPlaying != nil { _ = wait.wait(timeout: .now() + 0.4) }

        getPID?(queue) { pid in
            slot.pid = pid
            wait.signal()
        }
        if getPID != nil { _ = wait.wait(timeout: .now() + 0.4) }

        getClients?(queue) { array in
            let items = (array as NSArray?) ?? []
            var fallbackBundle = ""
            var fallbackName = ""
            for item in items {
                let obj = item as AnyObject
                let bundle = bundleOf?(obj).map { $0 as String } ?? ""
                let name = nameOf?(obj).map { $0 as String } ?? ""
                let pid = pidOf?(obj) ?? 0
                if fallbackBundle.isEmpty {
                    fallbackBundle = bundle
                    fallbackName = name
                }
                if slot.pid != 0 && pid == slot.pid {
                    slot.bundleID = bundle
                    slot.displayName = name
                    break
                }
            }
            if slot.bundleID.isEmpty {
                slot.bundleID = fallbackBundle
                slot.displayName = fallbackName
            }
            wait.signal()
        }
        if getClients != nil { _ = wait.wait(timeout: .now() + 0.4) }
        return true
    }

    private static func artwork(_ value: Any?) -> (path: String, stamp: Int)? {
        let data: Data?
        if let bytes = value as? Data {
            data = bytes
        } else if let bytes = value as? NSData {
            data = bytes as Data
        } else {
            data = nil
        }
        guard let data, !data.isEmpty else { return nil }
        let path = "/tmp/coucou-now-playing.jpg"
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            return nil
        }
        var stamp = data.count
        if let first = data.first { stamp = stamp &* 31 &+ Int(first) }
        if data.count > 16 { stamp = stamp &* 31 &+ Int(data[data.count / 2]) }
        return (path, stamp)
    }

    private static func text(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "missing value" { return nil }
        return trimmed
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

    private static func stringKey(_ handle: UnsafeMutableRawPointer, _ name: String) -> String {
        guard let raw = dlsym(handle, name) else { return name }
        return raw.load(as: CFString?.self).map { $0 as String } ?? name
    }

    private nonisolated(unsafe) static var didRegister = false

    nonisolated private static func registerIfNeeded(_ handle: UnsafeMutableRawPointer) {
        if didRegister { return }
        didRegister = true
        typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
        let register: RegisterFn? = symbol(handle, "MRMediaRemoteRegisterForNowPlayingNotifications")
        let call = { register?(DispatchQueue.main) }
        if Thread.isMainThread {
            call()
        } else {
            DispatchQueue.main.sync(execute: call)
        }
    }

    private static func framework() -> UnsafeMutableRawPointer? {
        dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        guard let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }
}

/// Drives Logic Pro's Stem Splitter for one audio file.
/// Logic closes the current project when another project is opened, so this
/// never uses New, Open, or Open Recent. The song is imported into the project
/// that is already open, then Functions > Stem Splitter > Apply.
enum LogicStemSplitter {
    static let bundleID = "com.apple.logic10"

    static func installed() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Stem Splitter runs on Apple silicon only, including when Coucou itself is translated.
    static func appleSilicon() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 {
            return value == 1
        }
        return false
    }

    nonisolated static func split(path: String) -> String {
        guard let result = OSAScript.run(script, args: [path]), !result.isEmpty else { return "failed" }
        return result
    }

    /// The path arrives as an argument so a quote in the filename cannot change the script.
    private nonisolated static let script = """
    on run argv
      if (count of argv) < 1 then return "failed"
      set songPath to item 1 of argv
      set logicName to "Logic Pro"
      tell application "System Events"
        if not (exists process logicName) then
          tell application logicName to activate
        end if
        repeat 40 times
          if exists process logicName then exit repeat
          delay 0.5
        end repeat
        if not (exists process logicName) then return "no-logic"
        tell process logicName
          set frontmost to true
          repeat 40 times
            if (count of windows) > 0 then exit repeat
            delay 0.5
          end repeat
          if (count of windows) is 0 then return "no-project"
          repeat with w in windows
            try
              set bnames to name of every button of w
              if bnames contains "Save" and bnames contains "Cancel" then return "busy"
            end try
          end repeat
          set hasTracks to false
          repeat with w in windows
            try
              set wname to name of w
              if wname contains ".logicx" or wname contains "Tracks" then set hasTracks to true
            end try
          end repeat
          if hasTracks is false then return "no-project"
          try
            click menu item "Audio File…" of menu "Import" of menu item "Import" of menu "File" of menu bar item "File" of menu bar 1
          on error
            click menu item "Audio File..." of menu "Import" of menu item "Import" of menu "File" of menu bar item "File" of menu bar 1
          end try
        end tell
        delay 0.8
        keystroke "g" using {command down, shift down}
        delay 0.4
        keystroke songPath
        delay 0.2
        key code 36
        delay 0.6
        key code 36
      end tell
      delay 1.2
      set splitter to "disabled"
      repeat 8 times
        my clickButtonNamedContaining(logicName, "tempo", "No")
        my clickButtonNamedContaining(logicName, "tempo", "Don")
        set splitter to my openStemSplitter(logicName)
        if splitter is "clicked" or splitter is "no-functions" then exit repeat
        delay 0.8
      end repeat
      if splitter is not "clicked" then return splitter
      set applied to false
      repeat 20 times
        set action to my clickStemAction(logicName)
        if action is "offline" then return "offline"
        if action is "applied" then
          set applied to true
          exit repeat
        end if
        delay 0.3
      end repeat
      if applied is false then return "no-apply"
      delay 1
      repeat 180 times
        if my stemBusy(logicName) is false then
          delay 1
          if my stemBusy(logicName) is false then return "ok"
        end if
        delay 1
      end repeat
      return "timeout"
    end run

    on openStemSplitter(logicName)
      tell application "System Events"
        tell process logicName
          set targetButton to missing value
          set bestY to 100000
          set queue to UI elements of window 1
          set seen to 0
          repeat while (count of queue) > 0 and seen < 900
            set e to item 1 of queue
            if (count of queue) is 1 then
              set queue to {}
            else
              set queue to rest of queue
            end if
            set seen to seen + 1
            try
              if role of e is "AXMenuButton" and description of e is "Functions" then
                set py to item 2 of (position of e)
                if py < bestY then
                  set bestY to py
                  set targetButton to e
                end if
              end if
            end try
            try
              set kids to UI elements of e
              if (count of kids) > 0 and (count of kids) < 50 then set queue to queue & kids
            end try
          end repeat
          if targetButton is missing value then return "no-functions"
          click targetButton
          delay 0.4
          set stemItem to missing value
          try
            set stemItem to menu item "Stem Splitter…" of menu 1 of targetButton
          end try
          if stemItem is missing value then
            try
              set stemItem to menu item "Stem Splitter..." of menu 1 of targetButton
            end try
          end if
          if stemItem is missing value then
            key code 53
            return "no-functions"
          end if
          if enabled of stemItem is false then
            key code 53
            return "disabled"
          end if
          click stemItem
          return "clicked"
        end tell
      end tell
    end openStemSplitter

    on clickStemAction(logicName)
      tell application "System Events"
        tell process logicName
          repeat with w in windows
            if my windowIsStem(w) then
              try
                set blob to (value of every static text of w) as string
                if blob contains "Internet connection required" then
                  try
                    click button "OK" of w
                  end try
                  return "offline"
                end if
              end try
              try
                click button "Apply" of w
                return "applied"
              end try
              try
                click button "Split" of w
                return "applied"
              end try
              try
                if (count of sheets of w) > 0 then
                  click button "Apply" of sheet 1 of w
                  return "applied"
                end if
              end try
              try
                if (count of sheets of w) > 0 then
                  click button "Split" of sheet 1 of w
                  return "applied"
                end if
              end try
            end if
          end repeat
        end tell
      end tell
      return "miss"
    end clickStemAction

    on windowIsStem(w)
      tell application "System Events"
        try
          set wname to name of w
          if wname contains "Stem" then return true
          if wname contains ".logicx" then
            if (count of sheets of w) > 0 then
              set blob to (value of every static text of sheet 1 of w) as string
              if blob contains "Stem Splitter" or blob contains "Separate All Stems" then return true
            end if
            return false
          end if
        end try
        try
          set blob to (value of every static text of w) as string
          if blob contains "Stem Splitter" or blob contains "Separate All Stems" then return true
        end try
      end tell
      return false
    end windowIsStem

    on stemBusy(logicName)
      tell application "System Events"
        tell process logicName
          repeat with w in windows
            try
              set wname to name of w
              if wname contains "Stem" or wname contains "Splitting" then return true
              if wname contains ".logicx" and (count of sheets of w) > 0 then
                set blob to (value of every static text of sheet 1 of w) as string
                if blob contains "Splitting" or blob contains "Stem Splitter" or blob contains "Create Audio Files" then return true
              end if
            end try
          end repeat
        end tell
      end tell
      return false
    end stemBusy

    on clickButtonNamedContaining(logicName, needle, buttonNeedle)
      tell application "System Events"
        tell process logicName
          repeat with w in windows
            try
              set blob to (value of every static text of w) as string
              if blob contains needle then
                repeat with b in buttons of w
                  if name of b contains buttonNeedle then
                    click b
                    return true
                  end if
                end repeat
              end if
            end try
          end repeat
        end tell
      end tell
      return false
    end clickButtonNamedContaining
    """
}

final class ReleaseRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let url = request.url, LiveActivityBehavior.allowsReleaseRedirect(url) else { return nil }
        return request
    }
}

enum ReleaseProbe {
    nonisolated static func latest() async -> LiveActivityBehavior.PublishedRelease? {
        guard let url = URL(string: LiveActivityBehavior.releaseAPI) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Coucou", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return LiveActivityBehavior.publishedRelease(json: data)
    }

    /// Saves Coucou.zip. A failed download leaves any earlier saved zip in place.
    nonisolated static func downloadZip(from urlString: String, to destination: URL) async -> Bool {
        guard LiveActivityBehavior.allowedDownloadURL(urlString) != nil,
              let remote = URL(string: urlString) else { return false }
        let delegate = ReleaseRedirectGuard()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let partial = destination.appendingPathExtension("partial")
        do {
            let (temp, response) = try await session.download(from: remote)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            guard LiveActivityBehavior.isZipFile(at: temp) else { return false }
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: partial.path) { try fm.removeItem(at: partial) }
            try fm.moveItem(at: temp, to: partial)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: partial, to: destination)
            return fm.fileExists(atPath: destination.path)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            return false
        }
    }
}

enum ShortcutProbe {
    struct Load: Equatable, Sendable {
        var shortcuts: [NookShortcut]
        var failed: Bool
    }

    nonisolated static func catalog() -> Load {
        let folders = command(["list", "--folders"])
        guard folders.status == 0 else { return Load(shortcuts: [], failed: true) }
        let unfiled = command(["list", "--folder-name", "none", "--show-identifiers"])
        guard unfiled.status == 0 else { return Load(shortcuts: [], failed: true) }
        var groups: [(folder: String, lines: [String])] = [("", unfiled.lines)]
        for folder in folders.lines {
            let filed = command(["list", "--folder-name", folder, "--show-identifiers"])
            guard filed.status == 0 else { return Load(shortcuts: [], failed: true) }
            groups.append((folder, filed.lines))
        }
        return Load(shortcuts: NookShortcuts.catalog(groups: groups), failed: false)
    }

    /// Runs one shortcut and waits. Zero means it finished.
    nonisolated static func run(_ identifier: String) -> Int32 {
        command(["run", identifier]).status
    }

    private nonisolated static func command(_ arguments: [String]) -> (status: Int32, lines: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return (-1, []) }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return (process.terminationStatus, lines)
    }
}

enum QuickAppProbe {
    struct Load: Equatable, Sendable {
        var apps: [NookQuickApp]
        var failed: Bool
    }

    /// Apps in /Applications and the home Applications folder. One folder deeper covers Utilities.
    nonisolated static func catalog() -> Load {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home
        ]
        var found: [(name: String, bundleID: String)] = []
        var readable = false
        for root in roots {
            let read = apps(in: root)
            if read.readable { readable = true }
            found.append(contentsOf: read.apps)
        }
        guard readable else { return Load(apps: [], failed: true) }
        return Load(apps: NookQuickApps.catalog(apps: found), failed: false)
    }

    private nonisolated static func apps(in root: URL) -> (apps: [(name: String, bundleID: String)], readable: Bool) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: root.path) else {
            return ([], false)
        }
        var found: [(name: String, bundleID: String)] = []
        for name in names where !name.hasPrefix(".") {
            let url = root.appendingPathComponent(name)
            if name.hasSuffix(".app") {
                if let app = readApp(url) { found.append(app) }
                continue
            }
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            guard let children = try? manager.contentsOfDirectory(atPath: url.path) else { continue }
            for child in children where child.hasSuffix(".app") && !child.hasPrefix(".") {
                if let app = readApp(url.appendingPathComponent(child)) { found.append(app) }
            }
        }
        return (found, true)
    }

    private nonisolated static func readApp(_ url: URL) -> (name: String, bundleID: String)? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist) else { return nil }
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any],
              let app = NookQuickApps.entry(
                displayName: info["CFBundleDisplayName"] as? String,
                bundleName: info["CFBundleName"] as? String,
                fileName: url.lastPathComponent,
                bundleID: (info["CFBundleIdentifier"] as? String) ?? ""
              ) else { return nil }
        return (app.name, app.bundleID)
    }
}

enum BatteryProbe {
    static func read() -> (percent: Int, charging: Bool, watts: Double?, supply: Double?)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            let kind = info[kIOPSTypeKey] as? String
            if kind != nil && kind != (kIOPSInternalBatteryType as String) { continue }
            let current = number(info[kIOPSCurrentCapacityKey])
            let maxCap = number(info[kIOPSMaxCapacityKey]) ?? 100
            guard let current, maxCap > 0 else { continue }
            let charging = (info[kIOPSIsChargingKey] as? Bool) ?? ((info[kIOPSIsChargingKey] as? NSNumber)?.boolValue ?? false)
            let percent = Int((Double(current) / Double(maxCap) * 100).rounded())
            let power = powerSample(charging: charging)
            return (min(100, max(0, percent)), charging, power.pack, power.supply)
        }
        return nil
    }

    /// Watts coming in from the connection, plus the charger contract for diagnostics.
    /// The contract is never the number on the card. A 15W listing is the port's
    /// rating. The card shows the live input, and the pack watts only if that is missing.
    private static func powerSample(charging: Bool) -> (pack: Double?, supply: Double?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }
        let connected = (registryInt(service, "ExternalConnected") ?? 0) != 0
        let registryCharging = (registryInt(service, "IsCharging") ?? 0) != 0
        let supply = connected ? adapterWatts(service) : nil
        let chargingNow = charging || registryCharging
        if !connected && !chargingNow { return (nil, nil) }
        let pack = NookLayout.measuredChargeWatts(
            batteryPowerMilliwatts: batteryPowerMilliwatts(service),
            milliamps: registryInt(service, "InstantAmperage") ?? registryInt(service, "Amperage"),
            millivolts: registryInt(service, "Voltage"),
            charging: chargingNow
        )
        let input = connected ? portInputMilliwatts(service) : nil
        let shown = NookLayout.shownChargeWatts(inputMilliwatts: input, packWatts: pack)
        return (shown, supply)
    }

    /// Live milliwatts on the cable. `IPDInputPower` is the port measurement.
    /// `SystemPowerIn` is the same reading when the distribution block is missing.
    private static func portInputMilliwatts(_ service: io_registry_entry_t) -> Int? {
        if let distribution = registryDictionary(service, "PowerDistribution"),
           let power = number(distribution["IPDInputPower"]), power > 0 {
            return power
        }
        if let telemetry = registryDictionary(service, "PowerTelemetryData"),
           let power = number(telemetry["SystemPowerIn"]), power > 0 {
            return power
        }
        return nil
    }

    private static func registryDictionary(_ service: io_registry_entry_t, _ key: String) -> NSDictionary? {
        guard let raw = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        return raw as? NSDictionary
    }

    /// BatteryPower from PowerTelemetryData, in milliwatts. Negative while the pack is supplying the Mac.
    private static func batteryPowerMilliwatts(_ service: io_registry_entry_t) -> Int? {
        guard let raw = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let dict = raw as? NSDictionary else { return nil }
        return number(dict["BatteryPower"])
    }

    private static func adapterWatts(_ service: io_registry_entry_t) -> Double? {
        guard let raw = IORegistryEntryCreateCFProperty(service, "AdapterDetails" as NSString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        let watts: Int?
        if let dict = raw as? [String: Any] {
            watts = (dict["Watts"] as? NSNumber)?.intValue ?? dict["Watts"] as? Int
        } else if let dict = raw as? NSDictionary {
            watts = (dict["Watts"] as? NSNumber)?.intValue
        } else {
            watts = nil
        }
        guard let watts, watts > 0 else { return nil }
        return Double(watts)
    }

    private static func registryInt(_ service: io_registry_entry_t, _ key: String) -> Int? {
        guard let raw = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        if let number = raw as? NSNumber { return number.intValue }
        return nil
    }

    private static func number(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}

enum BluetoothProbe {
    static func connectedNames() -> [String] {
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return devices.compactMap { device in
            guard device.isConnected() else { return nil }
            let name = device.name ?? ""
            return name.isEmpty ? "Bluetooth device" : name
        }
    }
}
