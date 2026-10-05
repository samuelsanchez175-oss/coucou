import AppKit
import AVFoundation
import CoreImage
import CoreMedia
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

/// Open notch: Nook widgets. Tray is the button beside Nook on the main row.
struct NookView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var prefs = NookPreferences.shared
    @ObservedObject private var board = NookBoard.shared

    var body: some View {
        NookWidgetRow(prefs: prefs, board: board)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear { board.nookVisible = state.view == .nook }
            .onChange(of: state.view) { _, view in
                board.nookVisible = view == .nook
            }
    }
}

/// Hold area and the AirDrop tile. Reached from the Tray button beside Nook.
struct TrayView: View {
    @ObservedObject private var prefs = NookPreferences.shared
    @ObservedObject private var board = NookBoard.shared

    var body: some View {
        NookTrayPage(board: board, prefs: prefs)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Resting notch while audio or video is on: the play button only, on the right.
/// The closed notch does not show the app icon, the waveform, or the name.
struct NotchMediaShelf: View {
    @ObservedObject var board: NookBoard
    var islandWidth: CGFloat
    var contentCenterY: CGFloat

    var body: some View {
        let moving = NookPlayback.waveIsMoving(
            reportedPlaying: board.mediaIsPlaying,
            outputRunning: board.mediaOutputRunning
        )
        let symbol = moving ? "pause.fill" : "play.fill"
        let verb = moving ? "Pause" : "Play"
        Button {
            board.togglePlayback()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(verb)
        .help(verb)
        .position(
            x: NookPlayback.mediaShelfCenterX(islandWidth: islandWidth, wing: NookPlayback.mediaWing),
            y: contentCenterY
        )
    }
}

struct LiveActivityPill: View {
    let headline: NookHeadline

    /// The tray keeps its icon and shows the count. Other lines keep their sentence.
    private var shown: String {
        headline.id == "tray" ? NookLayout.trayCollapsedText(headline.text) : headline.text
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: headline.symbol)
            Text(shown)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(Color(hex: "#F5F6F8"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headline.text)
    }
}

// MARK: - Widget row

private struct NookWidgetRow: View {
    @ObservedObject var prefs: NookPreferences
    @ObservedObject var board: NookBoard

    var body: some View {
        let shown = prefs.widgets.filter(\.enabled)
        let pad = CGFloat(prefs.contentPadding)
        let widths = shown.map {
            NookLayout.columnWidth(id: $0.id, cells: $0.cells, contentPadding: pad)
        }
        Group {
            if shown.isEmpty {
                Text("Turn on a widget in Nook settings.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, widget in
                        if index > 0 && prefs.widgetDividers {
                            Rectangle()
                                .fill(Color.white.opacity(0.14))
                                .frame(width: 1)
                                .padding(.vertical, 6)
                        }
                        column(widget)
                            .frame(width: widths.indices.contains(index) ? widths[index] : nil)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private func column(_ widget: NookWidget) -> some View {
        let pad = CGFloat(prefs.contentPadding)
        switch widget.id {
        case "media":
            NookMediaColumn(board: board, prefs: prefs).padding(pad)
        case "calendar":
            NookCalendarColumn(board: board, prefs: prefs).padding(pad)
        case "mirror":
            NookMirrorColumn().padding(min(pad, 8))
        case "shortcuts":
            NookShortcutsColumn(board: board).padding(pad)
        case "notes":
            NookNotesColumn(board: board).padding(pad)
        case "todos":
            NookTodosColumn(board: board).padding(pad)
        case "timer":
            NookTimerColumn(board: board).padding(pad)
        case "quickApps":
            Text("Coming soon")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            EmptyView()
        }
    }
}

// MARK: - Media

private struct NookMediaColumn: View {
    @ObservedObject var board: NookBoard
    @ObservedObject var prefs: NookPreferences
    @ObservedObject private var picture = PictureInPictureController.shared
    @State private var dragSeconds: Double?

    var body: some View {
        if let title = board.mediaTitle, !title.isEmpty {
            playing(title)
        } else {
            idle
        }
    }

    private var idle: some View {
        VStack(spacing: 8) {
            Text("No app seems to be running")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
            Text("Wanna open one?")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            HStack(spacing: 14) {
                ForEach(NookMediaPlatform.launcher, id: \.self) { platform in
                    Button {
                        board.openApp(platform.title)
                    } label: {
                        NookPlatformGlyph(platform: platform, side: 42)
                    }
                    .buttonStyle(.plain)
                    .help(platform.title)
                    .accessibilityLabel(platform.title)
                }
            }
            .padding(.top, 2)
            .opacity(prefs.interactiveActivities ? 1 : 0.45)
            .allowsHitTesting(prefs.interactiveActivities)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func playing(_ title: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            artwork
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let artist = board.mediaArtist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "#A7ABB3"))
                        .lineLimit(1)
                }
                HStack(spacing: 2) {
                    transport("backward.fill", "Previous track") { board.skip(next: false) }
                    transport(
                        board.mediaIsPlaying ? "pause.fill" : "play.fill",
                        board.mediaIsPlaying ? "Pause" : "Play"
                    ) { board.togglePlayback() }
                    transport("forward.fill", "Next track") { board.skip(next: true) }
                    transport(
                        NookPictureInPicture.buttonSymbol(active: picture.active),
                        NookPictureInPicture.buttonLabel(active: picture.active),
                        help: NookPictureInPicture.buttonHelp(active: picture.active)
                    ) {
                        picture.toggle(
                            bundleID: board.mediaBundleID,
                            displayName: board.mediaDisplayName,
                            hasTitle: !(board.mediaTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }
                if board.mediaDuration > 0 {
                    scrubber
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func transport(_ symbol: String, _ label: String, help hint: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(!prefs.interactiveActivities)
        .accessibilityLabel(label)
        .help(hint ?? label)
    }

    private var shownPosition: Double { dragSeconds ?? board.mediaPosition }

    private var scrubber: some View {
        HStack(spacing: 4) {
            Text(clock(shownPosition))
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let fraction = min(1, max(0, shownPosition / board.mediaDuration))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(Color.white)
                        .frame(width: max(4, width * fraction))
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard prefs.interactiveActivities else { return }
                            let fraction = min(1, max(0, value.location.x / width))
                            dragSeconds = fraction * board.mediaDuration
                        }
                        .onEnded { value in
                            guard prefs.interactiveActivities else { return }
                            let fraction = min(1, max(0, value.location.x / width))
                            dragSeconds = nil
                            board.seek(to: fraction * board.mediaDuration)
                        }
                )
                .accessibilityLabel("Playback position")
                .help("Drag to move through the song")
            }
            .frame(height: 16)
            Text(clock(board.mediaDuration))
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(Color(hex: "#A7ABB3"))
    }

    private func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @ViewBuilder
    private var artwork: some View {
        let corner: CGFloat = prefs.preferRoundButtons ? 16 : 10
        Group {
            if let path = board.artworkPath,
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if let raw = board.mediaPlatform, let platform = NookMediaPlatform(rawValue: raw) {
                NookPlatformGlyph(platform: platform, side: 18)
                    .padding(2)
            }
        }
        .id(board.artworkToken)
    }
}

/// Music uses the installed icon. Spotify is the green wave circle.
/// YouTube is the white tile with the red play shape.
struct NookPlatformGlyph: View {
    var platform: NookMediaPlatform
    var side: CGFloat

    var body: some View {
        Group {
            if let image = NookMediaApps.icon(for: platform) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                drawn
            }
        }
        .frame(width: side, height: side)
        .clipShape(clip)
    }

    private var clip: AnyShape {
        if platform == .spotify {
            return AnyShape(Circle())
        }
        return AnyShape(RoundedRectangle(cornerRadius: side * 0.28, style: .continuous))
    }

    @ViewBuilder
    private var drawn: some View {
        switch platform {
        case .music:
            ZStack {
                Color(hex: "#FC3C44")
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.46, weight: .bold))
                    .foregroundStyle(.white)
            }
        case .spotify:
            ZStack {
                Circle().fill(Color(hex: "#1DB954"))
                SpotifyWaves()
                    .stroke(Color.black, style: StrokeStyle(lineWidth: side * 0.075, lineCap: .round))
                    .padding(side * 0.22)
            }
        case .youtube:
            ZStack {
                Color.white
                RoundedRectangle(cornerRadius: side * 0.16, style: .continuous)
                    .fill(Color(hex: "#FF0000"))
                    .padding(.horizontal, side * 0.1)
                    .padding(.vertical, side * 0.24)
                YouTubePlay()
                    .fill(Color.white)
                    .frame(width: side * 0.22, height: side * 0.16)
                    .offset(x: side * 0.015)
            }
        }
    }
}

private struct SpotifyWaves: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bars: [(CGFloat, CGFloat)] = [(0.30, 0.92), (0.52, 0.74), (0.74, 0.52)]
        for (yFrac, widthFrac) in bars {
            let y = rect.minY + rect.height * yFrac
            let width = rect.width * widthFrac
            let x = rect.midX - width / 2
            path.move(to: CGPoint(x: x, y: y + rect.height * 0.08))
            path.addQuadCurve(
                to: CGPoint(x: x + width, y: y + rect.height * 0.08),
                control: CGPoint(x: rect.midX, y: y - rect.height * 0.16)
            )
        }
        return path
    }
}

private struct YouTubePlay: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

enum NookMediaApps {
    static func icon(for platform: NookMediaPlatform) -> NSImage? {
        guard let url = registeredURL(for: platform) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// A real app on disk. An updater cache is not launched.
    static func launchURL(for platform: NookMediaPlatform) -> URL? {
        for path in platform.appPaths where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        guard let url = registeredURL(for: platform) else { return nil }
        let path = url.path
        if path.contains("PersistentCache") || path.contains("/temp/") { return nil }
        return FileManager.default.fileExists(atPath: path) ? url : nil
    }

    private static func registeredURL(for platform: NookMediaPlatform) -> URL? {
        for id in platform.bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return url
            }
        }
        return nil
    }
}

// MARK: - Calendar

private struct NookCalendarColumn: View {
    @ObservedObject var board: NookBoard
    @ObservedObject var prefs: NookPreferences
    @State private var selected = Calendar.current.startOfDay(for: Date())

    var body: some View {
        let days = weekDays
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(monthLabel)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 2) {
                    ForEach(days, id: \.self) { day in
                        dayChip(day)
                    }
                }
            }
            Spacer(minLength: 0)
            eventsBlock
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (-2...3).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: selected)
    }

