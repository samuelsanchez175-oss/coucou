import AppKit
import SwiftUI

/// Top-level SwiftUI view rendered inside the transparent panel.
/// The island is drawn at the top-center; everything else is transparent and click-through.
/// Note: drag-drop is handled at the AppKit level in IslandWindowController (FileDropNSView),
/// not in SwiftUI, to avoid interfering with SwiftUI hit-testing.
struct IslandRootView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var board = NookBoard.shared

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            IslandContainer(state: state)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .ignoresSafeArea()
        .onAppear {
            board.start()
            TerminalDesk.shared.start()
        }
    }
}

// MARK: - Island container

struct IslandContainer: View {
    @ObservedObject var state: AppState
    @ObservedObject private var prefs = NookPreferences.shared
    @ObservedObject private var board = NookBoard.shared
    @ObservedObject private var hud = HudController.shared
    @State private var islandWidth:  CGFloat = IslandConst.notchWidth
    @State private var islandHeight: CGFloat = IslandConst.notchHeight
    @State private var cornerRadius: CGFloat = IslandConst.roundedCorner
    // topRadius > 0 → convex expanded corners; < 0 → concave ear cutouts
    @State private var islandTopRadius: CGFloat = 0
    @State private var greetNotif: Bool = false
    /// Expanded words stay mounted through the short close fade, then drop.
    @State private var holdContent = false
    @State private var contentShown: Double = 0
    @State private var heldView: IslandView = .overview
    @State private var motionToken = 0

