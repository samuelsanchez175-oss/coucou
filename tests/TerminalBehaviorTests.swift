import Foundation

// IslandTypes mentions the bot eye. The real enum lives in the AppKit drawing file.
enum EyeShape: Equatable { case unused }

@main
enum TerminalBehaviorTests {
    static func main() {
        testProgressDoesNotLookIdle()
        testShellPromptStaysIdle()
        testClickedFaceWinsOverGreen()
        testOverviewFitsTheCluster()
        testLeftSwipeMatchesTheSettingsSentence()
        testUnselectedBlobAsksToAttach()
        testEveryBlobOpensInItsCorner()
        testOneOpenBlobStaysInItsQuadrant()
        testOpenWindowsShareTheScreen()
        testCollapsedBlobsStayBesideTheCamera()
        testCuddlerFollowsTheTerminal()
        testBlobUsesTheTerminalsOwnName()
        testBlobTitleFitsInThreeWords()
        testBlobStaysMarriedUntilTheTerminalEnds()
        testEachMarriedBlobShowsItsOwnResponse()
        testUnparsedListingKeepsTheGreenWindow()
        testLostMarriageReturnsToTheWindowInThatCorner()
        testStatusHeartbeats()
        testPageLockHoldsThenOpens()
        testDropHitsTheBlob()
        testNookKeepsTheSharedHeader()
        testHeaderSitsOnTheMenuBar()
        testBlobOpensAWindowAtTwentyPoint()
        print("Terminal behavior: 23 cases passed")
    }

    /// A download that prints "45%" must stay Working. Treating every
    /// trailing percent as a shell prompt makes the face flip every tick.
    static func testProgressDoesNotLookIdle() {
        let reading = TerminalBehavior.classify("fetching\n45%")
        precondition(reading.face == .working, "progress percent looked \(reading.face)")
        let packed = TerminalBehavior.classify("Build failed (100%)")
        precondition(packed.face == .working, "parenthesized percent looked \(packed.face)")
    }

    static func testShellPromptStaysIdle() {
        precondition(TerminalBehavior.classify("samuel@mac folder %").face == .idle)
        precondition(TerminalBehavior.classify("$").face == .idle)
        precondition(TerminalBehavior.classify("password:").face == .waiting)
        let missing = TerminalBehavior.classify("Grok CLI not found")
        precondition(missing.face == .idle && missing.grokMissing)
        precondition(TerminalBehavior.classify("").face == .idle)
        precondition(TerminalBehavior.classify("compiling sources").face == .working)
    }

    /// Home, chat, and the other header controls stay up on Nook.
    /// The other pages already keep that row.
    static func testNookKeepsTheSharedHeader() {
        precondition(IslandView.nook.showsSharedHeader, "Nook hid the home row")
        precondition(IslandView.nook.showsSharedHeader == IslandView.overview.showsSharedHeader)
        precondition(IslandView.prompt.showsSharedHeader)
        precondition(IslandView.upload.showsSharedHeader)
        precondition(IslandView.settings.showsSharedHeader)
    }

    /// Opening from a colored face keeps that color. A stale click does not.
    static func testClickedFaceWinsOverGreen() {
        precondition(TerminalBehavior.chooseSlot(armedID: nil, age: nil) == "green")
        precondition(TerminalBehavior.chooseSlot(armedID: "orange", age: 0.05) == "orange")
        precondition(TerminalBehavior.chooseSlot(armedID: "orange", age: 2) == "green")
    }

    static func testOverviewFitsTheCluster() {
        let height = IslandConst.viewLayouts[.overview]!.height
        precondition(
            height + 0.5 >= TerminalBehavior.overviewHeight,
            "overview is \(height)pt and the terminal cluster needs \(TerminalBehavior.overviewHeight)pt"
        )
        precondition(TerminalBehavior.compactSide == 28)
        // Four faces, the Attach row, and the lock at the bottom of the tile.
        precondition(TerminalBehavior.overviewHeight == 280, "overview is \(TerminalBehavior.overviewHeight)")
        precondition(TerminalBehavior.faceColumn == 108)
        precondition(TerminalBehavior.faceGridWidth == 232, "both face columns share one centered group")
        let right = TerminalBehavior.overviewRightCard(islandWidth: IslandConst.expandedWidth)
        precondition(right + 0.5 >= TerminalBehavior.faceGridWidth + 16, "the four tiles fit the right card, right=\(right)")
        precondition(
            IslandConst.viewLayouts[.overview]!.botY == TerminalBehavior.overviewBlobCenterY,
            "the left blob lines up with the center of the four faces"
        )
    }

