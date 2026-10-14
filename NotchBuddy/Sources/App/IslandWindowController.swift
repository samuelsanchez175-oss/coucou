import AppKit
import Combine
import ObjectiveC
import SwiftUI

@MainActor
final class IslandWindowController: NSWindowController {

    private var islandPanel: IslandPanel!
    private var state: AppState { AppState.shared }

    // State machine (replaces all hover/absence/auto-close timers)
    let fsm = IslandStateMachine()

    private var wasInIsland = false
    /// Settings tab whose notch page should stay up. `.none` means settings is closed.
    private var settingsPreview: SettingsNotchPage = .none
    /// True after the first pointer sample, so launch does not tick by itself.
    private var hapticReady = false
    private var hapticWasOutside = true
    private var pageLockWasOn = false
    private var frameTimer: Timer?
    private var keyMonitor: Any?
    private var escapeMonitor: Any?
    private var viewSubscription: AnyCancellable?
    private var displaySubscription: AnyCancellable?
    private var autoCloseSubscription: AnyCancellable?
    private var openOnHoverSubscription: AnyCancellable?

    // Confused recovery timer (set by handleDizzy)
    private var confusedRecoveryTimer: DispatchWorkItem?

    // Voice result auto-dismiss timer
    #if !APPSTORE
    private var voiceResultWork: DispatchWorkItem?
    /// True only while Coucou listens for the answer to a question it asked.
    private var isInConversation = false
    /// Context (last action, on-device model session) is kept a little after a turn so
    /// "OK Coucou, et Stripe aussi" still works; this resets it.
    private var voiceContextExpiry: DispatchWorkItem?
    private var conversationContext = ConversationContext()
    private var consecutiveFailures = 0
    private var hasSpokenPasCompris = false
    #endif

    // Suppress peek sound on next reveal (e.g. musicReveal)
    var silentNextReveal = false

    // Finished-pin timer
    private var finishedPinTimer: DispatchWorkItem?

    // Bot-head hover (love emote — mirrors prototype botHover())
    private var hoverTimer: DispatchWorkItem?
    private var botHoverTimer: DispatchWorkItem?
    private var botHovering: Bool = false
    private var lastLoveTime: Double = 0
    private var botHoverStartPos: CGPoint = .zero

    // Window attach drag (M8)
    private var attachDragStart: NSPoint? = nil
    private var pendingIslandClick = false   // any island click → expand on mouseUp
    /// Closed-notch color under the press. The faces unmount when the notch opens, so the gesture never ends.
    private var blobPressID: String?
    private var blobPressAt: Date?
    /// The closed blob under the pointer. Hover can open the notch before the click lands.
    private var closedAimID: String?
    private var closedAimAt: Date?
    private var pendingExpandView: IslandView?
    private var pipelineDrag = false
    private var inAttachDrag = false
    private var dragGhostPanel: NSPanel? = nil
    private var dragGhostSize: CGFloat = 0
    private var ghostCurrentOrigin: NSPoint = .zero
    private var highlightPanel: NSPanel? = nil
    private var highlightWindowPid: pid_t = 0

    // Notch real dimensions (set on init)
    private var notchW: CGFloat = IslandConst.notchWidth
    private var notchH: CGFloat = IslandConst.notchHeight
    private var hasNotch = true

    // Island-local key monitor (active only when island is key window)
    private var localKeyMonitor: Any?