    private let openSpring = Animation.spring(response: 0.5, dampingFraction: 0.72)
    private let closeEase  = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.34)

    private var chatPromptHeight: CGFloat {
        let base: CGFloat = 240
        let perMsg: CGFloat = 40
        return min(300, base + CGFloat(state.chatHistory.count) * perMsg)
    }

    /// Pixels the content must be pushed down to clear the concave ear transparent area.
    /// = 0 in expanded mode (no ears), = earRadius in compact/notch mode.
    private var earOffset: CGFloat { max(0, -islandTopRadius) }

    var body: some View {
        // Canvas active during drag-over (.upload), post-drop animation (.uploading),
        // AND choose overlay (.choose) — canvas handles the full sequence through user action.
        // Engine deactivates when user clicks a canvas choose button or navigates away.
        let uploadActive = state.mode == .expanded
            && UploadSequenceEngine.shared.isActive
            && (state.view == .upload || state.view == .uploading || state.view == .choose)

        let greetingActive = state.mode == .expanded && state.view == .greeting
        let nookActive = state.mode == .expanded && (state.view == .nook || state.view == .tray)
        let clearance = NotchClearance(occludedHeight: state.hasNotch ? state.notchHeight : 0)
        let earY = clearance.earCenterY(fallback: islandHeight)
        let dropY = clearance.readableCenterY(fallback: islandHeight)
        let showMedia = NookPlayback.showsOnClosedNotch(
            bundleID: board.mediaBundleID,
            displayName: board.mediaDisplayName,
            title: board.mediaTitle,
            playing: board.mediaIsPlaying
        )
        let earHeight = clearance.expandedOffset > 0 ? clearance.expandedOffset : islandHeight

        return ZStack(alignment: .topLeading) {
            // Black island shape. The open notch covers the menu bar, and the buttons sit on that black.
            IslandShape(width: islandWidth, height: islandHeight,
                        cornerRadius: cornerRadius, topRadius: islandTopRadius)
                .fill(prefs.translucentNotch ? Color.black.opacity(0.62) : Color.black)

            // Content is laid out at the settled size, then scaled into the
            // growing shape. Opacity and blur follow IslandMotion so the open
            // does not show squished type and the close does not leave a ghost.
            if state.mode == .expanded || holdContent {
                let drawnView = state.mode == .expanded ? state.view : heldView
                let target = displayedSize(mode: .expanded, view: drawnView)
                let scale = contentScale(target: target)
                let contentHeight = max(0, target.1 - clearance.expandedOffset)
                let drawGreeting = drawnView == .greeting && !uploadActive
                Group {
                    if drawGreeting {
                        GreetingCanvasView(state: state)
                            .frame(width: IslandConst.expandedWidth, height: 150)
                            .offset(x: (target.0 - IslandConst.expandedWidth) / 2)
                    } else if uploadActive {
                        ZStack(alignment: .topLeading) {
                            UploadCanvasView(state: state)
                                .frame(width: target.0, height: contentHeight)
                            if clearance.expandedOffset == 0 {
                                IslandHeader(state: state)
                                    .frame(width: target.0, height: 34)
                                    .offset(y: 8)
                            }
                        }
                    } else {
                        IslandContentView(state: state)
                            .frame(width: target.0, height: max(0, contentHeight - earOffset))
                            .offset(y: earOffset)
                    }
                }
                .offset(y: clearance.expandedOffset)
                .scaleEffect(scale, anchor: .top)
                .frame(width: islandWidth, height: islandHeight, alignment: .top)
                .blur(radius: IslandMotion.blur(scale: scale))
                .opacity(contentShown)
                .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                      cornerRadius: cornerRadius, topRadius: islandTopRadius))
                .allowsHitTesting(state.mode == .expanded && contentShown > 0.9)

                if clearance.expandedOffset > 0 && drawnView != .greeting {
                    let wings = TerminalBehavior.menuBarWings(islandWidth: target.0, notchWidth: state.notchWidth)
                    IslandHeader(
                        state: state,
                        notchLeading: wings.notchLeading,
                        notchTrailing: wings.notchTrailing,
                        bandWidth: target.0
                    )
                    .frame(width: target.0, height: clearance.expandedOffset)
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: islandWidth, height: clearance.expandedOffset, alignment: .center)
                    .opacity(drawnView == .confused ? 0 : contentShown)
                    .allowsHitTesting(state.mode == .expanded && contentShown > 0.9 && drawnView != .confused)
                }
            }

            // Single BotPlacement — always alive in the view tree so spring animations
            // fire from the current position (e.g. choose at 60,101) when canvas deactivates.
            // Hidden during upload canvas or greeting (both draw their own Mochi).
            BotPlacement(state: state, islandW: islandWidth, islandH: islandHeight,
                         sideWing: state.mode == .expanded ? 0 : board.restingExtra)
                // Keep idle animations inside the resting strip. Expanded views
                // retain the panel's full height for particles and hands.
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: islandWidth,
                                      height: state.mode == .expanded ? IslandConst.panelHeight : islandHeight)
                }
                .opacity(uploadActive || greetingActive || nookActive ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: uploadActive || greetingActive || nookActive)

            CountdownBar(state: state, islandW: islandWidth)

            if state.mode != .expanded, !hud.visible {
                let kind = IslandMotion.shelf(playing: showMedia, pointerOnNotch: board.pointerOnNotch)
                if kind != .faces {
                    NotchMediaShelf(
                        board: board,
                        islandWidth: islandWidth,
                        contentCenterY: earY
                    )
                    .frame(width: islandWidth, height: islandHeight)
                }
            }

            if state.mode != .expanded, !hud.visible, let edge = edgeHeadline {
                if edge.id == "tray", board.trayWing > 0 {
                    LiveActivityPill(headline: edge)
                        .frame(maxWidth: max(24, board.trayWing - 8))
                        .position(
                            x: NookLayout.trayPillCenterX(side: board.trayWing),
                            y: NookLayout.collapsedAnchorY(housingCenter: earY)
                        )
                } else if edge.id == "media", state.hasNotch {
                    let placed = NookPlayback.mediaTitlePlacement(
                        islandWidth: islandWidth,
                        notchWidth: state.notchWidth
                    )
                    if placed.maxWidth > 0 {
                        LiveActivityPill(headline: edge)
                            .frame(width: placed.maxWidth, alignment: .leading)
                            .clipped()
                            .position(
                                x: placed.centerX,
                                y: NookLayout.collapsedAnchorY(housingCenter: earY)
                            )
                    }
                } else if edge.id != "tray" {
                    let inNotch = board.restingExtra <= 0
                    LiveActivityPill(headline: edge)
                        .frame(maxWidth: inNotch ? max(40, islandWidth - 28) : max(80, board.restingExtra - 16))
                        .position(
                            x: inNotch ? islandWidth / 2 : islandWidth - board.restingExtra / 2,
                            y: NookLayout.collapsedAnchorY(housingCenter: earY)
                        )
                }
            }

            if hud.visible {
                let hudWing: CGFloat = state.mode == .expanded ? 0 : HudBehavior.wing
                let openWidth = displayedSize(mode: state.mode, view: state.view).0
                let restingWidth = openWidth - IslandMotion.balancedWidth(side: hudWing)
                let showStrip = HudBehavior.stripShown(
                    showing: true,
                    shapeWidth: islandWidth,
                    restingWidth: restingWidth,
                    openWidth: openWidth
                )
                if showStrip {
                    HudStrip(title: hud.title, symbol: hud.symbol, percent: hud.percent, fraction: hud.fraction)
                        .frame(width: HudBehavior.wing, height: 28)
                        .position(
                            x: state.mode == .expanded
                                ? islandWidth / 2
                                : HudBehavior.stripCenterX(islandWidth: islandWidth, wing: HudBehavior.wing),
                            y: state.mode == .expanded
                                ? (clearance.expandedOffset > 0 ? dropY : 22)
                                : NookLayout.collapsedAnchorY(housingCenter: earY)
                        )
                }
            }

            if state.mode != .expanded {
                let blobs = TerminalBehavior.collapsedBlobCenters(
                    islandWidth: islandWidth,
                    notchWidth: state.notchWidth
                )
                CompactTerminalFaces()
                    .scaleEffect(IslandRestingLayout(width: islandWidth, height: earHeight).miniGridScale)
                    .position(x: blobs.facesX, y: earY)
                    .transition(.opacity)
            }

            if state.mode == .expanded {
                DrawerPullTab(state: state, restingHeight: max(1, islandHeight - state.drawerExtension)) {
                    NotificationCenter.default.post(name: .islandCollapse, object: nil)
                }
                .position(x: islandWidth / 2, y: max(DrawerPull.tabCenterInset, islandHeight - DrawerPull.tabCenterInset))
            }
        }
        .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)
        .coordinateSpace(name: "coucouDrawer")
        .onChange(of: state.mode) { oldMode, newMode in
            if newMode == .expanded {
                TerminalDesk.shared.applyExpandSelection()
                heldView = state.view
            }
            let shrinking = modeOrder(newMode) < modeOrder(oldMode)
            let anim = shrinking ? closeEase : openSpring
            let (w, h) = displayedSize(mode: newMode, view: state.view)
            let cr  = newMode == .expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner
            let tr: CGFloat = 0
            withAnimation(anim) {
                islandWidth      = w
                islandHeight     = h
                cornerRadius     = cr
                islandTopRadius  = tr
            }
            animateContentReveal(opening: newMode == .expanded, closing: oldMode == .expanded && newMode != .expanded)
        }
        .onChange(of: state.view) { _, newView in
            if state.mode == .expanded { heldView = newView }
            guard state.mode == .expanded else { return }
            // Deactivate engine if user navigates outside the upload flow
            let uploadViews: Set<IslandView> = [.upload, .uploading, .choose]
            if UploadSequenceEngine.shared.isActive && !uploadViews.contains(newView) {
                UploadSequenceEngine.shared.deactivate()
            }
            let (w, h) = displayedSize(mode: .expanded, view: newView)
            withAnimation(openSpring) {
                islandWidth  = w
                islandHeight = h
            }
        }
        .onChange(of: state.chatHistory.count) { _, _ in
            guard state.mode == .expanded, state.view == .prompt else { return }
            withAnimation(openSpring) { islandHeight = chatPromptHeight }
        }
        .onAppear {
            let (w, h) = displayedSize(mode: state.mode, view: state.view)
            islandWidth      = w
            islandHeight     = h
            cornerRadius     = state.mode == .expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner
            islandTopRadius  = 0
            heldView = state.view
            if state.mode == .expanded {
                holdContent = true
                contentShown = 1
            }
            HudController.shared.start()
        }
        .onChange(of: hud.visible) { _, _ in fitIsland() }
        .onChange(of: board.restingExtra) { _, _ in fitIsland() }
        .onChange(of: board.mediaTitle) { _, _ in fitIsland() }
        .onChange(of: board.playingSource) { _, _ in fitIsland() }
        .onChange(of: board.mediaIsPlaying) { _, _ in fitIsland() }
        .onChange(of: board.mediaWing) { _, _ in fitIsland() }
        .onChange(of: board.trayWing) { _, _ in fitIsland() }
        .onChange(of: state.notchWidth) { _, _ in fitIsland() }
        .onChange(of: state.notchHeight) { _, _ in fitIsland() }
        .onChange(of: prefs.widgets) { _, _ in fitIsland() }
        .onChange(of: prefs.widgetDividers) { _, _ in fitIsland() }
        .onChange(of: prefs.contentPadding) { _, _ in fitIsland() }
        .onChange(of: state.drawerExtension) { _, extensionHeight in
            // A pull changes height only. Writing the open width here fought
            // the close and left a wide bar after the drawer had folded.
            guard state.mode == .expanded else { return }
            let (openWidth, fullHeight) = displayedSize(mode: .expanded, view: state.view)
            let openHeight = fullHeight - max(0, extensionHeight)
            let frame = DrawerPull.drawnSize(
                open: true,
                notchWidth: state.notchWidth,
                notchHeight: state.notchHeight,
                openWidth: openWidth,
                openHeight: openHeight,
                extensionHeight: extensionHeight
            )
            if state.drawerPulling {
                var snap = Transaction()
                snap.disablesAnimations = true
                withTransaction(snap) { islandHeight = frame.height }
            } else {
                withAnimation(openSpring) { islandHeight = frame.height }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in
            greetNotif.toggle()
        }
    }

    /// Scale of the settled panel inside the shape that is on screen right now.
    private func contentScale(target: (CGFloat, CGFloat)) -> Double {
        let widthRatio = target.0 > 1 ? islandWidth / target.0 : 1
        let heightRatio = target.1 > 1 ? islandHeight / target.1 : 1
        return min(1.0, Double(widthRatio), Double(heightRatio))
    }

    private func animateContentReveal(opening: Bool, closing: Bool) {
        guard opening || closing else { return }
        motionToken += 1
        let token = motionToken
        if opening {
            holdContent = true
            var snap = Transaction()
            snap.disablesAnimations = true
            withTransaction(snap) { contentShown = 0 }
            let fade = IslandMotion.openSharpAt - IslandMotion.openHiddenUntil
            withAnimation(.linear(duration: fade).delay(IslandMotion.openHiddenUntil)) {
                contentShown = 1
            }
            return
        }
        withAnimation(.linear(duration: IslandMotion.closeGoneAt)) {
            contentShown = 0
        }
        Task { @MainActor in
            let nanos = UInt64((IslandMotion.closeGoneAt + 0.02) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard token == motionToken, state.mode != .expanded else { return }
            holdContent = false
        }
    }

    private func modeOrder(_ m: IslandMode) -> Int {
        switch m { case .hidden: return 0; case .compact: return 1; case .expanded: return 2 }
    }

    private var edgeHeadline: NookHeadline? {
        if board.dropWing {
            return NookHeadline(id: "drop", text: "AirDrop", symbol: "square.and.arrow.up")
        }
        return board.headline
    }

    private func displayedSize(mode: IslandMode, view: IslandView) -> (CGFloat, CGFloat) {
        let (w, h) = islandSize(mode: mode, view: view,
                                progress: state.uploadProgress,
                                nw: state.notchWidth, nh: state.notchHeight,
                                hasNotch: state.hasNotch)
        if mode == .expanded && view == .prompt {
            let occluded = state.hasNotch ? state.notchHeight : 0
            let h = TerminalBehavior.expandedDrawerHeight(
                layoutHeight: chatPromptHeight,
                occludedHeight: occluded,
                headerInMenuBar: state.hasNotch
            )
            return (w, h + max(0, state.drawerExtension))
        }
        return (w, h)
    }

    private func fitIsland() {
        let (w, h) = displayedSize(mode: state.mode, view: state.view)
        let anim: Animation = hud.visible
            ? .spring(response: 0.28, dampingFraction: 0.82)
            : openSpring
        withAnimation(anim) {
            islandWidth = w
            islandHeight = h
        }
    }
}