    /// The extra Attach control picks the first color that has no window.
    static func testUnselectedBlobAsksToAttach() {
        let slots = [
            TerminalBehavior.SlotBinding(id: "green", windowID: 10),
            TerminalBehavior.SlotBinding(id: "orange", windowID: nil),
            TerminalBehavior.SlotBinding(id: "purple", windowID: nil),
            TerminalBehavior.SlotBinding(id: "red", windowID: 12),
        ]
        precondition(TerminalBehavior.attachTarget(slots: slots, selectedID: "green") == "orange")
        let selectedFree = [
            TerminalBehavior.SlotBinding(id: "green", windowID: nil),
            TerminalBehavior.SlotBinding(id: "orange", windowID: 4),
        ]
        precondition(TerminalBehavior.attachTarget(slots: selectedFree, selectedID: "green") == "green")
        let full = [
            TerminalBehavior.SlotBinding(id: "green", windowID: 1),
            TerminalBehavior.SlotBinding(id: "orange", windowID: 2),
        ]
        precondition(TerminalBehavior.attachTarget(slots: full, selectedID: "orange") == "orange")
        let open = [
            TerminalBehavior.WindowChoice(id: 10, title: "zsh"),
            TerminalBehavior.WindowChoice(id: 11, title: "  "),
            TerminalBehavior.WindowChoice(id: 12, title: "grok"),
        ]
        let choices = TerminalBehavior.attachChoices(open: open, takenByOthers: [10])
        precondition(choices.map(\.id) == [11, 12, 10], "order was \(choices.map(\.id))")
        precondition(TerminalBehavior.choiceTitle(choices[0].title) == "Terminal")
        precondition(TerminalBehavior.choiceTitle("grok") == "grok")
    }

    /// Each blob opens its own Terminal window at 20pt, then pulls that window
    /// out of the tab set before moving it. Prefer-tabs-always makes `do script`
    /// join the front window, and setting bounds on a tab slides the whole set.
    static func testBlobOpensAWindowAtTwentyPoint() {
        precondition(TerminalBehavior.terminalFontSize == 20)
        let text = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalDesk.swift", encoding: .utf8)
        precondition(
            text.contains("menu item \"Move Tab to New Window\" of menu \"Window\""),
            "a tabbed session is pulled into its own window"
        )
        let open = sourceSlice(text, from: "func openNew", until: "enum CotypistLink")
        let place = sourceSlice(text, from: "private static func place(", until: "func placeMany")
        let many = sourceSlice(text, from: "func placeMany", until: "private static func focus")
        for slice in [open, place, many] {
            precondition(slice.contains("moveTabToOwnWindow"), "detach before placing the window")
            let rememberAt = slice.range(of: "rememberWindowFrames")!
            let moveAt = slice.range(of: "moveTabToOwnWindow")!
            let boundsAt = slice.range(of: "set bounds")!
            let restoreAt = slice.range(of: "restoreOtherWindowFrames")!
            precondition(rememberAt.lowerBound < moveAt.lowerBound, "remember the other windows before a tab join can resize them")
            precondition(moveAt.lowerBound < boundsAt.lowerBound, "detach before moving, or the whole tab set slides")
            precondition(boundsAt.lowerBound < restoreAt.lowerBound, "put the other windows back after this one takes its corner")
            precondition(!slice.contains("in selected tab"), "the command must not join an open tab")
            precondition(!slice.contains("menu \"Shell\""), "the Shell menu was not making a separate window")
            precondition(slice.contains("font size of current settings"))
            precondition(slice.contains("TerminalBehavior.terminalFontSize"))
        }
        let scriptAt = open.range(of: "do script cmd")!
        precondition(open.range(of: "rememberWindowFrames")!.lowerBound < scriptAt.lowerBound)
        precondition(open.contains("do script cmd"), "a blob starts a command")
    }

    static func sourceSlice(_ text: String, from start: String, until end: String) -> String {
        guard let from = text.range(of: start), let to = text.range(of: end, range: from.upperBound..<text.endIndex) else {
            preconditionFailure("missing \(start)")
        }
        return String(text[from.lowerBound..<to.lowerBound])
    }

    /// This display's usable area is 2048×1285, starting 45pt under the menu bar.
    /// Green, yellow, purple, and red each take one corner and meet at the edges.
    static func testEveryBlobOpensInItsCorner() {
        precondition(TerminalBehavior.blobClick(slotID: "green", selectedID: "green") == .focus)
        precondition(TerminalBehavior.blobClick(slotID: "orange", selectedID: "green") == .focus)
        precondition(TerminalBehavior.blobClick(slotID: "purple", selectedID: "green") == .focus)
        precondition(TerminalBehavior.blobClick(slotID: "red", selectedID: "red") == .focus)
        let green = TerminalBehavior.quadrantBounds(slotID: "green", visibleLeft: 0, visibleTop: 45, visibleWidth: 2048, visibleHeight: 1285)
        let yellow = TerminalBehavior.quadrantBounds(slotID: "orange", visibleLeft: 0, visibleTop: 45, visibleWidth: 2048, visibleHeight: 1285)
        let purple = TerminalBehavior.quadrantBounds(slotID: "purple", visibleLeft: 0, visibleTop: 45, visibleWidth: 2048, visibleHeight: 1285)
        let red = TerminalBehavior.quadrantBounds(slotID: "red", visibleLeft: 0, visibleTop: 45, visibleWidth: 2048, visibleHeight: 1285)
        precondition(green == TerminalBehavior.TerminalBounds(left: 0, top: 45, right: 1024, bottom: 687), "green \(green)")
        precondition(yellow == TerminalBehavior.TerminalBounds(left: 1024, top: 45, right: 2048, bottom: 687), "yellow \(yellow)")
        precondition(purple == TerminalBehavior.TerminalBounds(left: 0, top: 687, right: 1024, bottom: 1330), "purple \(purple)")
        precondition(red == TerminalBehavior.TerminalBounds(left: 1024, top: 687, right: 2048, bottom: 1330), "red \(red)")
        precondition(TerminalBehavior.corner(slotID: "yellow") == .topRight)
        let g = TerminalBehavior.quadrantBounds(slotID: "green", visibleLeft: 10, visibleTop: 20, visibleWidth: 1001, visibleHeight: 801)
        let y = TerminalBehavior.quadrantBounds(slotID: "yellow", visibleLeft: 10, visibleTop: 20, visibleWidth: 1001, visibleHeight: 801)
        let p = TerminalBehavior.quadrantBounds(slotID: "purple", visibleLeft: 10, visibleTop: 20, visibleWidth: 1001, visibleHeight: 801)
        let r = TerminalBehavior.quadrantBounds(slotID: "red", visibleLeft: 10, visibleTop: 20, visibleWidth: 1001, visibleHeight: 801)
        precondition(g.left == 10 && g.top == 20)
        precondition(g.right == y.left && y.right == 1011)
        precondition(g.bottom == p.top && p.bottom == 821)
        precondition(y.bottom == r.top && r.right == y.right && r.bottom == p.bottom && p.right == r.left)
    }