    private func dayChip(_ day: Date) -> some View {
        let calendar = Calendar.current
        let on = calendar.isDate(day, inSameDayAs: selected)
        let today = calendar.isDateInToday(day)
        let letter = today
            ? calendar.shortWeekdaySymbols[calendar.component(.weekday, from: day) - 1].uppercased()
            : String(calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: day) - 1].prefix(1))
        return Button {
            selected = calendar.startOfDay(for: day)
        } label: {
            VStack(spacing: 2) {
                Text(letter)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(on ? Color(hex: "#4C8DFF") : Color.white.opacity(0.9))
            .frame(minWidth: 28, maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!prefs.interactiveActivities)
        .accessibilityLabel(accessibleDay(day))
    }

    private func accessibleDay(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: day)
    }

    @ViewBuilder
    private var eventsBlock: some View {
        let items = events(on: selected)
        if board.calendarDenied {
            Text("Calendar access is off. Turn it on in System Settings to show events.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(maxWidth: .infinity)
        } else if items.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                Text(emptyCaption)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .foregroundStyle(Color.white.opacity(0.45))
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, event in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(event.isAllDay ? "All day" : timeLabel(event.start))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(hex: "#4C8DFF"))
                            .frame(width: 58, alignment: .leading)
                        Text(event.title)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyCaption: String {
        if Calendar.current.isDateInToday(selected) { return "Nothing for today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return "Nothing on \(formatter.string(from: selected))"
    }

    private func events(on day: Date) -> [NookEventFact] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let now = Date()
        return board.events.filter { event in
            guard event.end > start, event.start < end else { return false }
            return NookLayout.includeEvent(
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
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Mirror

private struct NookMirrorColumn: View {
    @StateObject private var camera = MirrorCamera()

    var body: some View {
        Button {
            switch MirrorBehavior.press(wantsRunning: camera.wantsRunning) {
            case .start: camera.start()
            case .stop: camera.stop()
            }
        } label: {
            ZStack {
                Circle().fill(Color.white.opacity(0.08))
                if camera.running {
                    MirrorPreview(session: camera.session)
                        .allowsHitTesting(false)
                } else {
                    VStack(spacing: camera.asking ? 4 : 6) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: camera.asking ? 16 : 22, weight: .semibold))
                        Text(MirrorBehavior.visibleTitle(asking: camera.asking, denied: camera.denied, missing: camera.missing))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .lineLimit(camera.asking ? 2 : 1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(Color.white.opacity(camera.asking ? 0.95 : 0.72))
                    .padding(8)
                }
            }
            .contentShape(.interaction, Circle())
        }
        .buttonStyle(.plain)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help(MirrorBehavior.help(asking: camera.asking, wantsRunning: camera.wantsRunning, denied: camera.denied, missing: camera.missing))
        .accessibilityLabel(MirrorBehavior.accessibilityTitle(
            asking: camera.asking,
            wantsRunning: camera.wantsRunning,
            denied: camera.denied,
            missing: camera.missing
        ))
        .onDisappear { camera.stop() }
    }
}

final class MirrorCamera: ObservableObject, @unchecked Sendable {
    let session = AVCaptureSession()
    @Published var running = false
    @Published var wantsRunning = false
    @Published var asking = false
    @Published var denied = false
    @Published var missing = false
    private let queue = DispatchQueue(label: "coucou.mirror")
    private let planLock = NSLock()
    private var plan = MirrorSessionPlan(generation: 0, wantsRunning: false)
    private var configured = false
    private var savedLevels: [(NSWindow, NSWindow.Level)] = []

    func start() {
        let next = advance(.start)
        wantsRunning = true
        missing = false
        switch MirrorBehavior.prompt(for: Self.accessNow()) {
        case .startCamera:
            asking = false
            begin(startedGeneration: next.generation)
        case .ask:
            beginAsk(startedGeneration: next.generation)
        case .openSettings:
            asking = false
            denied = true
            wantsRunning = false
            _ = advance(.stop)
            NSWorkspace.shared.open(MirrorBehavior.cameraSettingsURL)
        }
    }

    func stop() {
        let next = advance(.stop)
        wantsRunning = false
        asking = false
        running = false
        apply(.accessory)
        restorePanelLevel()
        let generation = next.generation
        queue.async { [weak self] in
            guard let self else { return }
            guard self.currentPlan().generation == generation else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    deinit {
        let session = session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    private func begin(startedGeneration: Int) {
        denied = false
        queue.async { [weak self] in
            guard let self else { return }
            guard MirrorBehavior.shouldStayOn(plan: self.currentPlan(), startedGeneration: startedGeneration) else { return }
            if !self.configured {
                self.session.beginConfiguration()
                if let device = self.frontDevice(),
                   let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                    if self.session.canSetSessionPreset(.medium) {
                        self.session.sessionPreset = .medium
                    }
                    self.configured = true
                }
                self.session.commitConfiguration()
            }
            guard self.configured else {
                DispatchQueue.main.async {
                    guard MirrorBehavior.shouldStayOn(plan: self.currentPlan(), startedGeneration: startedGeneration) else { return }
                    self.missing = true
                    self.running = false
                    self.wantsRunning = false
                    _ = self.advance(.stop)
                }
                return
            }
            let stay = MirrorBehavior.shouldStayOn(plan: self.currentPlan(), startedGeneration: startedGeneration)
            if stay {
                if !self.session.isRunning { self.session.startRunning() }
            }
            let still = MirrorBehavior.shouldStayOn(plan: self.currentPlan(), startedGeneration: startedGeneration)
            if !still, self.session.isRunning { self.session.stopRunning() }
            let live = self.session.isRunning && still
            DispatchQueue.main.async {
                let current = MirrorBehavior.shouldStayOn(plan: self.currentPlan(), startedGeneration: startedGeneration)
                self.running = live && current
                self.wantsRunning = current
                if !current {
                    self.queue.async {
                        if self.session.isRunning { self.session.stopRunning() }
                    }
                }
            }
        }
    }

    private func frontDevice() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        let listed = discovery.devices.map { device in
            MirrorBehavior.listedDevice(
                id: device.uniqueID,
                lens: MirrorBehavior.lens(for: device.deviceType),
                facing: MirrorBehavior.facing(for: device.position)
            )
        }
        guard let id = MirrorBehavior.frontCameraID(listed) else { return nil }
        return discovery.devices.first { $0.uniqueID == id }
    }

    private func advance(_ action: MirrorBehavior.Action) -> MirrorSessionPlan {
        planLock.lock()
        defer { planLock.unlock() }
        plan = MirrorBehavior.advance(plan, action)
        return plan
    }

    private func currentPlan() -> MirrorSessionPlan {
        planLock.lock()
        defer { planLock.unlock() }
        return plan
    }

    /// Show Allow in the circle, then let macOS present the prompt. A menu-bar app never gets that prompt.
    private func beginAsk(startedGeneration: Int) {
        asking = true
        denied = false
        lowerPanelsForPrompt()
        let activation = MirrorBehavior.activation(for: .ask)
        apply(activation)
        let delay = MirrorBehavior.askDelay(for: activation)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard MirrorBehavior.shouldStayOn(plan: self.currentPlan(), startedGeneration: startedGeneration) else {
                self.finishAsk(startedGeneration: startedGeneration)
                return
            }
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let follow = MirrorBehavior.afterAsk(granted: ok)
                    self.finishAsk(startedGeneration: startedGeneration)
                    guard MirrorBehavior.shouldStayOn(plan: self.currentPlan(), startedGeneration: startedGeneration) else { return }
                    switch follow {
                    case .startCamera:
                        self.denied = false
                        self.begin(startedGeneration: startedGeneration)
                    case .openSettings:
                        self.asking = MirrorBehavior.keepsAsk(follow)
                        self.denied = false
                        self.wantsRunning = true
                        NSWorkspace.shared.open(MirrorBehavior.cameraSettingsURL)
                        NSApp.windows.first { $0 is IslandPanel }?.orderFrontRegardless()
                    case .ask:
                        self.asking = true
                    }
                }
            }
        }
    }

    /// This ask owns the prompt only while its press is still the latest one.
    private func finishAsk(startedGeneration: Int) {
        guard currentPlan().generation == startedGeneration else { return }
        asking = false
        apply(.accessory)
        restorePanelLevel()
    }

    private static func accessNow() -> MirrorAccess {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private func apply(_ activation: MirrorActivation) {
        switch activation {
        case .regular:
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        case .accessory:
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Other Coucou windows drop so the Allow prompt can be answered. The notch stays up so the circle can say it is asking.
    private func lowerPanelsForPrompt() {
        savedLevels = NSApp.windows.compactMap { window in
            guard (window is IslandPanel) == false else { return nil }
            return (window, window.level)
        }
        for (window, _) in savedLevels {
            window.level = .normal
        }
        NSApp.windows.first { $0 is IslandPanel }?.orderFrontRegardless()
    }

    private func restorePanelLevel() {
        for (window, level) in savedLevels {
            window.level = level
        }
        savedLevels.removeAll()
    }
}

private struct MirrorPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.videoLayer.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        if nsView.videoLayer.session !== session {
            nsView.videoLayer.session = session
        }
        nsView.mirrorFrontCamera()
    }
}

private final class PreviewNSView: NSView {
    override func makeBackingLayer() -> CALayer {
        let preview = AVCaptureVideoPreviewLayer()
        preview.videoGravity = .resizeAspectFill
        preview.backgroundColor = NSColor.black.cgColor
        return preview
    }

    var videoLayer: AVCaptureVideoPreviewLayer {
        guard let preview = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Mirror preview is missing its video layer")
        }
        return preview
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        videoLayer.frame = bounds
        let circle = CAShapeLayer()
        circle.path = CGPath(ellipseIn: bounds, transform: nil)
        videoLayer.mask = circle
        mirrorFrontCamera()
    }

    /// The preview fills the circle. Clicks pass through to the Mirror button.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func mirrorFrontCamera() {
        guard let connection = videoLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}

// MARK: - Other widgets

private struct NookNotesColumn: View {
    @ObservedObject var board: NookBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Notes", systemImage: "note.text")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
            TextEditor(text: $board.noteText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .scrollContentBackground(.hidden)
                .foregroundStyle(Color(hex: "#F5F6F8"))
                .onChange(of: board.noteText) { _, _ in board.saveNote() }
        }
    }
}