// MARK: - Island shape
//
// topRadius > 0 is ignored. An open notch meets the screen with a square top.
// topRadius < 0  → concave ear cutouts, |topRadius| = ear radius (compact/notch mode)
// topRadius = 0  → sharp top corners

struct IslandShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat   // bottom corners
    var topRadius: CGFloat      // see above

    var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>, CGFloat> {
        get { .init(.init(.init(width, height), cornerRadius), topRadius) }
        set {
            width        = newValue.first.first.first
            height       = newValue.first.first.second
            cornerRadius = newValue.first.second
            topRadius    = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let cr = max(0, cornerRadius)
        let top = IslandOutline.openTopRadius(requested: topRadius)
        var p  = Path()

        if top >= 0 {
            // Square top. A convex arc here fans out into the menu bar.
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: width, y: 0))
            p.addLine(to: CGPoint(x: width, y: height - cr))
            // Bottom-right corner
            p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            // Bottom edge
            p.addLine(to: CGPoint(x: cr, y: height))
            // Bottom-left corner
            p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            // Left edge
            p.addLine(to: CGPoint(x: 0, y: 0))
        } else {
            // ── Concave ear cutouts (compact / notch) ─────────────────────────
            let er = -top   // positive ear radius
            p.move(to: CGPoint(x: 0, y: 0))
            // Top-left ear
            p.addArc(center: CGPoint(x: 0, y: er), radius: er,
                     startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            // Top edge
            p.addLine(to: CGPoint(x: width - er, y: er))
            // Top-right ear
            p.addArc(center: CGPoint(x: width, y: er), radius: er,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            // Right edge
            p.addLine(to: CGPoint(x: width, y: height - cr))
            // Bottom-right corner
            p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            // Bottom edge
            p.addLine(to: CGPoint(x: cr, y: height))
            // Bottom-left corner
            p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            // Left edge back to top-left corner
            p.addLine(to: CGPoint(x: 0, y: 0))
        }

        p.closeSubpath()
        return p
    }
}

