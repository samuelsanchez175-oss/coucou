import Foundation

@main
enum IslandMotionTests {
    static func main() {
        testOpenHidesSquishedText()
        testOpenIsSharpOnceTheShapeSettles()
        testCloseDropsContentBeforeTheShapeFinishes()
        testGrowingShapeIsBlurred()
        testSettledShapeIsSharp()
        testIdleTrackShowsArtwork()
        testHoverKeepsTheTitleOffTheClosedNotch()
        testNoTrackKeepsTheFaces()
        testPeekWidthFollowsTheTitle()
        testAWingGrowsOnBothSides()
        testPullDownExtendsTheDrawer()
        testExtendedDrawerWaitsFiveTimesLonger()
        testExtendedDrawerKeepsFiveTimesTheArea()
        testCollapseReturnsToTheNotch()
        testEdgeApproachTicksOnce()
        testOpenTopCornersStayFlush()
        testPullBandStaysShort()
        print("Island motion: 17 cases passed")
    }

    /// Coucou's open frame at 0.1s drew the whole panel as tiny overlapping type.
    /// The shape is still growing then, so the words stay hidden.
    static func testOpenHidesSquishedText() {
        let early = IslandMotion.contentOpacity(opening: true, elapsed: 0.10)
        precondition(early == 0, "text was visible at 0.10s (\(early))")
        let edge = IslandMotion.contentOpacity(opening: true, elapsed: IslandMotion.openHiddenUntil)
        precondition(edge == 0, "text was visible at the hidden edge (\(edge))")
    }

    /// NotchNook was still a soft blob at 0.2s and sharp by about 0.3s.
    static func testOpenIsSharpOnceTheShapeSettles() {
        let mid = IslandMotion.contentOpacity(opening: true, elapsed: 0.25)
        precondition(mid > 0.4 && mid < 0.6, "mid fade was \(mid)")
        let sharp = IslandMotion.contentOpacity(opening: true, elapsed: IslandMotion.openSharpAt)
        precondition(sharp == 1, "content was not sharp at \(IslandMotion.openSharpAt)s (\(sharp))")
        precondition(IslandMotion.contentOpacity(opening: true, elapsed: 1) == 1)
    }

    /// Coucou's close left "Write to Terminal 1" under the menu bar after the
    /// black shape had already shrunk. Content is gone before that frame.
    static func testCloseDropsContentBeforeTheShapeFinishes() {
        precondition(IslandMotion.contentOpacity(opening: false, elapsed: 0) == 1)
        let half = IslandMotion.contentOpacity(opening: false, elapsed: IslandMotion.closeGoneAt / 2)
        precondition(half > 0.4 && half < 0.6, "close fade was \(half)")
        let gone = IslandMotion.contentOpacity(opening: false, elapsed: IslandMotion.closeGoneAt)
        precondition(gone == 0, "content still visible at \(IslandMotion.closeGoneAt)s (\(gone))")
        precondition(IslandMotion.closeGoneAt < 0.2, "close fade outlasts the shape")
    }

    /// The first wide NotchNook frame was three blurred blobs, not readable type.
    static func testGrowingShapeIsBlurred() {
        let blur = IslandMotion.blur(scale: 0.45)
        precondition(blur >= 10, "growing shape was too sharp (\(blur))")
    }

    static func testSettledShapeIsSharp() {
        precondition(IslandMotion.blur(scale: 1) == 0)
        precondition(IslandMotion.blur(scale: 0.95) == 0)
        precondition(IslandMotion.blur(scale: 1.04) == 0, "overshoot should not blur")
    }

    /// A playing track sits in the closed notch as artwork, with no title yet.
    static func testIdleTrackShowsArtwork() {
        let shelf = IslandMotion.shelf(playing: true, pointerOnNotch: false)
        precondition(shelf == .artwork, "idle playing shelf was \(shelf)")
    }

    /// Collapsed mode keeps the artwork and the play button. The video name stays off.
    static func testHoverKeepsTheTitleOffTheClosedNotch() {
        let shelf = IslandMotion.shelf(playing: true, pointerOnNotch: true)
        precondition(shelf == .artwork, "collapsed hover showed the title shelf \(shelf)")
        precondition(shelf != .peek)
    }

    static func testNoTrackKeepsTheFaces() {
        precondition(IslandMotion.shelf(playing: false, pointerOnNotch: false) == .faces)
        precondition(IslandMotion.shelf(playing: false, pointerOnNotch: true) == .faces)
    }