private struct NookTodosColumn: View {
    @ObservedObject var board: NookBoard
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("To-dos", systemImage: "checklist")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
            HStack(spacing: 6) {
                TextField("Add a to-do", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .onSubmit { commit() }
                Button("Add") { commit() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(board.todos) { item in
                        Button {
                            board.toggleTodo(item.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                Text(item.title)
                                    .lineLimit(1)
                                    .strikethrough(item.done)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func commit() {
        board.addTodo(draft)
        draft = ""
    }
}

private struct NookTimerColumn: View {
    @ObservedObject var board: NookBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Timer", systemImage: "timer")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
            if let remaining = board.timerRemaining {
                Text(clock(remaining))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else if board.timerEnded {
                Text("Timer ended")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Button("Dismiss") { board.dismissTimer() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            } else {
                Stepper(value: $board.timerMinutes, in: 1...180) {
                    Text("\(board.timerMinutes) minutes")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .lineLimit(1)
                }
                Button("Start timer") { board.startTimer() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct NookShortcutsColumn: View {
    @ObservedObject var board: NookBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Shortcuts", systemImage: "sparkles")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
            if board.shortcutNames.isEmpty {
                Text("No shortcuts yet.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(board.shortcutNames.prefix(12), id: \.self) { name in
                            Button(name) { board.runShortcut(name) }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Tray

private struct AirDropTileFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1 { value = next }
    }
}

private struct NookTrayPage: View {
    @ObservedObject var board: NookBoard
    @ObservedObject var prefs: NookPreferences

    var body: some View {
        let inset = NookLayout.trayInset(slider: prefs.trayWidth)
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                hold
                airDropTile
                    .frame(width: NookLayout.airDropTileWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, inset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(AirDropTileFrameKey.self) { frame in
            if frame != board.airDropTileFrame {
                board.airDropTileFrame = frame
            }
        }
    }

    private var hold: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    Color.white.opacity(board.dropHighlight ? 0.9 : 0.38),
                    style: StrokeStyle(lineWidth: board.dropHighlight ? 2 : 1.5, dash: [7, 6])
                )
            VStack(spacing: 0) {
                Group {
                    if board.tray.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 26, weight: .regular))
                            Text("Tray")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Text("Drop a file to keep it here.")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                        .foregroundStyle(Color.white.opacity(0.72))
                        .padding(16)
                    } else {
                        ScrollView {
                            let icon = NookLayout.trayIconPoints(prefs.trayIconSize)
                            let tileWidth = NookLayout.trayTileWidth(icon: icon)
                            LazyVGrid(
                                columns: [GridItem(
                                    .adaptive(minimum: tileWidth, maximum: tileWidth),
                                    spacing: 8
                                )],
                                spacing: 8
                            ) {
                                ForEach(board.tray) { item in
                                    trayFile(item)
                                }
                            }
                            .padding(12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                pipelineResult
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help("Drop a file to keep it in the tray. Drag it onto AirDrop when you want to send it.")
        .accessibilityLabel("Tray")
        .accessibilityHint("Drop a file to keep it here.")
    }

    /// The pipeline line sits inside the dashed tray, where the drawer does not clip it.
    @ViewBuilder
    private var pipelineResult: some View {
        if let readout = board.songFacts {
            VStack(alignment: .leading, spacing: 4) {
                if !board.songFactsName.isEmpty {
                    Text(board.songFactsName)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    songFact(readout.bpm.map(String.init) ?? "Unavailable", "BPM")
                    songFact(readout.keyName, "Key", colorHex: SongFacts.keyColorHex(keyName: readout.keyName))
                    songFact(readout.camelot, "Camelot")
                    songFact("\(readout.energy)", "Energy")
                }
                scaleNotes(SongFacts.scaleNotes(keyName: readout.keyName))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(board.airDropNote ?? board.songFactsName)
        } else if let note = board.airDropNote, !note.isEmpty {
            Text(note)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.86))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    private func songFact(_ value: String, _ label: String, colorHex: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(colorHex.map { Color(hex: $0) } ?? .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.62))
        }
    }

    @ViewBuilder
    private func scaleNotes(_ notes: [String]) -> some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(hex: SongFacts.noteColorHex(note)))
                            .lineLimit(1)
                    }
                }
                Text("Scale")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
        }
    }

    private func trayFile(_ item: NookLayout.TrayItem) -> some View {
        let name = NookLayout.trayDisplayName(item.name)
        let icon = NookLayout.trayIconPoints(prefs.trayIconSize)
        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Image(nsImage: trayIcon(item.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: icon, height: icon)
                    .accessibilityHidden(true)
                Text(name)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .padding(.top, 6)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .frame(
                width: NookLayout.trayTileWidth(icon: icon),
                height: NookLayout.trayTileHeight(icon: icon)
            )
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: NookLayout.trayTileCorner, style: .continuous))
            .foregroundStyle(.white)
            .contentShape(RoundedRectangle(cornerRadius: NookLayout.trayTileCorner, style: .continuous))
            .draggable(URL(fileURLWithPath: item.path))
            .accessibilityLabel("\(name). Drag onto AirDrop to send it.")
            .accessibilityHint("Drag onto AirDrop to send it.")
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    trayPipelineButton(item, name: name)
                    trayRemoveButton(item, name: name)
                }
                .padding(.top, 2)
                .padding(.trailing, 2)
            }
        }
    }

    /// Stock icon for this file's type: audio, video, markdown, and the rest each keep Apple's image.
    private func trayIcon(_ path: String) -> NSImage {
        let type = UTType(NookLayout.trayTypeIdentifier(path: path)) ?? .data
        let icon = NSWorkspace.shared.icon(for: type)
        icon.size = NSSize(width: 256, height: 256)
        return icon
    }

    private func trayPipelineButton(_ item: NookLayout.TrayItem, name: String) -> some View {
        let color = NookTrayChip.pipelineColorComponents()
        return TrayMark(
            symbol: NookTrayChip.pipelineSymbol,
            red: color.0,
            green: color.1,
            blue: color.2,
            label: NookTrayChip.pipelineLabel,
            hint: NookTrayChip.pipelineHint(name: name),
            choices: [
                TrayPipelineChoice(
                    title: NookTrayChip.title(.stems),
                    hint: NookTrayChip.hint(.stems)
                ) {
                    board.runTrayPipeline(.stems, on: item)
                },
                TrayPipelineChoice(
                    title: NookTrayChip.title(.songInfo),
                    hint: NookTrayChip.hint(.songInfo)
                ) {
                    board.runTrayPipeline(.songInfo, on: item)
                }
            ]
        ) {}
        .frame(width: 22, height: 22)
    }

    private func trayRemoveButton(_ item: NookLayout.TrayItem, name: String) -> some View {
        let color = NookTrayChip.removeColorComponents()
        return TrayMark(
            symbol: NookTrayChip.removeSymbol,
            red: color.0,
            green: color.1,
            blue: color.2,
            label: NookTrayChip.removeLabel,
            hint: NookTrayChip.removeHint(name: name)
        ) {
            board.removeFromTray(item)
        }
        .frame(width: 22, height: 22)
    }

    private var airDropTile: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.up.forward")
                .font(.system(size: 32, weight: .medium))
            Text("AirDrop")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text("Drop a file to send it.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(board.airDropHighlight ? 0.2 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    Color.white.opacity(board.airDropHighlight ? 0.95 : 0.45),
                    lineWidth: board.airDropHighlight ? 2 : 1.5
                )
        )
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: AirDropTileFrameKey.self,
                    value: geo.frame(in: .named("coucouDrawer"))
                )
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            board.receiveDrop(urls, landing: .airDrop)
            return true
        } isTargeted: { targeted in
            board.airDropHighlight = targeted
        }
        .help("Drop a file here to send it with AirDrop. A file already in the tray can be dragged onto this tile.")
        .accessibilityLabel("AirDrop")
        .accessibilityHint("Drop a file here to send it.")
    }
}