// MARK: - Bot placement helper

struct BotPlacement: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    let islandH: CGFloat
    var sideWing: CGFloat = 0

    var body: some View {
        let (cx, cy, diameter, opacity) = botPosition(
            mode: state.mode, view: state.view, islandW: islandW, islandH: islandH,
            uploadProgress: state.uploadProgress, hasNotch: state.hasNotch,
            occludedHeight: state.hasNotch ? state.notchHeight : 0,
            sideWing: sideWing, notchWidth: state.notchWidth)
        let canvasSize = diameter / 0.6
        let overhang: CGFloat = 40
        let isUploading = state.view == .uploading

        Group {
            // No glow in uploading mode — the tiny dot doesn't need it
            if state.mode == .expanded && !isUploading {
                Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: botGlowColor(state.effectiveState), location: 0),
                            .init(color: .clear, location: 0.62)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 1.1
                    ))
                    .frame(width: diameter * 2.2, height: diameter * 2.2)
                    .blur(radius: 6)
                    .opacity(botGlowOpacity(state.effectiveState))
                    .position(x: cx, y: cy)
                    .animation(.easeInOut(duration: 0.4), value: state.effectiveState)
            }

            // Uploading: no particle overhang (no hearts during upload), positioned directly at cy.
            // BotEngine cy = H/2 + 0 + oy*R + R*0.06 ≈ H/2 (body centered in canvas).
            // With .position(x:y:) placing the frame center at (uploadCx, cy), bot is at cy ✓.
            //
            // Normal: extra 40pt canvas at top for heart particles; position offset up by 20pt;
            // BotEngine compensates with cy = H/2 + particleOverhang/2 + oy*R + R*0.06.
            if isUploading {
                TimelineView(.animation) { tl in
                    let elapsed: Double = {
                        guard let start = state.uploadStartTime else { return 0 }
                        return tl.date.timeIntervalSince(start)
                    }()
                    let t = min(1.0, max(0, elapsed / state.uploadDuration))
                    // cx = 36 + 526*t: bot center at fill right edge (bar left=36, width=526)
                    let uploadCx = 36 + CGFloat(t * (2 - t)) * 526
                    BotCanvasView(state: state, particleOverhang: 0)
                        .frame(width: canvasSize, height: canvasSize)
                        .opacity(state.isDraggingBot ? 0 : opacity)
                        .position(x: uploadCx, y: cy)
                }
                .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
            } else {
                BotCanvasView(state: state, particleOverhang: overhang)
                    .frame(width: canvasSize, height: canvasSize + overhang)
                    .opacity(state.isDraggingBot ? 0 : opacity)
                    .position(x: cx, y: cy - overhang / 2)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: cx)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: cy)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: canvasSize)
                    .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
            }
        }
        // Branch switch (uploading ↔ normal) animates with a fast spring: uploading dot
        // scales out at bar-end while normal bot scales in at choose position.
        .animation(.spring(response: 0.36, dampingFraction: 0.72), value: isUploading)
        // Slap, drag, and hover are handled by the AppKit NSEvent monitor in
        // IslandWindowController — not SwiftUI gestures — so this is safe.
        .allowsHitTesting(false)
    }

    private func botGlowColor(_ s: BotState) -> Color {
        switch s {
        case .working:   return Color(hex: "#3B9EFF")
        case .thinking:  return Color(hex: "#A78BFA")
        case .searching: return Color(hex: "#6366F1")
        case .approval:  return Color(hex: "#F5A524")
        case .error:     return Color(hex: "#F4505E")
        case .finished:  return Color(hex: "#34D399")
        case .ratelimit: return Color(hex: "#F59E0B")
        default:         return Color.white
        }
    }

    private func botGlowOpacity(_ s: BotState) -> Double {
        switch s {
        case .idle, .sleeping: return 0.15
        case .dizzy:           return 0.0
        default:               return 0.65
        }
    }
}