    /// The peek is wider than the hardware notch by enough room for the title,
    /// and a blank title still reserves a short "Music" shelf.
    static func testPeekWidthFollowsTheTitle() {
        let song = IslandMotion.peekExtraWidth(title: "Home / X")
        precondition(song >= 120 && song <= 220, "peek width was \(song)")
        let blank = IslandMotion.peekExtraWidth(title: "   ")
        let music = IslandMotion.peekExtraWidth(title: "Music")
        precondition(blank == music, "blank title width \(blank) did not match Music \(music)")
        let longer = IslandMotion.peekExtraWidth(title: "A much longer song title than the notch")
        precondition(longer >= song && longer <= 220, "long title width was \(longer)")
    }

    /// A wing on one side adds the same width on the other, and the shape stays centered.
    static func testAWingGrowsOnBothSides() {
        precondition(IslandMotion.balancedWidth(side: 140) == 280)
        precondition(IslandMotion.balancedWidth(side: 0) == 0)
        let origin = IslandMotion.centeredOrigin(panelWidth: 720, islandWidth: 412 + 280)
        precondition(origin == 14, "wing shifted to one side (\(origin))")
    }

    /// Pulling the tab down lengthens the drawer. Pushing it up closes the drawer.
    static func testPullDownExtendsTheDrawer() {
        let down = DrawerPull.drag(extensionHeight: 0, translationY: 120, maxExtension: 400)
        precondition(!down.close)
        precondition(down.extensionHeight == 120, "pull down stopped at \(down.extensionHeight)")
        let clamped = DrawerPull.drag(extensionHeight: 0, translationY: 900, maxExtension: 400)
        precondition(clamped.extensionHeight == 400)
        precondition(!clamped.close)
        let up = DrawerPull.drag(extensionHeight: 120, translationY: -30, maxExtension: 400)
        precondition(up.close, "pushing the tab up left the drawer open")
        precondition(up.extensionHeight == 0)
        let twitch = DrawerPull.drag(extensionHeight: 120, translationY: -8, maxExtension: 400)
        precondition(!twitch.close)
        precondition(twitch.extensionHeight == 112)
        precondition(DrawerPull.indicatorWidth == 134)
        precondition(DrawerPull.indicatorHeight == 5)
    }

    /// A positive top radius rounds outward into the menu bar. The open notch stays flush.
    static func testOpenTopCornersStayFlush() {
        precondition(IslandOutline.openTopRadius(requested: 22) == 0, "expanded corners still fan outward")
        precondition(IslandOutline.openTopRadius(requested: 0) == 0)
        precondition(IslandOutline.openTopRadius(requested: -14) == -14, "the closed notch lost its ear")
        precondition(IslandOutline.cardTopRadius <= 4, "the card top still sweeps out (\(IslandOutline.cardTopRadius))")
        precondition(IslandOutline.cardTopRadius < IslandOutline.cardBottomRadius)
        let cards = try! String(contentsOfFile: "NotchBuddy/Sources/App/IslandViewContent.swift", encoding: .utf8)
        precondition(cards.contains("IslandOutline.cardTopRadius"), "the cards still use a round top")
        let shape = try! String(contentsOfFile: "NotchBuddy/Sources/App/IslandRootView.swift", encoding: .utf8)
        precondition(shape.contains("IslandOutline.openTopRadius"), "the housing can still round its top outward")
    }

    /// The white pill sits in a short band under the cards, not a tall empty footer.
    static func testPullBandStaysShort() {
        precondition(DrawerPull.contentClearance == 12, "pull band is still \(DrawerPull.contentClearance)")
        precondition(DrawerPull.tabCenterInset == 6, "pill inset is still \(DrawerPull.tabCenterInset)")
        precondition(DrawerPull.grabHeight == 16, "grab strip is still \(DrawerPull.grabHeight)")
        let gap = DrawerPull.contentClearance - DrawerPull.tabCenterInset - DrawerPull.indicatorHeight / 2
        precondition(gap >= 2 && gap <= 6, "pill gap was \(gap)")
        let root = try! String(contentsOfFile: "NotchBuddy/Sources/App/IslandRootView.swift", encoding: .utf8)
        precondition(root.contains("DrawerPull.contentClearance"), "the page still pads the pull band by hand")
        precondition(root.contains("DrawerPull.tabCenterInset"), "the pill position is still a fixed inset")
        precondition(root.contains("DrawerPull.grabHeight"), "the grab strip is still a tall frame")
    }