struct TrayPipelineChoice {
    var title: String
    var hint: String
    var run: () -> Void
}

@MainActor
protocol TrayMarkActing: AnyObject {
    func press(from view: NSView, event: NSEvent)
}

/// The plus and the X. A SwiftUI button on a tray chip never receives the press,
/// so this is a real button the notch can hand the click to.
private struct TrayMark: NSViewRepresentable {
    var symbol: String
    var title: String = ""
    var red: Double
    var green: Double
    var blue: Double
    var label: String
    var hint: String
    var choices: [TrayPipelineChoice] = []
    var action: () -> Void

    func makeNSView(context: Context) -> TrayMarkButton {
        let button = TrayMarkButton()
        button.isBordered = false
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.press(_:))
        context.coordinator.choices = choices
        apply(button)
        return button
    }

    func updateNSView(_ button: TrayMarkButton, context: Context) {
        context.coordinator.action = action
        context.coordinator.choices = choices
        apply(button)
    }

    func makeCoordinator() -> Coordinator { Coordinator(action) }

    private func apply(_ button: TrayMarkButton) {
        button.setAccessibilityLabel(label)
        button.setAccessibilityHelp(hint)
        button.toolTip = hint
        if title.isEmpty {
            button.imagePosition = .imageOnly
            button.title = ""
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.contentTintColor = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        } else {
            button.imagePosition = .noImage
            button.image = nil
            button.contentTintColor = .white
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium)
                ]
            )
        }
    }

    @MainActor
    final class Coordinator: NSObject, TrayMarkActing {
        var action: () -> Void
        var choices: [TrayPipelineChoice] = []
        init(_ action: @escaping () -> Void) { self.action = action }

        func press(from view: NSView, event: NSEvent) {
            guard !choices.isEmpty else {
                action()
                return
            }
            let menu = NSMenu()
            menu.autoenablesItems = false
            for (index, choice) in choices.enumerated() {
                let item = NSMenuItem(
                    title: choice.title,
                    action: #selector(choose(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                item.toolTip = choice.hint
                item.isEnabled = true
                menu.addItem(item)
            }
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        }

        @objc func press(_ sender: Any?) {
            guard let view = sender as? NSView else {
                action()
                return
            }
            let event = NSApp.currentEvent ?? NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: view.window?.windowNumber ?? 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
            guard let event else {
                action()
                return
            }
            press(from: view, event: event)
        }

        @objc func choose(_ sender: NSMenuItem) {
            let index = sender.tag
            guard choices.indices.contains(index) else { return }
            choices[index].run()
        }
    }
}