    convenience init() {
        let screen = Self.targetScreen(for: AppState.shared.islandDisplay)
        Self.currentScreen = screen
        let fitted = Self.fittedNotch(on: screen)
        let nW = fitted.width
        let nH = fitted.height

        let panelW: CGFloat = IslandConst.panelWidth
        let panelH: CGFloat = IslandConst.panelHeight
        let sf = screen.frame
        let panel = IslandPanel(
            contentRect: NSRect(x: sf.midX - panelW/2, y: sf.maxY - panelH,
                                width: panelW, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.notchWidth  = nW
        panel.notchHeight = nH

        self.init(window: panel)
        self.islandPanel = panel
        self.notchW = nW
        self.notchH = nH
        self.hasNotch = fitted.hasNotch
        setupPanel(screen: screen)
    }

    private func setupPanel(screen: NSScreen) {
        guard let panel = window as? IslandPanel else { return }
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        // Propagate real notch dimensions to AppState
        AppState.shared.notchWidth  = notchW
        AppState.shared.notchHeight = notchH
        AppState.shared.hasNotch = hasNotch

        NotificationCenter.default.addObserver(
            forName: .nookChromeChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyChrome() }
        }

        let contentSize = panel.contentRect(forFrameRect: panel.frame).size

        // Apple-recommended pattern: put NSHostingView and drag destination as siblings
        // inside a common superview, rather than embedding one inside the other.
        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        container.autoresizingMask = [.width, .height]

        let hosting = NotchHostingView(rootView: IslandRootView()
            .environmentObject(AppState.shared)
            .environment(\.layoutDirection, .leftToRight))
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]

        // FileDropNSView sits above SwiftUI. It stays out of clicks, and takes the
        // hit only while a file drag is on the pasteboard.
        let dropView = FileDropNSView(frame: NSRect(origin: .zero, size: contentSize))
        dropView.autoresizingMask = [.width, .height]
        dropView.onDragEntered = { [weak self] loc in
            Task { @MainActor in
                guard let self else { return }
                if let slot = self.terminalBlob(at: loc) {
                    self.pipelineDrag = false
                    TerminalDesk.shared.dropSlotID = slot
                    return
                }
                TerminalDesk.shared.dropSlotID = nil
                if self.dropChoice(at: loc) == .pipeline {
                    self.pipelineDrag = true
                    self.applyTrayHighlight(at: loc)
                    NookBoard.shared.dropWing = self.state.mode != .expanded
                    return
                }
                self.pipelineDrag = false
                let iLoc = self.windowToIsland(loc)
                AppState.shared.fileDragOver = true
                // The voice mail card stays on screen: the file will be its attachment.
                if AppState.shared.voiceMailDraft != nil && AppState.shared.view == .mail {
                    NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(1))
                    return
                }
                // enterZone sets isActive=true BEFORE hookExpand triggers re-render,
                // so IslandContainer sees isActive=true when state.view becomes .upload.
                UploadSequenceEngine.shared.enterZone(x: iLoc.x, y: iLoc.y)
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.upload)
                NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(1))
            }
        }
        dropView.onDragUpdated = { [weak self] loc in
            Task { @MainActor in
                guard let self else { return }
                if let slot = self.terminalBlob(at: loc) {
                    if self.pipelineDrag {
                        self.pipelineDrag = false
                        self.clearTrayHighlight()
                        NookBoard.shared.dropWing = false
                    }
                    if AppState.shared.fileDragOver {
                        AppState.shared.fileDragOver = false
                        NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(0))
                        UploadSequenceEngine.shared.exitZone()
                    }
                    TerminalDesk.shared.dropSlotID = slot
                    return
                }
                let wasOnBlob = TerminalDesk.shared.dropSlotID != nil
                TerminalDesk.shared.dropSlotID = nil
                if self.pipelineDrag {
                    self.applyTrayHighlight(at: loc)
                    return
                }
                if wasOnBlob {
                    self.pipelineDrag = false
                    let iLoc = self.windowToIsland(loc)
                    AppState.shared.fileDragOver = true
                    UploadSequenceEngine.shared.enterZone(x: iLoc.x, y: iLoc.y)
                    NotificationCenter.default.post(name: .hookExpand, object: IslandView.upload)
                    NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(1))
                    return
                }
                let iLoc = self.windowToIsland(loc)
                UploadSequenceEngine.shared.updateCursor(x: iLoc.x, y: iLoc.y)
            }
        }
        dropView.onDragExited = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                TerminalDesk.shared.dropSlotID = nil
                if self.pipelineDrag {
                    self.pipelineDrag = false
                    self.clearTrayHighlight()
                    NookBoard.shared.dropWing = false
                    return
                }
                AppState.shared.fileDragOver = false
                // Do NOT collapse — drag session still active; island stays open.
                NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(0))
                UploadSequenceEngine.shared.exitZone()
            }
        }
        dropView.onFilesDropped = { [weak self] urls, loc in
            Task { @MainActor in
                guard let self else { return }
                #if !APPSTORE
                // A voice email that is waiting for a file takes the drop.
                if VoiceActionRunner.shared.isMailInProgress, let url = urls.first {
                    await self.attachVoiceMailFile(url)
                    return
                }
                if AppState.shared.voiceMailDraft != nil, AppState.shared.view == .mail, let url = urls.first {
                    self.attachToVoiceMailCard(url)
                    return
                }
                #endif
                if let slot = self.terminalBlob(at: loc) {
                    self.pipelineDrag = false
                    TerminalDesk.shared.dropSlotID = nil
                    self.clearTrayHighlight()
                    NookBoard.shared.dropWing = false
                    AppState.shared.fileDragOver = false
                    TerminalDesk.shared.attachFiles(urls, to: slot)
                    return
                }
                TerminalDesk.shared.dropSlotID = nil
                let landing = self.trayLanding(at: loc)
                let pipeline = self.dropChoice(at: loc) == .pipeline || self.pipelineDrag
                self.pipelineDrag = false
                self.clearTrayHighlight()
                NookBoard.shared.dropWing = false
                if pipeline {
                    AppState.shared.fileDragOver = false
                    NookBoard.shared.receiveDrop(urls, landing: landing)
                    let stayOnNook = self.state.mode == .expanded && self.state.view == .nook && landing == .pipeline
                    if stayOnNook {
                        self.openNook()
                    } else {
                        self.openTray()
                    }
                    return
                }
                await FileDropHandler.handle(urls: urls, state: AppState.shared)
            }
        }

        container.addSubview(hosting)    // z-bottom: SwiftUI + mouse events
        container.addSubview(dropView)   // z-top: drag only (hitTest→nil, transparent to mouse)
        panel.contentView = container

        startPolling()
        observeScreenForPolling()
        startKeyMonitor()
        startLocalKeyMonitor()
        startHotKeys()
        wireFSM()
        #if !APPSTORE
        VoiceActionRunner.shared.configureLive()
        #endif

        // Make panel key whenever the prompt/chat view becomes active
        // (nonactivatingPanel never auto-becomes key, but TextField needs it)
        viewSubscription = state.$view
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newView in
                guard let self else { return }
                if newView == .prompt || newView == .nook || newView == .tray {
                    self.islandPanel.makeKey()
                }
            }

        // Screen choice changed in Settings: move right away (explicit user action).
        displaySubscription = state.$islandDisplay
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] choice in
                self?.moveToTargetScreen(choice: choice)
            }

        // Screen plugged/unplugged, lid closed, arrangement or resolution changed.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.moveToTargetScreen(choice: AppState.shared.islandDisplay) }
        }
    }

    // MARK: - Screen choice

    private func moveToTargetScreen(choice: IslandDisplayChoice) {
        guard !inAttachDrag, attachDragStart == nil else { return }
        relocate(to: Self.targetScreen(for: choice))
    }

    /// Recomputes the resting geometry for `screen` and moves the panel to its top centre.
    /// Always re-applied, even on the same screen: its menu bar or resolution may have changed.
    private func relocate(to screen: NSScreen) {
        guard let panel = window as? IslandPanel else { return }
        let geometry = Self.screenGeometry(for: screen)
        notchW = geometry.width
        notchH = geometry.height
        hasNotch = geometry.hasNotch
        panel.notchWidth  = notchW
        panel.notchHeight = notchH
        AppState.shared.notchWidth  = notchW
        AppState.shared.notchHeight = notchH
        AppState.shared.hasNotch = hasNotch
        Self.currentScreen = screen

        let sf = screen.frame
        let size = panel.frame.size
        panel.setFrame(NSRect(x: sf.midX - size.width/2, y: sf.maxY - size.height,
                              width: size.width, height: size.height), display: true)
        // notchWidth/hasNotch are not @Published: tell the views to resize the island.
        NotificationCenter.default.post(name: .islandScreenChanged, object: nil)
        state.objectWillChange.send()
    }

    /// Follow-the-mouse mode: hop to the cursor's screen while the island is not open,
    /// so an approval or a chat never jumps away mid-click.
    private func followMouseIfNeeded(_ mouse: NSPoint) {
        guard state.islandDisplay == .followMouse,
              state.mode != .expanded, !inAttachDrag, attachDragStart == nil else { return }
        if let current = Self.currentScreen, current.frame.contains(mouse) { return }
        guard let target = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
              target != Self.currentScreen else { return }
        relocate(to: target)
    }

    // MARK: - FSM wiring

    private func wireFSM() {
        fsm.allowsHide = { [weak self] in
            guard let self else { return true }
            if NookPreferences.shared.demoMode && self.hasNotch { return false }
            return true
        }

        // Apply the persisted preference immediately and keep live edits in sync.
        autoCloseSubscription = state.$autoCloseInterval.sink { [weak self] delay in
            self?.fsm.homeToPetitDelay = delay
        }
        openOnHoverSubscription = state.$openOnHover.sink { [weak self] on in
            self?.fsm.openOnHover = on
        }

        fsm.onTransition = { [weak self] from, to in
            guard let self else { return }
            let stayOpen = NookPreferences.shared.preventCloseOnMouseLeave
            switch to {
            case .hidden:
                if from == .coucou {
                    NotificationCenter.default.post(name: .greetingInterrupt, object: nil)
                    self.state.view = self.defaultView()
                }
                self.setMode(.hidden)

            case .petit:
                if from == .coucou {
                    // Fire interrupt first so canvas collapse starts before mode change
                    NotificationCenter.default.post(name: .greetingInterrupt, object: nil)
                } else if from == .hidden {
                    if self.silentNextReveal {
                        self.silentNextReveal = false
                    } else {
                        SoundEngine.shared.play("peek")
                    }
                } else if from == .listening {
                    // Voice session ended — no peek sound, just compact
                    #if !APPSTORE
                    VoiceEngine.shared.cancelListening()
                    #endif
                }
                // setMode BEFORE changing view: onChange(of: state.view) guards on .expanded,
                // so setting view while already compact won't trigger a spurious open animation.
                self.setMode(.compact)
                // Reset view when leaving .coucou or .listening so stale views
                // (e.g. .voiceResult) never linger on a collapsed island.
                if from == .coucou || from == .listening { self.state.view = self.defaultView() }
                // Start 60s hide timer if mouse is not currently over the island
                if !self.wasInIsland && self.settingsPreview == .none { self.fsm.mouseLeft() }

            case .home:
                let view = self.pendingExpandView ?? self.defaultView()
                self.pendingExpandView = nil
                if from == .coucou {
                    NotificationCenter.default.post(name: .greetingInterrupt, object: nil)
                }
                self.expand(to: view)
                // Start collapse timer if mouse not currently hovering.
                // A settings preview stays up until that window closes.
                if !self.wasInIsland && !stayOpen && self.settingsPreview == .none {
                    self.fsm.mouseLeft()
                }

            case .coucou:
                self.expand(to: .greeting)

            case .listening:
                // Island stays compact; caption panel handles display.
                #if !APPSTORE
                let screen = IslandWindowController.islandScreen()
                VoiceCaptionManager.shared.show(on: screen, notchHeight: AppState.shared.notchHeight)
                #endif
            }
        }

        // FSM observes greetComplete notification
        NotificationCenter.default.addObserver(
            forName: .greetComplete, object: nil, queue: .main
        ) { [weak self] _ in
            self?.fsm.greetComplete()
        }

        // An approval, or an email prepared by voice, stays open until I click.
        fsm.isHeldOpen = { AppState.shared.pendingApproval != nil || AppState.shared.voiceMailDraft != nil }

        // Voice: wake phrase detected → open listening island
        #if !APPSTORE
        NotificationCenter.default.addObserver(
            forName: .voiceWoke, object: nil, queue: .main
        ) { [weak self] note in
            let isDirect = (note.object as? String) == "direct"
            Task { @MainActor [weak self] in
                // Genuine wake phrase (not programmatic re-listen) → clear any pending question
                AppState.shared.voiceActive = true
                AppState.shared.voiceSubState = .listening
                self?.voiceContextExpiry?.cancel()
                if !isDirect {
                    VoiceActionRunner.shared.pendingQuestion = nil
                    // The island stays compact now: the tick says "I heard OK Coucou".
                    if AppState.shared.soundEnabled { SoundEngine.shared.play("tick") }
                }
                self?.fsm.voiceWoke()
            }
        }
        // Voice: command session ended — run intent, show result for 2 s, then collapse.
        NotificationCenter.default.addObserver(
            forName: .voiceFinished, object: nil, queue: .main
        ) { [weak self] note in
            let transcript = note.object as? String ?? ""
            Task { @MainActor [weak self] in
                guard let self else { return }
                if transcript.isEmpty {
                    if VoiceActionRunner.shared.isMailInProgress {
                        // Silence during the voice email: "no attachment" → the card opens,
                        // or the mail is cancelled. Say it, like any other answer.
                        let result = await VoiceActionRunner.shared.handleAnswer(
                            "", availablePills: PillCatalog.available)
                        VoiceCaptionManager.shared.appendResponse(result.message)
                        AppState.shared.voiceResult = result
                        self.speakAndContinueConversation(result)
                    } else if VoiceActionRunner.shared.pendingQuestion != nil {
                        // Re-listen timed out with no answer → show cancellation message
                        let result = await VoiceActionRunner.shared.handleAnswer(
                            "", availablePills: PillCatalog.available)
                        AppState.shared.voiceResult = result
                        self.expand(to: .voiceResult)
                        self.scheduleVoiceDismiss(delay: 1.5)
                    } else if self.isInConversation {
                        // No answer to Coucou's question: stop listening.
                        self.closeVoiceTurn()
                    } else {
                        self.fsm.voiceFinished()
                    }
                } else {
                    await self.handleVoiceCommand(transcript)
                }
            }
        }
        #endif
    }

    // MARK: - Polling loop
    // 60 Hz while the island is on screen, Mochi is on the desktop, a drag is under way or the
    // pointer is near the island; 8 Hz (with timer tolerance) while it is hidden and the pointer
    // is elsewhere, so a hidden island costs next to nothing (CLAUDE.md: 0 % CPU when hidden).

    private static let fastPoll: TimeInterval = 1.0 / 60.0
    private static let nearPoll: TimeInterval = 1.0 / 20.0
    private static let idlePoll: TimeInterval = 1.0 / 8.0
    private var pollInterval: TimeInterval = 0

    /// Screen asleep or locked: nothing to hover, the poll stops entirely.
    private var screenOff = false

    private func startPolling(interval: TimeInterval = IslandWindowController.fastPoll) {
        frameTimer?.invalidate()
        frameTimer = nil
        pollInterval = interval
        guard !screenOff else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop: already on the main actor, no Task per tick.
            MainActor.assumeIsolated { self?.pollFrame() }
        }
        // A few ms of slack lets macOS group our wakeups with others; hover is unaffected.
        timer.tolerance = interval == Self.idlePoll ? 0.04 : interval == Self.nearPoll ? 0.01 : 0.004
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    /// Picks the polling rate for the next ticks (see startPolling).
    /// Three rates for a hidden or resting island: 60 Hz close to the island itself, 20 Hz in the
    /// wide band around the panel (a pointer flicked up still reaches the close zone
    /// within one tick), 8 Hz elsewhere. Before, the whole band ran at 60 Hz, so a hidden
    /// island polled at 60 Hz most of the time. Desktop Mochi has its own poll.
    private func adjustPollRate(mouse: NSPoint, panelFrame: NSRect, islandRect: NSRect) {
        let island = islandRect.offsetBy(dx: panelFrame.minX, dy: panelFrame.minY)
        let nearIsland = island.insetBy(dx: -200, dy: -160).contains(mouse)
        let inBand = panelFrame.insetBy(dx: -120, dy: -120).contains(mouse)
        // The resting (compact) island is treated like the hidden one: Mochi reads the
        // pointer itself every frame, so only hover and clicks need this poll, and those
        // only near the island. 60 Hz while open, dragging or close to it.
        let busy = state.mode == .expanded || inAttachDrag || attachDragStart != nil
            || fsm.state == .home || fsm.state == .coucou || fsm.state == .listening || nearIsland
        let wanted = busy ? Self.fastPoll : inBand ? Self.nearPoll : Self.idlePoll
        if wanted != pollInterval { startPolling(interval: wanted) }
    }

    private func pollFrame() {
        guard let panel = window as? IslandPanel else { return }
        matchPanelWidth(panel)

        let mouse = NSEvent.mouseLocation
        followMouseIfNeeded(mouse)

        // Convert mouse to panel-local coords (macOS: origin bottom-left)
        let pf = panel.frame
        let local = CGPoint(x: mouse.x - pf.minX, y: mouse.y - pf.minY)

        // Island rect in panel coords
        let islandRect = panel.currentIslandFrame(nw: notchW, nh: notchH)
        // On a screen without a notch, the resting bar must not intercept clicks
        // in the app window immediately below the menu bar.
        // A pulled-down drawer keeps a region five times its area before closing.
        let hoverRect: CGRect
        if !hasNotch && state.mode != .expanded {
            hoverRect = islandRect
        } else if state.mode == .expanded {
            hoverRect = DrawerPull.keepOpenRect(
                island: islandRect,
                extended: DrawerPull.isExtended(state.drawerExtension)
            )
        } else {
            hoverRect = islandRect.insetBy(dx: -6, dy: -6)
        }
        let buttonHeld = NSEvent.pressedMouseButtons & 1 != 0
        let pulling = state.drawerPulling && state.mode == .expanded
        let panelBounds = CGRect(origin: .zero, size: panel.frame.size)
        // While the drawer is open the whole panel must take the press. A tray
        // chip can sit outside the hover math, and a click there used to fall
        // through to the desktop. Settings sits under that panel, so an open
        // settings tab keeps the press on the drawn island only.
        let overDrawn = hoverRect.contains(local) || pulling || (buttonHeld && state.mode == .expanded)
        let overPanel = state.mode == .expanded && panelBounds.contains(local)
        let inIsland = SettingsNotchPreview.panelTakesThePress(
            settingsOpen: settingsPreview != .none,
            overDrawnIsland: overDrawn,
            overPanel: overPanel
        )

        // Toggle click-through
        let shouldAcceptMouse = inIsland || inAttachDrag || attachDragStart != nil
        if panel.ignoresMouseEvents == shouldAcceptMouse {
            panel.ignoresMouseEvents = !shouldAcceptMouse
            if shouldAcceptMouse, let cv = panel.contentView {
                panel.invalidateCursorRects(for: cv)
            }
        }
        // Teach SwiftUI's views to take the first press before the user clicks.
        if state.mode == .expanded, let root = panel.contentView {
            NotchClickDelivery.patchTree(root)
        }

        // Mouse in desktop space (y-down from the menu-bar screen top) for Bot look-at
        let newPos = DesktopSpace.topDown(mouse, desktopTop: Self.desktopTop)
        let cur = AppState.shared.mousePosition
        if abs(newPos.x - cur.x) > 1 || abs(newPos.y - cur.y) > 1 {
            AppState.shared.mousePosition = newPos
        }

        // AppState can hide the island by itself (last task ended): keep the FSM in step.
        if state.mode == .hidden && fsm.state == .petit { fsm.hiddenExternally() }

        let prefs = NookPreferences.shared
        let typingLock = prefs.typingLocked

        if !hasNotch {
            if !prefs.handlerEnabled {
                panel.alphaValue = 0
            } else if prefs.handlerTransparent {
                panel.alphaValue = inIsland ? 1 : 0.02
            } else if panel.alphaValue != 1 {
                panel.alphaValue = 1
            }
        } else if panel.alphaValue != 1 {
            panel.alphaValue = 1
        }

        let onTerminalPage = state.mode == .expanded && state.view == .overview
        let desk = TerminalDesk.shared
        if !onTerminalPage {
            desk.lockLeftAt = nil
        } else if desk.pageLocked && inIsland {
            desk.lockLeftAt = nil
        } else if desk.pageLocked && !inIsland && wasInIsland {
            desk.lockLeftAt = Date()
        }
        let lockNow = Date().timeIntervalSinceReferenceDate
        let lockLeft = desk.lockLeftAt?.timeIntervalSinceReferenceDate
        let pageLockKeepsOpen = TerminalBehavior.holdsPageOpen(
            locked: desk.pageLocked,
            onPage: onTerminalPage,
            leftAt: lockLeft,
            now: lockNow
        )
        let pageLockExpired = TerminalBehavior.shouldReleasePageLock(
            locked: desk.pageLocked,
            onPage: onTerminalPage,
            leftAt: lockLeft,
            now: lockNow
        )
        if pageLockExpired {
            desk.releasePageLock()
        }

        if state.mode != .expanded, let slot = closedTerminalBlob(at: mouse) {
            closedAimID = slot
            closedAimAt = Date()
        }

        // Feed FSM hover enter/leave
        if !typingLock && inIsland && !wasInIsland {
            guard !inAttachDrag else { wasInIsland = inIsland; return }
            // If in coucou: tell greeting to stay open (tc → infinity)
            if fsm.state == .coucou {
                NotificationCenter.default.post(name: .greetingHover, object: nil)
            }
            fsm.mouseEntered()
            if prefs.alwaysOpenOnHover && settingsPreview == .none && (fsm.state == .petit || fsm.state == .hidden) {
                if let slot = closedAimID ?? closedTerminalBlob(at: mouse) {
                    TerminalDesk.shared.armSelection(slot)
                }
                fsm.click()
            }
        }
        if settingsPreview == .none && !typingLock && !inIsland && wasInIsland {
            let keepExpanded = prefs.preventCloseOnMouseLeave && fsm.state == .home
            let pageHeld = pageLockKeepsOpen && fsm.state == .home
            let extended = state.mode == .expanded && DrawerPull.isExtended(state.drawerExtension)
            if fsm.state == .home && !keepExpanded && !pageHeld && !extended {
                // Fold as soon as the pointer leaves the island. The 15s timer
                // made the open notch feel stuck. A locked terminal page waits 20s.
                fsm.collapse()
                fsm.mouseLeft()
            } else if fsm.state == .home && extended && !keepExpanded && !pageHeld {
                fsm.homeToPetitDelay = DrawerPull.autoCloseDelay(
                    base: state.autoCloseInterval,
                    extended: true
                )
                fsm.mouseLeft()
                fsm.homeToPetitDelay = DrawerPull.standardCloseDelay
            } else if !keepExpanded && !pageHeld {
                fsm.mouseLeft()
            }
        }
        if !hapticReady {
            hapticWasOutside = NotchHaptics.distance(from: local, to: islandRect) > NotchHaptics.approachBand
            hapticReady = true
        } else {
            let distance = NotchHaptics.distance(from: local, to: islandRect)
            let step = NotchHaptics.approach(
                distance: distance,
                band: NotchHaptics.approachBand,
                wasOutside: hapticWasOutside,
                enabled: !prefs.disableHaptics
            )
            hapticWasOutside = step.wasOutside
            if step.play {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
        if settingsPreview != .none {
            keepSettingsPreview()
        }
        if settingsPreview == .none && pageLockExpired && !inIsland && fsm.state == .home && !prefs.preventCloseOnMouseLeave {
            fsm.collapse()
            fsm.mouseLeft()
        } else if settingsPreview == .none && pageLockWasOn && !desk.pageLocked && !inIsland && onTerminalPage && fsm.state == .home && !prefs.preventCloseOnMouseLeave {
            fsm.collapse()
            fsm.mouseLeft()
        }
        pageLockWasOn = desk.pageLocked
        NookBoard.shared.notePointer(inIsland)
        wasInIsland = inIsland

        // Bot-head hover (love emote)
        let overBot = state.mode == .expanded && state.stateOverride == nil && isBotHit(local)
        if overBot && !botHovering { botHoverIn(mousePos: NSEvent.mouseLocation) }
        if !overBot && botHovering { botHoverOut() }
        botHovering = overBot
        if botHovering {
            let m = NSEvent.mouseLocation
            let dist = hypot(m.x - botHoverStartPos.x, m.y - botHoverStartPos.y)
            if dist > 40 {
                botHoverStartPos = m
                botHoverTimer?.cancel()
                scheduleLoveTimer()
            }
        }

        // Ghost Mochi follows cursor + window highlight during drag (60 Hz, no throttle)
        if inAttachDrag {
            updateDragGhost()
            updateWindowHighlight()
        }

        adjustPollRate(mouse: mouse, panelFrame: pf, islandRect: islandRect)
    }

    /// Screen asleep or locked: stop polling; back at the idle rate when it wakes.
    private func observeScreenForPolling() {
        let ws = NSWorkspace.shared.notificationCenter
        let dc = DistributedNotificationCenter.default()
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pausePollingForScreenOff() }
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resumePollingAfterScreenOff() }
        }
        dc.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pausePollingForScreenOff() }
        }
        dc.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resumePollingAfterScreenOff() }
        }
    }

    private func pausePollingForScreenOff() {
        screenOff = true
        frameTimer?.invalidate()
        frameTimer = nil
    }

    private func resumePollingAfterScreenOff() {
        guard screenOff else { return }
        screenOff = false
        startPolling(interval: Self.idlePoll)
    }

    private var lastMouse: CGPoint = .zero
    private var lastHighlightMouse: CGPoint = .zero
    private var lastHighlightScan: CFTimeInterval = 0

    // MARK: - Bot-head hover (love emote — mirrors prototype botHover())

    private func botHoverIn(mousePos: CGPoint) {
        guard state.mode == .expanded, state.stateOverride == nil else { return }
        guard CACurrentMediaTime() - lastLoveTime > 6 else { return }
        botHoverStartPos = mousePos
        NotificationCenter.default.post(name: .botBlink, object: nil)
        NotificationCenter.default.post(name: .botSetTgEs, object: CGFloat(1.08))
        SoundEngine.shared.play("hover")
        scheduleLoveTimer()
    }

    private func botHoverOut() {
        botHoverTimer?.cancel()
        NotificationCenter.default.post(name: .botSetTgEs, object: CGFloat(1))
    }

    private func scheduleLoveTimer() {
        botHoverTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.botHovering, self.state.stateOverride == nil else { return }
            guard CACurrentMediaTime() - self.lastLoveTime > 6 else { return }
            self.lastLoveTime = CACurrentMediaTime()
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.love)
            SoundEngine.shared.play("love")
        }
        botHoverTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9, execute: item)
    }

    private func scheduleHover(after delay: TimeInterval, action: @escaping () -> Void) {
        hoverTimer?.cancel()
        let item = DispatchWorkItem(block: action)
        hoverTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Mode transitions

    private func modeLevel(_ m: IslandMode) -> Int {
        switch m { case .hidden: return 0; case .compact: return 1; case .expanded: return 2 }
    }

    func setMode(_ mode: IslandMode) {
        let prev = state.mode
        guard mode != prev else { return }
        let shrinking = modeLevel(mode) < modeLevel(prev)
        let anim: Animation = shrinking
            ? .timingCurve(0.45, 0, 0.2, 1, duration: 0.34)
            : .spring(response: 0.5, dampingFraction: 0.72)
        withAnimation(anim) {
            state.mode = mode
            if mode != .expanded {
                state.drawerExtension = 0
                state.drawerPulling = false
            }
        }
        if mode == .expanded { SoundEngine.shared.play("open") }
        if prev == .expanded {
            SoundEngine.shared.play("close")
            if fsm.isHeldOpen?() != true { state.isPinned = false }
            fsm.homeToPetitDelay = DrawerPull.standardCloseDelay
        }
    }

    func expand(to view: IslandView) {
        state.view = view
        if state.mode == .expanded {
            // Already expanded — just switch view
        } else {
            setMode(.expanded)
        }
        state.lastActivity = .now
    }

    /// Keep the notch on the settings tab that is open, so edits show as they happen.
    private func applySettingsPreview(_ tab: String) {
        let page = SettingsNotchPreview.page(for: tab)
        settingsPreview = page
        if page == .none {
            NookBoard.shared.dropWing = false
            if !wasInIsland { fsm.hideNow() }
            return
        }
        keepSettingsPreview()
    }

    private func keepSettingsPreview() {
        let board = NookBoard.shared
        var resized = false
        func setDrop(_ on: Bool) {
            guard board.dropWing != on else { return }
            board.dropWing = on
            resized = true
        }
        func setTray(_ on: Bool) {
            guard board.showsTray != on else { return }
            board.showsTray = on
            resized = true
        }
        switch settingsPreview {
        case .none:
            return
        case .home:
            setDrop(false)
            setTray(false)
            presentExpanded(.overview)
        case .activities:
            setTray(false)
            setDrop(false)
            presentCompact()
        case .nook:
            setDrop(false)
            setTray(false)
            presentExpanded(.nook)
        case .tray:
            setDrop(false)
            setTray(false)
            presentExpanded(.tray)
        case .drop:
            setTray(false)
            setDrop(true)
            presentCompact()
        }
        if resized { board.refreshChrome() }
    }

    private func presentExpanded(_ view: IslandView) {
        if state.drawerExtension > 0 {
            state.drawerExtension = 0
            state.drawerPulling = false
        }
        guard state.mode != .expanded || state.view != view else { return }
        pendingExpandView = view
        if fsm.state == .home {
            expand(to: view)
            pendingExpandView = nil
        } else {
            fsm.showHome()
        }
    }

    private func presentCompact() {
        guard state.mode != .compact else { return }
        state.drawerExtension = 0
        state.drawerPulling = false
        if fsm.state == .petit {
            setMode(.compact)
        } else {
            fsm.showPetit()
        }
    }

    func collapse(allowPendingApproval: Bool = false) {
        let keepsApprovalPending = allowPendingApproval && state.pendingApproval != nil
        if fsm.isHeldOpen?() == true && !keepsApprovalPending { return }
        state.isPinned = false
        finishedPinTimer?.cancel()
        #if !APPSTORE
        VoiceSpeaker.shared.stop()
        if isInConversation || AppState.shared.voiceActive {
            isInConversation = false
            voiceResultWork?.cancel()
            voiceResultWork = nil
            VoiceEngine.shared.endConversation()
            VoiceCaptionManager.shared.hide(after: 0)
            AppState.shared.voiceResult = nil
            AppState.shared.voiceActive = false
        }
        #endif
        // Home and the greeting shrink back to the notch. Compact is the hover
        // shelf only, and stopping there left the closed drawer wide.
        fsm.collapse()
        if state.mode != .hidden {
            setMode(.hidden)
        }
        window?.resignKey()
    }

    // MARK: - Global hot keys (Carbon)

    private func startHotKeys() {
        HotKeyCenter.shared.start { [weak self] action in
            self?.handleHotKey(action)
        }
    }

    func handleHotKey(_ action: ShortcutAction) {
        switch action {
        case .toggleIsland:
            if state.mode == .expanded {
                collapse(allowPendingApproval: true)
            } else {
                islandPanel.makeKey()
                fsm.openedExternally()
                expand(to: defaultView())
            }

        case .openChat:
            islandPanel.makeKey()
            expand(to: .prompt)

        case .goToAlert:
            if state.pendingApproval != nil {
                islandPanel.makeKey()
                fsm.openedExternally()
                expand(to: .approval)
            } else if state.pendingQuestion != nil {
                islandPanel.makeKey()
                expand(to: .question)
            } else {
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.annoyed)
                SoundEngine.shared.play("error")
            }

        case .jumpToTerminal:
            #if !APPSTORE
            performJumpToTerminal()
            #endif

        case .attachFrontWindow:
            #if !APPSTORE
            performAttachFrontWindow()
            #endif

        case .nextPill:
            cyclePill(by: +1)

        case .prevPill:
            cyclePill(by: -1)

        case .muteToggle:
            state.soundEnabled.toggle()
            if state.soundEnabled { SoundEngine.shared.play("tick") }
            NotificationCenter.default.post(
                name: .triggerEmote,
                object: state.soundEnabled ? BotEmote.happy : BotEmote.annoyed)

        case .desktopToggle:
            DesktopMochiController.shared.flyOutOrHome()

        case .wardrobeToggle:
            if state.mode == .expanded && state.view == .wardrobe {
                collapse()
            } else {
                islandPanel.makeKey()
                expand(to: .wardrobe)
            }

        case .talkToCoucou:
            #if !APPSTORE
            VoiceSpeaker.shared.stop()
            VoiceEngine.shared.startListeningDirectly()
            #endif
        }
    }

    // MARK: - Island-local shortcuts

    private func startLocalKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.islandPanel.isKeyWindow else { return event }
            return self.handleIslandKey(event) ? nil : event
        }
    }

    @discardableResult
    private func handleIslandKey(_ event: NSEvent) -> Bool {
        let raw = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let cmd = raw == .command

        // ⌘→ — next pill
        if cmd && event.keyCode == 124 { cyclePill(by: +1); return true }
        // ⌘← — previous pill
        if cmd && event.keyCode == 123 { cyclePill(by: -1); return true }
        // ⌘↓ — navigate list down
        if cmd && event.keyCode == 125 { navigateCard(by: +1); return true }
        // ⌘↑ — navigate list up
        if cmd && event.keyCode == 126 { navigateCard(by: -1); return true }
        // ⌘O — open selected card item
        if cmd && event.keyCode == 31  { openCardSelection(); return true }
        // ⌘E — toggle diff
        if cmd && event.keyCode == 14 && state.view == .overview {
            NotificationCenter.default.post(name: .islandToggleDiff, object: nil)
            return true
        }
        // ⌘↩ — send chat message
        if cmd && event.keyCode == 36 && state.view == .prompt {
            NotificationCenter.default.post(name: .islandSendMessage, object: nil)
            return true
        }
        // ⌘K — new conversation
        if cmd && event.keyCode == 40 && state.view == .prompt {
            NotificationCenter.default.post(name: .islandNewConversation, object: nil)
            return true
        }
        // ⌘, — open Settings
        if cmd && event.keyCode == 43 {
            NotificationCenter.default.post(name: .openFullSettings, object: nil)
            return true
        }
        // ⌘P — pin / unpin
        if cmd && event.keyCode == 35 {
            state.isPinned.toggle()
            return true
        }
        // ⌘1–⌘9 — switch to pill by number
        let digitCodes: [UInt16: Int] = [18:1,19:2,20:3,21:4,23:5,22:6,26:7,28:8,25:9]
        if cmd, let n = digitCodes[event.keyCode] {
            switchToPill(number: n); return true
        }
        // ⎋ Escape — focused views (.onExitCommand) have first crack; fall back to collapse
        if event.keyCode == 53 && raw.isEmpty {
            let consumed = NSApp.sendAction(Selector(("cancelOperation:")), to: nil, from: nil)
            let canCollapse = !state.isPinned || state.pendingApproval != nil
            if !consumed && state.mode == .expanded && canCollapse {
                collapse(allowPendingApproval: true)
            }
            return true
        }
        return false
    }

    // MARK: - Pill cycling helpers

    private func cyclePill(by delta: Int) {
        guard !state.tasks.isEmpty else { return }
        let ids = state.tasks.map { $0.id }
        let cur = ids.firstIndex(of: state.focusId ?? "") ?? 0
        state.setFocus(ids[(cur + delta + ids.count) % ids.count])
        state.cardSelection = nil
        expand(to: .overview)
    }

    private func switchToPill(number: Int) {
        guard number >= 1, number <= state.tasks.count else { return }
        state.setFocus(state.tasks[number - 1].id)
        state.cardSelection = nil
        expand(to: .overview)
    }

    private func navigateCard(by delta: Int) {
        guard state.cardItemCount > 0 else { return }
        state.cardSelection = ShortcutLogic.navigate(
            selection: state.cardSelection, delta: delta, itemCount: state.cardItemCount)
    }

    private func openCardSelection() {
        guard state.cardSelection != nil else { return }
        NotificationCenter.default.post(name: .islandActivateCardSelection, object: nil)
    }

    // MARK: - Terminal jump

    #if !APPSTORE
    private func performJumpToTerminal() {
        guard state.focusTask != nil else {
            SoundEngine.shared.play("error")
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.annoyed)
            return
        }
        if !TerminalTarget.activate(sessionBundleId: state.focusTask?.sessionBundleId) {
            NSWorkspace.shared.open(
                URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        }
        collapse(allowPendingApproval: true)
    }

    private func performAttachFrontWindow() {
        guard let app = state.lastExternalApp else {
            SoundEngine.shared.play("error"); return
        }
        guard let ctx = WindowContextCapture.captureActive(from: app) else {
            SoundEngine.shared.play("error"); return
        }
        state.promptContext = ctx
        SoundEngine.shared.play("approve")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        islandPanel.makeKey()
        expand(to: .prompt)
    }
    #endif

    // MARK: - Keyboard (Escape closes)

    /// A short press focuses. A hold opens that color in its corner.
    /// The pointer can leave the notch before the mouse comes up.
    private func finishBlobPress() {
        let pressedBlob = blobPressID
        let pressedAt = blobPressAt
        blobPressID = nil
        blobPressAt = nil
        guard let slot = pressedBlob, settingsPreview == .none else { return }
        let held = pressedAt.map { Date().timeIntervalSince($0) } ?? 0
        TerminalDesk.shared.armSelection(slot)
        switch TerminalBehavior.blobPress(held: held) {
        case .focus: TerminalDesk.shared.focus(slot)
        case .tile: TerminalDesk.shared.openOrFocus(slot)
        }
    }

    private func startKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handleNotchScroll(event) }
            return event
        }
        NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            Task { @MainActor in self?.handleNotchScroll(event) }
        }

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Every key typed anywhere lands here: only Escape goes further (no Task per key).
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                guard let self = self else { return }
                NookPreferences.shared.noteTyping()
                if event.keyCode == 53 { self.handleEscape() }
            }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let swallow = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.window?.isKeyWindow == true else { return false }
                if TerminalDesk.shared.consumeEscape() { return true }
                if self.settingsPreview != .none { return false }
                if self.state.mode == .expanded && !self.state.isPinned {
                    self.collapse()
                    return true
                }
                return false
            }
            return swallow ? nil : event
        }

        // Hook server expand requests (alerts only)
        NotificationCenter.default.addObserver(forName: .hookExpand, object: nil, queue: .main) { [weak self] note in
            guard let self, self.settingsPreview == .none, let view = note.object as? IslandView else { return }
            self.fsm.openedExternally()
            self.expand(to: view)
        }

        // Hook server compact reveal (non-alert work events: session start, tool use, etc.)
        NotificationCenter.default.addObserver(forName: .hookReveal, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.settingsPreview == .none else { return }
            self.fsm.reveal()
        }

        // Music started playing: reveal silently (no peek sound)
        NotificationCenter.default.addObserver(forName: .musicReveal, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.silentNextReveal = true
            self.fsm.reveal()
            self.silentNextReveal = false
        }

        // Email prepared by voice: open the mail card, filled in, for me to check and send.
        NotificationCenter.default.addObserver(forName: .voiceShowMailCard, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.fsm.openedExternally()
            self.expand(to: .mail)
        }

        // Collapse requests from views (OK button, etc.)
        NotificationCenter.default.addObserver(forName: .islandCollapse, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.settingsPreview == .none else { return }
            self.collapse()
        }
        NotificationCenter.default.addObserver(forName: .openNookPage, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.settingsPreview == .none else { return }
            self.openNook()
        }

        NotificationCenter.default.addObserver(forName: .settingsNotchPreview, object: nil, queue: .main) { [weak self] note in
            let tab = note.object as? String ?? "closed"
            MainActor.assumeIsolated { self?.applySettingsPreview(tab) }
        }

        // Wardrobe open/close from desktop Mochi right-click (does NOT post .hookExpand)
        NotificationCenter.default.addObserver(forName: .openWardrobeFromDesktop, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.state.mode == .expanded && self.state.view == .wardrobe {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self.state.view = .overview
                }
            } else {
                self.expand(to: .wardrobe)
            }
        }

        // .botDizzy — posted by BotEngine.slap() on 3rd hit; show confused view + recover after 3.3s
        NotificationCenter.default.addObserver(forName: .botDizzy, object: nil, queue: .main) { [weak self] _ in
            self?.handleDizzy()
        }

        // Eye tracking at the mouse's own rate: Mochi's look target follows every mouse move
        // instead of the island poll (8 to 20 Hz away from the island, which made the head step).
        // Nothing runs while the mouse is still, and a hidden island skips the work.
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { _ in
            MainActor.assumeIsolated { IslandWindowController.trackMouseLook() }
        }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            MainActor.assumeIsolated { IslandWindowController.trackMouseLook() }
            return event
        }

        // Window attach drag.
        // Uses MainActor.assumeIsolated (synchronous) to avoid race with pollFrame().
        // Global mouseUp is the reliable fallback when cursor is outside our panel frame.
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                if let panel = self.window as? IslandPanel {
                    let overPanel = panel.frame.contains(NSEvent.mouseLocation)
                    if event.window === panel || overPanel {
                        NotchClickDelivery.prepare(panel)
                    }
                }
                let screen = NSEvent.mouseLocation
                let openHit: String? = {
                    guard self.state.mode == .expanded, let panel = self.window else { return nil }
                    let local = CGPoint(x: screen.x - panel.frame.minX, y: screen.y - panel.frame.minY)
                    return self.terminalBlob(at: local)
                }()
                let closedHit = self.state.mode == .expanded ? nil : self.closedTerminalBlob(at: screen)
                let aimFresh = self.closedAimAt.map { Date().timeIntervalSince($0) < 0.45 } ?? false
                let slot = openHit ?? closedHit ?? (aimFresh ? self.closedAimID : nil)
                // The hover poll can still be false on the click that lands. A hit blob still counts.
                guard self.wasInIsland || slot != nil else { return }
                self.fsm.userInteracted()
                self.pendingIslandClick = true
                self.blobPressID = nil
                self.blobPressAt = nil
                if let slot {
                    self.blobPressID = slot
                    self.blobPressAt = Date()
                    TerminalDesk.shared.armSelection(slot)
                }
                self.hoverTimer?.cancel()
                self.botHoverTimer?.cancel()
                self.botHovering = false
                // Drag only starts when clicking directly on the bot head
                guard self.isBotHit(event.locationInWindow) else { return }
                // Notch Mochi is invisible when on desktop — no drag, no slap
                guard !self.state.mochiOnDesktop else { return }
                self.attachDragStart = NSEvent.mouseLocation
                // Post slap only when expanded
                guard self.state.mode == .expanded else { return }
                NotificationCenter.default.post(name: .triggerSlap, object: nil)
            }
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard let start = self.attachDragStart, !self.inAttachDrag else { return }
                let m = NSEvent.mouseLocation
                guard hypot(m.x - start.x, m.y - start.y) > 3 else { return }
                self.inAttachDrag = true
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.love)
                self.showDragGhost()
            }
            return event
        }

        // mouseUp — local (cursor still in panel) + global (cursor moved outside panel frame)
        let finishDrag: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self, self.inAttachDrag else { return }
                let mouse = NSEvent.mouseLocation
                self.inAttachDrag = false
                self.attachDragStart = nil
                self.state.stateOverride = nil

                #if !APPSTORE
                let windowCtx = self.windowContextAtPoint(mouse)
                let inNotchZone = self.window?.frame.contains(mouse) == true

                if let ctx = windowCtx {
                    // Drop on a window → attach context as before
                    self.hideDragGhost()
                    self.state.promptContext = ctx
                    SoundEngine.shared.play("approve")
                    NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
                    self.expand(to: .prompt)
                } else if !inNotchZone {
                    // Drop outside notch zone → install Mochi on the desktop.
                    // Prevent hideDragGhost from closing the ghost panel so we can promote it.
                    let ghost = self.dragGhostPanel
                    self.dragGhostPanel = nil   // nil first so hideDragGhost skips close
                    self.hideDragGhost()        // resets isDraggingBot, closes highlight panel
                    DesktopMochiController.shared.install(ghostPanel: ghost, at: mouse)
                } else {
                    // Drop back in notch zone → Mochi returns to notch
                    self.hideDragGhost()
                }
                #else
                let inNotchZoneAS = self.window?.frame.contains(mouse) == true
                if !inNotchZoneAS {
                    let ghost = self.dragGhostPanel
                    self.dragGhostPanel = nil
                    self.hideDragGhost()
                    DesktopMochiController.shared.install(ghostPanel: ghost, at: mouse)
                } else {
                    self.hideDragGhost()
                }
                #endif
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                let hadPendingClick = self.pendingIslandClick
                let wasDragging     = self.inAttachDrag
                self.pendingIslandClick = false
                if wasDragging {
                    self.blobPressID = nil
                    self.blobPressAt = nil
                    finishDrag()
                } else {
                    self.attachDragStart = nil
                    self.finishBlobPress()
                    if hadPendingClick && self.settingsPreview == .none && self.state.mode != .expanded && NookPreferences.shared.nookEnabled {
                        if self.fsm.state == .home {
                            // FSM already thinks it's open (e.g. the view folded it): just reopen.
                            self.expand(to: self.defaultView())
                        } else {
                            self.fsm.click()   // FSM petit/hidden→home; onTransition calls expand(to:)
                        }
                    }
                }
            }
            return event
        }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.finishBlobPress()
            }
            finishDrag()
        }

        // Global hotkey to show island. A hold that ends outside the notch
        // still finishes on the monitor above, before this shortcut runs.
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self, self.state.hotkeyEnabled else { return }
                let pressed = event.modifierFlags.intersection([.command, .control, .option, .shift]).rawValue
                guard pressed == self.state.hotkeyFlags, event.keyCode == self.state.hotkeyCode else { return }
                if self.state.mode == .hidden || self.state.mode == .compact {
                    self.expand(to: .overview)
                }
            }
        }

        NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard self.wasInIsland, self.isBotHit(event.locationInWindow) else { return }
                guard !self.state.mochiOnDesktop else { return }
                if self.state.mode == .expanded && self.state.view == .wardrobe {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        self.state.view = .overview
                    }
                } else {
                    self.expand(to: .wardrobe)
                }
            }
            return event
        }

        // Track last external app for window context capture
        let ourBundle = Bundle.main.bundleIdentifier ?? ""
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier != ourBundle {
                self.state.lastExternalApp = app
            }
        }
    }

    // MARK: - Drag ghost window (Mochi follows cursor during drag)

    private func showDragGhost() {
        guard dragGhostPanel == nil else { return }
        // Same size as compact bot: diameter=20 → canvasSize≈33, scale 2× for grab comfort
        let canvasSize: CGFloat = 40 / 0.6      // ~67
        dragGhostSize = canvasSize

        let mouse = NSEvent.mouseLocation
        let s = dragGhostSize
        ghostCurrentOrigin = NSPoint(x: mouse.x - s/2, y: mouse.y - s/2)

        let panel = NSPanel(
            contentRect: NSRect(x: ghostCurrentOrigin.x, y: ghostCurrentOrigin.y, width: s, height: s),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let hosting = NSHostingView(
            rootView: GhostBotView(canvasSize: canvasSize)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: s, height: s)
        panel.contentView = hosting
        panel.alphaValue = 0
        panel.orderFront(nil)
        dragGhostPanel = panel
        AppState.shared.isDraggingBot = true

        // Fade + scale-in handled by GhostBotView SwiftUI animation;
        // also fade in the window itself for extra smoothness
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hideDragGhost() {
        dragGhostPanel?.close()
        dragGhostPanel = nil
        highlightPanel?.close()
        highlightPanel = nil
        highlightWindowPid = 0
        AppState.shared.isDraggingBot = false
    }

    private func updateDragGhost() {
        guard let panel = dragGhostPanel else { return }
        let s = dragGhostSize
        let mouse = NSEvent.mouseLocation
        // Direct follow — bot is "held", no trailing lag
        ghostCurrentOrigin = NSPoint(x: mouse.x - s/2, y: mouse.y - s/2)
        panel.setFrameOrigin(ghostCurrentOrigin)
    }

    // MARK: - Window highlight overlay (white border on target window during drag)

    private func updateWindowHighlight() {
        let mouse = NSEvent.mouseLocation
        // Listing every window is costly: skip while the pointer stays put (a window
        // moving under a still pointer is caught within a quarter second).
        let now = CACurrentMediaTime()
        if hypot(mouse.x - lastHighlightMouse.x, mouse.y - lastHighlightMouse.y) < 2,
           now - lastHighlightScan < 0.25 { return }
        lastHighlightMouse = mouse
        lastHighlightScan = now
        guard let (appKitBounds, pid) = windowBoundsAtScreenPoint(mouse) else {
            // Fade out + close if no window under cursor
            if let old = highlightPanel {
                let captured = old
                highlightPanel = nil
                highlightWindowPid = 0
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.12
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    captured.animator().alphaValue = 0
                }, completionHandler: { captured.close() })
            }
            return
        }

        if pid == highlightWindowPid, let existing = highlightPanel {
            // Same window — just track position (windows rarely move, instant is fine)
            existing.setFrame(appKitBounds, display: false)
        } else {
            // New window — close old immediately, fade-in new
            highlightPanel?.close()
            highlightPanel = nil
            highlightWindowPid = pid

            let panel = NSPanel(
                contentRect: appKitBounds,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.ignoresMouseEvents = true

            let hosting = NSHostingView(rootView:
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.75), lineWidth: 3)
                    .shadow(color: Color.white.opacity(0.5), radius: 16)
                    .padding(2)
                    .ignoresSafeArea()
            )
            hosting.frame = CGRect(origin: .zero, size: appKitBounds.size)
            hosting.autoresizingMask = [.width, .height]
            panel.contentView = hosting
            panel.alphaValue = 0
            panel.orderFront(nil)
            highlightPanel = panel

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    private func windowBoundsAtScreenPoint(_ screenPoint: NSPoint) -> (CGRect, pid_t)? {
        guard let screen = window?.screen ?? NSScreen.main else { return nil }
        let screenMaxY = screen.frame.maxY
        let cgPoint = CGPoint(x: screenPoint.x, y: screenMaxY - screenPoint.y)

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ourBundle = Bundle.main.bundleIdentifier ?? ""
        for info in list {
            guard let b = info[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? CGFloat, let y = b["Y"] as? CGFloat,
                  let w = b["Width"] as? CGFloat, let h = b["Height"] as? CGFloat else { continue }
            guard CGRect(x: x, y: y, width: w, height: h).contains(cgPoint) else { continue }
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier != ourBundle,
                  app.activationPolicy == .regular else { continue }
            // CG → AppKit: flip Y
            return (CGRect(x: x, y: screenMaxY - y - h, width: w, height: h), pid)
        }
        return nil
    }

    // MARK: - Window context at screen point (for drag-attach)

    func windowContextAtPoint(_ screenPoint: NSPoint) -> PromptContext? {
        let screen = window?.screen ?? NSScreen.main
        // CGWindowList uses top-left origin; NSEvent.mouseLocation uses bottom-left
        let screenMaxY = screen?.frame.maxY ?? NSScreen.main!.frame.maxY
        let cgPoint = CGPoint(x: screenPoint.x, y: screenMaxY - screenPoint.y)

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ourBundle = Bundle.main.bundleIdentifier ?? ""

        for info in windowList {
            guard let b = info[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? CGFloat, let y = b["Y"] as? CGFloat,
                  let w = b["Width"] as? CGFloat, let h = b["Height"] as? CGFloat else { continue }
            guard CGRect(x: x, y: y, width: w, height: h).contains(cgPoint) else { continue }

            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier != ourBundle,
                  app.activationPolicy == .regular else { continue }

            return WindowContextCapture.captureActive(from: app)
        }
        return nil
    }

    // MARK: - Coordinate conversion: window (AppKit, y-up) → island coords (y-down, 0,0 = island top-left)

    /// The closed-notch color under a screen point. The open drawer uses `terminalBlob`.
    func closedTerminalBlob(at screenPoint: CGPoint) -> String? {
        guard state.mode != .expanded, let panel = window else { return nil }
        let (islandW, islandH) = islandSize(
            mode: state.mode,
            view: state.view,
            progress: state.uploadProgress,
            nw: notchW,
            nh: notchH,
            hasNotch: state.hasNotch
        )
        let local = CGPoint(x: screenPoint.x - panel.frame.minX, y: screenPoint.y - panel.frame.minY)
        let islandLeft = IslandMotion.centeredOrigin(panelWidth: panel.frame.width, islandWidth: islandW)
        let clearance = NotchClearance(occludedHeight: state.hasNotch ? notchH : 0)
        let earHeight = clearance.expandedOffset > 0 ? clearance.expandedOffset : islandH
        let centers = TerminalBehavior.collapsedBlobCenters(
            islandWidth: islandW,
            notchWidth: state.hasNotch ? notchW : 0
        )
        return TerminalBehavior.collapsedBlobSlot(
            x: local.x - islandLeft,
            y: panel.frame.height - local.y,
            centerX: centers.facesX,
            centerY: clearance.earCenterY(fallback: islandH),
            scale: IslandRestingLayout(width: islandW, height: earHeight).miniGridScale
        )
    }

    /// The terminal face under a window-local drag point, only on this page.
    func terminalBlob(at windowPoint: CGPoint) -> String? {
        guard state.mode == .expanded, state.view == .overview else { return nil }
        let local = windowToIsland(windowPoint)
        let contentTop = NotchClearance(occludedHeight: state.hasNotch ? state.notchHeight : 0).expandedOffset
        return TerminalBehavior.blobSlot(
            x: local.x,
            y: local.y,
            islandWidth: IslandConst.expandedWidth,
            contentTop: contentTop,
            headerInContent: !(state.hasNotch && state.notchHeight > 0)
        )
    }

    func windowToIsland(_ loc: CGPoint) -> CGPoint {
        let panelH = window?.frame.height ?? IslandConst.panelHeight
        let panelW = window?.frame.width  ?? IslandConst.panelWidth
        let islandLeft = (panelW - IslandConst.expandedWidth) / 2
        // Island is glued to panel top; its bottom in AppKit = panelH - 176
        return CGPoint(
            x: loc.x - islandLeft,
            y: panelH - loc.y                // AppKit y is from bottom; island y from top
        )
    }

    // MARK: - Helpers

    func defaultView() -> IslandView {
        if state.pendingApproval != nil { return .approval }
        if !state.tasks.isEmpty { return .overview }
        return NookPreferences.shared.nookEnabled ? .nook : .empty
    }

    func openNook() {
        openShelf(.nook)
    }

    func openTray() {
        openShelf(.tray)
    }

    private func openShelf(_ view: IslandView) {
        if state.mode == .expanded {
            state.view = view
            return
        }
        pendingExpandView = view
        if fsm.state == .petit || fsm.state == .hidden {
            fsm.click()
        } else {
            expand(to: view)
        }
    }

    private func applyTrayHighlight(at screenPoint: CGPoint) {
        let landing = trayLanding(at: screenPoint)
        NookBoard.shared.airDropHighlight = landing == .airDrop
        NookBoard.shared.dropHighlight = landing != .airDrop
    }

    private func clearTrayHighlight() {
        NookBoard.shared.dropHighlight = false
        NookBoard.shared.airDropHighlight = false
    }

    /// Hold versus AirDrop once the tray page is open. The tile frame is island-local.
    /// `draggingLocation` is already in this window, with the origin at the bottom left.
    private func trayLanding(at windowPoint: CGPoint) -> NookFileLanding {
        guard let panel = window as? IslandPanel else { return .pipeline }
        let island = panel.currentIslandFrame(nw: notchW, nh: notchH)
        let point = NookLayout.islandLocalPoint(windowPoint: windowPoint, islandFrame: island)
        let board = NookBoard.shared
        let trayPage = state.mode == .expanded && state.view == .tray
        return NookLayout.trayLanding(trayPage: trayPage, point: point, tile: board.airDropTileFrame)
    }

    private func dropChoice(at screenPoint: CGPoint) -> NookDropChoice {
        guard let panel = window as? IslandPanel else { return .agent }
        let local = panel.convertPoint(fromScreen: screenPoint)
        let island = panel.currentIslandFrame(nw: notchW, nh: notchH)
        let inside = island.contains(local)
        let fraction = island.width > 1 ? (local.x - island.minX) / island.width : 0
        return NookLayout.dropChoice(
            expanded: state.mode == .expanded,
            nookOpen: state.view == .nook || state.view == .tray,
            insideIsland: inside,
            xFraction: fraction
        )
    }

    func baseMode() -> IslandMode {
        guard state.isPresent else { return .hidden }
        return state.tasks.isEmpty ? .hidden : .compact
    }

    // MARK: - Activity reset (call on any user interaction in island)

    func resetActivity() {
        state.lastActivity = .now
    }

    // MARK: - Finished task pin (5.2s)

    func pinForFinished(taskId: String) {
        state.isPinned = true
        finishedPinTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.state.removeTask(id: taskId)
            self.state.isPinned = false
            self.collapse()
        }
        finishedPinTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2, execute: item)
    }

    // MARK: - Dizzy recovery (triggered by BotEngine.slap via .botDizzy)

    private func handleDizzy() {
        let prevView = state.view
        state.stateOverride = .dizzy
        expand(to: .confused)
        confusedRecoveryTimer?.cancel()
        let recovery = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.state.stateOverride = nil
            if self.state.view == .confused {
                let fallback = self.state.tasks.isEmpty ? IslandView.empty : .overview
                self.state.view = (prevView == .confused) ? fallback : prevView
            }
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        }
        confusedRecoveryTimer = recovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3, execute: recovery)
    }

    // MARK: - Bot hit test (for slap trigger)

    private func isBotHit(_ windowPoint: CGPoint) -> Bool {
        let s = AppState.shared
        let panelH = window?.frame.height ?? IslandConst.panelHeight
        let panelW = window?.frame.width  ?? IslandConst.panelWidth
        let (islandW, fixedH) = islandSize(mode: s.mode, view: s.view,
                                            progress: s.uploadProgress, nw: notchW, nh: notchH,
                                            hasNotch: s.hasNotch)
        // Chat view resizes dynamically — must match IslandContainer.chatPromptHeight
        let islandH: CGFloat
        if s.mode == .expanded && s.view == .prompt {
            let base: CGFloat = 240
            let perMsg: CGFloat = 40
            let chat = min(300, base + CGFloat(s.chatHistory.count) * perMsg)
            islandH = TerminalBehavior.expandedDrawerHeight(
                layoutHeight: chat,
                occludedHeight: s.hasNotch ? notchH : 0,
                headerInMenuBar: s.hasNotch
            )
        } else {
            islandH = fixedH
        }
        let islandMinX = IslandMotion.centeredOrigin(panelWidth: panelW, islandWidth: islandW)
        let wing: CGFloat = (s.mode == .hidden || s.mode == .compact) ? NookBoard.shared.restingExtra : 0
        let (cx, cy, diameter, _) = botPosition(mode: s.mode, view: s.view,
                                                  islandW: islandW, islandH: islandH,
                                                  uploadProgress: s.uploadProgress, hasNotch: s.hasNotch,
                                                  sideWing: wing, notchWidth: notchW)
        let radius = (diameter / 0.6) / 2
        // botPosition cy is from island TOP; panel AppKit coords have y=0 at bottom
        // island top in AppKit coords = panelH (island glued to top of panel/screen)
        let botX = islandMinX + cx
        let botY = panelH - cy
        let dx = windowPoint.x - botX
        let dy = windowPoint.y - botY
        return dx*dx + dy*dy <= radius * radius
    }

    // MARK: - Notch detection (static)

    static func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    /// Notch size plus the General-tab fine tune, or the no-notch handler size.
    static func fittedNotch(on screen: NSScreen) -> (width: CGFloat, height: CGFloat, hasNotch: Bool) {
        let geometry = screenGeometry(for: screen)
        let prefs = NookPreferences.shared
        if geometry.hasNotch {
            return (
                max(60, geometry.width + CGFloat(prefs.notchWidthOffset)),
                max(8, geometry.height + CGFloat(prefs.notchHeightOffset)),
                true
            )
        }
        guard prefs.handlerEnabled else { return (1, 1, false) }
        return (CGFloat(prefs.handlerWidth), CGFloat(prefs.handlerHeight), false)
    }

    /// The closed island grows by the same amount on both sides. Widen the
    /// panel when that shape no longer fits, and keep the panel centered.
    private func matchPanelWidth(_ panel: IslandPanel) {
        let (islandW, _) = islandSize(
            mode: state.mode, view: state.view,
            progress: state.uploadProgress, nw: notchW, nh: notchH,
            hasNotch: state.hasNotch
        )
        let visualH = panel.currentIslandFrame(nw: notchW, nh: notchH).height
        let neededW = max(IslandConst.panelWidth, ceil(islandW))
        let neededH = max(IslandConst.panelHeight, ceil(visualH + 8))
        let frame = panel.frame
        guard abs(frame.width - neededW) > 0.5 || abs(frame.height - neededH) > 0.5,
              let screen = panel.screen ?? Self.notchScreen() ?? NSScreen.main else { return }
        let sf = screen.frame
        panel.setFrame(
            NSRect(x: sf.midX - neededW / 2, y: sf.maxY - neededH, width: neededW, height: neededH),
            display: false
        )
    }

    private func applyChrome() {
        guard let screen = window?.screen ?? Self.notchScreen() ?? NSScreen.main else { return }
        let fitted = Self.fittedNotch(on: screen)
        notchW = fitted.width
        notchH = fitted.height
        hasNotch = fitted.hasNotch
        islandPanel.notchWidth = notchW
        islandPanel.notchHeight = notchH
        AppState.shared.notchWidth = notchW
        AppState.shared.notchHeight = notchH
        AppState.shared.hasNotch = hasNotch
    }

    private var lastNotchGesture = Date.distantPast

    private func handleEscape() {
        if TerminalDesk.shared.consumeEscape() { return }
        if settingsPreview != .none { return }
        if state.mode == .expanded && !state.isPinned {
            collapse()
        }
    }

    private func handleNotchScroll(_ event: NSEvent) {
        let prefs = NookPreferences.shared
        guard Date().timeIntervalSince(lastNotchGesture) > 0.45 else { return }
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        let mouse = NSEvent.mouseLocation
        let overNotch = isMouseOverIsland(mouse)
        if overNotch && !prefs.gesturesWhileHovering { return }
        if !overNotch { return }

        if prefs.horizontalMediaGestures,
           abs(dx) > 8, abs(dx) > abs(dy),
           NookBoard.shared.playingSource != nil {
            lastNotchGesture = Date()
            let next = NookLayout.mediaSkipsToNext(
                deltaX: dx,
                naturalScrolling: event.isDirectionInvertedFromDevice,
                invert: prefs.invertMediaGestures
            )
            NookBoard.shared.skip(next: next)
            return
        }

        guard prefs.verticalGestures else { return }
        guard settingsPreview == .none else { return }
        guard abs(dy) > 8, abs(dy) > abs(dx) else { return }
        lastNotchGesture = Date()
        if dy > 0 {
            if fsm.state == .hidden || fsm.state == .petit { fsm.click() }
        } else if fsm.state == .home || state.mode == .expanded {
            collapse()
        } else if fsm.state == .petit {
            setMode(.hidden)
            fsm.hiddenExternally()
        }
    }

    private func isMouseOverIsland(_ mouse: CGPoint) -> Bool {
        guard let panel = window as? IslandPanel else { return false }
        let local = CGPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        let islandRect = panel.currentIslandFrame(nw: notchW, nh: notchH)
        return islandRect.insetBy(dx: -6, dy: -6).contains(local)
    }

    /// Top of the menu-bar screen in AppKit coordinates: origin of `DesktopSpace`.
    static var desktopTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    /// Mochi's look target from the current mouse position (see the mouse-moved monitors).
    static func trackMouseLook() {
        let app = AppState.shared
        guard app.mode != .hidden || app.mochiOnDesktop else { return }
        let pos = DesktopSpace.topDown(NSEvent.mouseLocation, desktopTop: desktopTop)
        let cur = app.mousePosition
        if abs(pos.x - cur.x) > 1 || abs(pos.y - cur.y) > 1 { app.mousePosition = pos }
    }

    /// Screen the island currently sits on (Settings window, desktop Mochi flights).
    private(set) static var currentScreen: NSScreen?

    static func islandScreen() -> NSScreen {
        if let s = currentScreen, NSScreen.screens.contains(s) { return s }
        return notchScreen() ?? NSScreen.main!
    }

    /// Screen matching the user's choice; falls back to the notch screen, then the main one.
    static func targetScreen(for choice: IslandDisplayChoice) -> NSScreen {
        let screens = NSScreen.screens
        let mouse = NSEvent.mouseLocation
        let candidates = screens.map {
            IslandDisplayCandidate(uuid: displayUUID($0), hasNotch: $0.safeAreaInsets.top > 0,
                                   containsMouse: $0.frame.contains(mouse))
        }
        if let i = IslandDisplayResolver.index(for: choice, in: candidates) { return screens[i] }
        return notchScreen() ?? NSScreen.main ?? screens[0]
    }

    /// Stable display UUID (the NSScreenNumber can change after a reboot or a replug).
    static func displayUUID(_ screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func screenGeometry(for screen: NSScreen) -> IslandScreenGeometry {
        let visibleMenuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        // visibleFrame includes the menu bar only while it is visible. Keep a
        // small resting bar when menus auto-hide or the app is in full screen.
        let menuBarHeight = visibleMenuBarHeight > 0
            ? visibleMenuBarHeight : NSStatusBar.system.thickness
        return IslandScreenGeometry(
            screenWidth: screen.frame.width, safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: menuBarHeight
        )
    }

    nonisolated func cleanup() {
        // Called explicitly before release if needed
    }
}

