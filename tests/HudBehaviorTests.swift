import Foundation

@main
enum HudBehaviorTests {
    static func main() {
        testVolumeKeysStepInSixteenths()
        testMuteKeepsTheLevel()
        testBrightnessKeysStayOnBrightness()
        testKeyUpDoesNotChangeAnything()
        testPercentAndSymbol()
        testStripCoversANarrowNotch()
        testBarSitsBesideTheCamera()
        testFillMovesOnAVolumeStep()
        testStripWaitsUntilTheWingClearsTheCamera()
        testTheNotchDrawsTheBarInTheWing()
        print("HUD behavior: 10 cases passed")
    }

    /// The volume keys move one sixteenth. A muted speaker unmutes and keeps its level.
    static func testVolumeKeysStepInSixteenths() {
        var level = HudLevel(volume: 0.5, muted: true, brightness: 0.4)
        let up = HudBehavior.next(level: level, key: .volumeUp)
        precondition(up.kind == .volume, "volume up looked like \(up.kind)")
        precondition(up.level.muted == false, "volume up left the speaker muted")
        precondition(up.level.volume == 0.5625, "volume up landed on \(up.level.volume)")
        precondition(up.level.brightness == 0.4, "volume up changed brightness")

        level = HudLevel(volume: 0, muted: false, brightness: 1)
        let down = HudBehavior.next(level: level, key: .volumeDown)
        precondition(down.level.volume == 0, "volume down below zero became \(down.level.volume)")
        precondition(down.level.muted, "zero volume stayed unmuted")

        let capped = HudBehavior.next(
            level: HudLevel(volume: 1, muted: false, brightness: 0),
            key: .volumeUp
        )
        precondition(capped.level.volume == 1, "volume up past full became \(capped.level.volume)")
    }

    static func testMuteKeepsTheLevel() {
        let muted = HudBehavior.next(
            level: HudLevel(volume: 0.5, muted: false, brightness: 0.2),
            key: .mute
        )
        precondition(muted.level.muted && muted.level.volume == 0.5, "mute changed the saved level")
        precondition(HudBehavior.shownFraction(kind: .volume, level: muted.level) == 0)

        let restored = HudBehavior.next(level: muted.level, key: .mute)
        precondition(restored.level.muted == false && restored.level.volume == 0.5)
        precondition(HudBehavior.shownFraction(kind: .volume, level: restored.level) == 0.5)
    }

    static func testBrightnessKeysStayOnBrightness() {
        let down = HudBehavior.next(
            level: HudLevel(volume: 0.25, muted: true, brightness: 1),
            key: .brightnessDown
        )
        precondition(down.kind == .brightness)
        precondition(down.level.brightness == 0.9375, "brightness down landed on \(down.level.brightness)")
        precondition(down.level.volume == 0.25 && down.level.muted, "brightness key touched the volume")
        precondition(HudBehavior.shownFraction(kind: .brightness, level: down.level) == 0.9375)
    }

    static func testKeyUpDoesNotChangeAnything() {
        precondition(HudBehavior.key(code: 0, keyState: 0x0A) == .volumeUp)
        precondition(HudBehavior.key(code: 1, keyState: 0x0A) == .volumeDown)
        precondition(HudBehavior.key(code: 7, keyState: 0x0A) == .mute)
        precondition(HudBehavior.key(code: 2, keyState: 0x0A) == .brightnessUp)
        precondition(HudBehavior.key(code: 3, keyState: 0x0A) == .brightnessDown)
        precondition(HudBehavior.key(code: 0, keyState: 0x0B) == nil, "key up was treated as a press")
        precondition(HudBehavior.key(code: 16, keyState: 0x0A) == nil, "play key was treated as volume")
    }

    static func testPercentAndSymbol() {
        precondition(HudBehavior.percent(0) == "0%")
        precondition(HudBehavior.percent(1) == "100%")
        precondition(HudBehavior.percent(0.5) == "50%")
        precondition(HudBehavior.symbol(kind: .volume, value: 0.5, muted: true) == "speaker.slash.fill")
        precondition(HudBehavior.symbol(kind: .volume, value: 0.5, muted: false) == "speaker.wave.1.fill")
        precondition(HudBehavior.symbol(kind: .volume, value: 1, muted: false) == "speaker.wave.2.fill")
        precondition(HudBehavior.symbol(kind: .brightness, value: 0.2, muted: false) == "sun.max.fill")
    }

    static func testStripCoversANarrowNotch() {
        precondition(HudBehavior.wingWidth(showing: true) == HudBehavior.wing)
        precondition(HudBehavior.wing > 180, "a narrow notch still hides the bar")
        precondition(HudBehavior.stripHeight == 32)
        precondition(HudBehavior.visibleSeconds == 1.4)
    }