final class TrayMarkButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        if imagePosition == .imageOnly {
            return NSSize(width: 22, height: 22)
        }
        let base = super.intrinsicContentSize
        return NSSize(width: base.width + 12, height: max(22, base.height))
    }

    override func mouseDown(with event: NSEvent) {
        guard let acting = target as? TrayMarkActing else { return }
        acting.press(from: self, event: event)
    }
}

// MARK: - Picture in picture

@MainActor
final class PictureInPictureController: ObservableObject {
    static let shared = PictureInPictureController()

    @Published var active = false
    private var panel: NSPanel?
    private var mirror: BrowserMirror?
    private var working = false
    private var lastToggle = Date.distantPast
    private var askedForCapture = false

    func toggle(bundleID: String, displayName: String, hasTitle: Bool) {
        let now = Date()
        guard NookPictureInPicture.acceptsPress(secondsSinceLast: now.timeIntervalSince(lastToggle)) else { return }
        lastToggle = now
        if mirror != nil {
            stopMirror()
            active = false
            return
        }
        switch NookPictureInPicture.kind(bundleID: bundleID, displayName: displayName, hasTitle: hasTitle) {
        case .unavailable:
            return
        case .artwork:
            if panel == nil {
                showArtwork()
            } else {
                closeArtwork()
            }
            active = panel != nil
        case .browser(let application):
            guard !working else { return }
            closeArtwork()
            working = true
            let turningOff = active
            Task.detached {
                let outcome = BrowserPictureInPicture.toggle(application: application, turningOff: turningOff)
                await PictureInPictureController.shared.finish(outcome)
            }
        }
    }

    private func finish(_ outcome: NookPictureInPictureOutcome) {
        working = false
        switch outcome {
        case .entered: active = true
        case .exited: active = false
        case .failed: break
        case .mirror(let windowID, let left, let top, let right, let bottom):
            startMirror(windowID: windowID, crop: NookPictureInPicture.ScreenRect(
                left: left, top: top, right: right, bottom: bottom
            ))
        }
    }

    private func startMirror(windowID: UInt32, crop: NookPictureInPicture.ScreenRect) {
        switch NookPictureInPicture.captureAsk(
            alreadyAllowed: CGPreflightScreenCaptureAccess(),
            alreadyAsked: askedForCapture
        ) {
        case .allowed:
            break
        case .ask:
            askedForCapture = true
            guard CGRequestScreenCaptureAccess() else { return }
        case .skip:
            return
        }
        let session = BrowserMirror(windowID: windowID, crop: crop)
        session.onReady = { [weak self] in
            self?.active = true
        }
        session.onClose = { [weak self] in
            self?.mirror = nil
            self?.active = false
        }
        mirror = session
        session.start()
    }

    private func stopMirror() {
        mirror?.stop()
        mirror = nil
    }