// MARK: - IslandPanel

/// The notch is a non-activating panel. SwiftUI's private views refuse the
/// first press, so a drag that starts on a tray file never begins. Make the
/// panel key, and teach each view class inside it to accept that press.
@MainActor
enum NotchClickDelivery {
    private static var patched: Set<ObjectIdentifier> = []

    static func prepare(_ panel: IslandPanel) {
        if !panel.isKeyWindow { panel.makeKey() }
        if let root = panel.contentView { patch(root) }
    }

    static func patchTree(_ view: NSView) {
        patch(view)
    }

    private static func patch(_ view: NSView) {
        let cls: AnyClass = object_getClass(view) ?? NSView.self
        if patched.insert(ObjectIdentifier(cls)).inserted {
            let sel = #selector(NSView.acceptsFirstMouse(for:))
            guard let method = class_getInstanceMethod(NSView.self, sel),
                  let encoding = method_getTypeEncoding(method) else { return }
            let takeFirstPress: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
            class_replaceMethod(cls, sel, imp_implementationWithBlock(takeFirstPress), encoding)
        }
        for child in view.subviews {
            patch(child)
        }
    }
}

/// The notch is a non-activating panel. The first press must reach the tray,
/// or a drag onto AirDrop never starts.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// SwiftUI's private subviews refuse the first press. This view accepts it,
    /// and mouseDown forwards the press into SwiftUI. Text fields keep their own hit.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if let hit = super.hitTest(point), Self.isTextInput(hit) {
            return hit
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        if let mark = trayMark(at: event.locationInWindow) {
            mark.mouseDown(with: event)
            return
        }
        super.mouseDown(with: event)
    }

    /// Finds the plus or the X under this press. SwiftUI draws them, but the
    /// click has to be handed to the button or the pipeline never starts.
    private func trayMark(at windowPoint: NSPoint) -> TrayMarkButton? {
        let local = convert(windowPoint, from: nil)
        guard let hit = super.hitTest(local) else { return nil }
        if let mark = Self.mark(hit, containing: windowPoint) { return mark }
        var current: NSView? = hit
        while let cursor = current, !(cursor is NotchHostingView) {
            for child in cursor.subviews.reversed() {
                if let mark = Self.mark(child, containing: windowPoint) { return mark }
            }
            current = cursor.superview
        }
        return nil
    }

    private static func mark(_ view: NSView, containing windowPoint: NSPoint) -> TrayMarkButton? {
        if let mark = view as? TrayMarkButton {
            let local = mark.convert(windowPoint, from: nil)
            if mark.bounds.contains(local) { return mark }
        }
        for child in view.subviews.reversed() {
            if let found = mark(child, containing: windowPoint) { return found }
        }
        return nil
    }

    private static func isTextInput(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let cursor = current {
            if cursor is NSTextField || cursor is NSTextView { return true }
            if cursor is NotchHostingView { return false }
            current = cursor.superview
        }
        return false
    }
}