    /// A pulled-down drawer waits five times the usual auto-close time.
    static func testExtendedDrawerWaitsFiveTimesLonger() {
        precondition(DrawerPull.autoCloseDelay(base: 15, extended: false) == 15)
        precondition(DrawerPull.autoCloseDelay(base: 15, extended: true) == 75)
        precondition(DrawerPull.autoCloseDelay(base: 10, extended: true) == 50)
        precondition(!DrawerPull.isExtended(0))
        precondition(DrawerPull.isExtended(40))
    }

    /// The pointer can wander a region five times the drawer before closing starts.
    static func testExtendedDrawerKeepsFiveTimesTheArea() {
        let island = CGRect(x: 40, y: 80, width: 640, height: 300)
        let normal = DrawerPull.keepOpenRect(island: island, extended: false)
        precondition(normal.width == island.width + 12)
        precondition(normal.height == island.height + 12)
        let wide = DrawerPull.keepOpenRect(island: island, extended: true)
        let ratio = (wide.width * wide.height) / (island.width * island.height)
        precondition(abs(ratio - 5) < 0.001, "keep-open area was \(ratio) times the drawer")
        precondition(abs(wide.midX - island.midX) < 0.001)
        precondition(abs(wide.maxY - island.maxY) < 0.001, "the top of the drawer moved")
        precondition(wide.minY < island.minY)
    }

    /// Closing drops the pulled drawer back to the notch.
    /// The extra height and the wide keep-open area must not remain.
    static func testCollapseReturnsToTheNotch() {
        let notchW: CGFloat = 251
        let notchH: CGFloat = 32
        let openW: CGFloat = 640
        let openH: CGFloat = 266
        let pulled = DrawerPull.drawnSize(
            open: true,
            notchWidth: notchW,
            notchHeight: notchH,
            openWidth: openW,
            openHeight: openH,
            extensionHeight: 180
        )
        precondition(pulled.width == openW, "a pull widened the drawer to \(pulled.width)")
        precondition(pulled.height == openH + 180, "pull height was \(pulled.height)")
        let closed = DrawerPull.drawnSize(
            open: false,
            notchWidth: notchW,
            notchHeight: notchH,
            openWidth: openW,
            openHeight: openH,
            extensionHeight: 180
        )
        precondition(closed.width == notchW, "collapsed drawer stayed wide at \(closed.width)")
        precondition(closed.height == notchH, "collapsed drawer kept extra height \(closed.height)")
        let hover = DrawerPull.keepOpenRect(
            island: CGRect(x: 0, y: 0, width: openW, height: openH + 180),
            extended: true
        )
        precondition(closed.width < hover.width, "collapsed shape used the keep-open area")
    }

    /// Nearing the notch edge ticks once. Sitting there does not repeat, and the switch can turn it off.
    static func testEdgeApproachTicksOnce() {
        let notch = CGRect(x: 900, y: 1280, width: 251, height: 45)
        let inside = NotchHaptics.distance(from: CGPoint(x: 1024, y: 1300), to: notch)
        precondition(inside == 0, "a point on the notch was \(inside) away")
        let beside = NotchHaptics.distance(from: CGPoint(x: 870, y: 1300), to: notch)
        precondition(abs(beside - 30) < 0.01, "the left edge was \(beside) away")

        let far = NotchHaptics.approach(distance: 80, band: NotchHaptics.approachBand, wasOutside: true, enabled: true)
        precondition(!far.play)
        precondition(far.wasOutside)
        let near = NotchHaptics.approach(distance: 12, band: NotchHaptics.approachBand, wasOutside: true, enabled: true)
        precondition(near.play, "reaching the edge did not tick")
        precondition(!near.wasOutside)
        let stay = NotchHaptics.approach(distance: 4, band: NotchHaptics.approachBand, wasOutside: false, enabled: true)
        precondition(!stay.play, "the tick repeated while the pointer stayed at the edge")
        let off = NotchHaptics.approach(distance: 12, band: NotchHaptics.approachBand, wasOutside: true, enabled: false)
        precondition(!off.play, "the switch did not turn the tick off")
        precondition(!off.wasOutside)
    }
}