func botPosition(mode: IslandMode, view: IslandView, islandW: CGFloat, islandH: CGFloat, uploadProgress: Double, hasNotch: Bool = true, occludedHeight: CGFloat = 0, sideWing: CGFloat = 0, notchWidth: CGFloat = 0) -> (CGFloat, CGFloat, CGFloat, Double) {
    let housing = (hasNotch && occludedHeight > 0) ? min(occludedHeight, islandH) : 0
    let contentH = islandH - housing
    let wing = max(0, sideWing)
    switch mode {
    case .hidden, .compact:
        let clearance = NotchClearance(occludedHeight: housing)
        let earH = housing > 0 ? housing : islandH
        let ear = IslandRestingLayout(width: islandW, height: earH)
        let y = clearance.earCenterY(fallback: islandH)
        let notch = notchWidth > 0 ? notchWidth : (hasNotch ? min(islandW, IslandScreenGeometry.fallbackNotchWidth) : 0)
        if notch > 0, notch < islandW {
            let blobs = TerminalBehavior.collapsedBlobCenters(islandWidth: islandW, notchWidth: notch)
            return (blobs.whiteX, y, ear.botDiameter, 1)
        }
        return (hasNotch ? 40 + wing : islandW / 2, y, ear.botDiameter, 1)
    case .expanded:
        let layout = IslandConst.viewLayouts[view]!
        let diameter = layout.botDiameter
        // Uploading: Mochi dot rides the leading edge of the progress fill.
        // Bar in island coords: left=36, width=526. cx = 36 + progress*526 (dot center at fill right edge).
        // cy comes from ViewLayout.botY (bar center in content coords), then drops below the housing.
        if view == .uploading {
            let cx = 36 + CGFloat(uploadProgress) * 526
            return (cx, (layout.botY ?? 103) + housing, diameter, 1)
        }
        let cx = layout.botX
        let headerInMenuBar = housing > 0 && view != .greeting
        let cy: CGFloat
        if let fixedY = layout.botY {
            cy = TerminalBehavior.blobCenterY(layoutY: fixedY, headerInMenuBar: headerInMenuBar)
        } else {
            // Center of the fixed 84pt card. The header row is gone once it lives in the menu bar.
            let headerBottom: CGFloat = headerInMenuBar ? 0 : 42
            let cardH: CGFloat = 84
            cy = headerBottom + (contentH - headerBottom - cardH) / 2 + cardH / 2
        }
        return (cx, cy + housing, diameter, 1)
    }
}

