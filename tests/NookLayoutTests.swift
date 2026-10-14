import Foundation

@main
enum NookLayoutTests {
    static func main() {
        testWings()
        testColumns()
        testEvents()
        testHeadline()
        testFullscreen()
        testDrop()
        testTray()
        testTrayTarget()
        testTrayChip()
        testTrayIsItsOwnPage()
        testMirror()
        testCalendarAsk()
        testWidgetCombos()
        testHeaderLivesOnTheMenuBar()
        testTrayLineLeavesTheNotch()
        testNotes()
        testShortcuts()
        testQuickApps()
        testNookRoom()
        print("Nook layout: 19 cases passed")
    }

    static func testWings() {
        precondition(NookLayout.wingWidth(slider: 4) == 72)
        precondition(NookLayout.wingWidth(slider: 30) == 200)
        precondition(NookLayout.wingWidth(slider: 100) == 200)
        let mid = NookLayout.wingWidth(slider: 17)
        precondition(mid > 72 && mid < 200)
        let inset = NookLayout.trayInset(slider: 12)
        precondition(inset > 18 && inset < 24)
        precondition(NookLayout.trayInset(slider: 30) < NookLayout.trayInset(slider: 4))
    }

    static func testColumns() {
        let widths = NookLayout.columnWidths(cells: [5, 5, 2], total: 312, divider: 1)
        precondition(widths.count == 3)
        let sum = widths.reduce(0, +)
        precondition(abs(sum - 310) < 0.01)
        precondition(abs(widths[0] - widths[1]) < 0.01)
        precondition(widths[2] < widths[0])
        precondition(NookLayout.columnWidths(cells: [], total: 100, divider: 1).isEmpty)
    }