    /// Opening one blob, or two, still puts each color in its own corner.
    /// A lone window must not grow to fill the screen.
    static func testOneOpenBlobStaysInItsQuadrant() {
        let span = (left: 0, top: 45, width: 2048, height: 1285)
        let one = TerminalBehavior.quadrantPlacements(
            slotIDs: ["red"],
            visibleLeft: span.left, visibleTop: span.top, visibleWidth: span.width, visibleHeight: span.height
        )
        precondition(
            one["red"] == TerminalBehavior.TerminalBounds(left: 1024, top: 687, right: 2048, bottom: 1330),
            "red \(String(describing: one["red"]))"
        )
        let two = TerminalBehavior.quadrantPlacements(
            slotIDs: ["green", "orange"],
            visibleLeft: span.left, visibleTop: span.top, visibleWidth: span.width, visibleHeight: span.height
        )
        precondition(two["green"] == TerminalBehavior.TerminalBounds(left: 0, top: 45, right: 1024, bottom: 687))
        precondition(two["orange"] == TerminalBehavior.TerminalBounds(left: 1024, top: 45, right: 2048, bottom: 687))
        let desk = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalDesk.swift", encoding: .utf8)
        let frames = sourceSlice(desk, from: "private func frames(", until: "private func reflowOpen")
        let reflow = sourceSlice(desk, from: "private func reflowOpen", until: "private func adopt")
        precondition(frames.contains("quadrantPlacements"), "opening a blob uses that color's corner")
        precondition(!frames.contains("tiledFrames"), "opening a blob must not stretch into an empty corner")
        precondition(reflow.contains("quadrantPlacements"))
        precondition(!reflow.contains("tiledFrames"))
        let place = sourceSlice(desk, from: "private static func place(", until: "func placeMany")
        let many = sourceSlice(desk, from: "func placeMany", until: "private static func focus")
        for slice in [place, many] {
            precondition(slice.contains("tty of selected tab"), "the moved tab is found again after it leaves the set")
            precondition(slice.contains("set bounds of placedWindow"), "bounds land on the window that owns the tab")
            precondition(!slice.contains("set bounds of window id wid"), "the old id is the tab set left behind")
        }
    }

    /// Two windows split the screen. Three give the lone side the full height.
    static func testOpenWindowsShareTheScreen() {
        let span = (left: 0, top: 45, width: 2048, height: 1285)
        let two = TerminalBehavior.tiledFrames(
            slotIDs: ["green", "orange"],
            visibleLeft: span.left, visibleTop: span.top, visibleWidth: span.width, visibleHeight: span.height
        )
        precondition(two["green"] == TerminalBehavior.TerminalBounds(left: 0, top: 45, right: 1024, bottom: 1330), "left \(String(describing: two["green"]))")
        precondition(two["orange"] == TerminalBehavior.TerminalBounds(left: 1024, top: 45, right: 2048, bottom: 1330))
        let sameSide = TerminalBehavior.tiledFrames(
            slotIDs: ["green", "purple"],
            visibleLeft: span.left, visibleTop: span.top, visibleWidth: span.width, visibleHeight: span.height
        )
        precondition(sameSide["green"] == TerminalBehavior.TerminalBounds(left: 0, top: 45, right: 2048, bottom: 687))
        precondition(sameSide["purple"] == TerminalBehavior.TerminalBounds(left: 0, top: 687, right: 2048, bottom: 1330))
        let three = TerminalBehavior.tiledFrames(
            slotIDs: ["green", "purple", "orange"],
            visibleLeft: span.left, visibleTop: span.top, visibleWidth: span.width, visibleHeight: span.height
        )
        precondition(three["green"] == TerminalBehavior.TerminalBounds(left: 0, top: 45, right: 1024, bottom: 687))
        precondition(three["purple"] == TerminalBehavior.TerminalBounds(left: 0, top: 687, right: 1024, bottom: 1330))
        precondition(three["orange"] == TerminalBehavior.TerminalBounds(left: 1024, top: 45, right: 2048, bottom: 1330), "right \(String(describing: three["orange"]))")
        let one = TerminalBehavior.tiledFrames(
            slotIDs: ["red"],
            visibleLeft: span.left, visibleTop: span.top, visibleWidth: span.width, visibleHeight: span.height
        )
        precondition(one["red"] == TerminalBehavior.TerminalBounds(left: 0, top: 45, right: 2048, bottom: 1330))
    }