    private func showArtwork() {
        let host = NSHostingView(rootView: PictureArtworkPanel(board: NookBoard.shared) { [weak self] in
            self?.closeArtwork()
            self?.active = false
        })
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 128),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = host
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 300, y: screen.minY + 80))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func closeArtwork() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct PictureArtworkPanel: View {
    @ObservedObject var board: NookBoard
    var close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            artwork
            VStack(alignment: .leading, spacing: 6) {
                Text(board.mediaTitle ?? "")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let artist = board.mediaArtist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "#A7ABB3"))
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    mini("backward.fill", "Previous track") { board.skip(next: false) }
                    mini(board.mediaIsPlaying ? "pause.fill" : "play.fill", board.mediaIsPlaying ? "Pause" : "Play") {
                        board.togglePlayback()
                    }
                    mini("forward.fill", "Next track") { board.skip(next: true) }
                }
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close picture")
            .help("Closes the floating picture.")
        }
        .padding(12)
        .frame(width: 280, height: 128)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func mini(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let path = board.artworkPath,
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Color.white.opacity(0.08)
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

enum BrowserPictureInPicture {
    static func toggle(application: String, turningOff: Bool) -> NookPictureInPictureOutcome {
        guard application == "Google Chrome" || application == "Safari" else { return .failed }
        let inventory = run(inventoryScript(application: application))
        let choice = firstVideo(application: application, inventory: inventory)
        let state = choice?.frame.state ?? "none"
        switch NookPictureInPicture.step(buttonIsOn: turningOff, videoState: state) {
        case .unavailable:
            return turningOff ? .exited : .failed
        case .exitWithoutLeaving:
            guard let choice else { return .exited }
            let exited = run(exitScript(application: application, window: choice.window, tab: choice.tab))
            return NookPictureInPicture.outcome(exited)
        case .showExisting:
            let width = (choice?.right ?? 0) - (choice?.left ?? 0)
            let height = (choice?.bottom ?? 0) - (choice?.top ?? 0)
            let pictureUp = pictureIsOnScreen(browserWidth: width, browserHeight: height)
            let browserID = choice.flatMap {
                windowID(left: $0.left, top: $0.top, right: $0.right, bottom: $0.bottom)
            }
            let onScreen = browserID.map { isOnScreen($0) } ?? false
            if NookPictureInPicture.place(step: .showExisting, browserOnThisDesktop: onScreen, pictureOnThisDesktop: pictureUp) == .mirrorHere {
                guard let choice else { return .failed }
                if let picture = NookPictureInPicture.offscreenPicture(
                    among: listedWindows(), browserWidth: width, browserHeight: height
                ) {
                    let crop = NookPictureInPicture.pictureCrop(width: picture.width, height: picture.height)
                    return .mirror(windowID: picture.id, left: crop.left, top: crop.top, right: crop.right, bottom: crop.bottom)
                }
                guard let browserID else { return .failed }
                return mirrorOutcome(browserID: browserID, choice: choice)
            }
            raisePicture(browserWidth: width, browserHeight: height)
            return pictureUp ? .entered : .failed
        case .enterWithoutLeaving:
            guard let choice else { return .failed }
            let browserID = windowID(left: choice.left, top: choice.top, right: choice.right, bottom: choice.bottom)
            let onScreen = browserID.map { isOnScreen($0) } ?? false
            if NookPictureInPicture.route(browserOnThisDesktop: onScreen) == .mirrorHere {
                guard let browserID else { return .failed }
                return mirrorOutcome(browserID: browserID, choice: choice)
            }
            return enterWithoutLeaving(application: application, choice: choice)
        }
    }

    private static func mirrorOutcome(browserID: UInt32, choice: Choice) -> NookPictureInPictureOutcome {
        let width = choice.right - choice.left
        let height = choice.bottom - choice.top
        let crop = NookPictureInPicture.mirrorCrop(
            frame: choice.frame, windowWidth: width, windowHeight: height
        ) ?? NookPictureInPicture.ScreenRect(left: 0, top: 0, right: max(width, 1), bottom: max(height, 1))
        return .mirror(windowID: browserID, left: crop.left, top: crop.top, right: crop.right, bottom: crop.bottom)
    }

    /// The browser is already on this desktop. Open its picture without switching desktops.
    /// The notch sits above the page, so it steps aside while the press lands.
    private static func enterWithoutLeaving(application: String, choice: Choice) -> NookPictureInPictureOutcome {
        var choice = choice
        let hooked = run(hookScript(application: application, window: choice.window, tab: choice.tab))
        guard hooked.contains("hooked") else { return .failed }
        let previous = NSWorkspace.shared.frontmostApplication
        if let fresh = waitForFrame(application: application, window: choice.window, tab: choice.tab) {
            choice.frame = fresh
        }
        guard let point = NookPictureInPicture.videoClick(
            choice.frame,
            windowLeft: choice.left, windowTop: choice.top, windowRight: choice.right, windowBottom: choice.bottom,
            coveredBy: notchCover()
        ) else {
            restoreFront(previous)
            return .failed
        }
        let saved = CGEvent(source: nil)?.location
        let browserWidth = choice.right - choice.left
        let browserHeight = choice.bottom - choice.top
        setNotchHidden(true)
        setClicksPassThrough(true)
        var looks = 0
        while !NookPictureInPicture.notchIsClear(cover: notchCover(), x: point.x, y: point.y), looks < 8 {
            Thread.sleep(forTimeInterval: 0.04)
            looks += 1
        }
        let spots = NookPictureInPicture.clickSpots(
            primary: point,
            windowLeft: choice.left,
            windowTop: choice.top,
            windowRight: choice.right,
            windowBottom: choice.bottom
        )
        var read = ""
        var clicksSent = 0
        var pollsSinceClick = 0
        var pictureUp = false
        var press = NookPictureInPicture.nextPress(read: read, clicksSent: clicksSent, pollsSinceClick: pollsSinceClick)
        while press != .stop {
            if press == .click {
                if !spots.isEmpty {
                    let spot = spots[min(clicksSent, spots.count - 1)]
                    click(x: spot.x, y: spot.y)
                }
                clicksSent += 1
                pollsSinceClick = 0
            } else {
                pollsSinceClick += 1
            }
            Thread.sleep(forTimeInterval: 0.18)
            read = run(readScript(application: application, window: choice.window, tab: choice.tab))
            pictureUp = pictureIsOnScreen(browserWidth: browserWidth, browserHeight: browserHeight)
            if NookPictureInPicture.pictureReady(read: read, pictureOnScreen: pictureUp) { break }
            press = NookPictureInPicture.nextPress(read: read, clicksSent: clicksSent, pollsSinceClick: pollsSinceClick)
        }
        if NookPictureInPicture.outcome(read) == .entered, !pictureUp {
            pictureUp = waitForPicture(browserWidth: browserWidth, browserHeight: browserHeight)
        }
        setClicksPassThrough(false)
        setNotchHidden(false)
        if let saved { move(x: saved.x, y: saved.y) }
        let ready = NookPictureInPicture.pictureReady(read: read, pictureOnScreen: pictureUp)
        if ready {
            raisePicture(browserWidth: browserWidth, browserHeight: browserHeight)
        }
        restoreFront(previous)
        if ready {
            raisePicture(browserWidth: browserWidth, browserHeight: browserHeight)
        }
        if NookPictureInPicture.outcome(read) == .exited { return .exited }
        return ready ? .entered : .failed
    }

    private struct Choice {
        var window: Int
        var tab: Int
        var frame: NookPictureInPicture.VideoFrame
        var left: Double
        var top: Double
        var right: Double
        var bottom: Double
    }

    /// The active web tab first, then any other web tab that actually has a video.
    private static func firstVideo(application: String, inventory: String) -> Choice? {
        let rows = parse(inventory)
        let ordered = rows.sorted { lhs, rhs in
            let leftScore = (lhs.window == 1 && lhs.active) ? 0 : 1
            let rightScore = (rhs.window == 1 && rhs.active) ? 0 : 1
            if leftScore != rightScore { return leftScore < rightScore }
            if lhs.window != rhs.window { return lhs.window < rhs.window }
            return lhs.tab < rhs.tab
        }
        for row in ordered {
            let raw = run(stateScript(application: application, window: row.window, tab: row.tab))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let frame = NookPictureInPicture.parseVideo(raw) else { continue }
            return Choice(
                window: row.window, tab: row.tab, frame: frame,
                left: row.left, top: row.top, right: row.right, bottom: row.bottom
            )
        }
        return nil
    }

    private struct Row {
        var window: Int
        var tab: Int
        var active: Bool
        var left: Double
        var top: Double
        var right: Double
        var bottom: Double
    }

    private static func parse(_ report: String) -> [Row] {
        var rows: [Row] = []
        for line in report.split(separator: "\n") {
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 8,
                  let window = Int(parts[0]),
                  let tab = Int(parts[1]),
                  parts[3] == "web",
                  let left = Double(parts[4]),
                  let top = Double(parts[5]),
                  let right = Double(parts[6]),
                  let bottom = Double(parts[7]) else { continue }
            rows.append(Row(
                window: window, tab: tab, active: parts[2] == "active",
                left: left, top: top, right: right, bottom: bottom
            ))
        }
        return rows
    }

    private static func inventoryScript(application: String) -> String {
        """
        tell application "\(application)"
          if (count of windows) is 0 then return "none"
          set report to ""
          set winIndex to 0
          repeat with theWindow in windows
            set winIndex to winIndex + 1
            set theBounds to bounds of theWindow
            set activeIndex to active tab index of theWindow
            set boundText to ((item 1 of theBounds) as text) & " " & ((item 2 of theBounds) as text) & " " & ((item 3 of theBounds) as text) & " " & ((item 4 of theBounds) as text)
            set tabIndex to 0
            repeat with theTab in tabs of theWindow
              set tabIndex to tabIndex + 1
              set pageURL to URL of theTab
              set tabKind to "skip"
              if pageURL starts with "http" then set tabKind to "web"
              set tabMark to "other"
              if tabIndex is activeIndex then set tabMark to "active"
              set report to report & (winIndex as text) & " " & (tabIndex as text) & " " & tabMark & " " & tabKind & " " & boundText & linefeed
            end repeat
          end repeat
          return report
        end tell
        """
    }

    private static func stateScript(application: String, window: Int, tab: Int) -> String {
        javaScript(application, window: window, tab: tab, source: NookPictureInPicture.videoFrameScript())
    }

    private static func hookScript(application: String, window: Int, tab: Int) -> String {
        javaScript(application, window: window, tab: tab, source: NookPictureInPicture.hookScript())
    }

    private static func readScript(application: String, window: Int, tab: Int) -> String {
        javaScript(application, window: window, tab: tab, source: NookPictureInPicture.readScript())
    }

    private static func exitScript(application: String, window: Int, tab: Int) -> String {
        let source = "(function(){if(document.pictureInPictureElement){document.exitPictureInPicture();return 'exited';}return 'none';})()"
        return javaScript(application, window: window, tab: tab, source: source)
    }

    private static func focusScript(application: String, window: Int, tab: Int) -> String {
        """
        tell application "\(application)"
          set index of window \(window) to 1
          set active tab index of window 1 to \(tab)
          return "focused"
        end tell
        """
    }

    private static func javaScript(_ application: String, window: Int, tab: Int, source: String) -> String {
        let escaped = source.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        if application == "Safari" {
            return """
            tell application "Safari"
              set answer to do JavaScript "\(escaped)" in tab \(tab) of window \(window)
              return answer
            end tell
            """
        }
        return """
        tell application "\(application)"
          set answer to execute tab \(tab) of window \(window) javascript "\(escaped)"
          return answer
        end tell
        """
    }

    private static func run(_ source: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"]
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() } catch { return "" }
        input.fileHandleForWriting.write(Data(source.utf8))
        try? input.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Focus the tab that is playing, then leave the browser in front.
    static func showPlaying(application: String) {
        let inventory = run(inventoryScript(application: application))
        if let choice = bestPlayingVideo(application: application, inventory: inventory) {
            _ = run(focusScript(application: application, window: choice.window, tab: choice.tab))
        }
        let bundle = application == "Safari" ? "com.apple.Safari" : "com.google.Chrome"
        NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?
            .activate(options: [.activateIgnoringOtherApps])
    }

    /// The playing video wins. Otherwise the front window's own video is enough.
    private static func bestPlayingVideo(application: String, inventory: String) -> Choice? {
        let rows = parse(inventory).sorted { lhs, rhs in
            let leftScore = (lhs.window == 1 && lhs.active) ? 0 : 1
            let rightScore = (rhs.window == 1 && rhs.active) ? 0 : 1
            if leftScore != rightScore { return leftScore < rightScore }
            if lhs.window != rhs.window { return lhs.window < rhs.window }
            return lhs.tab < rhs.tab
        }
        var fallback: Choice?
        for row in rows {
            let raw = run(stateScript(application: application, window: row.window, tab: row.tab))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let frame = NookPictureInPicture.parseVideo(raw) else { continue }
            let choice = Choice(
                window: row.window, tab: row.tab, frame: frame,
                left: row.left, top: row.top, right: row.right, bottom: row.bottom
            )
            if let current = fallback {
                if NookPictureInPicture.prefersPlayingVideo(frame.state, over: current.frame.state) {
                    fallback = choice
                }
            } else {
                fallback = choice
            }
            if frame.state == "play" { return choice }
        }
        return fallback
    }

    /// Return to the app the person was using, on the desktop they were using.
    private static func restoreFront(_ application: NSRunningApplication?) {
        application?.activate(options: [])
    }

    /// Read the video again once the page can lay itself out.
    private static func waitForFrame(application: String, window: Int, tab: Int) -> NookPictureInPicture.VideoFrame? {
        var last: NookPictureInPicture.VideoFrame?
        for _ in 0..<8 {
            let raw = run(stateScript(application: application, window: window, tab: tab))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let frame = NookPictureInPicture.parseVideo(raw) {
                last = frame
                if NookPictureInPicture.frameIsLaidOut(frame), NookPictureInPicture.pageIsVisible(raw) {
                    Thread.sleep(forTimeInterval: 0.12)
                    return frame
                }
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return last
    }

    /// The notch panel, in top-left screen coordinates. It follows every desktop.
    private static func notchCover() -> NookPictureInPicture.ScreenRect? {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var union: NookPictureInPicture.ScreenRect?
        for window in info {
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            guard owner == "Coucou" else { continue }
            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let x = bounds["X"] as? Double ?? 0
            let y = bounds["Y"] as? Double ?? 0
            let width = bounds["Width"] as? Double ?? 0
            let height = bounds["Height"] as? Double ?? 0
            guard width >= 40, height >= 20 else { continue }
            let rect = NookPictureInPicture.ScreenRect(left: x, top: y, right: x + width, bottom: y + height)
            if let existing = union {
                union = NookPictureInPicture.ScreenRect(
                    left: min(existing.left, rect.left),
                    top: min(existing.top, rect.top),
                    right: max(existing.right, rect.right),
                    bottom: max(existing.bottom, rect.bottom)
                )
            } else {
                union = rect
            }
        }
        return union
    }

    /// The notch is on every desktop and would take the press meant for the page.
    private static func setNotchHidden(_ hidden: Bool) {
        let apply = { @MainActor in
            for window in NSApplication.shared.windows {
                if hidden {
                    window.orderOut(nil)
                } else {
                    window.orderFrontRegardless()
                }
            }
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(apply)
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated(apply)
            }
        }
    }

    /// Let the browser receive the press that the notch panel would otherwise take.
    private static func setClicksPassThrough(_ pass: Bool) {
        let apply = { @MainActor in
            for window in NSApplication.shared.windows {
                window.ignoresMouseEvents = pass
            }
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(apply)
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated(apply)
            }
        }
    }

    private static func listedWindows() -> [NookPictureInPicture.ListedWindow] {
        let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        var listed: [NookPictureInPicture.ListedWindow] = []
        for window in info {
            let id = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            guard id != 0 else { continue }
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let width = bounds["Width"] as? Double ?? 0
            let height = bounds["Height"] as? Double ?? 0
            let onScreen = window[kCGWindowIsOnscreen as String] as? Bool ?? false
            let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            listed.append(NookPictureInPicture.ListedWindow(
                id: id, owner: owner, width: width, height: height, onScreen: onScreen, layer: layer
            ))
        }
        return listed
    }

    private static func pictureIsOnScreen(browserWidth: Double, browserHeight: Double) -> Bool {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in info {
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            guard owner == "Google Chrome" || owner == "Safari" else { continue }
            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let width = bounds["Width"] as? Double ?? 0
            let height = bounds["Height"] as? Double ?? 0
            if NookPictureInPicture.isPictureWindow(
                width: width, height: height, browserWidth: browserWidth, browserHeight: browserHeight
            ) {
                return true
            }
        }
        return false
    }

    private static func waitForPicture(browserWidth: Double, browserHeight: Double) -> Bool {
        if pictureIsOnScreen(browserWidth: browserWidth, browserHeight: browserHeight) { return true }
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 0.15)
            if pictureIsOnScreen(browserWidth: browserWidth, browserHeight: browserHeight) { return true }
        }
        return false
    }

    private static func isOnScreen(_ windowID: UInt32) -> Bool {
        let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in info {
            let id = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            guard id == windowID else { continue }
            return window[kCGWindowIsOnscreen as String] as? Bool ?? false
        }
        return false
    }

    private static func windowID(left: Double, top: Double, right: Double, bottom: Double) -> UInt32? {
        let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let width = right - left
        let height = bottom - top
        for window in info {
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            guard owner == "Google Chrome" || owner == "Safari" else { continue }
            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let x = bounds["X"] as? Double ?? -1
            let y = bounds["Y"] as? Double ?? -1
            let w = bounds["Width"] as? Double ?? 0
            let h = bounds["Height"] as? Double ?? 0
            if abs(x - left) < 4, abs(y - top) < 4, abs(w - width) < 8, abs(h - height) < 8 {
                return (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            }
        }
        var largest: (id: UInt32, area: Double)?
        for window in info {
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            guard owner == "Google Chrome" || owner == "Safari" else { continue }
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let w = bounds["Width"] as? Double ?? 0
            let h = bounds["Height"] as? Double ?? 0
            let area = w * h
            if area > (largest?.area ?? 200_000) {
                largest = ((window[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0, area)
            }
        }
        return largest?.id
    }

    /// Lift the floating picture above the other windows on this desktop.
    private static func raisePicture(browserWidth: Double, browserHeight: Double) {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var match: (width: Double, height: Double)?
        for window in info {
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            guard owner == "Google Chrome" || owner == "Safari" else { continue }
            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let width = bounds["Width"] as? Double ?? 0
            let height = bounds["Height"] as? Double ?? 0
            guard NookPictureInPicture.isPictureWindow(
                width: width, height: height, browserWidth: browserWidth, browserHeight: browserHeight
            ) else { continue }
            if match == nil || width * height > match!.width * match!.height {
                match = (width, height)
            }
        }
        guard let match else { return }
        let bundles = ["com.google.Chrome", "com.apple.Safari"]
        for bundle in bundles {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var wins: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &wins)
            let list = wins as? [AXUIElement] ?? []
            for window in list {
                var sizeValue: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)
                var size = CGSize.zero
                if let sizeValue, CFGetTypeID(sizeValue) == AXValueGetTypeID() {
                    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
                }
                if abs(size.width - match.width) < 8, abs(size.height - match.height) < 8 {
                    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                    return
                }
            }
        }
    }

    private static func click(x: Double, y: Double) {
        let point = CGPoint(x: x, y: y)
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
    }

    private static func move(x: Double, y: Double) {
        let point = CGPoint(x: x, y: y)
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
    }
}

