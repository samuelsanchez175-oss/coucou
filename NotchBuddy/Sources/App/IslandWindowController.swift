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

    // Confused recovery timer (set by handleDizzy)
    private var confusedRecoveryTimer: DispatchWorkItem?

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

    convenience init() {
        let screen = Self.notchScreen() ?? NSScreen.main!
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

        let hosting = NotchHostingView(rootView: IslandRootView().environmentObject(AppState.shared))
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
        startKeyMonitor()
        wireFSM()

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
    }

    // MARK: - FSM wiring

    private func wireFSM() {
        fsm.allowsHide = { [weak self] in
            guard let self else { return true }
            if NookPreferences.shared.demoMode && self.hasNotch { return false }
            return true
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
                    SoundEngine.shared.play("peek")
                }
                // setMode BEFORE changing view: onChange(of: state.view) guards on .expanded,
                // so setting view while already compact won't trigger a spurious open animation.
                self.setMode(.compact)
                if from == .coucou { self.state.view = self.defaultView() }
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
            }
        }

        // FSM observes greetComplete notification
        NotificationCenter.default.addObserver(
            forName: .greetComplete, object: nil, queue: .main
        ) { [weak self] _ in
            self?.fsm.greetComplete()
        }
    }

    // MARK: - 60 Hz polling loop

    private func startPolling() {
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.pollFrame() }
        }
        RunLoop.main.add(frameTimer!, forMode: .common)
    }

    private func pollFrame() {
        guard let panel = window as? IslandPanel else { return }
        matchPanelWidth(panel)

        let mouse = NSEvent.mouseLocation

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
        // through to the desktop.
        let inIsland = hoverRect.contains(local) || pulling || (buttonHeld && state.mode == .expanded)
            || (state.mode == .expanded && panelBounds.contains(local))

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

        // Mouse in screen coords (Y flipped, origin top-left) for Bot look-at
        let screenH = panel.screen?.frame.height ?? NSScreen.main!.frame.height
        let newPos = CGPoint(x: mouse.x - (panel.screen?.frame.minX ?? 0), y: screenH - mouse.y)
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

        // Feed FSM hover enter/leave
        if !typingLock && inIsland && !wasInIsland {
            guard !inAttachDrag else { wasInIsland = inIsland; return }
            // If in coucou: tell greeting to stay open (tc → infinity)
            if fsm.state == .coucou {
                NotificationCenter.default.post(name: .greetingHover, object: nil)
            }
            fsm.mouseEntered()
            if prefs.alwaysOpenOnHover && settingsPreview == .none && (fsm.state == .petit || fsm.state == .hidden) {
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
    }

    private var lastMouse: CGPoint = .zero

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
            state.isPinned = false
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

    func collapse() {
        state.isPinned = false
        finishedPinTimer?.cancel()
        // Home and the greeting shrink back to the notch. Compact is the hover
        // shelf only, and stopping there left the closed drawer wide.
        fsm.collapse()
        if state.mode != .hidden {
            setMode(.hidden)
        }
        window?.resignKey()
    }

    // MARK: - Keyboard (Escape closes)

    private func startKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handleNotchScroll(event) }
            return event
        }
        NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            Task { @MainActor in self?.handleNotchScroll(event) }
        }

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
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
            self.expand(to: view)
        }

        // Hook server compact reveal (non-alert work events: session start, tool use, etc.)
        NotificationCenter.default.addObserver(forName: .hookReveal, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.settingsPreview == .none else { return }
            self.fsm.reveal()
        }

        // Collapse requests from views (OK button, etc.)
        NotificationCenter.default.addObserver(forName: .islandCollapse, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.settingsPreview == .none else { return }
            self.collapse()
        }

        NotificationCenter.default.addObserver(forName: .settingsNotchPreview, object: nil, queue: .main) { [weak self] note in
            let tab = note.object as? String ?? "closed"
            MainActor.assumeIsolated { self?.applySettingsPreview(tab) }
        }

        // .botDizzy — posted by BotEngine.slap() on 3rd hit; show confused view + recover after 3.3s
        NotificationCenter.default.addObserver(forName: .botDizzy, object: nil, queue: .main) { [weak self] _ in
            self?.handleDizzy()
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
                guard self.wasInIsland else { return }
                self.pendingIslandClick = true
                self.hoverTimer?.cancel()
                self.botHoverTimer?.cancel()
                self.botHovering = false
                // Drag only starts when clicking directly on the bot head
                guard self.isBotHit(event.locationInWindow) else { return }
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
                self.hideDragGhost()
                #if !APPSTORE
                if let ctx = self.windowContextAtPoint(mouse) {
                    self.state.promptContext = ctx
                    SoundEngine.shared.play("approve")
                    NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
                    self.expand(to: .prompt)
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
                    finishDrag()
                } else {
                    self.attachDragStart = nil
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
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            finishDrag()
        }

        // Global hotkey to show island
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

    private func windowContextAtPoint(_ screenPoint: NSPoint) -> PromptContext? {
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
    static let settingsNotchPreview = Notification.Name("notchBuddy.settingsNotchPreview")
    static let openFullSettings = Notification.Name("notchBuddy.openFullSettings")
    static let hookReveal       = Notification.Name("notchBuddy.hookReveal")
    // Greeting ↔ IslandWindowController
    static let greetComplete    = Notification.Name("notchBuddy.greetComplete")
    static let greetingHover    = Notification.Name("notchBuddy.greetingHover")
    static let greetingInterrupt = Notification.Name("notchBuddy.greetingInterrupt")
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
        let pull = max(0, AppState.shared.drawerExtension)
        let width: CGFloat
        if view == .nook || view == .tray {
            let prefs = NookPreferences.shared
            let columns = prefs.widgets.filter(\.enabled).map { NookColumnSpec(id: $0.id, cells: $0.cells) }
            width = NookLayout.nookDrawerWidth(
                columns: columns,
                dividers: prefs.widgetDividers,
                contentPadding: CGFloat(prefs.contentPadding)
            )
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