    /// The blob shows the title Terminal wrote on the window, not "Terminal 1".
    static func testBlobUsesTheTerminalsOwnName() {
        let title = "  samuel — -zsh — 80×24  "
        precondition(TerminalBehavior.adoptedName(windowTitle: title, fallback: "Terminal 1") == "samuel — -zsh — 80×24")
        precondition(TerminalBehavior.adoptedName(windowTitle: "   ", fallback: "Terminal 1") == "Terminal 1")
        precondition(TerminalBehavior.adoptedName(windowTitle: "", fallback: "Terminal 2") == "Terminal 2")
        let long = "samuel — ⠴ - Thinking - Port NotchNook settings and Grok into Coucou"
        let prompt = TerminalBehavior.promptName(long)
        precondition(prompt.hasSuffix("…"), prompt)
        precondition(prompt.count <= 42, "prompt is \(prompt.count) characters")
        precondition(TerminalBehavior.promptName("grok") == "grok")
    }

    /// The line under the blob is two or three whole words, short enough to read with no ellipsis.
    static func testBlobTitleFitsInThreeWords() {
        let grok = "samuel — ⠴ - Thinking - Port NotchNook settings and Grok into Co… - grok — grok ▸ python — 64×35"
        let live = "samuel — ⠙ - Running: the green window - Coucou blob quadrants, charge watts, sta… - grok — grok ▸ osascript — 84×23"
        let names = [
            TerminalBehavior.shortTitle(grok, fallback: "Terminal 1"),
            TerminalBehavior.shortTitle(live, fallback: "Terminal 1"),
            TerminalBehavior.shortTitle("samuel — -zsh — 80×24", fallback: "Terminal 1"),
            TerminalBehavior.shortTitle("samuel — PROBE-BR — -zsh — 143×39", fallback: "Terminal 4"),
            TerminalBehavior.shortTitle("   ", fallback: "Terminal 1"),
        ]
        precondition(names[0] == "Port NotchNook", names[0])
        precondition(names[1] == "Coucou blob", names[1])
        precondition(names[2] == "samuel", names[2])
        precondition(names[3] == "PROBE-BR", names[3])
        precondition(names[4] == "Terminal 1", names[4])
        for shown in names {
            let words = shown.split(separator: " ")
            precondition((1...3).contains(words.count), shown)
            precondition(!shown.contains("…") && !shown.contains("..."), shown)
            precondition(
                TerminalBehavior.labelWidth(shown) <= TerminalBehavior.blobNameWidth,
                "\(shown) is \(TerminalBehavior.labelWidth(shown)) wide"
            )
        }
    }

    /// A blob keeps the window it opened until that window is gone.
    /// The name under the blob is that window's name, and each light
    /// follows that window's own status.
    static func testBlobStaysMarriedUntilTheTerminalEnds() {
        let running = "samuel — ⠧ - Running: Read the terminal file - grok — grok ▸ bun — 84×49"
        let asking = "samuel — Action Required - grok — grok ▸ python — 84×49"
        let quiet = "samuel — Coucou: toggle brightness and volume - grok — grok ▸ python — 84×49"
        let incoming = "samuel — Waiting for response - grok — grok ▸ bun — 84×49"
        let settled = "samuel — Waiting for your next prompt - grok — grok ▸ python — 84×49"

        let kept = TerminalBehavior.marriage(windowID: 42, liveWindowIDs: [42, 99], listed: true)
        precondition(kept.windowID == 42 && kept.terminated == false, "a live window stays married")
        let blankRead = TerminalBehavior.marriage(windowID: 42, liveWindowIDs: [42], listed: true)
        precondition(blankRead.windowID == 42 && blankRead.terminated == false, "a blank read does not end the marriage")
        let ended = TerminalBehavior.marriage(windowID: 42, liveWindowIDs: [99], listed: true)
        precondition(ended.windowID == nil && ended.terminated, "a closed window ends the marriage")
        let unread = TerminalBehavior.marriage(windowID: 42, liveWindowIDs: [], listed: false)
        precondition(unread.windowID == 42 && unread.terminated == false, "a failed listing keeps the marriage")
        let stranger = TerminalBehavior.marriage(windowID: nil, liveWindowIDs: [23143, 23148], listed: true)
        precondition(stranger.windowID == nil && stranger.terminated == false, "an open window the blob did not open stays unclaimed")

        precondition(TerminalBehavior.shortTitle(running, fallback: "Terminal 1") == "Read the terminal", TerminalBehavior.shortTitle(running, fallback: "Terminal 1"))
        precondition(TerminalBehavior.shortTitle(quiet, fallback: "Terminal 2") == "Coucou toggle", TerminalBehavior.shortTitle(quiet, fallback: "Terminal 2"))

        let lights = [
            TerminalBehavior.classify(title: running, contents: "   "),
            TerminalBehavior.classify(title: asking, contents: ""),
            TerminalBehavior.classify(title: quiet, contents: "missing"),
            TerminalBehavior.classify(title: incoming, contents: ""),
        ]
        precondition(lights.map(\.face) == [.working, .waiting, .idle, .working], "faces \(lights.map(\.face))")
        precondition(TerminalBehavior.classify(title: settled, contents: "").face == .idle)
        precondition(TerminalBehavior.classify(title: running, contents: "samuel@mac ~ %").face == .idle, "a shell prompt is idle")
        precondition(TerminalBehavior.classify(title: quiet, contents: "password:").face == .waiting)
        let colors = lights.map { TerminalBehavior.statusColorHex(for: $0.face) }
        precondition(colors == ["#3D8BFF", "#C084FC", "#FF9F1C", "#3D8BFF"], "colors \(colors)")

        let desk = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalDesk.swift", encoding: .utf8)
        let tick = sourceSlice(desk, from: "private func tick()", until: "private func apply(")
        precondition(tick.contains("TerminalBehavior.marriage"), "a tick keeps the window the blob opened")
        precondition(tick.contains("classify(title:"), "each blob reads its own window title")
        precondition(!tick.contains("claimOpenWindowsOnce"), "a tick must not marry a window the blob did not open")
        precondition(!desk.contains("claimOpenWindowsOnce"), "open windows are not claimed on launch")
        let view = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalNotchView.swift", encoding: .utf8)
        let compact = sourceSlice(view, from: "struct CompactTerminalFaces", until: "struct TerminalSettingsSection")
        precondition(compact.contains("statusColorHex"), "each compact blob shows its own status light")
        precondition(TerminalBehavior.collapsedStatusLight == 8, "the closed-notch status light is \(TerminalBehavior.collapsedStatusLight)pt")
        precondition(TerminalBehavior.collapsedStatusShift == 5, "the closed-notch status light hangs off the corner")
        precondition(compact.contains("collapsedStatusLight"), "the closed notch uses the larger status light")
        precondition(compact.contains("collapsedStatusShift"), "the closed-notch status light sits past the blob")
    }