/// Live picture of a browser window that is on another desktop.
/// The panel stays on this desktop, so the button does not switch Spaces.
private final class BrowserMirror: NSObject, SCStreamOutput, @unchecked Sendable {
    var onReady: (@MainActor () -> Void)?
    var onClose: (@MainActor () -> Void)?

    private let windowID: UInt32
    private let crop: NookPictureInPicture.ScreenRect
    private let queue = DispatchQueue(label: "coucou.mirror")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var stream: SCStream?
    private var panel: NSPanel?
    private var imageView: NSImageView?
    private var stopped = false

    init(windowID: UInt32, crop: NookPictureInPicture.ScreenRect) {
        self.windowID = windowID
        self.crop = crop
    }

    func start() {
        Task { await self.begin() }
    }

    func stop() {
        stopped = true
        let stream = self.stream
        self.stream = nil
        panel?.orderOut(nil)
        panel = nil
        if let stream {
            Task { try? await stream.stopCapture() }
        }
    }

    private func begin() async {
        guard !stopped else { return }
        guard CGPreflightScreenCaptureAccess() else {
            await MainActor.run { self.onClose?() }
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                await MainActor.run { self.onClose?() }
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let cropWidth = max(1, crop.right - crop.left)
            let cropHeight = max(1, crop.bottom - crop.top)
            let config = SCStreamConfiguration()
            config.sourceRect = CGRect(x: crop.left, y: crop.top, width: cropWidth, height: cropHeight)
            let longest = max(cropWidth, cropHeight)
            let fit = min(1, 960 / longest)
            config.width = max(2, Int((cropWidth * fit).rounded(.down) / 2) * 2)
            config.height = max(2, Int((cropHeight * fit).rounded(.down) / 2) * 2)
            config.showsCursor = false
            config.capturesAudio = false
            config.minimumFrameInterval = CMTime(value: 1, timescale: 12)
            config.queueDepth = 3
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            guard !stopped else {
                try? await stream.stopCapture()
                return
            }
            self.stream = stream
            await MainActor.run {
                guard !self.stopped else { return }
                self.showPanel(width: cropWidth, height: cropHeight)
                self.onReady?()
            }
        } catch {
            await MainActor.run { self.onClose?() }
        }
    }