final class IslandPanel: NSPanel {
    var notchWidth:  CGFloat = IslandConst.notchWidth
    var notchHeight: CGFloat = IslandConst.notchHeight

    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }

    /// Allow panel to sit in the menu bar / notch area — don't let macOS push it down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    func currentIslandFrame(nw: CGFloat, nh: CGFloat) -> CGRect {
        let s = AppState.shared
        let (w, fixedH) = islandSize(mode: s.mode, view: s.view,
                                      progress: s.uploadProgress, nw: nw, nh: nh,
                                      hasNotch: s.hasNotch)
        let h: CGFloat
        if s.mode == .expanded && s.view == .prompt {
            let base: CGFloat = 240
            let perMsg: CGFloat = 40
            let chat = min(300, base + CGFloat(s.chatHistory.count) * perMsg)
            h = TerminalBehavior.expandedDrawerHeight(
                layoutHeight: chat,
                occludedHeight: s.hasNotch ? nh : 0,
                headerInMenuBar: s.hasNotch
            ) + max(0, s.drawerExtension)
        } else {
            h = fixedH
        }
        let origin = IslandMotion.centeredOrigin(panelWidth: frame.width, islandWidth: w)
        return CGRect(x: origin, y: frame.height - h, width: w, height: h)
    }
}