    /// Each married blob follows its own window. Grok's prompt box is not a status.
    /// A response in that window's title lights the blob blue. The prompt box stays orange.
    static func testEachMarriedBlobShowsItsOwnResponse() {
        let chrome = """
          ╭──────────────────────────────────────────────────────────╮
          │ ❯                                                        │
          ╰─────────────────────── Grok 4.7 (high) · always-approve ─╯

          Shift+Tab:mode  │  Ctrl+c:cancel  │  Ctrl+b:send to bg  │
        """
        let responding = "samuel — ⠼ - List live Terminal window titles… - Fix terminal blob quadrants, state, coll… - grok — grok ▸ osascript — 64×25"
        let incoming = "samuel — ⠸ - Waiting for response… - Clone design repos and install taste ski… - grok — grok ▸ node — 84×23"
        let settled = "samuel — Waiting for your next prompt - grok — grok ▸ python — 84×49"
        let asking = "samuel — Action Required - grok — grok ▸ python — 84×49"

        let green = TerminalBehavior.classify(title: responding, contents: chrome)
        let yellow = TerminalBehavior.classify(title: incoming, contents: chrome)
        let quiet = TerminalBehavior.classify(title: settled, contents: chrome)
        let question = TerminalBehavior.classify(title: asking, contents: chrome)
        precondition(green.face == .working, "the green window's response was \(green.face)")
        precondition(yellow.face == .working, "another window's response was \(yellow.face)")
        precondition(quiet.face == .idle, "the prompt box hid the quiet title as \(quiet.face)")
        precondition(question.face == .waiting, "a question was \(question.face)")
        precondition(TerminalBehavior.blobLightHex(slotHex: "#22C55E", face: green.face) == "#3D8BFF")
        precondition(TerminalBehavior.blobLightHex(slotHex: "#F29B38", face: yellow.face) == "#3D8BFF")
        precondition(TerminalBehavior.blobLightHex(slotHex: "#22C55E", face: quiet.face) == "#22C55E")
        precondition(TerminalBehavior.blobLightHex(slotHex: "#7C5CFF", face: question.face) == "#C084FC")
        precondition(TerminalBehavior.classify(title: incoming, contents: "samuel@mac ~ %").face == .idle)

        let view = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalNotchView.swift", encoding: .utf8)
        precondition(view.contains("blobLightHex"), "the blob lights up in its own terminal's status color")
    }

    /// Terminal's `tab` is a window tab, so the listing comes back as "104tabsamuel".
    /// That text is not an empty window list. The green window stays married,
    /// and a real listing of its response lights the green blob blue.
    static func testUnparsedListingKeepsTheGreenWindow() {
        let broken = "160tabsamuel — Thinking\n104tabsamuel — ⠋ - Running: the green window\u{1e}❯ grok Shift+Tab"
        let missed = TerminalBehavior.parseSnapshot(broken, slotCount: 4)
        let kept = TerminalBehavior.marriage(
            windowID: 104,
            liveWindowIDs: missed.windows.map(\.id),
            listed: missed.listed
        )
        precondition(kept.windowID == 104 && kept.terminated == false, "an unparsed listing divorced the green window")

        let title = "samuel — ⠋ - Running: the green window - grok — grok ▸ osascript — 84×23"
        let real = "160\tother project\n104\t\(title)\u{1e}❯\nGrok 4.7\nShift+Tab:mode"
        let read = TerminalBehavior.parseSnapshot(real, slotCount: 4)
        precondition(read.listed, "a tab-separated listing is a real window list")
        precondition(read.windows.map(\.id) == [160, 104], "ids \(read.windows.map(\.id))")
        let married = TerminalBehavior.marriage(
            windowID: 104,
            liveWindowIDs: read.windows.map(\.id),
            listed: read.listed
        )
        precondition(married.windowID == 104 && married.terminated == false)
        let face = TerminalBehavior.classify(title: read.windows[1].title, contents: "❯\nGrok 4.7\nShift+Tab:mode")
        precondition(face.face == .working, "the green response was \(face.face)")
        precondition(TerminalBehavior.blobLightHex(slotHex: "#22C55E", face: face.face) == "#3D8BFF")
        precondition(TerminalBehavior.statusColorHex(for: face.face) == "#3D8BFF")

        let gone = TerminalBehavior.parseSnapshot("\u{1e}", slotCount: 4)
        precondition(gone.listed && gone.windows.isEmpty, "a real empty list still means the windows are gone")
        let ended = TerminalBehavior.marriage(windowID: 104, liveWindowIDs: gone.windows.map(\.id), listed: gone.listed)
        precondition(ended.terminated, "a closed terminal still ends the marriage")

        let desk = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalDesk.swift", encoding: .utf8)
        let snapshot = sourceSlice(desk, from: "static func snapshot", until: "nonisolated static func openOrFocus")
        precondition(snapshot.contains("character id 9"), "the listing must split the id and the title with a real tab")
        precondition(!snapshot.contains("& tab &"), "Terminal's tab class was written into the listing as the word tab")
        precondition(snapshot.contains("parseSnapshot"), "the tick uses the listing parser")
    }