    @MainActor
    private func showPanel(width: Double, height: Double) {
        let panelWidth = min(480, width)
        let panelHeight = panelWidth * height / width
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .black
        panel.isOpaque = false
        panel.hasShadow = true
        let imageView = NSImageView()
        imageView.imageScaling = .scaleAxesIndependently
        imageView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        imageView.autoresizingMask = [.width, .height]
        self.imageView = imageView
        let close = NSButton(frame: NSRect(x: panelWidth - 28, y: panelHeight - 28, width: 22, height: 22))
        close.bezelStyle = .inline
        close.isBordered = false
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close picture")
        close.contentTintColor = .white
        close.target = self
        close.action = #selector(closeFromButton)
        close.toolTip = "Closes the floating picture."
        close.setAccessibilityLabel("Close picture")
        let host = NSView(frame: imageView.frame)
        host.addSubview(imageView)
        host.addSubview(close)
        panel.contentView = host
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - panelWidth - 24, y: screen.minY + 80))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    @MainActor
    @objc private func closeFromButton() {
        stop()
        onClose?()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !stopped, let image = image(from: sample) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.imageView?.image = image
        }
    }

    private func image(from sample: CMSampleBuffer) -> NSImage? {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let source = CIImage(cvPixelBuffer: buffer)
        guard let rendered = context.createCGImage(source, from: source.extent) else { return nil }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return NSImage(cgImage: rendered, size: NSSize(width: CGFloat(rendered.width) / scale, height: CGFloat(rendered.height) / scale))
    }
}