// MARK: - Ghost bot view (animated scale-in on appear)

struct GhostBotView: View {
    let canvasSize: CGFloat
    @State private var scale: CGFloat = 0.35

    var body: some View {
        BotCanvasView(state: AppState.shared)
            .frame(width: canvasSize, height: canvasSize)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                    scale = 1.0
                }
            }
    }
}

// MARK: - Voice command handling

#if !APPSTORE
extension IslandWindowController {

    /// Run the intent derived from `transcript`, show VoiceResultView, then continue conversation or collapse.
    @MainActor
    func handleVoiceCommand(_ transcript: String) async {
        let t0     = Date()
        let pills  = PillCatalog.available
        let runner = VoiceActionRunner.shared

        // Propagate recognition locale so responses are in the spoken language.
        // Answers in the answer language, whatever language I spoke.
        runner.commandLocale = VoiceSettings.answerLocale

        // ── Conversation end phrase ────────────────────────────────────────────────
        let normTranscript = WakePhrase.normalise(transcript)
        if isInConversation && TurnEndPolicy.conversationEndPhrases.contains(normTranscript) {
            VoiceTranscriptHistory.shared.record(transcript: transcript, note: "end", origin: .end)
            closeVoiceTurn()
            return
        }

        // Mochi transitions to "thinking" while we process
        AppState.shared.voiceSubState = .thinking

        // ── Claude as the brain (Settings → Voice, the user's Anthropic key) ───────
        // Every phrase goes to Claude, which acts with Coucou's tools. Only when Claude
        // can't be reached does the phrase parser below take over.
        if runner.pendingQuestion == nil, ClaudeVoiceBrain.isActive {
            if await handleWithClaude(transcript) { return }
            appendAppLog("nb.log", "[Voice] Claude unreachable, phrase parser used")
        }

        // ── Short noise / spurious activation guard (conversation mode only) ────────
        // A transcript shorter than 2 words that isn't a pill name or known command
        // is almost certainly a false activation. Silently re-listen without feedback.
        // A one-word reply to Coucou's own question ("Tana", "non", "yes" after "want the
        // details?") is expected, not noise.
        if isInConversation && runner.pendingQuestion == nil && !runner.hasWebThread {
            let normWords = normTranscript.split(separator: " ").map(String.init)
            if normWords.count < 2 {
                let isPillName = pills.contains { IntentParser.normalise($0.name) == normTranscript }
                let isKnown    = IntentParser.parse(normTranscript, pills: pills) != .unknown
                if !isPillName && !isKnown {
                    // Never log the words themselves (VOICE.md: no transcript on disk).
                    appendAppLog("nb.log", "[Voice] ignoring short spurious transcript")
                    VoiceTranscriptHistory.shared.record(transcript: transcript, note: "—", origin: .ignored)
                    closeVoiceTurn()
                    return
                }
            }
        }

        // ── Follow-up answer to a pending question ─────────────────────────────────
        if runner.pendingQuestion != nil {
            let result = await runner.handleAnswer(transcript, availablePills: pills)
            VoiceTranscriptHistory.shared.record(transcript: transcript, note: result.message, origin: .answer)
            // A question back ("What's the subject?") is not a miss: no reaction.
            if result.outcome == .failure { voiceMissReaction() }
            VoiceCaptionManager.shared.setUserLine(transcript)
            VoiceCaptionManager.shared.appendResponse(result.message)
            AppState.shared.voiceResult = result
            speakAndContinueConversation(result)
            return
        }

        // ── Multi-action: removals before additions ───────────────────────────────
        if var intents = IntentParser.parseMultiAction(transcript, pills: pills), intents.count >= 2 {
            // Sort: removals first
            intents.sort { a, b in
                let isRemoveA: Bool
                switch a {
                case .pillRemove, .pillRemoveMultiple: isRemoveA = true
                default: isRemoveA = false
                }
                let isRemoveB: Bool
                switch b {
                case .pillRemove, .pillRemoveMultiple: isRemoveB = true
                default: isRemoveB = false
                }
                return isRemoveA && !isRemoveB
            }
            VoiceTranscriptHistory.shared.record(
                transcript: transcript,
                note: intents.map { String(describing: $0) }.joined(separator: " + "),
                origin: .multi)
            var parts: [String] = []
            var anyFailure = false
            var lastSuccess: VoiceIntent? = nil
            for intent in intents {
                let r = await runner.run(intent, availablePills: pills, rawTranscript: transcript)
                parts.append(r.message)
                if case .failure = r.outcome { anyFailure = true }
                // .question in multi-action: treat as failure (no re-listen in combined flow).
                if case .question = r.outcome { anyFailure = true }
                if case .success = r.outcome { lastSuccess = intent }
            }
            if let last = lastSuccess { conversationContext.update(last) }
            let combined = VoiceActionResult(
                outcome: anyFailure ? .failure : .success,
                message: parts.joined(separator: " · ")
            )
            if anyFailure { voiceMissReaction() }
            VoiceCaptionManager.shared.setUserLine(transcript)
            VoiceCaptionManager.shared.appendResponse(combined.message)
            AppState.shared.voiceResult = combined
            speakAndContinueConversation(combined)
            return
        }

        // ── Relative context resolution ────────────────────────────────────────────
        var intent: VoiceIntent
        let transcriptOrigin: TranscriptOrigin
        if conversationContext.lastIntent != nil,
           let resolved = conversationContext.resolveRelative(transcript, pills: pills) {
            intent = resolved
            transcriptOrigin = .context
        } else {
            intent = IntentParser.parse(transcript, pills: pills)
            transcriptOrigin = .parser
        }

        // Web search on (Settings → Voice): a question no pill or service answers goes to
        // Claude with web search, and so does the reply to its own follow-up question.
        if case .unknown = intent, runner.info.webSearchEnabled, runner.info.hasWebKey,
           VoiceQuery.looksLikeQuestion(transcript) || (isInConversation && runner.hasWebThread) {
            intent = .webSearch(query: transcript)
        }
        if case .webSearch(let q) = intent, !q.isEmpty,
           runner.info.webSearchEnabled, runner.info.hasWebKey, VoiceSettings.speakEnabled {
            // A web search takes a few seconds: say so instead of going quiet.
            VoiceSpeaker.shared.onDidFinish = nil
            let wait = VoiceSettings.language == "fr" ? "Je regarde." : "Let me check."
            VoiceSpeaker.shared.speak(wait, locale: VoiceSettings.answerLocale)
        }

        // ── Single command ─────────────────────────────────────────────────────────
        let locale = VoiceSettings.answerLocale
        let tParseEnd = Date()
        let parseMs   = Int(tParseEnd.timeIntervalSince(t0) * 1000)

        // Update caption user line immediately
        VoiceCaptionManager.shared.setUserLine(transcript)

        var result = await runner.run(intent, availablePills: pills, rawTranscript: transcript)
        var effectiveIntent = intent
        VoiceTranscriptHistory.shared.record(transcript: transcript, intent: intent, origin: transcriptOrigin)

        let tActionEnd = Date()
        let actionMs   = Int(tActionEnd.timeIntervalSince(tParseEnd) * 1000)

        // Incomplete phrase ("je veux que tu ajoutes…", nothing named): ask which pill
        // and listen for it, instead of guessing or saying "pas compris".
        var askedBack = false
        if case .unknown = intent, let ask = runner.askIfIncomplete(transcript) {
            result = ask
            askedBack = true
        }

        // If unknown, try VoiceBrain (macOS 26 + Apple Intelligence) with streaming TTS.
        // (Not when Claude is the brain and just couldn't be reached: no local model then.)
        if case .unknown = intent, !askedBack, !ClaudeVoiceBrain.isActive {
            let tBrain0  = Date()
            let brainWarm = VoiceBrain.shared.isSessionReady
            var brainUsed = false

            // A stale "finished speaking" handler from the previous turn would re-open
            // the mic between two streamed sentences: drop it before streaming.
            VoiceSpeaker.shared.onDidFinish = nil

            let brain = await VoiceBrain.shared.resolveWithStreaming(
                transcript, pills: pills
            ) { sentence, hasActions in
                // When the model is acting (tool call), its text is not spoken: the real
                // outcome comes from VoiceActionRunner below ("C'est fait" must not be
                // said before the action ran, or when it failed / needs a question).
                if !hasActions { VoiceSpeaker.shared.enqueue(sentence, locale: locale) }
                VoiceCaptionManager.shared.appendResponse(sentence)
            }

            let brainMs = Int(Date().timeIntervalSince(tBrain0) * 1000)
            appendAppLog("nb.log",
                "[Voice] turn: parse=\(parseMs)ms action=\(actionMs)ms brain=\(brainMs)ms (\(brainWarm ? "warm" : "cold"))")

            if let brain {
                if !brain.intents.isEmpty {
                    // Run the actions the model asked for: removals before additions.
                    var sorted = brain.intents
                    sorted.sort { a, b in
                        let ra: Bool = { switch a { case .pillRemove, .pillRemoveMultiple: return true; default: return false } }()
                        let rb: Bool = { switch b { case .pillRemove, .pillRemoveMultiple: return true; default: return false } }()
                        return ra && !rb
                    }
                    effectiveIntent = sorted[0]
                    var parts: [String] = []
                    var anyFailure = false
                    var questionResult: VoiceActionResult? = nil
                    for bi in sorted {
                        let r = await runner.run(bi, availablePills: pills, rawTranscript: transcript)
                        parts.append(r.message)
                        switch r.outcome {
                        case .success:
                            effectiveIntent = bi
                            VoiceTranscriptHistory.shared.record(transcript: transcript, intent: bi, origin: .brain)
                        case .failure:
                            anyFailure = true
                        case .question:
                            questionResult = r
                        }
                    }
                    // Same path as a parser command below: short spoken confirmation,
                    // or the question ("laquelle j'enlève ?") with its re-listen.
                    VoiceCaptionManager.shared.clearResponse()
                    result = questionResult ?? VoiceActionResult(
                        outcome: anyFailure ? .failure : .success,
                        message: parts.joined(separator: " · "))
                } else if !brain.text.isEmpty {
                    result = VoiceActionResult(outcome: .success, message: brain.text)
                    brainUsed = true
                }
            }

            if brainUsed {
                // TTS sentences already enqueued via streaming. Enter conversation and
                // continue once the speaker queue drains.
                conversationContext.update(effectiveIntent)
                consecutiveFailures = 0
                AppState.shared.voiceResult = result
                _enterConversationAfterStreamedSpeech()
                return
            }

            appendAppLog("nb.log", "[Voice] turn: parse=\(parseMs)ms action=\(actionMs)ms brain=\(brainMs)ms (\(brainWarm ? "warm" : "cold")) — no result")
        } else {
            appendAppLog("nb.log", "[Voice] turn: parse=\(parseMs)ms action=\(actionMs)ms (parser)")
        }

        // Mid-conversation, a phrase with no command in it (talking to someone else,
        // "on s'en fout c'est"…) is dropped silently: no dizzy Mochi, no "pas compris".
        // Two in a row end the conversation.
        if case .unknown = effectiveIntent, result.outcome == .failure {
            if isInConversation {
                // Second miss (or noise while waiting for an answer): stop there.
                appendAppLog("nb.log", "[Voice] answer had no command in it, ignored")
                closeVoiceTurn()
                return
            }
            // First miss right after "OK Coucou": ask once, like a person would
            // ("Pardon, tu peux répéter ?"), then listen for the repeat.
            let again = VoiceActionResult(
                outcome: .success,
                message: VoiceActionRunner.localizedString("voice.ask-repeat", locale: runner.commandLocale))
            VoiceCaptionManager.shared.appendResponse(again.message)
            AppState.shared.voiceResult = again
            speakAndContinueConversation(again)
            return
        }

        // Mochi reaction + consecutive failure tracking
        switch result.outcome {
        case .success:
            conversationContext.update(effectiveIntent)
            consecutiveFailures = 0
        case .failure:
            voiceMissReaction()
            if isInConversation { consecutiveFailures += 1 }
        case .question:
            break   // Mochi will show listening after re-open
        }

        // After 2 consecutive failures in conversation mode: end without speaking
        if isInConversation && consecutiveFailures >= 2 {
            consecutiveFailures = 0
            endConversation(speaking: false)
            return
        }

        // Update caption with result; island stays compact (no expand).
        VoiceCaptionManager.shared.appendResponse(result.message)
        AppState.shared.voiceResult = result

        if case .question = result.outcome {
            // Speak the question aloud, then re-listen once speech finishes.
            // Give 5 s initial silence so the user has time to read/hear the question.
            let speaker = VoiceSpeaker.shared
            if VoiceSettings.speakEnabled {
                speaker.speak(result.message, locale: locale)
                speaker.onDidFinish = { [weak self] in
                    Task { @MainActor in
                        guard self != nil else { return }
                        VoiceEngine.shared.startListeningDirectly(firstWordTimeout: Self.answerWait(5.0))
                    }
                }
            } else {
                voiceResultWork?.cancel()
                voiceResultWork = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard self != nil else { return }
                    VoiceEngine.shared.startListeningDirectly(firstWordTimeout: Self.answerWait(5.0))
                }
            }
        } else {
            speakAndContinueConversation(result)
        }
    }

    @MainActor
    private func showVoiceResult(_ result: VoiceActionResult, emote: BotEmote? = nil) {
        if let emote = emote {
            NotificationCenter.default.post(name: .triggerEmote, object: emote)
        } else if result.outcome == .failure {
            voiceMissReaction()
        }
        AppState.shared.voiceResult = result
        expand(to: .voiceResult)
        scheduleVoiceDismiss(delay: 2.0)
    }

    /// Speak the result, then stop listening — unless the answer is a question, in which
    /// case listen once for the reply. Coucou cannot tell whether I am talking to it or
    /// to someone else, so it only keeps the mic open when it asked something.
    @MainActor
    private func speakAndContinueConversation(_ result: VoiceActionResult) {
        let asks = Self.isQuestion(result)
        let speaker = VoiceSpeaker.shared
        if VoiceSettings.speakEnabled {
            AppState.shared.voiceSubState = .speaking
            speaker.speak(result.message, locale: VoiceSettings.answerLocale)
            speaker.onDidFinish = { [weak self] in
                Task { @MainActor in self?.finishVoiceTurn(expectAnswer: asks) }
            }
        } else {
            // No speech: leave the caption up a moment, then finish.
            voiceResultWork?.cancel()
            let item = DispatchWorkItem { [weak self] in
                Task { @MainActor in self?.finishVoiceTurn(expectAnswer: asks) }
            }
            voiceResultWork = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
        }
    }

    /// After the on-device model's streamed answer: same rule once the speech drains.
    @MainActor
    private func _enterConversationAfterStreamedSpeech() {
        let asks = Self.isQuestion(AppState.shared.voiceResult)
        let speaker = VoiceSpeaker.shared
        if speaker.isSpeaking {
            speaker.onDidFinish = { [weak self] in
                Task { @MainActor in self?.finishVoiceTurn(expectAnswer: asks) }
            }
        } else {
            finishVoiceTurn(expectAnswer: asks)
        }
    }

    /// A question Coucou asked: an explicit follow-up, or an answer ending with "?".
    private static func isQuestion(_ result: VoiceActionResult?) -> Bool {
        guard let result else { return false }
        if case .question = result.outcome { return true }
        let t = result.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasSuffix("?") || t.hasSuffix("？") || t.hasSuffix("؟")
    }

    /// Listen once for the reply to Coucou's question, or close the turn.
    @MainActor
    private func finishVoiceTurn(expectAnswer: Bool) {
        // First time I speak one language and Coucou answers in another: offer once to
        // answer in mine ("You're speaking French. Want me to answer in French?").
        if !expectAnswer, !ClaudeVoiceBrain.isActive, !VoiceSettings.languageOfferDone,
           let spoken = VoiceEngine.shared.speechLocale?.language.languageCode?.identifier,
           ["fr", "en"].contains(spoken), spoken != VoiceSettings.language,
           VoiceEngine.shared.isEnabled {
            VoiceSettings.languageOfferDone = true
            let offer = VoiceActionRunner.shared.offerLanguageSwitch(to: spoken)
            VoiceCaptionManager.shared.appendResponse(offer)
            let speaker = VoiceSpeaker.shared
            if VoiceSettings.speakEnabled {
                speaker.speak(offer, locale: VoiceSettings.answerLocale)
                speaker.onDidFinish = {
                    Task { @MainActor in VoiceEngine.shared.startListeningDirectly(firstWordTimeout: 5.0) }
                }
            } else {
                VoiceEngine.shared.startListeningDirectly(firstWordTimeout: 5.0)
            }
            return
        }
        // One follow-up only: the reply to a question closes the turn after it is handled
        // (unless that reply leads to another question, e.g. "which one do I remove?").
        if expectAnswer && VoiceEngine.shared.isEnabled {
            isInConversation = true
            if !ClaudeVoiceBrain.isActive { VoiceBrain.shared.beginConversation() }
            if AppState.shared.soundEnabled { SoundEngine.shared.play("tick") }
            AppState.shared.voiceSubState = .listening
            VoiceEngine.shared.startConversationTurn(firstWordTimeout: Self.answerWait(8.0))
        } else {
            closeVoiceTurn()
        }
    }

    /// One turn with Claude: caption, spoken answer, and a re-listen when Claude asked
    /// something (its answer ends with "?"). False when Claude couldn't be reached.
    @MainActor
    private func handleWithClaude(_ transcript: String) async -> Bool {
        VoiceCaptionManager.shared.setUserLine(transcript)
        // A stale "finished speaking" handler must not reopen the mic during the wait.
        VoiceSpeaker.shared.onDidFinish = nil
        let t0 = Date()
        guard let reply = await ClaudeVoiceBrain.shared.respond(to: transcript), !reply.failed else {
            return false
        }
        appendAppLog("nb.log", "[Voice] Claude turn \(Int(Date().timeIntervalSince(t0) * 1000)) ms\(reply.acted ? ", acted" : "")")
        let fr = VoiceSettings.language == "fr"
        let text = reply.text.isEmpty ? (fr ? "C'est fait." : "Done.") : reply.text
        VoiceTranscriptHistory.shared.record(transcript: transcript, note: text, origin: .brain)
        consecutiveFailures = 0
        if reply.acted { NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy) }
        VoiceCaptionManager.shared.appendResponse(text)
        let result = VoiceActionResult(outcome: .success, message: text)
        AppState.shared.voiceResult = result
        speakAndContinueConversation(result)
        return true
    }

    /// A file dropped on the notch while the voice email card is open: it becomes the
    /// attachment, and Coucou says so.
    @MainActor
    func attachToVoiceMailCard(_ url: URL) {
        // Not listening any more: Coucou's own "attached" must not come back as a turn.
        VoiceEngine.shared.cancelListening()
        if isInConversation || AppState.shared.voiceActive { closeVoiceTurn() }
        let state = AppState.shared
        state.fileDragOver = false
        state.droppedFile = DroppedFile(url: url, name: url.lastPathComponent)
        NotificationCenter.default.post(name: .botGulp, object: nil)
        NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(0))
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        if state.soundEnabled { SoundEngine.shared.play("approve") }
        fsm.openedExternally()
        expand(to: .mail)
        let fr = VoiceSettings.language == "fr"
        let text = fr ? "\(url.lastPathComponent) est en pièce jointe. Tu n'as plus qu'à cliquer sur Envoyer."
                      : "\(url.lastPathComponent) is attached. Just click Send."
        if VoiceSettings.speakEnabled {
            VoiceSpeaker.shared.onDidFinish = nil
            VoiceSpeaker.shared.speak(text, locale: VoiceSettings.answerLocale)
        }
    }

    /// A voice command that failed: a small "huh?" from Mochi. Not .botDizzy, which is the
    /// slap reaction and opened the "Too many hits at once" card in the middle of a mail.
    @MainActor
    func voiceMissReaction() {
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
    }

    /// Seconds to wait for the first word of a reply: longer while Coucou waits for a
    /// file, since finding it in Finder and dragging it takes a moment.
    @MainActor
    static func answerWait(_ normal: TimeInterval) -> TimeInterval {
        VoiceActionRunner.shared.isWaitingForAttachment ? 20.0 : normal
    }

    /// A file dropped on the notch while Coucou asked for an attachment: stop listening,
    /// a little gulp, then the filled-in mail card and Coucou says so.
    @MainActor
    func attachVoiceMailFile(_ url: URL) async {
        VoiceEngine.shared.cancelListening()
        let state = AppState.shared
        state.fileDragOver = false
        NotificationCenter.default.post(name: .botGulp, object: nil)
        NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(0))
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        if state.soundEnabled { SoundEngine.shared.play("approve") }
        let result = await VoiceActionRunner.shared.attachDroppedFile(url)
        VoiceCaptionManager.shared.appendResponse(result.message)
        state.voiceResult = result
        speakAndContinueConversation(result)
    }

    /// Stop listening and let the island settle. The context (last action, model session)
    /// stays 90 s so a new "OK Coucou, et Stripe aussi" still understands "aussi".
    @MainActor
    private func closeVoiceTurn() {
        isInConversation = false
        consecutiveFailures = 0
        hasSpokenPasCompris = false
        VoiceEngine.shared.endConversation()
        VoiceCaptionManager.shared.endConversation()
        scheduleVoiceDismiss(delay: 0.3)
        voiceContextExpiry?.cancel()
        let expiry = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.conversationContext.reset()
                VoiceActionRunner.shared.resetWebThread()
                ClaudeVoiceBrain.shared.reset()
                VoiceBrain.shared.endConversation()
            }
        }
        voiceContextExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: expiry)
    }

    /// Kept for the paths that still call it (collapse, end phrase): close and forget.
    @MainActor
    private func endConversation(speaking: Bool) {
        closeVoiceTurn()
    }

    @MainActor
    private func scheduleVoiceDismiss(delay: TimeInterval) {
        voiceResultWork?.cancel()
        VoiceCaptionManager.shared.hide(after: delay)
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Mochi winks as the exchange ends — but only when the sub-state is still .speaking
            // (not if voiceActive was already cleared by a collapse).
            if AppState.shared.voiceActive {
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.wink)
            }
            AppState.shared.voiceSubState = .none
            AppState.shared.voiceResult = nil
            AppState.shared.voiceActive = false
            if AppState.shared.voiceMailDraft != nil {
                // The voice email card stays open until I click Send or Cancel.
                self.fsm.openedExternally()
                self.expand(to: .mail)
                return
            }
            // If the island is already expanded (user opened it during voice): stay open.
            guard self.fsm.state != .home else { return }
            // Reset view before collapsing so shouldIgnoreWake never sees a stale .voiceResult.
            AppState.shared.view = self.defaultView()
            self.fsm.voiceFinished()
        }
        voiceResultWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