    /// A relaunch drops the saved window id, but the window Coucou tiled into
    /// that color's corner is still there. The blob marries that window again
    /// and lights from its title. A terminal sitting somewhere else stays unclaimed.
    static func testLostMarriageReturnsToTheWindowInThatCorner() {
        let green = TerminalBehavior.quadrantBounds(
            slotID: "green", visibleLeft: 0, visibleTop: 45, visibleWidth: 2048, visibleHeight: 1285
        )
        let orange = TerminalBehavior.quadrantBounds(
            slotID: "orange", visibleLeft: 0, visibleTop: 45, visibleWidth: 2048, visibleHeight: 1285
        )
        let purple = TerminalBehavior.quadrantBounds(
            slotID: "purple", visibleLeft: 0, visibleTop: 45, visibleWidth: 2048, visibleHeight: 1285
        )
        let red = TerminalBehavior.quadrantBounds(
            slotID: "red", visibleLeft: 0, visibleTop: 45, visibleWidth: 2048, visibleHeight: 1285
        )
        let title = "samuel — ⠋ - Running: the green window - grok — grok ▸ bun — 83×23"
        let listing = """
        160\t0\t45\t1016\t680\t\(title)
        617\t1024\t45\t2048\t687\tsamuel — ⠴ - Thinking - other work
        593\t0\t687\t1024\t1330\tsamuel — Waiting for response… - third
        400\t200\t200\t700\t600\tsamuel — Action Required - not ours
        """
        let read = TerminalBehavior.parseSnapshot(listing + "\u{1e}❯\nShift+Tab:mode", slotCount: 4)
        precondition(read.listed, "a corner listing is a real window list")
        precondition(read.windows[0].bounds == TerminalBehavior.TerminalBounds(left: 0, top: 45, right: 1016, bottom: 680))
        let corners = read.windows.compactMap { window -> TerminalBehavior.CornerWindow? in
            guard let bounds = window.bounds else { return nil }
            return TerminalBehavior.CornerWindow(id: window.id, bounds: bounds)
        }
        precondition(TerminalBehavior.windowInCorner(quadrant: green, windows: corners, taken: []) == 160)
        precondition(TerminalBehavior.windowInCorner(quadrant: orange, windows: corners, taken: []) == 617)
        precondition(TerminalBehavior.windowInCorner(quadrant: purple, windows: corners, taken: [593]) == nil, "a window another color owns stays put")
        precondition(TerminalBehavior.windowInCorner(quadrant: red, windows: corners, taken: []) == nil, "an empty corner stays empty")
        let doubled = corners + [TerminalBehavior.CornerWindow(id: 161, bounds: green)]
        precondition(TerminalBehavior.windowInCorner(quadrant: green, windows: doubled, taken: []) == nil, "two windows in one corner are not guessed")
        let face = TerminalBehavior.classify(title: read.windows[0].title, contents: "❯\nShift+Tab:mode")
        precondition(face.face == .working, "the recovered window's response was \(face.face)")
        precondition(TerminalBehavior.blobLightHex(slotHex: "#22C55E", face: face.face) == "#3D8BFF")

        let desk = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalDesk.swift", encoding: .utf8)
        let tick = sourceSlice(desk, from: "private func tick()", until: "private func apply(")
        precondition(tick.contains("windowInCorner"), "a tick marries the window already in that corner")
        let open = sourceSlice(desk, from: "func openOrFocus(", until: "func togglePageLock(")
        precondition(open.contains("windowInCorner"), "pressing the blob focuses the window already in that corner")
        let snapshot = sourceSlice(desk, from: "static func snapshot", until: "nonisolated static func openOrFocus")
        precondition(snapshot.contains("bounds of w"), "the listing reads each window's own frame")
    }