// MARK: - Pull tab

/// White pill at the bottom of the open drawer. Pull down to lengthen it. Pull up to close it.
private struct DrawerPullTab: View {
    @ObservedObject var state: AppState
    var restingHeight: CGFloat
    var onClose: () -> Void
    @State private var startExtension: CGFloat?

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.white)
                .frame(width: DrawerPull.indicatorWidth, height: DrawerPull.indicatorHeight)
        }
        .frame(width: max(DrawerPull.indicatorWidth + 24, 180), height: DrawerPull.grabHeight)
        .contentShape(.interaction, Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("coucouDrawer"))
                .onChanged { value in
                    guard state.mode == .expanded else { return }
                    if startExtension == nil { startExtension = state.drawerExtension }
                    state.drawerPulling = true
                    let result = DrawerPull.drag(
                        extensionHeight: startExtension ?? 0,
                        translationY: value.translation.height,
                        maxExtension: pullLimit()
                    )
                    if result.close {
                        finishClose()
                    } else {
                        state.drawerExtension = result.extensionHeight
                    }
                }
                .onEnded { value in
                    let result = DrawerPull.drag(
                        extensionHeight: startExtension ?? state.drawerExtension,
                        translationY: value.translation.height,
                        maxExtension: pullLimit()
                    )
                    startExtension = nil
                    state.drawerPulling = false
                    guard state.mode == .expanded else { return }
                    if result.close {
                        finishClose()
                    } else {
                        state.drawerExtension = result.extensionHeight
                    }
                }
        )
        .accessibilityLabel(DrawerPull.isExtended(state.drawerExtension) ? "Pull up to close" : "Pull down to extend")
        .help(DrawerPull.isExtended(state.drawerExtension)
              ? "Pull up to close the drawer."
              : "Pull down to make the drawer taller. It then waits five times longer, across a wider area, before it closes. Pull up to close it.")
    }

    private func pullLimit() -> CGFloat {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        let height = screen?.frame.height ?? 900
        return DrawerPull.maxExtension(screenHeight: height, restingDrawerHeight: restingHeight)
    }

    private func finishClose() {
        startExtension = nil
        // The close animation clears the pull. Zeroing it first sprang the
        // drawer down to a short wide bar before the notch shrink started.
        onClose()
    }
}