#endif

// MARK: - Notification names

extension Notification.Name {
    static let triggerEmote     = Notification.Name("notchBuddy.triggerEmote")
    static let triggerSlap      = Notification.Name("notchBuddy.triggerSlap")
    static let botDizzy         = Notification.Name("notchBuddy.botDizzy")
    static let botGreet         = Notification.Name("notchBuddy.botGreet")
    static let botBlink         = Notification.Name("notchBuddy.botBlink")
    static let botSetTgEs       = Notification.Name("notchBuddy.botSetTgEs")
    static let botGulp          = Notification.Name("notchBuddy.botGulp")
    static let botMorphTo       = Notification.Name("notchBuddy.botMorphTo")
    static let islandAction     = Notification.Name("notchBuddy.islandAction")
    static let islandCollapse   = Notification.Name("notchBuddy.islandCollapse")
    static let openNookPage     = Notification.Name("notchBuddy.openNookPage")
    static let settingsNotchPreview = Notification.Name("notchBuddy.settingsNotchPreview")
    static let voiceShowMailCard   = Notification.Name("notchBuddy.voiceShowMailCard")
    static let islandSendMessage   = Notification.Name("notchBuddy.islandSendMessage")
    static let islandNewConversation = Notification.Name("notchBuddy.islandNewConversation")
    static let islandToggleDiff           = Notification.Name("notchBuddy.islandToggleDiff")
    static let islandActivateCardSelection = Notification.Name("notchBuddy.islandActivateCardSelection")
    static let openFullSettings = Notification.Name("notchBuddy.openFullSettings")
    static let hookReveal       = Notification.Name("notchBuddy.hookReveal")
    static let musicReveal      = Notification.Name("notchBuddy.musicReveal")
    // Greeting ↔ IslandWindowController
    static let greetComplete    = Notification.Name("notchBuddy.greetComplete")
    static let checkMondayRecap = Notification.Name("notchBuddy.checkMondayRecap")
    static let greetingHover    = Notification.Name("notchBuddy.greetingHover")
    static let greetingInterrupt = Notification.Name("notchBuddy.greetingInterrupt")
    static let openWardrobeFromDesktop = Notification.Name("notchBuddy.openWardrobeFromDesktop")
    // Island moved to another screen (resting size may differ: notch vs bar)
    static let islandScreenChanged = Notification.Name("notchBuddy.islandScreenChanged")
}