    /// The closed notch keeps the white blob in the left ear and the four blobs in the right ear.
    static func testCollapsedBlobsStayBesideTheCamera() {
        let notch: CGFloat = 251
        let island = notch + TerminalBehavior.collapsedWing * 2
        let centers = TerminalBehavior.collapsedBlobCenters(islandWidth: island, notchWidth: notch)
        let cameraLeft = (island - notch) / 2
        let cameraRight = cameraLeft + notch
        precondition(centers.whiteX + 10 < cameraLeft, "white \(centers.whiteX) camera \(cameraLeft)")
        precondition(centers.facesX - 14 > cameraRight, "faces \(centers.facesX) camera \(cameraRight)")
        precondition(TerminalBehavior.collapsedWing >= TerminalBehavior.compactSide)
        let root = try! String(contentsOfFile: "NotchBuddy/Sources/App/IslandRootView.swift", encoding: .utf8)
        precondition(root.contains("collapsedBlobCenters"), "the closed notch places both blobs")
        precondition(
            !root.contains("state.mode == .compact && !hud.visible && !showMedia"),
            "media must not hide the four blobs"
        )
        let sizing = try! String(contentsOfFile: "NotchBuddy/Sources/App/IslandWindowController.swift", encoding: .utf8)
        precondition(sizing.contains("collapsedWing"), "the closed notch is wide enough for both ears")
    }

    /// Each terminal face is a different cuddler. Idle, a response, and a question do not share one pose.
    static func testCuddlerFollowsTheTerminal() {
        precondition(TerminalBehavior.cuddlerState(for: .idle) == .idle)
        precondition(TerminalBehavior.cuddlerState(for: .working) == .working)
        precondition(TerminalBehavior.cuddlerState(for: .waiting) == .question)
        let states: [BotState] = [
            TerminalBehavior.cuddlerState(for: .idle),
            TerminalBehavior.cuddlerState(for: .working),
            TerminalBehavior.cuddlerState(for: .waiting),
        ]
        precondition(Set(states).count == 3, "the cuddler needs a different pose for each terminal")
        let bot = try! String(contentsOfFile: "NotchBuddy/Sources/App/BotCanvasView.swift", encoding: .utf8)
        precondition(bot.contains("cuddlerState"), "the white blob follows the selected terminal")
        precondition(bot.contains("engine.setState(task.state"), "each colored blob follows its own terminal")
    }

    /// Idle is a slow orange beat. A response is a faster blue beat. A question is the fastest purple beat.
    static func testStatusHeartbeats() {
        precondition(TerminalBehavior.statusPhrase(for: .idle) == "Idle")
        precondition(TerminalBehavior.statusPhrase(for: .working) == "New response available")
        precondition(TerminalBehavior.statusPhrase(for: .waiting) == "Needs your input")
        precondition(TerminalBehavior.statusColorHex(for: .idle) == "#FF9F1C")
        precondition(TerminalBehavior.statusColorHex(for: .working) == "#3D8BFF")
        precondition(TerminalBehavior.statusColorHex(for: .waiting) == "#C084FC")
        let idle = TerminalBehavior.heartbeatBPM(for: .idle)
        let response = TerminalBehavior.heartbeatBPM(for: .working)
        let input = TerminalBehavior.heartbeatBPM(for: .waiting)
        precondition(idle < response && response < input, "bpm \(idle) \(response) \(input)")
        precondition(TerminalBehavior.heartbeatLevel(seconds: 0.08, bpm: 60) > 0.9)
        precondition(TerminalBehavior.heartbeatLevel(seconds: 0.5, bpm: 60) == 0)
        let idlePeak = 0.08 * (60.0 / idle)
        let inputPeak = 0.08 * (60.0 / input)
        precondition(abs(idlePeak - inputPeak) > 0.05, "peaks were too close")
    }

    /// A locked terminal page stays open for 20 seconds after the pointer leaves.
    /// The lock icon opens across the last 3 seconds, then the hold ends.
    static func testPageLockHoldsThenOpens() {
        precondition(TerminalBehavior.pageLockHold == 20)
        precondition(TerminalBehavior.pageLockUnlock == 3)
        precondition(TerminalBehavior.holdsPageOpen(locked: true, onPage: true, leftAt: nil, now: 0) == false)
        precondition(TerminalBehavior.holdsPageOpen(locked: false, onPage: true, leftAt: 0, now: 1) == false)
        precondition(TerminalBehavior.holdsPageOpen(locked: true, onPage: false, leftAt: 0, now: 1) == false)
        precondition(TerminalBehavior.holdsPageOpen(locked: true, onPage: true, leftAt: 0, now: 19.9))
        precondition(TerminalBehavior.holdsPageOpen(locked: true, onPage: true, leftAt: 0, now: 20) == false)
        precondition(TerminalBehavior.shouldReleasePageLock(locked: true, onPage: true, leftAt: 0, now: 19.9) == false)
        precondition(TerminalBehavior.shouldReleasePageLock(locked: true, onPage: true, leftAt: 0, now: 20))
        precondition(TerminalBehavior.lockOpenAmount(locked: true, leftAt: nil, now: 5) == 0)
        precondition(TerminalBehavior.lockOpenAmount(locked: true, leftAt: 0, now: 17) == 0)
        let mid = TerminalBehavior.lockOpenAmount(locked: true, leftAt: 0, now: 18.5)
        precondition(abs(mid - 0.5) < 0.001, "open amount was \(mid)")
        precondition(TerminalBehavior.lockOpenAmount(locked: true, leftAt: 0, now: 20) == 1)
        precondition(TerminalBehavior.lockOpenAmount(locked: false, leftAt: 0, now: 1) == 1)
    }