// MARK: - Countdown bar

struct CountdownBar: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    @State private var barWidth: CGFloat = 0
    @State private var timer: Timer? = nil

    var body: some View {
        GeometryReader { _ in
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: barWidth, height: 2)
                .cornerRadius(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateBar()
        }
    }

    private func updateBar() {
        guard state.mode == .expanded && !state.isPinned else {
            barWidth = 0
            return
        }
        let autoClose = state.autoCloseInterval
        let window = min(10.0, autoClose * 0.6)
        let elapsed = Date.now.timeIntervalSince(state.lastActivity)
        let remaining = autoClose - elapsed
        if remaining < window {
            barWidth = max(0, CGFloat(remaining / window) * 160)
        } else {
            barWidth = 0
        }
    }
}

// MARK: - Island content (header + views, only in expanded mode)

struct IslandContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        let headerInMenuBar = state.hasNotch && state.notchHeight > 0
        return VStack(spacing: 0) {
            if state.view.showsSharedHeader && !headerInMenuBar {
                IslandHeader(state: state)
                    .frame(height: 34)
                    .opacity(state.view == .confused ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: state.view == .confused)
            }

            // The nook is wider than the home page. Laying every page out at
            // that width centered the home tiles and clipped them on both sides.
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(IslandView.allCases, id: \.self) { v in
                        let active = state.view == v
                        // Views that fill available height instead of the fixed 98pt content frame:
                        // chat (prompt) is always flexible; mail is flexible only when active so
                        // it doesn't push the stack taller when inactive.
                        let isTall = v == .prompt || v == .nook || v == .tray || v == .overview || (v == .mail && active)
                        let anim: Animation = active
                            ? .spring(response: 0.4, dampingFraction: 0.8).delay(0.16)
                            : .easeIn(duration: 0.16)
                        IslandViewContent(view: v, state: state)
                            .frame(width: geo.size.width, height: isTall ? geo.size.height : 98, alignment: .topLeading)
                            .clipped()
                            .opacity(active ? 1 : 0)
                            .scaleEffect(active ? 1 : 0.97)
                            .allowsHitTesting(active)
                            .animation(anim, value: state.view)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, TerminalBehavior.overviewPageInset)
        }
        .padding(.top, headerInMenuBar ? 0 : 8)
        .padding(.bottom, DrawerPull.contentClearance)
        .foregroundColor(Color(hex: "#F5F6F8"))
    }
}