    /// A centered bar on a 251pt notch sits in the camera and never shows.
    /// The bar lives in the menu bar to the right of the camera, and the same width is added on the left.
    /// The production change that fails this: keeping the island at the camera width.
    static func testBarSitsBesideTheCamera() {
        let notch: CGFloat = 251
        let wing = HudBehavior.wingWidth(showing: true)
        precondition(HudBehavior.wingWidth(showing: false) == 0, "a hidden bar still widens the notch")
        precondition(wing >= 160, "the bar has no room beside the camera")
        let island = notch + wing * 2
        let center = HudBehavior.stripCenterX(islandWidth: island, wing: wing)
        let cameraLeading = (island - notch) / 2
        let cameraTrailing = cameraLeading + notch
        let stripLeading = center - wing / 2
        let stripTrailing = center + wing / 2
        precondition(stripLeading >= cameraTrailing - 0.5, "the bar overlaps the camera at \(stripLeading)")
        precondition(stripTrailing <= island + 0.5, "the bar runs off the menu bar")
        precondition(HudBehavior.wing >= HudBehavior.contentWidth, "the icon, name, and percent do not fit the wing")
    }

    /// The fill uses a real track. A muted bar is empty. One volume step moves it enough to see.
    /// The production change that fails this: a track with no width, or a step smaller than a few points.
    static func testFillMovesOnAVolumeStep() {
        precondition(HudBehavior.trackWidth >= 64, "the track is too small to see")
        precondition(HudBehavior.fillWidth(fraction: 0) == 0)
        precondition(HudBehavior.fillWidth(fraction: 1) == HudBehavior.trackWidth)
        precondition(HudBehavior.fillWidth(fraction: 0.5) == HudBehavior.trackWidth / 2)
        precondition(HudBehavior.fillWidth(fraction: -1) == 0)
        precondition(HudBehavior.fillWidth(fraction: 2) == HudBehavior.trackWidth)
        let before = HudBehavior.fillWidth(fraction: 0.5)
        let after = HudBehavior.fillWidth(fraction: 0.5625)
        precondition(after - before >= 4, "a volume step only moved the bar \(after - before) points")
    }

    /// The bar stays hidden while the black shape is still inside the camera, then appears once the wing is open.
    /// Turning the bar off hides it before the shape shrinks, so it cannot ghost back into the notch.
    /// The production change that fails this: drawing the bar at full opacity on the first frame.
    static func testStripWaitsUntilTheWingClearsTheCamera() {
        let resting: CGFloat = 251
        let open: CGFloat = 251 + HudBehavior.wing * 2
        precondition(HudBehavior.stripShown(showing: true, shapeWidth: resting, restingWidth: resting, openWidth: open) == false)
        precondition(HudBehavior.stripShown(showing: true, shapeWidth: resting + (open - resting) * 0.5, restingWidth: resting, openWidth: open) == false)
        precondition(HudBehavior.stripShown(showing: true, shapeWidth: resting + (open - resting) * 0.91, restingWidth: resting, openWidth: open) == false)
        precondition(HudBehavior.stripShown(showing: true, shapeWidth: resting + (open - resting) * 0.92, restingWidth: resting, openWidth: open))
        precondition(HudBehavior.stripShown(showing: true, shapeWidth: open + 8, restingWidth: resting, openWidth: open),
                     "a spring past the wing hid the bar")
        precondition(HudBehavior.stripShown(showing: false, shapeWidth: open, restingWidth: resting, openWidth: open) == false,
                     "the bar stayed up while the wing closed")
        precondition(HudBehavior.stripShown(showing: true, shapeWidth: 640, restingWidth: 640, openWidth: 640),
                     "an open drawer with no extra wing hid the bar")
    }

    /// The closed notch grows the wing and draws the fill on a fixed track, clear of the camera.
    /// The production change that fails this: a centered strip, a GeometryReader track, or a window that stays camera-width.
    static func testTheNotchDrawsTheBarInTheWing() {
        let size = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "func islandSize",
            until: "func notchInformationIsRunning"
        )
        precondition(size.contains("HudBehavior.wingWidth"), "the window stays the camera width while the bar is up")

        let displayed = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "func displayedSize",
            until: "func fitIsland"
        )
        precondition(!displayed.contains("HudBehavior.width"), "the bar collapses the island back onto the camera")

        let hud = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "if hud.visible {",
            until: "DrawerPullTab"
        )
        precondition(hud.contains("stripCenterX"), "the bar is still centered on the camera")
        precondition(hud.contains("stripShown"), "the bar draws before the wing clears the camera")
        precondition(hud.contains("collapsedAnchorY"), "the closed bar leaves the menu bar")
        precondition(hud.contains("fillWidth") || hud.contains("HudStrip"), "the notch does not draw the bar")

        let strip = sourceSlice(
            file: "NotchBuddy/Sources/App/HudController.swift",
            from: "struct HudStrip",
            until: "foregroundStyle"
        )
        precondition(strip.contains("HudBehavior.fillWidth"), "the fill does not use the track width")
        precondition(strip.contains("HudBehavior.trackWidth"), "the track has no fixed width")
        precondition(strip.contains("HudBehavior.titleWidth"), "the name width changes and the bar jumps")
        precondition(!strip.contains("GeometryReader"), "the track collapses and the fill never shows")
        precondition(strip.contains("value: fraction"), "the fill does not animate when the level changes")
    }

    static func sourceSlice(file: String, from start: String, until end: String) -> String {
        let text = try! String(contentsOfFile: file, encoding: .utf8)
        guard let from = text.range(of: start), let to = text.range(of: end, range: from.upperBound..<text.endIndex) else {
            preconditionFailure("missing \(start) in \(file)")
        }
        return String(text[from.lowerBound..<to.lowerBound])
    }
}