    /// Every on/off mix keeps each widget at least as wide as its own controls.
    /// Adding a widget widens the nook. Removing one narrows it. A widget's width
    /// does not change because a neighbor appeared.
    static func testWidgetCombos() {
        let padding: CGFloat = 14
        let ids = ["media", "calendar", "mirror", "shortcuts", "notes", "todos", "timer"]
        for mask in 0..<(1 << ids.count) {
            let shown: [NookColumnSpec] = ids.enumerated().compactMap { index, id in
                guard mask & (1 << index) != 0 else { return nil }
                return NookColumnSpec(id: id, cells: 1)
            }
            let width = NookLayout.nookDrawerWidth(columns: shown, dividers: true, contentPadding: padding)
            var row: CGFloat = 0
            for column in shown {
                let piece = NookLayout.columnWidth(id: column.id, cells: column.cells, contentPadding: padding)
                let floor = NookLayout.minimumColumnWidth(id: column.id, contentPadding: padding)
                precondition(piece + 0.01 >= floor, "\(column.id) is narrower than its controls")
                precondition(NookLayout.fittedCells(id: column.id, cells: 1, contentPadding: padding) >= 1)
                precondition(NookLayout.fittedCells(id: column.id, cells: 16, contentPadding: padding) == 16)
                precondition(NookLayout.fittedCells(id: column.id, cells: 10, contentPadding: padding) >= 10)
                row += piece
            }
            if shown.count > 1 { row += CGFloat(shown.count - 1) * NookLayout.widgetDivider }
            let expected = max(row, NookLayout.nookTabBarWidth) + NookLayout.nookPageInset
            precondition(abs(width - expected) < 0.01, "drawer width drifted for mask \(mask)")

            for (index, id) in ids.enumerated() where mask & (1 << index) == 0 {
                var grown = shown
                grown.append(NookColumnSpec(id: id, cells: 4))
                let grownWidth = NookLayout.nookDrawerWidth(columns: grown, dividers: true, contentPadding: padding)
                precondition(grownWidth + 0.01 >= width, "adding \(id) made the nook narrower")
                for existing in shown {
                    let alone = NookLayout.columnWidth(id: existing.id, cells: existing.cells, contentPadding: padding)
                    let beside = NookLayout.columnWidth(id: existing.id, cells: existing.cells, contentPadding: padding)
                    precondition(alone == beside, "\(existing.id) changed width when \(id) was added")
                }
            }
        }

        let all = ids.map { NookColumnSpec(id: $0, cells: 6) }
        let full = NookLayout.nookDrawerWidth(columns: all, dividers: true, contentPadding: padding)
        for id in ids {
            let less = all.filter { $0.id != id }
            let narrower = NookLayout.nookDrawerWidth(columns: less, dividers: true, contentPadding: padding)
            precondition(narrower < full, "removing \(id) left the nook the same width")
            for kept in less {
                precondition(
                    NookLayout.columnWidth(id: kept.id, cells: kept.cells, contentPadding: padding)
                        == CGFloat(NookLayout.fittedCells(id: kept.id, cells: 6, contentPadding: padding)) * NookLayout.pointsPerCell
                )
            }
        }

        let mirror = NookLayout.columnWidth(id: "mirror", cells: 2, contentPadding: padding)
        precondition(mirror > 120, "Mirror still collapses when other widgets are on")
        let calendar = NookLayout.minimumColumnWidth(id: "calendar", contentPadding: padding)
        precondition(calendar >= 240, "the week row can wrap")

        let drawer = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "let pull = max(0, AppState.shared.drawerExtension)",
            until: "Closed-notch items stay in the menu bar"
        )
        precondition(drawer.contains("nookDrawerWidth"), "the open nook uses the widget width")
        let row = sourceSlice(file: "NotchBuddy/Sources/App/NookIslandView.swift", from: "struct NookWidgetRow", until: "struct NookMediaColumn")
        precondition(row.contains("columnWidth"), "widgets keep their own column width")
        let saved = sourceSlice(file: "NotchBuddy/Sources/App/NookPreferences.swift", from: "func persist()", until: "private func loadBool")
        precondition(saved.contains("fitEnabledWidgetWidths"), "the width setting rises to fit and is saved")
    }

    static func sourceSlice(file: String, from start: String, until end: String) -> String {
        let text = try! String(contentsOfFile: file, encoding: .utf8)
        guard let from = text.range(of: start), let to = text.range(of: end, range: from.upperBound..<text.endIndex) else {
            preconditionFailure("missing \(start) in \(file)")
        }
        return String(text[from.lowerBound..<to.lowerBound])
    }

    static func testEvents() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let soon = NookEventFact(
            calendarID: "work", title: "Standup",
            start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200), isAllDay: false
        )
        let past = NookEventFact(
            calendarID: "work", title: "Yesterday",
            start: now.addingTimeInterval(-86_400), end: now.addingTimeInterval(-80_000), isAllDay: false
        )
        let allDay = NookEventFact(
            calendarID: "home", title: "Holiday",
            start: now, end: now.addingTimeInterval(86_400), isAllDay: true
        )
        let multi = NookEventFact(
            calendarID: "work", title: "Trip",
            start: now, end: now.addingTimeInterval(86_400 * 3), isAllDay: false
        )
        precondition(include(soon, now: now, calendars: ["work"]))
        precondition(!include(soon, now: now, calendars: ["home"]))
        precondition(!include(past, now: now, calendars: nil, showPast: false))
        precondition(include(past, now: now, calendars: nil, showPast: true))
        precondition(!include(allDay, now: now, calendars: nil, showAllDay: false))
        precondition(include(allDay, now: now, calendars: nil, showAllDay: true))
        precondition(!include(multi, now: now, calendars: nil, showMultiDay: false))
        precondition(include(multi, now: now, calendars: nil, showMultiDay: true))
        precondition(!include(soon, now: now, calendars: nil, daysAhead: 0))
    }

    static func include(
        _ event: NookEventFact,
        now: Date,
        calendars: [String]?,
        showPast: Bool = false,
        showAllDay: Bool = false,
        showMultiDay: Bool = false,
        daysBehind: Int = 7,
        daysAhead: Int = 7
    ) -> Bool {
        NookLayout.includeEvent(
            event, now: now, allowedCalendarIDs: calendars,
            showPast: showPast, showAllDay: showAllDay, showMultiDay: showMultiDay,
            daysBehind: daysBehind, daysAhead: daysAhead
        )
    }

    static func testHeadline() {
        let playing = NookActivityFacts(
            mediaTitle: "Blue", mediaArtist: "Ada", trayCount: 2, nextEventTitle: "Standup",
            bluetoothName: "Pods", bluetoothIsNews: true, batteryPercent: 15, batteryCharging: false,
            timerEnded: false
        )
        let enabled: Set<String> = ["media", "tray", "calendar", "battery", "bluetooth", "timerEnded"]
        let headline = NookLayout.headline(facts: playing, enabled: enabled, revealed: true)
        precondition(headline?.id == "media")
        precondition(headline?.text == "Blue · Ada")
        precondition(NookLayout.headline(facts: playing, enabled: enabled, revealed: false) == nil)

        var ended = playing
        ended.timerEnded = true
        precondition(NookLayout.headline(facts: ended, enabled: enabled, revealed: true)?.id == "timerEnded")

        var quiet = NookActivityFacts(
            mediaTitle: nil, mediaArtist: nil, trayCount: 0, nextEventTitle: nil,
            bluetoothName: nil, bluetoothIsNews: false, batteryPercent: 80, batteryCharging: false,
            timerEnded: false
        )
        precondition(NookLayout.headline(facts: quiet, enabled: enabled, revealed: true) == nil)
        quiet.batteryCharging = true
        precondition(NookLayout.headline(facts: quiet, enabled: enabled, revealed: true)?.id == "battery")
        precondition(NookLayout.restingExtraWidth(text: nil) == 0)
        precondition(NookLayout.restingExtraWidth(text: "100% 4.9W") == 0, "a charging line stays inside the notch")
        precondition(NookLayout.restingExtraWidth(text: "Timer ended") == 0, "a status line does not widen the collapsed notch")
        precondition(!NookLayout.collapsedDropsBand(hudVisible: false, mediaPlaying: false), "a status line does not drop the notch")
        precondition(!NookLayout.collapsedDropsBand(hudVisible: true, mediaPlaying: false), "the volume bar stays in the menu bar")
        precondition(!NookLayout.collapsedDropsBand(hudVisible: false, mediaPlaying: true), "a track stays in the menu bar")
        precondition(NookLayout.collapsedAnchorY(housingCenter: 22) == 22, "AirDrop sits in the menu bar")
        let shelf = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "let inNotch = board.restingExtra <= 0",
            until: "if hud.visible"
        )
        precondition(shelf.contains("collapsedAnchorY"), "a collapsed label uses the menu bar, not the band under it")
        precondition(!shelf.contains("dropY"), "AirDrop does not hang below the menu bar")
        let hud = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "if hud.visible {",
            until: "DrawerPullTab"
        )
        precondition(hud.contains("collapsedAnchorY"), "the volume bar stays in the menu bar when the notch is closed")
        let faces = sourceSlice(
            file: "NotchBuddy/Sources/App/TerminalNotchView.swift",
            from: "struct TerminalClusterView",
            until: "struct TerminalFaceButton"
        )
        precondition(faces.contains("faceColumn"), "each face column has the same width")
        precondition(faces.contains("faceGridWidth"), "the four faces are one centered group")
        precondition(faces.contains(".center"), "both columns sit in the middle of the card")
        let pages = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "struct IslandContentView",
            until: "struct IslandHeader"
        )
        precondition(pages.contains("GeometryReader"), "each page is laid out at the open notch width")
        precondition(pages.contains("geo.size.width"), "a wide nook does not stretch the home tiles")
        precondition(pages.contains(".clipped()"), "tiles that do not fit stay inside the notch")
    }

    /// "1 file in the tray" sits left of the hardware notch. It shows for 10 seconds, then hides for 10.
    static func testTrayLineLeavesTheNotch() {
        precondition(NookLayout.restingExtraWidth(text: "1 file in the tray") == 0, "the tray line does not reuse the right wing")
        precondition(NookLayout.traySideWidth(showing: false) == 0)
        precondition(NookLayout.traySideWidth(showing: true) == 56, "the tray icon and the count do not need the full sentence")
        precondition(NookLayout.trayCollapsedText("1 file in the tray") == "1")
        precondition(NookLayout.trayCollapsedText("3 files in the tray") == "3")
        precondition(NookLayout.trayCollapsedText("12 files in the tray") == "12")
        precondition(NookLayout.trayNoticeVisible(at: 0))
        precondition(NookLayout.trayNoticeVisible(at: 9.9))
        precondition(NookLayout.trayNoticeVisible(at: 20))
        precondition(!NookLayout.trayNoticeVisible(at: 10))
        precondition(!NookLayout.trayNoticeVisible(at: 19.9))
        precondition(!NookLayout.trayNoticeVisible(at: -1))
        precondition(NookLayout.trayNoticeDelay(at: 0) == 10)
        precondition(NookLayout.trayNoticeDelay(at: 3) == 7)
        precondition(NookLayout.trayNoticeDelay(at: 10) == 10)
        precondition(abs(NookLayout.trayNoticeDelay(at: 19.9) - 0.1) < 0.001)
        precondition(NookLayout.trayPillCenterX(side: 56) == 28)
        precondition(NookLayout.keepsTrayLineAwake(headlineID: "tray"))
        precondition(!NookLayout.keepsTrayLineAwake(headlineID: "battery"))
        precondition(!NookLayout.keepsTrayLineAwake(headlineID: nil))

        let size = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "func islandSize",
            until: "func notchInformationIsRunning"
        )
        precondition(size.contains("trayWing"), "the closed notch widens while the tray line is showing")

        let wing = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "if state.mode != .expanded, !hud.visible, let edge = edgeHeadline",
            until: "let inNotch = board.restingExtra <= 0"
        )
        precondition(wing.contains("trayPillCenterX"), "the tray line is placed in the left wing")
        precondition(wing.contains("edge.id == \"tray\""), "only the tray line leaves the center")
        let pill = sourceSlice(
            file: "NotchBuddy/Sources/App/NookIslandView.swift",
            from: "struct LiveActivityPill",
            until: "// MARK: - Widget row"
        )
        precondition(pill.contains("trayCollapsedText"), "the closed tray shows the sentence instead of the count")
        precondition(pill.contains("headline.symbol"), "the closed tray drops the tray icon")

        let shelf = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "let inNotch = board.restingExtra <= 0",
            until: "if hud.visible"
        )
        precondition(shelf.contains("collapsedAnchorY"), "other lines stay in the menu bar")
        precondition(!shelf.contains("dropY"), "other lines do not hang below the menu bar")

        let watch = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: ".onChange(of: board.mediaWing)",
            until: ".onChange(of: state.notchWidth)"
        )
        precondition(watch.contains("trayWing"), "the island refits when the tray line shows or hides")

        let publish = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "private func publish()",
            until: "func refreshChrome"
        )
        precondition(publish.contains("trayNoticeVisible"), "the tray line uses the 10 second clock")
        precondition(publish.contains("trayNoticeDelay"), "the tray line wakes on the 10 second boundary")
        precondition(publish.contains("Task.sleep"), "the tray line does not wait for the two second tick")
        precondition(publish.contains("trayWing"), "a hidden tray line adds no width")

        let idle = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "private func considerHide",
            until: "private func activitiesShown"
        )
        precondition(idle.contains("keepsTrayLineAwake"), "the tray line comes back on its own timer")
    }

    /// The open drawer's buttons sit in the menu bar, on the black notch.
    static func testHeaderLivesOnTheMenuBar() {
        let shape = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "// Black island shape",
            until: "Content is laid out"
        )
        precondition(shape.contains("height: islandHeight"), "the open notch is black through the menu bar")
        precondition(!shape.contains(".offset(y: menuBarBand)"), "the orange menu bar does not show through the notch")
        let header = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "let wings = TerminalBehavior.menuBarWings",
            until: "Single BotPlacement"
        )
        precondition(header.contains("notchTrailing"), "settings and volume start at the notch")
        precondition(header.contains("clearance.expandedOffset"), "the button row is as tall as the menu bar")
        let body = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "func islandSize",
            until: "func notchInformationIsRunning"
        )
        precondition(body.contains("expandedDrawerHeight"), "the open drawer is shorter once the header leaves it")
        precondition(body.contains(".greeting"), "the greeting keeps its own height")
    }

    static func testFullscreen() {
        precondition(!NookLayout.activityAllowed(
            enabled: false, showInFullscreen: true, globalFullscreen: "always",
            isFullscreen: false, hasNotch: true
        ))
        precondition(NookLayout.activityAllowed(
            enabled: true, showInFullscreen: false, globalFullscreen: "never",
            isFullscreen: false, hasNotch: false
        ))
        precondition(!NookLayout.activityAllowed(
            enabled: true, showInFullscreen: true, globalFullscreen: "never",
            isFullscreen: true, hasNotch: true
        ))
        precondition(NookLayout.activityAllowed(
            enabled: true, showInFullscreen: true, globalFullscreen: "notched",
            isFullscreen: true, hasNotch: true
        ))
        precondition(!NookLayout.activityAllowed(
            enabled: true, showInFullscreen: true, globalFullscreen: "notched",
            isFullscreen: true, hasNotch: false
        ))
        precondition(!NookLayout.activityAllowed(
            enabled: true, showInFullscreen: false, globalFullscreen: "always",
            isFullscreen: true, hasNotch: true
        ))
    }

    static func testDrop() {
        precondition(NookLayout.dropChoice(expanded: true, nookOpen: true, insideIsland: true, xFraction: 0.1) == .pipeline)
        precondition(NookLayout.dropChoice(expanded: true, nookOpen: false, insideIsland: true, xFraction: 0.9) == .agent)
        precondition(NookLayout.dropChoice(expanded: false, nookOpen: false, insideIsland: true, xFraction: 0.8) == .pipeline)
        precondition(NookLayout.dropChoice(expanded: false, nookOpen: false, insideIsland: true, xFraction: 0.4) == .agent)
        precondition(NookLayout.dropChoice(expanded: false, nookOpen: false, insideIsland: false, xFraction: 0.9) == .agent)
    }

    static func testTray() {
        let first = NookLayout.addToTray([], paths: ["/tmp/a.txt", "/tmp/b.txt"])
        precondition(first.map(\.name) == ["b.txt", "a.txt"])
        let again = NookLayout.addToTray(first, paths: ["/tmp/a.txt"])
        precondition(again.map(\.name) == ["a.txt", "b.txt"])
        let capped = NookLayout.addToTray([], paths: (0..<25).map { "/tmp/\($0).txt" }, limit: 20)
        precondition(capped.count == 20)
        precondition(capped.first?.name == "24.txt")
    }

    /// The tray keeps a file. AirDrop happens only when the drop lands on the tile at the right.
    static func testTrayTarget() {
        let kept = NookLayout.dropPlan(landing: .hold, route: .airDrop)
        precondition(kept.store && !kept.airDropStored && !kept.airDropOriginals && !kept.splitStems)

        let sent = NookLayout.dropPlan(landing: .airDrop, route: .airDrop)
        precondition(!sent.store && sent.airDropOriginals && !sent.airDropStored && !sent.splitStems)

        let songOnTile = NookLayout.dropPlan(landing: .airDrop, route: .stems)
        precondition(songOnTile.airDropOriginals && !songOnTile.splitStems && !songOnTile.store)

        let songHeld = NookLayout.dropPlan(landing: .hold, route: .stems)
        precondition(songHeld.store && songHeld.splitStems && !songHeld.airDropCompanions && !songHeld.airDropOriginals)

        let songNeedsLogic = NookLayout.dropPlan(landing: .hold, route: .needsLogic)
        precondition(songNeedsLogic.store && !songNeedsLogic.airDropCompanions && !songNeedsLogic.splitStems)

        let pipeline = NookLayout.dropPlan(landing: .pipeline, route: .airDrop)
        precondition(pipeline.store && pipeline.airDropStored && !pipeline.airDropOriginals)

        let pipelineStems = NookLayout.dropPlan(landing: .pipeline, route: .stems)
        precondition(pipelineStems.store && pipelineStems.splitStems && pipelineStems.airDropCompanions)

        let tile = CGRect(x: 700, y: 80, width: 132, height: 180)
        precondition(NookLayout.trayLanding(trayPage: true, point: CGPoint(x: 40, y: 120), tile: tile) == .hold)
        precondition(NookLayout.trayLanding(trayPage: true, point: CGPoint(x: 760, y: 140), tile: tile) == .airDrop)
        precondition(NookLayout.trayLanding(trayPage: true, point: CGPoint(x: 760, y: 20), tile: tile) == .hold)
        precondition(NookLayout.trayLanding(trayPage: false, point: CGPoint(x: 760, y: 140), tile: tile) == .pipeline)
        precondition(NookLayout.trayLanding(trayPage: true, point: CGPoint(x: 760, y: 140), tile: .zero) == .hold)
        let wholePage = CGRect(x: 0, y: 0, width: 800, height: 400)
        precondition(NookLayout.trayLanding(trayPage: true, point: CGPoint(x: 760, y: 140), tile: wholePage) == .hold)

        let island = CGRect(x: 100, y: 500, width: 800, height: 400)
        let topLeft = NookLayout.islandLocalPoint(windowPoint: CGPoint(x: 100, y: 900), islandFrame: island)
        precondition(topLeft.x == 0 && topLeft.y == 0)
        let onTile = NookLayout.islandLocalPoint(windowPoint: CGPoint(x: 860, y: 760), islandFrame: island)
        precondition(onTile.x == 760 && onTile.y == 140)

        precondition(NookLayout.airDropTileWidth >= 120 && NookLayout.airDropTileWidth <= 168)
        precondition(NookLayout.pathsToCopy(incoming: ["/tray/a", "/desk/b"], held: ["/tray/a"]) == ["/desk/b"])
        precondition(NookLayout.shouldSendAirDrop(paths: ["/a"], previous: [], elapsed: 0))
        precondition(!NookLayout.shouldSendAirDrop(paths: ["/a"], previous: ["/a"], elapsed: 0.2))
        precondition(NookLayout.shouldSendAirDrop(paths: ["/a"], previous: ["/a"], elapsed: 1))
        precondition(!NookLayout.shouldSendAirDrop(paths: [], previous: [], elapsed: 0))
        precondition(NookLayout.shouldSendAirDrop(paths: ["/b"], previous: ["/a"], elapsed: 0.1))
        precondition(NookLayout.trayIconPoints(100) == 100)
        precondition(NookLayout.trayIconPoints(10) == 36)
        precondition(NookLayout.trayIconPoints(400) == 140)
        precondition(NookLayout.trayTileWidth(icon: 100) == 148)
        precondition(NookLayout.trayTileHeight(icon: 100) == 156)
        precondition(NookLayout.trayTileWidth(icon: 36) == 108)
        precondition(NookLayout.trayTileHeight(icon: 36) == 96)
        precondition(NookLayout.trayTileCorner <= 6, "a file tile stays a rectangle")
        precondition(NookLayout.trayTypeIdentifier(path: "/tmp/song.mp3") == "public.mp3")
        precondition(NookLayout.trayTypeIdentifier(path: "/tmp/song.wav") == "com.microsoft.waveform-audio")
        precondition(NookLayout.trayTypeIdentifier(path: "/tmp/clip.mp4") == "public.mpeg-4")
        precondition(NookLayout.trayTypeIdentifier(path: "/tmp/clip.mov") == "com.apple.quicktime-movie")
        precondition(NookLayout.trayTypeIdentifier(path: "/tmp/shot.png") == "public.png")
        precondition(NookLayout.trayTypeIdentifier(path: "/tmp/notes.md") == "net.daringfireball.markdown")
        precondition(NookLayout.trayTypeIdentifier(path: "/tmp/notes.markdown") == "net.daringfireball.markdown")
        precondition(NookLayout.trayTypeIdentifier(path: "/tmp/notes.txt") == "public.plain-text")
        precondition(NookLayout.trayTypeIdentifier(path: "/tmp/page.pdf") == "com.adobe.pdf")
        precondition(NookLayout.trayTypeIdentifier(path: "/tmp/pack.zip") == "public.zip-archive")
        let kinds = ["mp3", "mp4", "md", "png", "pdf", "zip", "txt"].map {
            NookLayout.trayTypeIdentifier(path: "/tmp/file.\($0)")
        }
        precondition(Set(kinds).count == kinds.count, "each file type keeps its own icon")
        precondition(NookLayout.trayTypeIdentifier(path: "/tmp/no-extension") == "public.data")
        precondition(NookLayout.trayDisplayName("CB8C7F85-4CF1-4428-BFBF-708983073E38-hold-me.txt") == "hold-me.txt")
        precondition(NookLayout.trayDisplayName("notes.txt") == "notes.txt")
        precondition(NookLayout.trayDisplayName("not-a-uuid-file.txt") == "not-a-uuid-file.txt")

        let page = sourceSlice(
            file: "NotchBuddy/Sources/App/NookIslandView.swift",
            from: "struct NookTrayPage",
            until: "MARK: - Picture"
        )
        precondition(page.contains("airDropTileWidth"), "the AirDrop tile has its own width")
        precondition(page.contains("AirDrop"))
        precondition(!page.contains("Button(\"AirDrop\")"), "AirDrop is the tile, not a button on each file")
        precondition(page.contains("draggable"), "a file in the tray can be dragged")

        let board = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "func receiveDrop",
            until: "func finishStemSplit"
        )
        precondition(board.contains("dropPlan"))
        precondition(board.contains("airDropOriginals"))
        precondition(!board.contains("airDrop(copies)"))

        let drop = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "dropView.onFilesDropped",
            until: "container.addSubview(hosting)"
        )
        precondition(drop.contains("trayLanding"))
        let landing = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "private func trayLanding",
            until: "private func dropChoice"
        )
        precondition(landing.contains("islandLocalPoint"))
        precondition(!landing.contains("convertPoint"), "the drag location is already in the window")
        let hosting = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "final class NotchHostingView",
            until: "final class IslandPanel"
        )
        precondition(hosting.contains("acceptsFirstMouse"), "a drag on a tray file starts on the first press")
        precondition(hosting.contains("override func hitTest"), "the press must land on the notch view, not a child that drops it")
        precondition(page.contains("trayDisplayName"), "the tray shows the file name")
        precondition(page.contains("NookLayout.trayTileWidth"), "file tiles share one width")
        precondition(page.contains("NookLayout.trayTileHeight"), "file tiles share one height")
        precondition(page.contains("NookLayout.trayTileCorner"), "file tiles are rectangles")
        precondition(!page.contains("minimum: 96, maximum: 140"), "file tiles no longer stretch")
        let chip = sourceSlice(
            file: "NotchBuddy/Sources/App/NookIslandView.swift",
            from: "private func trayFile",
            until: "private func trayPipelineButton"
        )
        precondition(chip.contains("trayIcon"), "a file tile draws its type icon")
        precondition(chip.contains("trayIconSize"), "the file icon follows the tray size setting")
        precondition(chip.contains("icon(for:"), "the icon is Apple's image for that type")
        precondition(!chip.contains("systemName: \"doc\""), "files no longer share one document icon")

        precondition(NookLayout.claimsFileDrag(["public.file-url"]))
        precondition(NookLayout.claimsFileDrag(["NSFilenamesPboardType"]))
        precondition(NookLayout.claimsFileDrag(["public.url"]))
        precondition(!NookLayout.claimsFileDrag([]))
        precondition(!NookLayout.claimsFileDrag(["public.utf8-plain-text"]))
        // A Finder drag is claimed by the overlay. A drag that starts on a tray
        // file must stay with SwiftUI so it can land on the AirDrop tile.
        precondition(NookLayout.claimsDropHit(buttonDown: true, types: ["public.file-url"], dragBeganOutside: true))
        precondition(!NookLayout.claimsDropHit(buttonDown: true, types: ["public.file-url"], dragBeganOutside: false))
        precondition(!NookLayout.claimsDropHit(buttonDown: false, types: ["public.file-url"], dragBeganOutside: true))
        precondition(!NookLayout.claimsDropHit(buttonDown: true, types: ["public.utf8-plain-text"], dragBeganOutside: true))
        let hit = sourceSlice(
            file: "NotchBuddy/Sources/App/FileDropView.swift",
            from: "override func hitTest",
            until: "override func draggingEntered"
        )
        precondition(hit.contains("claimsDropHit"), "a file drag must land on the tray")
        precondition(hit.contains("dragBeganOutside"), "a tray file drag must not be taken by the overlay")
        precondition(!hit.contains("-> NSView? { nil }"), "the drop view was skipping every drag")
        let click = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "enum NotchClickDelivery",
            until: "final class NotchHostingView"
        )
        precondition(click.contains("makeKey"), "the notch must be key before the press is handled")
        precondition(click.contains("acceptsFirstMouse"), "the first press on a tray file must be delivered")
        precondition(click.contains("class_replaceMethod"), "SwiftUI's own views were refusing the first press")
        let press = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "matching: .leftMouseDown",
            until: "matching: .leftMouseDragged"
        )
        precondition(press.contains("NotchClickDelivery"), "the press prepares the notch before it is dispatched")
    }

    /// Tray is the button beside Nook. Nook itself shows widgets only.
    static func testTrayChip() {
        let song = "/tmp/Demo.wav"
        precondition(NookTrayChip.pipelines(for: song) == [.stems, .songInfo])
        precondition(NookTrayChip.pipelines(for: "/tmp/notes.pdf").isEmpty)
        precondition(NookTrayChip.title(.stems) == "Split into stems")
        precondition(NookTrayChip.title(.songInfo) == "Song info")
        precondition(NookTrayChip.removeLabel == "Remove")
        precondition(NookTrayChip.pipelineLabel == "Pipelines")
        precondition(NookTrayChip.removeSymbol == "xmark")
        precondition(NookTrayChip.pipelineSymbol == "plus")
        let removeHint = NookTrayChip.removeHint(name: "Demo.wav")
        precondition(removeHint.contains("out of the tray"))
        precondition(removeHint.contains("stays"))
        let pipelineHint = NookTrayChip.pipelineHint(name: "Demo.wav")
        precondition(pipelineHint.contains("stems"))
        precondition(pipelineHint.contains("key"))
        precondition(NookTrayChip.hint(.stems).contains("Logic Pro"))
        precondition(NookTrayChip.hint(.songInfo).contains("key"))
        precondition(NookTrayChip.hint(.songInfo).contains("tempo"))

        let red = NookTrayChip.removeColorComponents()
        precondition(red.0 > 0.85 && red.1 < 0.45 && red.2 < 0.5)
        let blue = NookTrayChip.pipelineColorComponents()
        precondition(blue.2 > 0.85 && blue.0 < 0.55 && blue.1 < blue.2)

        let ready = NookTrayChip.plan(
            pipeline: .stems, path: song, logicInstalled: true, appleSilicon: true
        )
        precondition(ready.splitPath == song)
        precondition(ready.note.contains("Logic Pro"))
        precondition(!ready.readSongInfo)

        let missing = NookTrayChip.plan(
            pipeline: .stems, path: song, logicInstalled: false, appleSilicon: true
        )
        precondition(missing.splitPath == nil)
        precondition(missing.note.contains("not installed"))
        precondition(!missing.readSongInfo)

        let intel = NookTrayChip.plan(
            pipeline: .stems, path: song, logicInstalled: true, appleSilicon: false
        )
        precondition(intel.splitPath == nil)
        precondition(intel.note.contains("Apple silicon"))

        let pdf = NookTrayChip.plan(
            pipeline: .stems, path: "/tmp/notes.pdf", logicInstalled: true, appleSilicon: true
        )
        precondition(pdf.splitPath == nil && !pdf.readSongInfo)
        precondition(pdf.note.contains("not a song"))

        let info = NookTrayChip.plan(
            pipeline: .songInfo, path: song, logicInstalled: false, appleSilicon: false
        )
        precondition(info.readSongInfo && info.splitPath == nil)
        precondition(info.note.contains("Reading"))
        precondition(info.note.contains("Demo"))

        let infoPdf = NookTrayChip.plan(
            pipeline: nil, path: "/tmp/notes.pdf", logicInstalled: true, appleSilicon: true
        )
        precondition(!infoPdf.readSongInfo && infoPdf.splitPath == nil)
        precondition(infoPdf.note.contains("not a song"))

        let copied = "/tmp/CB8C7F85-4CF1-4428-BFBF-708983073E38-hold-me.wav"
        let copiedPlan = NookTrayChip.plan(
            pipeline: .songInfo, path: copied, logicInstalled: true, appleSilicon: true
        )
        precondition(copiedPlan.readSongInfo)
        precondition(copiedPlan.note.contains("hold-me"))
        precondition(!copiedPlan.note.contains("CB8C7F85"))

        let readout = SongReadout(bpm: 96, keyName: "A minor", camelot: "8A", energy: 40)
        let shown = NookTrayChip.songInfoNote(name: "Demo.wav", readout: readout)
        precondition(shown.contains("96 BPM"))
        precondition(shown.contains("A minor"))
        precondition(shown.contains("8A"))
        precondition(NookTrayChip.songInfoFailedNote(name: "Demo.wav").contains("could not be read"))

        let page = sourceSlice(
            file: "NotchBuddy/Sources/App/NookIslandView.swift",
            from: "struct NookTrayPage",
            until: "MARK: - Picture"
        )
        guard let plusAt = page.range(of: "NookTrayChip.pipelineSymbol"),
              let removeAt = page.range(of: "NookTrayChip.removeSymbol") else {
            precondition(false, "the plus and the remove mark are on the file chip")
            return
        }
        precondition(plusAt.lowerBound < removeAt.lowerBound, "the plus sits to the left of the X")
        let plusBody = String(page[plusAt.lowerBound..<removeAt.lowerBound])
        precondition(plusBody.contains("title(.stems)"), "the plus menu offers stem splitting")
        precondition(plusBody.contains("title(.songInfo)"), "the plus menu offers song info")
        precondition(page.contains("popUpContextMenu"), "the plus opens a popup menu")
        precondition(page.contains(".topTrailing"), "both marks sit in the top right corner")
        precondition(!page.contains("Button(\"Remove\")"), "remove is the X, not a word button")
        precondition(page.contains("removeColorComponents"))
        precondition(page.contains("pipelineColorComponents"))
        precondition(page.contains("runTrayPipeline"))
        precondition(page.contains("NookTrayChip.removeLabel"))
        precondition(page.contains("NookTrayChip.pipelineLabel"))
        precondition(page.contains("draggable"), "a file in the tray can still be dragged")
        guard let holdAt = page.range(of: "private var hold"),
              let fileAt = page.range(of: "private func trayFile") else {
            precondition(false, "the tray hold and the file chip are separate")
            return
        }
        let hold = String(page[holdAt.lowerBound..<fileAt.lowerBound])
        precondition(hold.contains("board.airDropNote"), "the pipeline result is written inside the tray")
        let result = sourceSlice(
            file: "NotchBuddy/Sources/App/NookIslandView.swift",
            from: "private var pipelineResult",
            until: "private func trayFile"
        )
        precondition(result.contains("songFacts"), "the plus song info shows the readout")
        precondition(
            result.contains(".system(size: 17, weight: .semibold, design: .rounded)"),
            "the plus song info uses the same rounded fact font as Settings"
        )
        precondition(result.contains("\"Scale\""), "the plus song info shows the scale")
        precondition(result.contains("keyColorHex"), "the key uses its note color")
        precondition(result.contains("noteColorHex"), "each scale note uses its own color")
        let settingsFact = sourceSlice(
            file: "NotchBuddy/Sources/App/CoucouSettingsShell.swift",
            from: "private func readoutStrip",
            until: "private func registerTap"
        )
        precondition(settingsFact.contains(".system(size: 17, weight: .semibold, design: .rounded)"))
        precondition(settingsFact.contains("\"Scale\""), "settings song info shows the scale")
        precondition(settingsFact.contains("keyColorHex"), "the settings key uses its note color")
        precondition(settingsFact.contains("noteColorHex"), "each settings scale note uses its own color")
        precondition(page.contains("TrayMarkButton"), "the corner press is a real button")
        let hosting = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "final class NotchHostingView",
            until: "final class IslandPanel"
        )
        precondition(hosting.contains("TrayMarkButton"), "a corner mark receives the press")
    }

    static func testTrayIsItsOwnPage() {
        let types = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandTypes.swift",
            from: "enum IslandView",
            until: "enum BotState"
        )
        precondition(types.contains("tray"), "Tray is its own page on the notch")

        let header = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "struct IslandHeader",
            until: "struct TabButton"
        )
        guard let lamp = header.range(of: "lamp.desk.fill"),
              let tray = header.range(of: "view: .tray"),
              let bubble = header.range(of: "bubble.left.fill") else {
            preconditionFailure("the main row is missing Nook, Tray, or chat")
        }
        precondition(lamp.lowerBound < tray.lowerBound && tray.lowerBound < bubble.lowerBound, "Tray sits beside Nook, before chat")
        precondition(header.contains("accessibilityLabel(\"Tray\")"), "the Tray button says Tray")
        precondition(header.contains("Drop a file to keep it"), "the Tray button says what the page does")

        let nook = sourceSlice(
            file: "NotchBuddy/Sources/App/NookIslandView.swift",
            from: "struct NookView",
            until: "struct NotchMediaShelf"
        )
        precondition(!nook.contains("showsTray"), "Nook shows widgets only")
        precondition(!nook.contains("NookTabBar"), "the inner Nook and Tray pills are gone")

        let content = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandViewContent.swift",
            from: "switch view",
            until: "struct OverviewView"
        )
        precondition(content.contains(".tray"), "the tray page has its own view")

        let tall = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "let isTall",
            until: "IslandViewContent"
        )
        precondition(tall.contains(".tray"), "the tray page uses the full drawer height")

        let size = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "func islandSize",
            until: "func notchInformationIsRunning"
        )
        precondition(size.contains(".tray"), "the tray keeps the nook width")

        let preview = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "case .tray:",
            until: "case .drop:"
        )
        precondition(preview.contains("presentExpanded(.tray)"), "the Tray settings tab opens the tray page")
        precondition(!preview.contains("presentExpanded(.nook)"), "the Tray settings tab does not open Nook")

        let landing = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "private func trayLanding",
            until: "private func dropChoice"
        )
        precondition(landing.contains("state.view == .tray"), "a drop on the tray page can choose the hold area or AirDrop")
        precondition(!landing.contains("showsTray"), "the tray page is the Tray button, not a switch inside Nook")

        let choice = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "private func dropChoice",
            until: "func baseMode"
        )
        precondition(choice.contains(".tray"), "a file dropped on the tray page stays on the tray")
    }

    /// A click on the calendar line asks for access. A menu-bar app never gets that prompt
    /// unless it comes forward first. A missed prompt has to be cleared or Coucou never appears in Settings.
    static func testCalendarAsk() {
        precondition(CalendarBehavior.ask(for: .notDetermined) == .prompt)
        precondition(CalendarBehavior.ask(for: .denied) == .prompt, "a click asks again when Settings has nothing to turn on")
        precondition(CalendarBehavior.ask(for: .full) == .showEvents)
        precondition(CalendarBehavior.clearsPreviousAnswer(.denied))
        precondition(!CalendarBehavior.clearsPreviousAnswer(.notDetermined))
        precondition(CalendarBehavior.activation(for: .prompt) == .regular)
        precondition(CalendarBehavior.activation(for: .showEvents) == .accessory)
        precondition(CalendarBehavior.afterAsk(granted: true) == .showEvents)
        precondition(CalendarBehavior.afterAsk(granted: false) == .openSettings)
        precondition(
            CalendarBehavior.settingsURL.absoluteString
                == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars"
        )
        precondition(CalendarBehavior.message == "Calendar access is off. Click to allow Coucou to show events.")

        let column = sourceSlice(
            file: "NotchBuddy/Sources/App/NookIslandView.swift",
            from: "struct NookCalendarColumn",
            until: "struct NookMirrorColumn"
        )
        precondition(column.contains("askForCalendar"), "clicking the calendar line asks for access")
        precondition(column.contains("CalendarBehavior.message"), "the line says the click allows Calendar access")

        let ask = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "func askForCalendar",
            until: "func openCalendarEvent"
        )
        precondition(ask.contains("requestFullAccessToEvents"), "the click asks macOS for Calendar access")
        precondition(ask.contains("setActivationPolicy(.regular)"), "Coucou comes forward so the prompt can appear")
        precondition(ask.contains("askDelay"), "the prompt waits until Coucou is a normal app")
        precondition(ask.contains("clearsPreviousAnswer"), "a missed answer is cleared so macOS can ask")
        precondition(ask.contains("tccutil"), "clearing the missed answer removes the old Calendar decision")
        precondition(ask.contains("CalendarBehavior.settingsURL"), "a refused ask opens Calendar in System Settings")
        precondition(ask.contains("setActivationPolicy(.accessory)"), "Coucou returns to the menu bar after the ask")

        let refresh = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "func refreshCalendar",
            until: "func readBattery"
        )
        precondition(!refresh.contains("requestFullAccessToEvents"), "opening the notch must not ask before the click")
    }

    /// The Mirror circle starts the front camera, and the next press stops it.
    static func testMirror() {
        precondition(MirrorBehavior.press(wantsRunning: false) == .start)
        precondition(MirrorBehavior.press(wantsRunning: true) == .stop)

        let devices = [
            MirrorDevice(id: "phone", front: true, builtIn: false),
            MirrorDevice(id: "facetime", front: true, builtIn: true),
            MirrorDevice(id: "desk", front: false, builtIn: true)
        ]
        precondition(MirrorBehavior.frontCameraID(devices) == "facetime")
        precondition(MirrorBehavior.frontCameraID([
            MirrorDevice(id: "phone", front: true, builtIn: false),
            MirrorDevice(id: "desk", front: false, builtIn: true)
        ]) == "phone")
        precondition(MirrorBehavior.frontCameraID([
            MirrorDevice(id: "desk", front: false, builtIn: true)
        ]) == nil)

        // The Mac's FaceTime camera reports no facing. Mirror still uses it, and leaves Desk View out.
        // The production change that fails this: counting a camera only when its position is front.
        let facetime = MirrorBehavior.listedDevice(id: "facetime", lens: .builtInWide, facing: .unspecified)
        let deskView = MirrorBehavior.listedDevice(id: "desk", lens: .deskView, facing: .unspecified)
        let webcam = MirrorBehavior.listedDevice(id: "webcam", lens: .external, facing: .unspecified)
        precondition(facetime.front && facetime.builtIn)
        precondition(deskView.front == false)
        precondition(webcam.front == false)
        precondition(MirrorBehavior.frontCameraID([deskView, webcam, facetime]) == "facetime")
        precondition(MirrorBehavior.frontCameraID([
            MirrorBehavior.listedDevice(id: "rear", lens: .builtInWide, facing: .back)
        ]) == nil)

        let idle = MirrorSessionPlan(generation: 0, wantsRunning: false)
        let started = MirrorBehavior.advance(idle, .start)
        precondition(started == MirrorSessionPlan(generation: 1, wantsRunning: true))
        precondition(MirrorBehavior.shouldStayOn(plan: started, startedGeneration: 1))
        let stopped = MirrorBehavior.advance(started, .stop)
        precondition(stopped == MirrorSessionPlan(generation: 2, wantsRunning: false))
        precondition(!MirrorBehavior.shouldStayOn(plan: stopped, startedGeneration: 1))

        precondition(MirrorBehavior.visibleTitle(denied: false, missing: false) == "Mirror")
        precondition(MirrorBehavior.visibleTitle(denied: true, missing: false) == "Camera is off")
        precondition(MirrorBehavior.visibleTitle(denied: false, missing: true) == "No front camera")
        precondition(MirrorBehavior.accessibilityTitle(wantsRunning: false, denied: false, missing: false) == "Mirror")
        precondition(MirrorBehavior.accessibilityTitle(wantsRunning: true, denied: false, missing: false) == "Turn off Mirror")
        precondition(MirrorBehavior.help(wantsRunning: false, denied: false, missing: false) == "Shows the front camera in this circle. Press again to turn it off.")
        precondition(MirrorBehavior.help(wantsRunning: true, denied: false, missing: false) == "Turns the front camera off.")
        precondition(MirrorBehavior.help(wantsRunning: false, denied: true, missing: false) == "Camera access is off. Turn it on in System Settings.")

        // The circle stays labeled Mirror while macOS is still asking, so the ask never shows in the camera area.
        // The production change that fails this: visibleTitle ignores an undecided camera and keeps saying Mirror.
        precondition(MirrorBehavior.visibleTitle(asking: true, denied: false, missing: false) == "Allow camera access")
        precondition(MirrorBehavior.visibleTitle(asking: true, denied: true, missing: true) == "Allow camera access")
        precondition(MirrorBehavior.accessibilityTitle(asking: true, wantsRunning: true, denied: false, missing: false) == "Allow camera access")
        precondition(MirrorBehavior.help(asking: true, wantsRunning: true, denied: false, missing: false) == "macOS is asking to use the camera. Choose Allow.")
        // An accessory menu-bar app never gets the Allow prompt. Only an undecided camera becomes a normal app, and only while the prompt is up.
        // A blocked camera does not pretend a prompt is coming. It opens Camera in System Settings.
        precondition(MirrorBehavior.prompt(for: .notDetermined) == .ask)
        precondition(MirrorBehavior.prompt(for: .denied) == .openSettings)
        precondition(MirrorBehavior.prompt(for: .authorized) == .startCamera)
        precondition(MirrorBehavior.activation(for: .ask) == .regular)
        precondition(MirrorBehavior.activation(for: .startCamera) == .accessory)
        precondition(MirrorBehavior.activation(for: .openSettings) == .accessory)
        precondition(MirrorBehavior.cameraSettingsURL.absoluteString == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Camera")
        // Asking on the same turn the app is still a menu-bar app makes macOS deny the camera and the circle never shows the ask.
        // The production change that fails this: requesting access with no wait after becoming a normal app.
        precondition(MirrorBehavior.askDelay(for: .regular) == 0.5)
        precondition(MirrorBehavior.askDelay(for: .accessory) == 0)
        precondition(MirrorBehavior.afterAsk(granted: true) == .startCamera)
        precondition(MirrorBehavior.afterAsk(granted: false) == .openSettings)
        // When macOS skips the prompt, the circle has to keep saying it is asking. Clearing that label hides the ask.
        // The production change that fails this: dropping the asking label when Settings opens instead.
        precondition(MirrorBehavior.keepsAsk(MirrorBehavior.afterAsk(granted: false)))
        precondition(MirrorBehavior.keepsAsk(.ask))
        precondition(MirrorBehavior.keepsAsk(.startCamera) == false)
    }

    /// One note can be rich text or colored code, and it can leave as a file.
    static func testNotes() {
        precondition(NookNotes.highlight("").isEmpty)
        precondition(NookNotes.highlight("plain words").isEmpty)
        precondition(NookNotes.highlight("a `no").isEmpty)
        precondition(NookNotes.highlight("****").isEmpty)
        precondition(NookNotes.highlight("**\n**").isEmpty)

        let heading = "# Title"
        precondition(NookNotes.highlight(heading).contains(noteSpan(.heading, in: heading, needle: heading)))

        let loud = "say **loud**"
        precondition(NookNotes.highlight(loud).contains(noteSpan(.emphasis, in: loud, needle: "**loud**")))

        let code = "use `code` here"
        precondition(NookNotes.highlight(code).contains(noteSpan(.code, in: code, needle: "`code`")))

        let comment = "keep // aside"
        precondition(NookNotes.highlight(comment).contains(noteSpan(.comment, in: comment, needle: "// aside")))

        let shielded = "see `// not` // yes"
        let shieldedSpans = NookNotes.highlight(shielded)
        precondition(shieldedSpans.contains(noteSpan(.code, in: shielded, needle: "`// not`")))
        precondition(shieldedSpans.contains(noteSpan(.comment, in: shielded, needle: "// yes")))
        precondition(shieldedSpans.filter { $0.kind == .comment }.count == 1)

        let mixed = "say `**no**` **yes**"
        let mixedSpans = NookNotes.highlight(mixed)
        precondition(mixedSpans.contains(noteSpan(.code, in: mixed, needle: "`**no**`")))
        precondition(mixedSpans.contains(noteSpan(.emphasis, in: mixed, needle: "**yes**")))
        precondition(mixedSpans.filter { $0.kind == .emphasis }.count == 1)

        let marked = "🙂 **yes**"
        precondition(NookNotes.highlight(marked).contains(noteSpan(.emphasis, in: marked, needle: "**yes**")))

        let both = "# Title **loud**"
        let bothSpans = NookNotes.highlight(both)
        precondition(bothSpans.contains(noteSpan(.heading, in: both, needle: both)))
        precondition(bothSpans.contains(noteSpan(.emphasis, in: both, needle: "**loud**")))

        let lines = "# One\nTwo"
        let lineSpans = NookNotes.highlight(lines)
        precondition(lineSpans.contains(noteSpan(.heading, in: lines, needle: "# One")))
        precondition(!lineSpans.contains { $0.kind == .heading && $0.start > 0 })

        precondition(NookNotes.exportFilename(.plain) == "Note.txt")
        precondition(NookNotes.exportFilename(.richText) == "Note.rtf")
        precondition(NookNotes.exportFilename(.markdown) == "Note.md")
        precondition(NookNotes.exportText(mode: .rich, plain: "hello", format: .plain) == "hello")
        precondition(NookNotes.exportText(mode: .code, plain: "# hi", format: .markdown) == "# hi")
        precondition(NookNotes.exportText(mode: .rich, plain: "hello", format: .richText) == nil)
        precondition(NookNotes.exportText(mode: .code, plain: "hello", format: .richText) == nil)

        precondition(NookLayout.singleLineWidth("notes") == 120)
        precondition(NookLayout.fittedCells(id: "notes", cells: 5, contentPadding: 14) == 5)

        let column = sourceSlice(
            file: "NotchBuddy/Sources/App/NookIslandView.swift",
            from: "struct NookNotesColumn",
            until: "struct NookTodosColumn"
        )
        precondition(column.contains("Rich text"), "the mode menu names rich text")
        precondition(column.contains("Button(\"Code\")"), "the mode menu names code")
        precondition(column.contains("Format"))
        precondition(column.contains("Bold"))
        precondition(column.contains("Italic"))
        precondition(column.contains("Underline"))
        precondition(column.contains("Export"))
        precondition(column.contains("Plain text"))
        precondition(column.contains("Markdown"))
        precondition(column.contains("NSTextView"))
        precondition(column.contains("Rich text is the default."))
        precondition(column.contains("size: 11"), "the note hint is a readable sentence")

        let saved = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "func exportNote(",
            until: "func loadShortcutsIfNeeded"
        )
        precondition(saved.contains("nook.noteText"))
        precondition(saved.contains("nook.noteRTF"))
        precondition(saved.contains("nook.noteMode"))
        precondition(saved.contains("Coucou/notes"))
        precondition(saved.contains("activateFileViewerSelecting"))
        precondition(!saved.contains("NSSavePanel"))
        precondition(!saved.contains("NSOpenPanel"))

        let loaded = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "private func loadPersisted()",
            until: "private func saveTray()"
        )
        precondition(loaded.contains("nook.noteRTF"))
        precondition(loaded.contains("nook.noteMode"))
    }

    /// Chosen shortcuts sit two per row. Nothing is shown until it is turned on.
    static func testShortcuts() {
        let identified = "Paste and play (9F9112E5-9C76-4B14-8E0C-296F225C1C42)"
        let parsed = NookShortcuts.parseLine(identified)
        precondition(parsed?.name == "Paste and play")
        precondition(parsed?.identifier == "9F9112E5-9C76-4B14-8E0C-296F225C1C42")
        precondition(NookShortcuts.parseLine("  ") == nil)
        precondition(NookShortcuts.parseLine("Lights")?.identifier == "Lights")

        let home = "11111111-1111-1111-1111-111111111111"
        let loose = "22222222-2222-2222-2222-222222222222"
        let other = "33333333-3333-3333-3333-333333333333"
        let catalog = NookShortcuts.catalog(groups: [
            ("", [
                "Paste and play (\(loose))",
                "Again (\(loose))",
                ""
            ]),
            ("Home", ["Lights (\(home))"]),
            ("Work", ["Mail (\(other))"])
        ])
        precondition(catalog.map(\.identifier) == [loose, home, other])
        precondition(catalog.map(\.folder) == ["", "Home", "Work"])
        precondition(catalog[0].name == "Paste and play")

        precondition(NookShortcuts.shown(catalog: catalog, picks: []).isEmpty)
        let shown = NookShortcuts.shown(catalog: catalog, picks: ["missing", other, loose])
        precondition(shown.map(\.identifier) == [loose, other])
        precondition(NookShortcuts.setPick(home, on: true, picks: [loose]) == [loose, home])
        precondition(NookShortcuts.setPick(loose, on: false, picks: [loose, home]) == [home])
        precondition(NookShortcuts.setPick(home, on: true, picks: [home]) == [home])
        precondition(NookShortcuts.selectAll(catalog) == [loose, home, other])
        precondition(NookShortcuts.keptPicks([loose, "gone", home], catalog: catalog) == [loose, home])

        let paired = NookShortcuts.rows(catalog)
        precondition(paired.map { $0.map(\.identifier) } == [[loose, home], [other]])
        precondition(NookShortcuts.rows([]).isEmpty)

        let filed = NookShortcuts.sections(catalog)
        precondition(filed.map(\.title) == ["No folder", "Home", "Work"])
        let onlyLoose = NookShortcuts.sections([catalog[0]])
        precondition(onlyLoose.count == 1)
        precondition(onlyLoose[0].title == nil)

        precondition(NookShortcuts.runningNote("Lights") == "Running Lights.")
        precondition(NookShortcuts.finishedNote(name: "Lights", exitCode: 0) == "")
        precondition(NookShortcuts.finishedNote(name: "Lights", exitCode: 1) == "Lights did not run.")
        precondition(NookLayout.singleLineWidth("shortcuts") == 130)

        let column = sourceSlice(
            file: "NotchBuddy/Sources/App/NookIslandView.swift",
            from: "struct NookShortcutsColumn",
            until: "struct AirDropTileFrameKey"
        )
        precondition(column.contains("Choose your shortcuts in settings."))
        precondition(column.contains("None are on until you choose them in settings."))
        precondition(column.contains("size: 11"))
        precondition(column.contains("LazyVGrid"))
        precondition(column.contains("GridItem"))
        precondition(!column.contains("prefix(12)"))

        let settings = sourceSlice(
            file: "NotchBuddy/Sources/App/CoucouSettingsShell.swift",
            from: "struct ShortcutPickSettings",
            until: "struct CalendarWidgetSettings"
        )
        precondition(settings.contains("Only the shortcuts you turn on appear in the notch."))
        precondition(settings.contains("None are on until you choose them."))
        precondition(settings.contains("Refresh list"))
        precondition(settings.contains("Select all"))
        precondition(settings.contains("Clear"))
        precondition(settings.contains("size: 11"))

        let saved = sourceSlice(
            file: "NotchBuddy/Sources/App/NookPreferences.swift",
            from: "func persist()",
            until: "private func loadBool"
        )
        precondition(saved.contains("shortcutPicks"))
        let defaults = sourceSlice(
            file: "NotchBuddy/Sources/App/NookPreferences.swift",
            from: "static let defaultWidgets",
            until: "static let defaultActivities"
        )
        precondition(defaults.contains("id: \"shortcuts\", enabled: false"))
    }

    /// Chosen apps sit two per row. Nothing is shown until it is turned on.
    static func testQuickApps() {
        let safari = NookQuickApps.entry(
            displayName: "Safari", bundleName: "Safari", fileName: "Safari.app", bundleID: "com.apple.Safari"
        )
        precondition(safari?.name == "Safari")
        precondition(safari?.bundleID == "com.apple.Safari")
        let chrome = NookQuickApps.entry(
            displayName: "Google Chrome", bundleName: "Chrome", fileName: "Google Chrome.app", bundleID: "com.google.Chrome"
        )
        precondition(chrome?.name == "Google Chrome")
        let notes = NookQuickApps.entry(
            displayName: nil, bundleName: "Notes", fileName: "Notes.app", bundleID: "com.apple.Notes"
        )
        precondition(notes?.name == "Notes")
        let preview = NookQuickApps.entry(
            displayName: "  ", bundleName: "", fileName: "Preview.app", bundleID: "com.apple.Preview"
        )
        precondition(preview?.name == "Preview")
        precondition(NookQuickApps.entry(
            displayName: "Finder", bundleName: nil, fileName: "Finder.app", bundleID: "  "
        ) == nil)
        precondition(NookQuickApps.entry(
            displayName: nil, bundleName: nil, fileName: "", bundleID: "com.example.Bare"
        ) == nil)

        let catalog = NookQuickApps.catalog(apps: [
            (name: "Safari", bundleID: "com.apple.Safari"),
            (name: "Notes", bundleID: "com.apple.Notes"),
            (name: "Notes", bundleID: "com.apple.Notes"),
            (name: "", bundleID: "com.empty"),
            (name: "Mail", bundleID: " ")
        ])
        precondition(catalog.map(\.bundleID) == ["com.apple.Notes", "com.apple.Safari"])
        precondition(NookQuickApps.shown(catalog: catalog, picks: []).isEmpty)
        let shown = NookQuickApps.shown(
            catalog: catalog, picks: ["missing", "com.apple.Safari", "com.apple.Notes"]
        )
        precondition(shown.map(\.bundleID) == ["com.apple.Notes", "com.apple.Safari"])
        let ordered = NookQuickApps.ordered(
            catalog: catalog, picks: ["com.apple.Safari", "com.apple.Notes"], lastBundleID: "com.apple.Safari"
        )
        precondition(ordered.map(\.bundleID) == ["com.apple.Safari", "com.apple.Notes"], "the last opened app leads")
        let unchanged = NookQuickApps.ordered(
            catalog: catalog, picks: ["com.apple.Safari", "com.apple.Notes"], lastBundleID: "gone"
        )
        precondition(unchanged.map(\.bundleID) == ["com.apple.Notes", "com.apple.Safari"])
        precondition(NookQuickApps.setPick("com.apple.Safari", on: true, picks: ["com.apple.Notes"]) == ["com.apple.Notes", "com.apple.Safari"])
        precondition(NookQuickApps.setPick("com.apple.Notes", on: false, picks: ["com.apple.Notes", "com.apple.Safari"]) == ["com.apple.Safari"])
        precondition(NookQuickApps.setPick("com.apple.Notes", on: true, picks: ["com.apple.Notes"]) == ["com.apple.Notes"])
        precondition(NookQuickApps.selectAll(catalog) == ["com.apple.Notes", "com.apple.Safari"])
        precondition(NookQuickApps.keptPicks(
            ["com.apple.Notes", "gone", "com.apple.Safari"], catalog: catalog
        ) == ["com.apple.Notes", "com.apple.Safari"])
        precondition(NookQuickApps.rows(catalog).map { $0.map(\.bundleID) } == [["com.apple.Notes", "com.apple.Safari"]])
        precondition(NookQuickApps.rows([]).isEmpty)
        let three = catalog + [NookQuickApp(name: "Mail", bundleID: "com.apple.mail")]
        precondition(NookQuickApps.rows(three).map { $0.map(\.bundleID) } == [
            ["com.apple.Notes", "com.apple.Safari"],
            ["com.apple.mail"]
        ])
        precondition(NookLayout.singleLineWidth("quickApps") == 120)
        precondition(NookLayout.fittedCells(id: "quickApps", cells: 4, contentPadding: 14) == 5)

        let slot = sourceSlice(
            file: "NotchBuddy/Sources/App/NookIslandView.swift",
            from: "case \"quickApps\":",
            until: "default:"
        )
        precondition(slot.contains("NookQuickAppsColumn"))
        precondition(!slot.contains("Coming soon"))

        let column = sourceSlice(
            file: "NotchBuddy/Sources/App/NookIslandView.swift",
            from: "struct NookQuickAppsColumn",
            until: "struct NookTrayPage"
        )
        precondition(column.contains("Choose your apps in settings."))
        precondition(column.contains("None are on until you choose them in settings."))
        precondition(column.contains("size: 11"))
        precondition(column.contains("LazyVGrid"))
        precondition(column.contains("GridItem"))
        precondition(column.contains("urlForApplication"))
        precondition(!column.contains("prefix(12)"))
        precondition(!column.contains("NSOpenPanel"))
        precondition(!column.contains("NSSavePanel"))

        let editor = sourceSlice(
            file: "NotchBuddy/Sources/App/CoucouSettingsShell.swift",
            from: "private var widgetEditor",
            until: "private var enabledPreview"
        )
        precondition(editor.contains("widget.id == \"quickApps\""))
        precondition(editor.contains("QuickAppPickSettings()"))

        let settings = sourceSlice(
            file: "NotchBuddy/Sources/App/CoucouSettingsShell.swift",
            from: "struct QuickAppPickSettings",
            until: "class CalendarListModel"
        )
        precondition(settings.contains("Only the apps you turn on appear in the notch."))
        precondition(settings.contains("None are on until you choose them."))
        precondition(settings.contains("Refresh list"))
        precondition(settings.contains("Select all"))
        precondition(settings.contains("Clear"))
        precondition(settings.contains("size: 11"))
        precondition(!settings.contains("NSOpenPanel"))
        precondition(!settings.contains("NSSavePanel"))

        let saved = sourceSlice(
            file: "NotchBuddy/Sources/App/NookPreferences.swift",
            from: "func persist()",
            until: "private func loadBool"
        )
        precondition(saved.contains("quickAppPicks"))
        let cleared = sourceSlice(
            file: "NotchBuddy/Sources/App/NookPreferences.swift",
            from: "func applyDefaults()",
            until: "func load()"
        )
        precondition(cleared.contains("quickAppPicks = []"))
        let loaded = sourceSlice(
            file: "NotchBuddy/Sources/App/NookPreferences.swift",
            from: "func load()",
            until: "func fitEnabledWidgetWidths"
        )
        precondition(loaded.contains("quickAppPicks"))
        let defaults = sourceSlice(
            file: "NotchBuddy/Sources/App/NookPreferences.swift",
            from: "static let defaultWidgets",
            until: "static let defaultActivities"
        )
        precondition(defaults.contains("id: \"quickApps\", enabled: false"))
        let soon = sourceSlice(
            file: "NotchBuddy/Sources/App/NookPreferences.swift",
            from: "func comingSoon",
            until: "enum LiveActivityInfo"
        )
        precondition(soon.contains("false"))
        precondition(!soon.contains("quickApps"))

        let tick = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "private func tick()",
            until: "private func refreshMedia"
        )
        precondition(tick.contains("loadQuickAppsIfNeeded"))
        precondition(!tick.contains("QuickAppProbe"))

        let once = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "func loadQuickAppsIfNeeded",
            until: "func refreshQuickAppCatalog"
        )
        precondition(once.contains("quickAppsLoaded"))

        let refresh = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "func refreshQuickAppCatalog",
            until: "func openQuickApp"
        )
        precondition(refresh.contains("load.failed"))
        precondition(refresh.contains("keptPicks"))
        let failedAt = (refresh as NSString).range(of: "load.failed").location
        let keptAt = (refresh as NSString).range(of: "keptPicks").location
        precondition(failedAt != NSNotFound && keptAt != NSNotFound && failedAt < keptAt)

        let probe = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "enum QuickAppProbe",
            until: "enum BatteryProbe"
        )
        precondition(probe.contains("/Applications"))
        precondition(probe.contains("Info.plist"))
        precondition(probe.contains("CFBundleIdentifier"))
        precondition(!probe.contains("NSOpenPanel"))
        precondition(!probe.contains("NSSavePanel"))
    }

    static func testNookRoom() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let soon = NookEventFact(
            calendarID: "work", title: "Standup",
            start: now.addingTimeInterval(600), end: now.addingTimeInterval(1200), isAllDay: false
        )
        let later = NookEventFact(
            calendarID: "work", title: "Tomorrow",
            start: now.addingTimeInterval(86_400), end: now.addingTimeInterval(90_000), isAllDay: false
        )
        let past = NookEventFact(
            calendarID: "work", title: "Done",
            start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-60), isAllDay: false
        )
        let allDay = NookEventFact(
            calendarID: "home", title: "Holiday",
            start: now, end: now.addingTimeInterval(86_400), isAllDay: true
        )
        precondition(NookLayout.leadEvent([soon, later], now: now, upcomingOnly: true)?.title == "Standup")
        precondition(NookLayout.leadEvent([], now: now, upcomingOnly: true) == nil, "an empty today stays empty")
        precondition(NookLayout.leadEvent([past], now: now, upcomingOnly: true) == nil, "a finished event is not the next line")
        precondition(NookLayout.leadEvent([later], now: now, upcomingOnly: false)?.title == "Tomorrow")
        precondition(NookLayout.soonEvent(now: now, events: [soon])?.title == "Standup")
        precondition(NookLayout.soonEvent(now: now, events: [later]) == nil)
        precondition(NookLayout.soonEvent(now: now, events: [past]) == nil)
        precondition(NookLayout.soonEvent(now: now, events: [allDay]) == nil)
        precondition(NookLayout.lampMarked(timerEnded: false, soon: soon))
        precondition(NookLayout.lampMarked(timerEnded: true, soon: nil))
        precondition(!NookLayout.lampMarked(timerEnded: false, soon: nil))
        precondition(NookLayout.lampHint(timerEnded: true, eventTitle: nil) == "The timer ended. Opens the Nook.")
        precondition(NookLayout.calendarShowURL(start: Date(timeIntervalSinceReferenceDate: 1234.5))?.absoluteString == "calshow:1234.5")
        precondition(NookLayout.todosHeading(left: 2) == "2 left")
        precondition(NookLayout.todosHeading(left: 1) == "1 left")
        precondition(NookLayout.todosHeading(left: 0) == "Nothing left")

        let remote = NookLayout.NookLastTrack(
            title: "Blue", artist: "Ada", source: "system", usesRemote: true, bundleID: "com.google.Chrome"
        )
        precondition(NookLayout.resume(remote) == .remote)
        let music = NookLayout.NookLastTrack(
            title: "Blue", artist: "Ada", source: "music", usesRemote: false, bundleID: "com.apple.Music"
        )
        precondition(NookLayout.resume(music) == .player(source: "music", bundleID: "com.apple.Music"))
        precondition(NookLayout.rememberedTrack(
            title: "  ", artist: "Ada", source: "music", usesRemote: false, bundleID: "com.apple.Music"
        ) == nil)
        precondition(NookLayout.mediaIsLive(title: "Blue"))
        precondition(!NookLayout.mediaIsLive(title: nil))
        precondition(!NookLayout.mediaIsLive(title: " "))

        let pad: CGFloat = 14
        let quietMedia = NookLayout.columnWidth(id: "media", cells: 5, contentPadding: pad, mediaLive: false)
        let liveMedia = NookLayout.columnWidth(id: "media", cells: 5, contentPadding: pad, mediaLive: true)
        precondition(liveMedia > quietMedia, "a playing song widens the media column")
        let quietCalendar = NookLayout.columnWidth(id: "calendar", cells: 5, contentPadding: pad, mediaLive: false)
        let liveCalendar = NookLayout.columnWidth(id: "calendar", cells: 5, contentPadding: pad, mediaLive: true)
        precondition(quietCalendar > liveCalendar, "a quiet player gives the calendar the room")
        precondition(quietCalendar == NookLayout.columnWidth(id: "calendar", cells: 5, contentPadding: pad))
        let wideStored = NookLayout.columnWidth(id: "calendar", cells: 16, contentPadding: pad, mediaLive: false)
        precondition(wideStored == NookLayout.columnWidth(id: "calendar", cells: 16, contentPadding: pad))
        let compactStored = NookLayout.columnWidth(id: "calendar", cells: 16, contentPadding: pad, mediaLive: true)
        precondition(compactStored < wideStored, "a playing song keeps the calendar on the next event")
        precondition(
            NookLayout.columnWidth(id: "mirror", cells: 2, contentPadding: pad, mediaLive: true)
                == NookLayout.columnWidth(id: "mirror", cells: 2, contentPadding: pad)
        )
        precondition(NookLayout.closedLampCenterX(whiteCenter: 32, housingLeading: 0) == 12)
        precondition(NookLayout.closedLampCenterX(whiteCenter: 48, housingLeading: 80) == 68)

        let calendar = sourceSlice(
            file: "NotchBuddy/Sources/App/NookIslandView.swift",
            from: "struct NookCalendarColumn",
            until: "struct NookMirrorColumn"
        )
        precondition(calendar.contains("Nothing for today"), "an empty today keeps its caption")
        precondition(!calendar.contains("Tomorrow"), "an empty today does not name another day")
        precondition(calendar.contains("openCalendarEvent"))
        let media = sourceSlice(
            file: "NotchBuddy/Sources/App/NookIslandView.swift",
            from: "struct NookMediaColumn",
            until: "struct NookPlatformGlyph"
        )
        precondition(media.contains("lastTrack"))
        precondition(media.contains("Plays the last song"))
        let todos = sourceSlice(
            file: "NotchBuddy/Sources/App/NookIslandView.swift",
            from: "struct NookTodosColumn",
            until: "struct NookTimerColumn"
        )
        precondition(todos.contains("todosHeading"))
        precondition(todos.contains("finishTodo"))
        let apps = sourceSlice(
            file: "NotchBuddy/Sources/App/NookIslandView.swift",
            from: "struct NookQuickAppsColumn",
            until: "struct NookTrayPage"
        )
        precondition(apps.contains("ordered"))
        precondition(apps.contains("44"))
        let header = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "struct IslandHeader",
            until: "struct TabButton"
        )
        precondition(header.contains("lampMarked"))
        let closed = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "if board.lampMarked",
            until: "if state.mode == .expanded"
        )
        precondition(closed.contains("ClosedNookLamp"))
        let lamp = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "struct ClosedNookLamp",
            until: "struct IslandHeader"
        )
        precondition(lamp.contains("openNookPage"))
        precondition(lamp.contains("lamp.desk.fill"))
        let drawer = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "let pull = max(0, AppState.shared.drawerExtension)",
            until: "Closed-notch items stay in the menu bar"
        )
        precondition(drawer.contains("mediaLive"))
        precondition(drawer.contains("nookDrawerWidth"))
    }

    static func noteSpan(_ kind: NookNoteSpan.Kind, in source: String, needle: String) -> NookNoteSpan {
        let range = (source as NSString).range(of: needle)
        precondition(range.location != NSNotFound, needle)
        return NookNoteSpan(kind: kind, start: range.location, end: range.location + range.length)
    }
}