// MARK: - Island header (tabs + icons)

struct IslandHeader: View {
    @ObservedObject var state: AppState
    /// Set when the row lives in the menu bar, beside the hardware notch.
    var notchLeading: CGFloat? = nil
    var notchTrailing: CGFloat? = nil
    var bandWidth: CGFloat? = nil

    var body: some View {
        if let leading = notchLeading, let trailing = notchTrailing, let width = bandWidth,
           width > 0, trailing >= leading {
            HStack(spacing: 0) {
                tabs
                    .padding(.trailing, 8)
                    .frame(width: leading, alignment: .trailing)
                Color.clear
                    .frame(width: trailing - leading)
                    .accessibilityHidden(true)
                actions
                    .padding(.leading, 8)
                    .frame(width: max(0, width - trailing), alignment: .leading)
            }
            .frame(width: width, height: nil, alignment: .center)
            .frame(maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                tabs
                    .padding(.leading, 14)
                Spacer()
                actions
                    .padding(.trailing, 16)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var tabs: some View {
        HStack(spacing: 5) {
            TabButton(icon: "house.fill", view: .overview, state: state)
            TabButton(icon: "lamp.desk.fill", view: .nook, state: state)
                .help("Nook")
                .accessibilityLabel("Nook")
            TabButton(icon: "tray.fill", view: .tray, state: state)
                .help("Tray")
                .accessibilityLabel("Tray")
                .accessibilityHint("Opens the tray. Drop a file to keep it, or drag it onto AirDrop.")
            TabButton(icon: "bubble.left.fill", view: .prompt, state: state, preAction: {
                #if !APPSTORE
                if state.promptContext == nil {
                    state.promptContext = WindowContextCapture.captureActive(from: state.lastExternalApp)
                }
                #endif
            })
            TabButton(icon: "plus", view: .upload, state: state)
        }
    }

    private var actions: some View {
        HStack(spacing: 14) {
            Button(action: {
                if LiveActivityBehavior.settingsDestination() == .fullWindow {
                    NotificationCenter.default.post(name: .openFullSettings, object: nil)
                }
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")

            Button(action: { state.soundEnabled.toggle() }) {
                Image(systemName: state.soundEnabled ? "speaker.wave.2" : "speaker.slash")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .buttonStyle(.plain)
            .help("Volume")
            .accessibilityLabel("Volume")
        }
    }
}

struct TabButton: View {
    let icon: String
    let view: IslandView
    @ObservedObject var state: AppState
    var preAction: (() -> Void)? = nil
    @State private var isHovered = false

    private var isOn: Bool {
        if view == .overview { return state.view == .overview || state.view == .empty }
        return state.view == view
    }

    var body: some View {
        Button(action: {
            preAction?()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state.view = view
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(isOn ? Color(hex: "#F5F6F8") : (isHovered ? Color(hex: "#B0B5BE") : Color(hex: "#8E939C")))
                .frame(width: 30, height: 22)
                .background(
                    isOn ? Color(hex: "#1D1F23") :
                    isHovered ? Color.white.opacity(0.07) : Color.clear
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Color helper

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let val = UInt64(h, radix: 16) ?? 0
        let r = Double((val >> 16) & 0xFF) / 255
        let g = Double((val >> 8)  & 0xFF) / 255
        let b = Double( val        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