// MARK: - islandSize (takes real notch dimensions)

@MainActor
func islandSize(mode: IslandMode, view: IslandView,
                progress: Double = 0,
                nw: CGFloat = IslandConst.notchWidth,
                nh: CGFloat = IslandConst.notchHeight,
                hasNotch: Bool = false) -> (CGFloat, CGFloat) {
    let board = NookBoard.shared
    let hudWing = (mode == .hidden || mode == .compact) ? HudBehavior.wingWidth(showing: HudController.shared.visible) : 0
    let blobWing: CGFloat = mode == .hidden ? TerminalBehavior.collapsedWing : 0
    let side = (mode == .hidden || mode == .compact) ? board.restingExtra + board.mediaWing + board.trayWing + hudWing + blobWing : 0
    let extra = IslandMotion.balancedWidth(side: side)
    let clearance = NotchClearance(occludedHeight: hasNotch ? nh : 0)
    switch mode {
    case .hidden:
        return (nw + extra, clearance.restingHeight(fallback: nh, showingInformation: notchInformationIsRunning()))
    case .compact:
        return (nw + 160 + extra, clearance.restingHeight(fallback: nh, showingInformation: notchInformationIsRunning()))
    case .expanded:
        let layout = IslandConst.viewLayouts[view]!
        if view == .question, let h = QuestionLayout.height {
            return (IslandConst.expandedWidth, h)
        }
        let pull = max(0, AppState.shared.drawerExtension)
        let width: CGFloat
        if view == .nook || view == .tray {
            let prefs = NookPreferences.shared
            let columns = prefs.widgets.filter(\.enabled).map { NookColumnSpec(id: $0.id, cells: $0.cells) }
            let padding = CGFloat(prefs.contentPadding)
            if view == .nook {
                let mediaLive = NookLayout.mediaIsLive(title: board.mediaTitle)
                width = NookLayout.nookDrawerWidth(
                    columns: columns,
                    dividers: prefs.widgetDividers,
                    contentPadding: padding,
                    mediaLive: mediaLive
                )
            } else {
                width = NookLayout.nookDrawerWidth(
                    columns: columns,
                    dividers: prefs.widgetDividers,
                    contentPadding: padding
                )
            }
        } else {
            width = IslandConst.expandedWidth
        }
        let headerInMenuBar = hasNotch && view != .greeting
        return (width, TerminalBehavior.expandedDrawerHeight(
            layoutHeight: layout.height,
            occludedHeight: hasNotch ? nh : 0,
            headerInMenuBar: headerInMenuBar
        ) + pull)
    }
}

/// Closed-notch items stay in the menu bar. The island grows wide, not tall.
@MainActor
func notchInformationIsRunning() -> Bool {
    let title = NookBoard.shared.mediaTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let playing = NookBoard.shared.mediaIsPlaying && !title.isEmpty
    return NookLayout.collapsedDropsBand(
        hudVisible: HudController.shared.visible,
        mediaPlaying: playing
    )
}