    /// A file dropped on a face attaches to that color. The rest of the page does not.
    static func testDropHitsTheBlob() {
        precondition(TerminalBehavior.blobSlot(x: 360, y: 60, islandWidth: 640, contentTop: 0) == "green")
        precondition(TerminalBehavior.blobSlot(x: 500, y: 60, islandWidth: 640, contentTop: 0) == "orange")
        precondition(TerminalBehavior.blobSlot(x: 360, y: 110, islandWidth: 640, contentTop: 0) == "purple")
        precondition(TerminalBehavior.blobSlot(x: 500, y: 110, islandWidth: 640, contentTop: 0) == "red")
        precondition(TerminalBehavior.blobSlot(x: 100, y: 60, islandWidth: 640, contentTop: 0) == nil)
        precondition(TerminalBehavior.blobSlot(x: 400, y: 200, islandWidth: 640, contentTop: 0) == nil)
        precondition(TerminalBehavior.blobSlot(x: 360, y: 105, islandWidth: 640, contentTop: 45) == "green")
        // Header has moved into the menu bar, so the faces sit higher in the drawer.
        precondition(TerminalBehavior.blobSlot(x: 360, y: 70, islandWidth: 640, contentTop: 45, headerInContent: false) == "green")
        precondition(TerminalBehavior.blobSlot(x: 500, y: 70, islandWidth: 640, contentTop: 45, headerInContent: false) == "orange")
        precondition(TerminalBehavior.blobSlot(x: 360, y: 110, islandWidth: 640, contentTop: 45, headerInContent: false) == "purple")
        precondition(TerminalBehavior.attachmentQuery(path: "/Users/samuel/Notes.txt", isDirectory: false) == "@/Users/samuel/Notes.txt")
        precondition(TerminalBehavior.attachmentQuery(path: "/Users/samuel/.grok/README.md", isDirectory: false) == "@!/Users/samuel/.grok/README.md")
        precondition(TerminalBehavior.attachmentQuery(path: "/Users/samuel/Desktop/Photos", isDirectory: true) == "@/Users/samuel/Desktop/Photos/")
        precondition(TerminalBehavior.attachmentNote(names: ["Notes.txt"]) == "Attached Notes.txt")
        precondition(TerminalBehavior.attachmentNote(names: ["a", "b"]) == "Attached 2 files")
    }

    /// Home, Nook, and Tray sit in the menu bar. Settings starts at the notch's right edge.
    static func testHeaderSitsOnTheMenuBar() {
        precondition(TerminalBehavior.menuBarHeaderBand == 42, "the drawer header is the 8pt pad plus the 34pt row")
        precondition(TerminalBehavior.menuBarControlCenterY(band: 45) == 22.5, "controls are centered on the menu bar")
        let wings = TerminalBehavior.menuBarWings(islandWidth: 640, notchWidth: 251)
        precondition(abs(wings.notchLeading - 194.5) < 0.01, "left tabs end at the notch, leading=\(wings.notchLeading)")
        precondition(abs(wings.notchTrailing - 445.5) < 0.01, "settings start at the notch, trailing=\(wings.notchTrailing)")
        precondition(wings.notchTrailing + 48 < 640 - 16, "settings stay next to the notch, not the outer edge")
        precondition(TerminalBehavior.drawerBodyHeight(layoutHeight: 280, hasNotch: true) == 238, "the drawer loses the header row")
        precondition(TerminalBehavior.drawerBodyHeight(layoutHeight: 280, hasNotch: false) == 280, "a display with no notch keeps the header in the drawer")
        precondition(
            TerminalBehavior.expandedDrawerHeight(layoutHeight: 280, occludedHeight: 45, headerInMenuBar: true) == 283,
            "the open notch is the shorter drawer plus the menu bar"
        )
        precondition(
            TerminalBehavior.expandedDrawerHeight(layoutHeight: 280, occludedHeight: 45, headerInMenuBar: false) == 325,
            "greeting keeps its own height"
        )
        let shifted = TerminalBehavior.blobCenterY(layoutY: TerminalBehavior.overviewBlobCenterY, headerInMenuBar: true)
        precondition(abs(shifted - (TerminalBehavior.overviewBlobCenterY - 42)) < 0.01, "the left blob moves up with the faces")
        precondition(TerminalBehavior.blobCenterY(layoutY: 93, headerInMenuBar: false) == 93)
    }

    /// Settings: invert off, a left swipe plays the previous song.
    /// Invert on, that same left swipe plays the next song.
    /// The finger direction has to win over the system scroll setting.
    static func testLeftSwipeMatchesTheSettingsSentence() {
        // Natural scrolling: finger left is a negative delta.
        precondition(NookLayout.mediaSkipsToNext(deltaX: -12, naturalScrolling: true, invert: false) == false)
        precondition(NookLayout.mediaSkipsToNext(deltaX: -12, naturalScrolling: true, invert: true) == true)
        precondition(NookLayout.mediaSkipsToNext(deltaX: 12, naturalScrolling: true, invert: false) == true)
        // Traditional scrolling: finger left is a positive delta. Same song either way.
        precondition(NookLayout.mediaSkipsToNext(deltaX: 12, naturalScrolling: false, invert: false) == false)
        precondition(NookLayout.mediaSkipsToNext(deltaX: 12, naturalScrolling: false, invert: true) == true)
        precondition(NookLayout.mediaSkipsToNext(deltaX: -12, naturalScrolling: false, invert: false) == true)
    }
}
