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
        testClosedPurpleClickKeepsThatTerminal()
        testHoverOntoPurpleFocusesThatTerminal()
        testYellowCornerStaysOnYellow()
        testEmptyBlobClickOpensThatColor()
        testNewWindowKeepsTheBlobColor()
        testFontFillsTheCornerAfterTheColor()
        testOneClickOpensOneWindow()
        testModelFlagDoesNotUseTheLaunchCommand()
        testCuddlerFollowsTheTerminal()
        testBlobUsesTheTerminalsOwnName()
        testBlobTitleFitsInThreeWords()
        testBlobNameIsTheNounInTheTitle()
        testFreeBlobsClaimTerminalsThatWereAlreadyOpen()
        testLockedNounStaysUntilTheTerminalCloses()
        testPressFocusesAndHoldTiles()
        testToolClaimShinesAndWaitingFlashes()
        testBlobStaysMarriedUntilTheTerminalEnds()
        testEachMarriedBlobShowsItsOwnResponse()
        testUnparsedListingKeepsTheGreenWindow()
        testLostMarriageReturnsToTheWindowInThatCorner()
        testMarriageFollowsTheSameTerminalWhenItsWindowChanges()
        testStatusHeartbeats()
        testEmptyBlobHidesTheCornerLight()
        testEachTerminalChoosesAnAssistant()
        testPageLockHoldsThenOpens()
        testDropHitsTheBlob()
        testNookKeepsTheSharedHeader()
        testHeaderSitsOnTheMenuBar()
        testBlobOpensAWindowAtTwentyPoint()
        print("Terminal behavior: 39 cases passed")
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
        precondition(TerminalBehavior.homePlayerDrop == 24, "the home player needs room under the usage rows")
        precondition(TerminalBehavior.overviewHeight == 304, "overview is \(TerminalBehavior.overviewHeight)")
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
        let many = sourceSlice(text, from: "func placeMany", until: "static func focus")
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
        let many = sourceSlice(desk, from: "func placeMany", until: "static func focus")
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

    /// The line under the blob is the topic noun, short enough to read with no ellipsis.
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
        precondition(names[0] == "NotchNook", names[0])
        precondition(names[1] == "Coucou", names[1])
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

    /// A sentence in the terminal title becomes the one topic noun.
    static func testBlobNameIsTheNounInTheTitle() {
        let samples = [
            ("samuel — facebook saved library - grok — grok ▸ python — 80×24", "facebook"),
            ("samuel — coucou blob quadrants, charge watts - grok — grok ▸ python — 80×24", "coucou"),
            ("samuel — Veeze Genius note slices staged in parallel - grok — grok ▸ python — 52×49", "Veeze"),
            ("samuel — kanyewest genius lines - grok — grok ▸ python — 80×24", "kanyewest"),
            ("samuel — Assign blobs to the coucou window - grok — grok ▸ head — 83×23", "coucou"),
            ("samuel — ⠴ - Thinking - Port NotchNook settings and Grok into Coucou - grok — grok ▸ python — 64×35", "NotchNook"),
        ]
        for (title, noun) in samples {
            let shown = TerminalBehavior.shortTitle(title, fallback: "Terminal 1")
            precondition(shown == noun, "\(noun) came back as \(shown)")
            precondition(!shown.contains(" "), shown)
        }
    }

    /// While Terminal is restoring, a free blob takes a plain shell.
    /// After that, a plain shell stays free and Xcode, Grok, or Claude is still claimed.
    /// A blob that already has a window keeps it.
    static func testFreeBlobsClaimTerminalsThatWereAlreadyOpen() {
        let restoring = [
            TerminalBehavior.ListedWindow(id: 11, title: "samuel — -zsh — 80×24", tty: "/dev/ttys011"),
            TerminalBehavior.ListedWindow(id: 12, title: "coucou", tty: "/dev/ttys012"),
            TerminalBehavior.ListedWindow(id: 13, title: "xcodebuild", tty: "/dev/ttys013", process: "xcodebuild test"),
            TerminalBehavior.ListedWindow(id: 14, title: "claude", tty: "/dev/ttys014"),
            TerminalBehavior.ListedWindow(id: 15, title: "later", tty: "/dev/ttys015"),
        ]
        let slots = [
            TerminalBehavior.ClaimSlot(id: "green", windowID: nil, tty: ""),
            TerminalBehavior.ClaimSlot(id: "orange", windowID: 12, tty: "/dev/ttys012"),
            TerminalBehavior.ClaimSlot(id: "purple", windowID: nil, tty: ""),
            TerminalBehavior.ClaimSlot(id: "red", windowID: nil, tty: ""),
        ]
        let claimed = TerminalBehavior.claimFreeWindows(
            slots: slots,
            open: restoring,
            freeIDs: ["green", "purple", "red"],
            acceptPlain: true
        )
        precondition(claimed[0].windowID == 13 && claimed[0].tty == "/dev/ttys013", "green takes Xcode before the shell")
        precondition(claimed[1].windowID == 12 && claimed[1].tty == "/dev/ttys012", "yellow keeps coucou")
        precondition(claimed[2].windowID == 14 && claimed[2].tty == "/dev/ttys014", "purple takes Claude")
        precondition(claimed[3].windowID == 11 && claimed[3].tty == "/dev/ttys011", "red takes the shell that is left")
        precondition(claimed.allSatisfy { $0.windowID != 15 }, "the fifth window waits for a free blob")

        let shellFirst = [
            TerminalBehavior.ListedWindow(id: 31, title: "samuel — -zsh — 80×24", tty: "/dev/ttys031"),
            TerminalBehavior.ListedWindow(id: 32, title: "samuel — grok — grok ▸ python — 80×24", tty: "/dev/ttys032"),
        ]
        let ordered = TerminalBehavior.claimFreeWindows(
            slots: [
                TerminalBehavior.ClaimSlot(id: "green", windowID: nil, tty: ""),
                TerminalBehavior.ClaimSlot(id: "orange", windowID: nil, tty: ""),
                TerminalBehavior.ClaimSlot(id: "purple", windowID: 12, tty: "/dev/ttys012"),
                TerminalBehavior.ClaimSlot(id: "red", windowID: nil, tty: ""),
            ],
            open: shellFirst,
            freeIDs: ["green", "orange", "red"],
            acceptPlain: true
        )
        precondition(ordered[0].windowID == 32 && ordered[0].tty == "/dev/ttys032", "green takes Grok when the shell is listed first")
        precondition(ordered[1].windowID == 31 && ordered[1].tty == "/dev/ttys031", "yellow takes the shell that is left")
        precondition(ordered[2].windowID == 12, "purple keeps its window")
        precondition(ordered[3].windowID == nil, "red stays free once the tool and the shell are taken")

        let later = [
            TerminalBehavior.ListedWindow(id: 21, title: "samuel — -zsh — 80×24", tty: "/dev/ttys021"),
            TerminalBehavior.ListedWindow(id: 22, title: "samuel — grok — grok ▸ python — 80×24", tty: "/dev/ttys022"),
        ]
        let settled = TerminalBehavior.claimFreeWindows(
            slots: slots,
            open: later,
            freeIDs: ["green", "purple", "red"],
            acceptPlain: false
        )
        precondition(settled[0].windowID == 22 && settled[0].tty == "/dev/ttys022", "green takes the later Grok window")
        precondition(settled[1].windowID == 12, "yellow keeps its window")
        precondition(settled[2].windowID == nil && settled[3].windowID == nil, "plain shells opened later stay free")
        precondition(settled.allSatisfy { $0.windowID != 21 }, "the plain shell stays unclaimed")
        precondition(TerminalBehavior.startupGrace == 8, "plain shells stay claimable for 8 seconds after the first window")
    }

    /// The first good noun stays. A typed name is not a placeholder. A closed terminal clears it.
    static func testLockedNounStaysUntilTheTerminalCloses() {
        let first = TerminalBehavior.lockNoun(current: "", candidate: "Veeze", sessionEnded: false)
        precondition(first == "Veeze", "the first noun locks")
        let kept = TerminalBehavior.lockNoun(current: first, candidate: "Preparing", sessionEnded: false)
        precondition(kept == "Veeze", "a later title does not replace the noun")
        let typed = TerminalBehavior.lockNoun(current: "Play on Words", candidate: "hockey", sessionEnded: false)
        precondition(typed == "Play on Words", "a typed name stays")
        let corrected = TerminalBehavior.lockNoun(current: "Replace", candidate: "Voice", sessionEnded: false)
        precondition(corrected == "Voice", "a weak lock changes once to the topic noun")
        precondition(TerminalBehavior.lockNoun(current: "Finish", candidate: "Penwork", sessionEnded: false) == "Penwork")
        precondition(TerminalBehavior.lockNoun(current: "Replace", candidate: "Preparing", sessionEnded: false) == "Replace", "another status word leaves the lock")
        precondition(TerminalBehavior.lockNoun(current: corrected, candidate: "Penwork", sessionEnded: false) == "Voice", "the corrected noun then sticks")
        let typedStatus = TerminalBehavior.lockNoun(current: "Finish", candidate: "Veeze", sessionEnded: false, userNamed: true)
        precondition(typedStatus == "Finish", "a name you typed stays, even when it is a status word")
        precondition(TerminalBehavior.lockNoun(current: "", candidate: "Terminal 1", sessionEnded: false).isEmpty, "Terminal 1 is not a noun")
        precondition(TerminalBehavior.lockNoun(current: "", candidate: "terminal", sessionEnded: false).isEmpty)
        precondition(TerminalBehavior.lockNoun(current: "Veeze", candidate: "coucou", sessionEnded: true).isEmpty, "a closed terminal clears the noun")
    }

    /// A short press focuses. Holding the blob tiles it.
    static func testPressFocusesAndHoldTiles() {
        precondition(TerminalBehavior.blobPress(held: 0.1) == .focus)
        precondition(TerminalBehavior.blobPress(held: 0.44) == .focus)
        precondition(TerminalBehavior.blobPress(held: TerminalBehavior.tileHold) == .tile)
        precondition(TerminalBehavior.tileHold == 0.45)
        let view = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalNotchView.swift", encoding: .utf8)
        precondition(view.contains("TerminalBlobPress"), "a press on the blob can focus or tile")
        precondition(view.contains("onTapGesture(count: 2)"), "double-click the name to change it")
        precondition(view.contains("lockName"), "a typed name is locked")
        let open = sourceSlice(view, from: "struct TerminalFaceButton", until: "struct TerminalPageLockButton")
        precondition(open.contains("case .focus: desk.focus"), "a click brings the window forward")
        precondition(open.contains("case .tile: desk.openOrFocus"), "a hold puts the window in its corner")
        precondition(open.contains("noticeStarted"), "the open notch hops when it needs input")
        precondition(open.contains("noticeHopOpen"), "the open figure hops a few points")
        let compact = sourceSlice(view, from: "struct CompactTerminalFaces", until: "struct TerminalSettingsSection")
        precondition(compact.contains("case .focus: desk.focus"), "the closed notch click brings the window forward")
        precondition(compact.contains("case .tile: desk.openOrFocus"), "the closed notch hold tiles the window")
        precondition(compact.contains("noticeStarted"), "the closed notch hops when it needs input")
        precondition(compact.contains("noticeHopCompact"), "the closed figure hops a few points")
        let canvas = try! String(contentsOfFile: "NotchBuddy/Sources/App/BotCanvasView.swift", encoding: .utf8)
        precondition(canvas.contains("ringScale"), "a ring grows out of the figure")
        precondition(canvas.contains("noticeLook"), "the glance turns the eyes")
        let engine = try! String(contentsOfFile: "NotchBuddy/Sources/CoucouKit/BotEngine.swift", encoding: .utf8)
        precondition(engine.contains("noticeLook"), "a notice glance wins over the wander")
    }

    /// Xcode shines purple, Grok blue, Claude orange. Needing input flashes once.
    static func testToolClaimShinesAndWaitingFlashes() {
        precondition(TerminalBehavior.sessionTool(title: "samuel — -zsh — 80×24", process: "xcodebuild test") == .xcode)
        precondition(TerminalBehavior.sessionTool(title: "xed Penwork.xcodeproj") == .xcode)
        precondition(TerminalBehavior.sessionTool(title: "samuel — claude — 80×24") == .claude)
        precondition(TerminalBehavior.sessionTool(title: "shell", process: "claude") == .claude)
        precondition(TerminalBehavior.sessionTool(title: "samuel — grok — grok ▸ python — 80×24") == .grok)
        precondition(TerminalBehavior.sessionTool(title: "samuel — -zsh — 80×24", process: "-zsh") == nil)
        precondition(TerminalBehavior.toolShineHex(.xcode) == "#C084FC")
        precondition(TerminalBehavior.toolShineHex(.grok) == "#3D8BFF")
        precondition(TerminalBehavior.toolShineHex(.claude) == "#FF9F1C")
        precondition(TerminalBehavior.attentionFlash(previous: .working, next: .waiting))
        precondition(TerminalBehavior.attentionFlash(previous: .idle, next: .waiting))
        precondition(TerminalBehavior.attentionFlash(previous: .waiting, next: .waiting) == false)
        precondition(TerminalBehavior.attentionFlash(previous: .idle, next: .working) == false)
        let peak = TerminalBehavior.noticePose(elapsed: 0.16)
        precondition(abs(peak.rise - 1) < 0.001, "the hop peaks once")
        let landed = TerminalBehavior.noticePose(elapsed: 0.37)
        precondition(landed.squashX > 1 && landed.squashY < 1, "the landing squashes")
        let looking = TerminalBehavior.noticePose(elapsed: 0.5)
        precondition(looking.glance == 1, "the glance holds")
        precondition(looking.ringScale > 1 && looking.ringOpacity > 0 && looking.ringOpacity < 0.9, "the ring grows and fades")
        let returning = TerminalBehavior.noticePose(elapsed: 0.85)
        precondition(returning.glance > 0 && returning.glance < 1, "the eyes come back")
        let finished = TerminalBehavior.noticePose(elapsed: 1)
        precondition(finished.rise == 0 && finished.glance == 0 && finished.ringOpacity == 0 && finished.squashX == 1)
        precondition(TerminalBehavior.noticePose(elapsed: -1).ringOpacity == 0)
        precondition(TerminalBehavior.noticeLookActive(elapsed: 1.05), "the eyes stay forward for a moment")
        precondition(TerminalBehavior.noticeLookActive(elapsed: 1.15) == false)
        let upLeft = TerminalBehavior.glanceDirection("green")
        let upRight = TerminalBehavior.glanceDirection("orange")
        let downLeft = TerminalBehavior.glanceDirection("purple")
        let downRight = TerminalBehavior.glanceDirection("red")
        precondition(upLeft.x < 0 && upLeft.y > 0, "green looks up-left")
        precondition(upRight.x > 0 && upRight.y > 0 && TerminalBehavior.glanceDirection("yellow") == upRight, "yellow looks up-right")
        precondition(downLeft.x < 0 && downLeft.y < 0, "purple looks down-left")
        precondition(downRight.x > 0 && downRight.y < 0, "red looks down-right")
        precondition(TerminalBehavior.noticeHopOpen == 6 && TerminalBehavior.noticeHopCompact == 3)
        let desk = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalDesk.swift", encoding: .utf8)
        let tick = sourceSlice(desk, from: "private func tick()", until: "private func apply(")
        precondition(tick.contains("toolShineHex"), "claiming Xcode, Grok, or Claude shines that color")
        precondition(tick.contains("TerminalFrameFlash"), "a claimed window flashes its blob color")
        precondition(tick.contains("attentionFlash"), "needing input flashes the blob color in the notch")
        precondition(tick.contains("notices[slot.id]"), "needing input starts the hop, glance, and ring")
        precondition(tick.contains("acceptPlain"), "plain shells are claimed while Terminal is restoring")
        precondition(tick.contains("firstWindowsAt"), "an empty listing does not start the restore clock")
        precondition(tick.contains("userNamed:"), "a name you typed is not replaced")
        precondition(tick.contains("shellProfile"), "a plain shell takes its blob profile")
        precondition(tick.contains("useShellProfile"), "claiming a plain shell colors that window")
        precondition(TerminalBehavior.shellProfile("green") == "Grass")
        precondition(TerminalBehavior.shellProfile("orange") == "Man Page")
        precondition(TerminalBehavior.shellProfile("yellow") == "Man Page")
        precondition(TerminalBehavior.shellProfile("purple") == "Violet")
        precondition(TerminalBehavior.shellProfile("red") == "Red Sands")
        precondition(TerminalBehavior.violetBackground == (red: 18000, green: 8000, blue: 28000))
        precondition(!tick.contains("reflowOpen"), "closing one terminal does not move the others")
        precondition(!tick.contains("closedOne && didTile"), "a closed terminal does not reflow the desk")
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

        precondition(TerminalBehavior.shortTitle(running, fallback: "Terminal 1") == "terminal", TerminalBehavior.shortTitle(running, fallback: "Terminal 1"))
        precondition(TerminalBehavior.shortTitle(quiet, fallback: "Terminal 2") == "Coucou", TerminalBehavior.shortTitle(quiet, fallback: "Terminal 2"))

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
        precondition(tick.contains("marriedWindow"), "a tick keeps the window the blob opened")
        precondition(tick.contains("classify(title:"), "each blob reads its own window title")
        precondition(tick.contains("claimFreeWindows"), "a free blob claims a restored terminal, or Xcode, Grok, or Claude")
        precondition(tick.contains("startupGrace"), "Coucou keeps looking after an empty start")
        precondition(tick.contains("lockNoun"), "the first noun stays until that terminal closes")
        precondition(!tick.contains("reflowOpen"), "closing one terminal leaves the other frames alone")
        let view = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalNotchView.swift", encoding: .utf8)
        let compact = sourceSlice(view, from: "struct CompactTerminalFaces", until: "struct TerminalSettingsSection")
        precondition(compact.contains("statusColorHex"), "each compact blob shows its own status light")
        precondition(TerminalBehavior.collapsedStatusLight == 8, "the closed-notch status light is \(TerminalBehavior.collapsedStatusLight)pt")
        precondition(TerminalBehavior.collapsedStatusShift == 5, "the closed-notch status light hangs off the corner")
        precondition(compact.contains("collapsedStatusLight"), "the closed notch uses the larger status light")
        precondition(compact.contains("collapsedStatusShift"), "the closed-notch status light sits past the blob")
    }

    /// Each married blob follows its own window. Grok's prompt box is not a status.
    /// A response keeps the blob's own color and lights the status dot blue.
    /// A blue glow sits behind the figure. The prompt box stays orange.
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
        precondition(TerminalBehavior.blobLightHex(slotHex: "#22C55E", face: green.face) == "#22C55E")
        precondition(TerminalBehavior.blobLightHex(slotHex: "#F29B38", face: yellow.face) == "#F29B38")
        precondition(TerminalBehavior.blobLightHex(slotHex: "#22C55E", face: quiet.face) == "#22C55E")
        precondition(TerminalBehavior.blobLightHex(slotHex: "#7C5CFF", face: question.face) == "#7C5CFF")
        precondition(TerminalBehavior.statusColorHex(for: green.face) == "#3D8BFF")
        precondition(TerminalBehavior.statusColorHex(for: question.face) == "#C084FC")
        precondition(TerminalBehavior.showsWorkingGlow(green.face))
        precondition(TerminalBehavior.showsWorkingGlow(question.face))
        precondition(TerminalBehavior.showsWorkingGlow(quiet.face) == false)
        precondition(TerminalBehavior.workingGlowHex == "#3D8BFF")
        precondition(TerminalBehavior.classify(title: incoming, contents: "samuel@mac ~ %").face == .idle)

        let view = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalNotchView.swift", encoding: .utf8)
        let open = sourceSlice(view, from: "struct TerminalFaceButton", until: "struct TerminalPageLockButton")
        precondition(open.contains("workingGlow"), "the open blob glows while it is working")
        precondition(open.contains("statusColorHex"), "the open status dot stays beside the name")
        precondition(!open.contains("blobLightHex"), "the open blob does not take the status color")
        guard let glow = open.range(of: "workingGlow"), let bot = open.range(of: "MiniBotCanvasView") else {
            preconditionFailure("the open face lost its glow or its figure")
        }
        precondition(glow.lowerBound < bot.lowerBound, "the glow is drawn behind the figure")
        let compactFace = sourceSlice(view, from: "struct CompactTerminalFaces", until: "struct TerminalSettingsSection")
        precondition(compactFace.contains("workingGlow"), "the closed notch glows behind a working blob")
        precondition(compactFace.contains("bottomTrailing"), "the closed-notch status light stays at the bottom right")
        precondition(compactFace.contains("statusColorHex"), "the closed-notch status light keeps its color")
        precondition(!compactFace.contains("blobLightHex"), "the closed blob does not take the status color")
        precondition(!compactFace.contains(".stroke"), "the working circle is not drawn on top of the closed blob")
        let task = sourceSlice(view, from: "private func faceTask", until: "struct TerminalPromptField")
        precondition(task.contains("color: slot.color"), "the figure is painted with the slot color")
        precondition(task.contains("holdSlotColor: true"), "a working terminal blob does not wash its body")
        let engine = try! String(contentsOfFile: "NotchBuddy/Sources/CoucouKit/BotEngine.swift", encoding: .utf8)
        let bodyDraw = sourceSlice(engine, from: "private func drawBody", until: "private func drawBlush")
        precondition(bodyDraw.contains("holdSlotColor"), "the body fill skips the state wash when the slot color is held")
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
        precondition(TerminalBehavior.blobLightHex(slotHex: "#22C55E", face: face.face) == "#22C55E")
        precondition(TerminalBehavior.showsWorkingGlow(face.face))
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
    /// and lights from its title. A window outside every corner is not that corner.
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
        precondition(TerminalBehavior.blobLightHex(slotHex: "#22C55E", face: face.face) == "#22C55E")
        precondition(TerminalBehavior.showsWorkingGlow(face.face))

        let desk = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalDesk.swift", encoding: .utf8)
        let tick = sourceSlice(desk, from: "private func tick()", until: "private func apply(")
        precondition(tick.contains("marriagesForCorners"), "a tick marries the window already in that corner")
        let open = sourceSlice(desk, from: "func openOrFocus(", until: "func togglePageLock(")
        precondition(open.contains("windowInCorner"), "pressing the blob focuses the window already in that corner")
        let snapshot = sourceSlice(desk, from: "static func snapshot", until: "nonisolated static func openOrFocus")
        precondition(snapshot.contains("bounds of w"), "the listing reads each window's own frame")
    }

    /// Terminal gives a session a new window id when its tab moves.
    /// The blob stays on that session. A window Coucou cannot read is skipped,
    /// so one bad window does not hide the rest. The heartbeat stays off.
    static func testMarriageFollowsTheSameTerminalWhenItsWindowChanges() {
        let live = [
            TerminalBehavior.LiveSession(id: 171, tty: "/dev/ttys000"),
            TerminalBehavior.LiveSession(id: 292, tty: "/dev/ttys001"),
        ]
        let repaired = TerminalBehavior.marriedWindow(
            savedID: 170,
            savedTTY: "/dev/ttys000",
            live: live,
            listed: true
        )
        precondition(repaired.windowID == 171 && repaired.terminated == false, "the same tty is still the green terminal")
        let stayed = TerminalBehavior.marriedWindow(savedID: 292, savedTTY: "/dev/ttys001", live: live, listed: true)
        precondition(stayed.windowID == 292 && stayed.terminated == false)
        let gone = TerminalBehavior.marriedWindow(
            savedID: 99,
            savedTTY: "",
            live: live,
            listed: true
        )
        precondition(gone.terminated && gone.windowID == nil, "a closed terminal still ends the marriage")
        let unread = TerminalBehavior.marriedWindow(savedID: 99, savedTTY: "/dev/ttys009", live: [], listed: false)
        precondition(unread.windowID == 99 && unread.terminated == false, "a failed listing keeps the marriage")
        let ambiguous = TerminalBehavior.marriedWindow(
            savedID: 99,
            savedTTY: "/dev/ttys000",
            live: [
                TerminalBehavior.LiveSession(id: 171, tty: "/dev/ttys000"),
                TerminalBehavior.LiveSession(id: 172, tty: "/dev/ttys000"),
            ],
            listed: true
        )
        precondition(ambiguous.terminated && ambiguous.windowID == nil, "two windows with one tty are not guessed")

        let listing = "170\t0.0\t45.0\t1024.0\t687.0\t/dev/ttys000\tsamuel — ⠋ - Running: keep this session\n643\t\t\t\t\t/dev/ttys003\tsamuel — bottom left"
        let read = TerminalBehavior.parseSnapshot(listing + "\u{1e}", slotCount: 2)
        precondition(read.listed, "a tty listing is a real window list")
        precondition(read.windows[0].tty == "/dev/ttys000", "tty was \(read.windows[0].tty)")
        precondition(read.windows[0].bounds == TerminalBehavior.TerminalBounds(left: 0, top: 45, right: 1024, bottom: 687))
        precondition(read.windows[0].title == "samuel — ⠋ - Running: keep this session")
        precondition(read.windows[1].tty == "/dev/ttys003" && read.windows[1].bounds == nil, "a window with no frame still keeps its tty")

        let desk = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalDesk.swift", encoding: .utf8)
        let snapshot = sourceSlice(desk, from: "static func snapshot", until: "nonisolated static func openOrFocus")
        precondition(snapshot.contains("tty of selected tab"), "the listing reads the session tty")
        precondition(!snapshot.contains("on error"), "a window with no id must not abort the listing")
        let tick = sourceSlice(desk, from: "private func tick()", until: "private func apply(")
        precondition(tick.contains("marriedWindow"), "a tick follows the session when the window id changes")
        precondition(tick.contains("placeInFlight"), "moving a tab does not divorce the blob mid-place")
        let open = sourceSlice(desk, from: "func openOrFocus(", until: "func togglePageLock(")
        precondition(open.contains("resolvedWindowID"), "a press focuses the session, not a new window")
        let resolver = sourceSlice(desk, from: "private func resolvedWindowID", until: "func openOrFocus")
        precondition(resolver.contains("marriedWindow"), "the press follows the saved session")
    }

    /// A click on the closed purple blob is the bottom-left color, and it still
    /// focuses that terminal after the notch opens.
    static func testClosedPurpleClickKeepsThatTerminal() {
        let centerX: CGFloat = 518
        let centerY: CGFloat = 22.5
        let scale: CGFloat = 1
        let side = TerminalBehavior.compactSide * scale
        func slot(_ dx: CGFloat, _ dy: CGFloat) -> String? {
            TerminalBehavior.collapsedBlobSlot(
                x: centerX + dx,
                y: centerY + dy,
                centerX: centerX,
                centerY: centerY,
                scale: scale
            )
        }
        precondition(slot(-side / 4, -side / 4) == "green")
        precondition(slot(side / 4, -side / 4) == "orange")
        precondition(slot(-side / 4, side / 4) == "purple", "purple is the bottom left")
        precondition(slot(side / 4, side / 4) == "red")
        precondition(slot(-side / 2 - 10, 0) == nil, "a click past the ear is not a blob")
        precondition(slot(-side / 4, side / 2 + 4) == "purple", "the figure that hangs below the frame is still purple")
        precondition(TerminalBehavior.collapsedBlobSlot(
            x: centerX, y: centerY, centerX: centerX, centerY: centerY, scale: 0
        ) == nil)

        let controller = try! String(contentsOfFile: "NotchBuddy/Sources/App/IslandWindowController.swift", encoding: .utf8)
        let press = sourceSlice(controller, from: "matching: .leftMouseDown", until: "matching: .leftMouseDragged")
        precondition(press.contains("closedTerminalBlob"), "the press remembers which closed blob was hit")
        let mouseUp = sourceSlice(controller, from: "matching: .leftMouseUp", until: "addGlobalMonitorForEvents")
        precondition(mouseUp.contains("finishBlobPress"), "mouse up still finishes the pressed blob")
        precondition(mouseUp.contains("fsm.click()") || mouseUp.contains("expand("), "the notch still opens")
        let finishAt = mouseUp.range(of: "finishBlobPress")
        let clickAt = mouseUp.range(of: "fsm.click()") ?? mouseUp.range(of: "expand(")
        precondition(finishAt != nil && clickAt != nil && finishAt!.lowerBound < clickAt!.lowerBound, "the terminal is focused before the notch opens and resets the color")
        let finish = sourceSlice(controller, from: "private func finishBlobPress", until: "private func startKeyMonitor")
        precondition(finish.contains("armSelection"), "the color is armed before the notch opens")
        precondition(finish.contains(".focus:"), "a click focuses that terminal")
    }

    /// Hover opens the notch as soon as the pointer arrives. The blob under that
    /// pointer stays selected, and the click still focuses it. One missed listing
    /// does not hand that terminal to another color.
    static func testHoverOntoPurpleFocusesThatTerminal() {
        precondition(TerminalBehavior.releaseMarriage(terminated: true, misses: 1) == false, "one missed listing keeps the marriage")
        precondition(TerminalBehavior.releaseMarriage(terminated: true, misses: 2), "a window that stays gone is released")
        precondition(TerminalBehavior.releaseMarriage(terminated: false, misses: 3) == false)

        let controller = try! String(contentsOfFile: "NotchBuddy/Sources/App/IslandWindowController.swift", encoding: .utf8)
        let hover = sourceSlice(controller, from: "alwaysOpenOnHover", until: "fsm.mouseLeft()")
        let beforeOpen = sourceSlice(hover, from: "alwaysOpenOnHover", until: "fsm.click()")
        precondition(beforeOpen.contains("armSelection"), "hover arms the blob under the pointer before the notch opens")
        precondition(beforeOpen.contains("closedAimID"), "hover uses the blob the pointer is on")
        let press = sourceSlice(controller, from: "matching: .leftMouseDown", until: "matching: .leftMouseDragged")
        precondition(press.contains("closedAimID"), "the click still focuses that blob after hover opens the notch")

        let desk = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalDesk.swift", encoding: .utf8)
        let tick = sourceSlice(desk, from: "private func tick()", until: "private func apply(")
        precondition(tick.contains("releaseMarriage"), "a tick waits before giving the terminal to another color")
    }

    /// A window sitting in the yellow corner lights the yellow blob.
    /// Purple does not keep it, and purple does not claim it later.
    /// Holding an empty color still opens that color in its own corner.
    static func testYellowCornerStaysOnYellow() {
        let span = (left: 0, top: 45, width: 2048, height: 1285)
        func quad(_ id: String) -> TerminalBehavior.TerminalBounds {
            TerminalBehavior.quadrantBounds(
                slotID: id,
                visibleLeft: span.left,
                visibleTop: span.top,
                visibleWidth: span.width,
                visibleHeight: span.height
            )
        }
        let quadrants = [
            "green": quad("green"),
            "orange": quad("orange"),
            "purple": quad("purple"),
            "red": quad("red"),
        ]
        let yellowFrame = TerminalBehavior.TerminalBounds(left: 1020, top: 45, right: 2048, bottom: 692)
        let greenFrame = TerminalBehavior.TerminalBounds(left: 0, top: 45, right: 1023, bottom: 700)
        let loose = TerminalBehavior.TerminalBounds(left: 200, top: 200, right: 700, bottom: 600)
        precondition(TerminalBehavior.cornerOwner(bounds: yellowFrame, quadrants: quadrants) == "orange", "the top-right frame is yellow")
        precondition(TerminalBehavior.cornerOwner(bounds: greenFrame, quadrants: quadrants) == "green")
        precondition(TerminalBehavior.cornerOwner(bounds: loose, quadrants: quadrants) == nil, "a window between corners is not guessed")

        let saved = [
            TerminalBehavior.CornerClaim(id: "green", windowID: 4618, tty: "/dev/ttys003", lockedName: "grok"),
            TerminalBehavior.CornerClaim(id: "orange", windowID: nil, tty: "", lockedName: ""),
            TerminalBehavior.CornerClaim(id: "purple", windowID: 4024, tty: "/dev/ttys007", lockedName: "Coucou"),
            TerminalBehavior.CornerClaim(id: "red", windowID: nil, tty: "", lockedName: ""),
        ]
        let windows = [
            TerminalBehavior.ListedWindow(id: 4618, title: "grok", bounds: greenFrame, tty: "/dev/ttys003"),
            TerminalBehavior.ListedWindow(id: 4024, title: "Coucou", bounds: yellowFrame, tty: "/dev/ttys007"),
        ]
        let seated = TerminalBehavior.marriagesForCorners(slots: saved, windows: windows, quadrants: quadrants)
        precondition(seated[0].windowID == 4618 && seated[0].lockedName == "grok", "green keeps its own corner")
        precondition(seated[1].windowID == 4024 && seated[1].tty == "/dev/ttys007" && seated[1].lockedName == "Coucou", "yellow takes the window in its corner")
        precondition(seated[2].windowID == nil && seated[2].tty.isEmpty && seated[2].lockedName.isEmpty, "purple lets go of the yellow window")
        precondition(seated[3].windowID == nil)

        let unframed = TerminalBehavior.marriagesForCorners(
            slots: saved,
            windows: [TerminalBehavior.ListedWindow(id: 4024, title: "Coucou", tty: "/dev/ttys007")],
            quadrants: quadrants
        )
        precondition(unframed[2].windowID == 4024, "a listing with no frame keeps the saved marriage")

        let parked = TerminalBehavior.marriagesForCorners(
            slots: [
                TerminalBehavior.CornerClaim(id: "purple", windowID: 50, tty: "/dev/ttys009", lockedName: "Notes"),
            ],
            windows: [TerminalBehavior.ListedWindow(id: 50, title: "Notes", bounds: loose, tty: "/dev/ttys009")],
            quadrants: quadrants
        )
        precondition(parked[0].windowID == 50 && parked[0].lockedName == "Notes", "a window outside every corner stays where it was opened")

        let claimed = TerminalBehavior.claimFreeWindows(
            slots: [
                TerminalBehavior.ClaimSlot(id: "green", windowID: 4618, tty: "/dev/ttys003"),
                TerminalBehavior.ClaimSlot(id: "orange", windowID: 1, tty: "/dev/ttys001"),
                TerminalBehavior.ClaimSlot(id: "purple", windowID: nil, tty: ""),
                TerminalBehavior.ClaimSlot(id: "red", windowID: nil, tty: ""),
            ],
            open: [TerminalBehavior.ListedWindow(id: 4024, title: "samuel — -zsh — 80×24", bounds: yellowFrame, tty: "/dev/ttys007")],
            freeIDs: ["purple", "red"],
            acceptPlain: true,
            quadrants: quadrants
        )
        precondition(claimed[2].windowID == nil && claimed[3].windowID == nil, "purple does not claim the window in the yellow corner")

        let desk = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalDesk.swift", encoding: .utf8)
        let tick = sourceSlice(desk, from: "private func tick()", until: "private func apply(")
        precondition(tick.contains("marriagesForCorners"), "a tick gives a corner back to its color")
        let open = sourceSlice(desk, from: "func openOrFocus(", until: "func togglePageLock(")
        precondition(open.contains("shellProfile"), "opening a color uses that color's terminal profile")
        precondition(open.contains("quadrantPlacements") || open.contains("cornerFrames"), "opening a color uses that color's corner")

        let controller = try! String(contentsOfFile: "NotchBuddy/Sources/App/IslandWindowController.swift", encoding: .utf8)
        let globalUp = sourceSlice(controller, from: "matching: .leftMouseUp) { [weak self] _ in", until: "matching: .keyDown")
        precondition(globalUp.contains("finishBlobPress"), "a hold still opens the color after the pointer leaves the notch")
        let finish = sourceSlice(controller, from: "private func finishBlobPress", until: "private func startKeyMonitor")
        precondition(finish.contains("openOrFocus"), "holding the blob opens that color in its corner")
        precondition(finish.contains(".focus:"), "a short press still only brings the window forward")
    }

    /// A click on green, yellow, purple, or red opens that color when it has no
    /// terminal. A color that already has one is only brought forward. The click
    /// counts even when the pointer just arrived.
    static func testEmptyBlobClickOpensThatColor() {
        let desk = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalDesk.swift", encoding: .utf8)
        let focus = sourceSlice(desk, from: "func focus(", until: "func openOrFocus(")
        let resolved = focus.range(of: "resolvedWindowID")
        let opens = focus.range(of: "openOrFocus")
        let raises = focus.range(of: "TerminalBridge.focus")
        precondition(
            resolved != nil && opens != nil && raises != nil
                && resolved!.lowerBound < opens!.lowerBound
                && opens!.lowerBound < raises!.lowerBound,
            "an empty blob opens that color; a married window is only raised"
        )

        let controller = try! String(contentsOfFile: "NotchBuddy/Sources/App/IslandWindowController.swift", encoding: .utf8)
        let press = sourceSlice(controller, from: "matching: .leftMouseDown", until: "matching: .leftMouseDragged")
        let hit = press.range(of: "closedTerminalBlob")
        let gate = press.range(of: "wasInIsland")
        precondition(
            hit != nil && gate != nil && hit!.lowerBound < gate!.lowerBound,
            "a blob click counts before the pointer has rested in the notch"
        )
        precondition(press.contains("terminalBlob"), "an open face uses the same click for every color")
        precondition(press.contains("|| slot != nil"), "a hit blob is pressed even when the notch has not seen the pointer yet")
    }

    /// Green, yellow, purple, and red each open in that color. Pulling the new
    /// tab into its own window happens first, and that window still gets Grass,
    /// Man Page, Violet, or Red Sands.
    static func testNewWindowKeepsTheBlobColor() {
        let desk = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalDesk.swift", encoding: .utf8)
        let created = sourceSlice(desk, from: "func openNew(", until: "enum CotypistLink")
        let createdMove = created.range(of: "moveTabToOwnWindow")
        let createdColor = created.range(of: "profileCommands")
        precondition(
            createdMove != nil && createdColor != nil && createdMove!.lowerBound < createdColor!.lowerBound,
            "a new window takes the blob color after it leaves the tab"
        )
        let placed = sourceSlice(desk, from: "func placeMany(", until: "func useShellProfile")
        let placedMove = placed.range(of: "moveTabToOwnWindow")
        let placedColor = placed.range(of: "profileCommands")
        precondition(
            placedMove != nil && placedColor != nil && placedMove!.lowerBound < placedColor!.lowerBound,
            "placing that window in its corner keeps the blob color"
        )
        let paint = sourceSlice(desk, from: "func profileCommands", until: "func useShellProfile")
        precondition(paint.contains("settings set profileName"), "the blob color is Grass, Man Page, Violet, or Red Sands")
        let opener = sourceSlice(desk, from: "func openOrFocus(", until: "func togglePageLock(")
        precondition(opener.contains("profile: shell"), "the click passes that blob's profile into the new window")
        precondition(opener.contains("placeMany(batch, focus: focus, profile: shell)"), "the corner placement uses the same profile")
    }

    /// Grass, Man Page, Violet, and Red Sands replace the current settings and
    /// put the font back to 11pt, which also shrinks the window. The size that
    /// stays is applied after that color, and the corner is applied after the size.
    static func testFontFillsTheCornerAfterTheColor() {
        let desk = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalDesk.swift", encoding: .utf8)
        let created = sourceSlice(desk, from: "func openNew(", until: "enum CotypistLink")
        let placed = sourceSlice(desk, from: "func placeMany(", until: "func useShellProfile")
        for slice in [created, placed] {
            let color = slice.range(of: "profileCommands")
            precondition(color != nil, "the blob color is applied")
            let font = slice.range(of: "font size of current settings", range: color!.upperBound..<slice.endIndex)
            precondition(font != nil, "the font is set after the color, or the profile puts it back to 11")
            let corner = slice.range(of: "set bounds", range: font!.upperBound..<slice.endIndex)
            precondition(corner != nil, "the corner is set after the font, or the window shrinks to the profile size")
        }
        let paint = sourceSlice(desk, from: "func useShellProfile", until: "func focus(")
        let switched = paint.range(of: "settings set profileName")
        precondition(switched != nil, "the follow-up still applies the blob color")
        let kept = paint.range(of: "font size of current settings", range: switched!.upperBound..<paint.endIndex)
        precondition(kept != nil, "the follow-up color keeps the larger font")
        let restored = paint.range(of: "set bounds", range: kept!.upperBound..<paint.endIndex)
        precondition(restored != nil, "the follow-up color puts the window back in its corner")
        let opener = sourceSlice(desk, from: "func openOrFocus(", until: "func togglePageLock(")
        let follow = opener.range(of: "useShellProfile")
        precondition(follow != nil, "a new window still takes its color after it is placed")
        precondition(
            opener.range(of: "bounds:", range: follow!.lowerBound..<opener.endIndex) != nil,
            "that follow-up is given the corner so it can put the window back"
        )
    }

    /// The notch click and the blob gesture both see one press. The second one
    /// must not start another terminal while the first is still opening.
    /// `launch` is an AppleScript command. Assigning the model line to it
    /// stops the window before Terminal creates it.
    static func testModelFlagDoesNotUseTheLaunchCommand() {
        let desk = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalDesk.swift", encoding: .utf8)
        let created = sourceSlice(desk, from: "func openNew(", until: "enum CotypistLink")
        precondition(!created.contains("set launch to"), "launch is an AppleScript command, so the model line never runs")
        precondition(created.contains("--model"), "Claude and Grok still start with the model saved under Keys")
        precondition(created.contains("shellLine"), "the model flag is passed in a plain variable")
    }

    static func testOneClickOpensOneWindow() {
        precondition(TerminalBehavior.startsOneWindow(inFlight: false), "the first press opens the color")
        precondition(TerminalBehavior.startsOneWindow(inFlight: true) == false, "a press already opening that color does not open a tab as well")
        let desk = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalDesk.swift", encoding: .utf8)
        let opener = sourceSlice(desk, from: "func openOrFocus(", until: "func togglePageLock(")
        let gate = opener.range(of: "startsOneWindow")
        let created = opener.range(of: "TerminalBridge.openOrFocus")
        precondition(
            gate != nil && created != nil && gate!.lowerBound < created!.lowerBound,
            "the extra press is ignored before a second terminal starts"
        )
    }
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

    /// Each color can open Grok, Claude, or Codex. An unknown choice stays on Grok.
    /// The settings page shows the three status lights instead of the long passage.
    static func testEachTerminalChoosesAnAssistant() {
        precondition(TerminalBehavior.launchTool("grok") == "grok")
        precondition(TerminalBehavior.launchTool("claude") == "claude")
        precondition(TerminalBehavior.launchTool("codex") == "codex")
        precondition(TerminalBehavior.launchTool("something-else") == "grok", "an unknown assistant stays on Grok")
        precondition(TerminalBehavior.missingLine(for: "claude") == "Claude CLI not found")
        precondition(TerminalBehavior.missingLine(for: "codex") == "Codex CLI not found")
        precondition(TerminalBehavior.cliIsMissing("Grok CLI not found"))
        precondition(TerminalBehavior.cliIsMissing("Claude CLI not found"))
        precondition(!TerminalBehavior.cliIsMissing("compiling sources"))
        precondition(
            TerminalBehavior.assistantDetail("claude", claudeModel: "claude-sonnet-4-6", grokModel: "grok-4.7")
                == "Claude Sonnet 4.6 in Keys"
        )
        precondition(
            TerminalBehavior.assistantDetail("grok", claudeModel: "claude-sonnet-4-6", grokModel: "grok-4.7")
                == "Grok 4.7 in Keys"
        )
        precondition(
            TerminalBehavior.modelArgument(tool: "claude", claudeModel: "claude-sonnet-4-6", grokModel: "grok-4.7")
                == "claude-sonnet-4-6"
        )
        precondition(
            TerminalBehavior.modelArgument(tool: "grok", claudeModel: "claude-sonnet-4-6", grokModel: " grok-4.7 ")
                == "grok-4.7"
        )
        precondition(
            TerminalBehavior.modelArgument(tool: "codex", claudeModel: "claude-sonnet-4-6", grokModel: "grok-4.7").isEmpty,
            "Codex has no model under Keys"
        )
        let claude = TerminalBehavior.classify("Claude CLI not found")
        precondition(claude.face == .idle && claude.grokMissing, "a missing Claude install stays idle")

        let view = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalNotchView.swift", encoding: .utf8)
        let settings = sourceSlice(view, from: "struct TerminalSettingsSection", until: "private func blobLabel")
        precondition(!settings.contains("The name stays on the first topic word"), "the long terminal passage is gone")
        precondition(settings.contains("statusColorHex"), "the settings page shows the status lights")
        precondition(settings.contains("Idle") && settings.contains("New response") && settings.contains("Needs input"), "the lights name the three states")
        precondition(settings.contains("launchTool"), "each terminal can choose its assistant")
        precondition(settings.contains("assistantDetail"), "the terminal row uses the model saved in Keys")
        let keys = try! String(contentsOfFile: "NotchBuddy/Sources/App/SettingsView.swift", encoding: .utf8)
        let keysBody = sourceSlice(keys, from: "var body: some View", until: "private func applyCustomModel")
        precondition(keysBody.contains("HStack(alignment: .top"), "the Keys page sits in two columns")
        precondition(settings.contains("Claude") && settings.contains("Codex") && settings.contains("Grok"), "the choices are Claude, Grok, and Codex")

        let desk = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalDesk.swift", encoding: .utf8)
        let created = sourceSlice(desk, from: "func openNew(", until: "enum CotypistLink")
        precondition(created.contains("toolName"), "a new window runs the assistant that color chose")
        precondition(created.contains("command -v"), "the window checks that the assistant is installed")
        precondition(created.contains("--model"), "a new window starts on the model saved in Keys")
        precondition(created.contains("quoted form of modelID"), "the model id is quoted")
        let opener = sourceSlice(desk, from: "func openOrFocus(", until: "func togglePageLock(")
        precondition(opener.contains("launchTool"), "opening a color uses that color's assistant")
        precondition(opener.contains("modelArgument"), "opening a color uses the model saved in Keys")
    }

    /// The orange corner light is a terminal's idle status. A blob with no
    /// window leaves that light off. A connected terminal keeps it.
    static func testEmptyBlobHidesTheCornerLight() {
        precondition(TerminalBehavior.showsStatusLight(connected: false) == false, "a blob with no terminal leaves the corner light off")
        precondition(TerminalBehavior.showsStatusLight(connected: true), "a connected terminal keeps its corner light")
        let view = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalNotchView.swift", encoding: .utf8)
        let open = sourceSlice(view, from: "struct TerminalFaceButton", until: "struct TerminalPageLockButton")
        let compact = sourceSlice(view, from: "struct CompactTerminalFaces", until: "struct TerminalSettingsSection")
        precondition(open.contains("showsStatusLight"), "the open blob light follows whether a terminal is connected")
        precondition(compact.contains("showsStatusLight"), "the closed-notch corner light follows whether a terminal is connected")
        precondition(open.contains("slot.windowID"), "the open blob checks its own window")
        precondition(compact.contains("slot.windowID"), "the closed notch checks its own window")
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

    /// Idle, a response, and a question keep their colors. The heartbeat is off.
    static func testStatusHeartbeats() {
        precondition(TerminalBehavior.statusPhrase(for: .idle) == "Idle")
        precondition(TerminalBehavior.statusPhrase(for: .working) == "New response available")
        precondition(TerminalBehavior.statusPhrase(for: .waiting) == "Needs your input")
        precondition(TerminalBehavior.statusColorHex(for: .idle) == "#FF9F1C")
        precondition(TerminalBehavior.statusColorHex(for: .working) == "#3D8BFF")
        precondition(TerminalBehavior.statusColorHex(for: .waiting) == "#C084FC")
        precondition(TerminalBehavior.heartbeatBPM(for: .idle) == 0)
        precondition(TerminalBehavior.heartbeatBPM(for: .working) == 0)
        precondition(TerminalBehavior.heartbeatBPM(for: .waiting) == 0)
        precondition(TerminalBehavior.heartbeatLevel(seconds: 0.08, bpm: 60) == 0)
        precondition(TerminalBehavior.heartbeatLevel(seconds: 0.5, bpm: 126) == 0)
        let faces = try! String(contentsOfFile: "NotchBuddy/Sources/App/TerminalNotchView.swift", encoding: .utf8)
        precondition(!faces.contains("heartbeatLevel"), "the blobs no longer pulse")
        precondition(!faces.contains("heartbeatBPM"), "the blobs no longer pulse")
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
        precondition(TerminalBehavior.blobSlot(x: 430, y: 60, islandWidth: 640, contentTop: 0) == "green")
        precondition(TerminalBehavior.blobSlot(x: 560, y: 60, islandWidth: 640, contentTop: 0) == "orange")
        precondition(TerminalBehavior.blobSlot(x: 430, y: 110, islandWidth: 640, contentTop: 0) == "purple")
        precondition(TerminalBehavior.blobSlot(x: 560, y: 110, islandWidth: 640, contentTop: 0) == "red")
        precondition(TerminalBehavior.blobSlot(x: 100, y: 60, islandWidth: 640, contentTop: 0) == nil)
        precondition(TerminalBehavior.blobSlot(x: 400, y: 200, islandWidth: 640, contentTop: 0) == nil)
        precondition(TerminalBehavior.blobSlot(x: 430, y: 105, islandWidth: 640, contentTop: 45) == "green")
        // Header has moved into the menu bar, so the faces sit higher in the drawer.
        precondition(TerminalBehavior.blobSlot(x: 430, y: 70, islandWidth: 640, contentTop: 45, headerInContent: false) == "green")
        precondition(TerminalBehavior.blobSlot(x: 560, y: 70, islandWidth: 640, contentTop: 45, headerInContent: false) == "orange")
        precondition(TerminalBehavior.blobSlot(x: 430, y: 110, islandWidth: 640, contentTop: 45, headerInContent: false) == "purple")
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
