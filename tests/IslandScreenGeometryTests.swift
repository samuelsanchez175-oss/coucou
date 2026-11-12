import Foundation

@main
enum IslandScreenGeometryTests {
    static func main() {
        // Regression: absent auxiliary areas must never mean "screen-wide notch".
        for screenWidth: CGFloat in [1080, 1920, 2560, 3840] {
            let geometry = IslandScreenGeometry(
                screenWidth: screenWidth, safeAreaTop: 0,
                auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 30
            )
            precondition(!geometry.hasNotch)
            precondition(geometry.width == 80)
            precondition(geometry.height == 24)
        }

        // A shorter menu bar must also contain the resting island.
        let shortMenuBar = IslandScreenGeometry(
            screenWidth: 1920, safeAreaTop: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 22
        )
        precondition(shortMenuBar.height == 22)

        // Real MacBook notch measurements retain their physical dimensions.
        let macBook = IslandScreenGeometry(
            screenWidth: 1512, safeAreaTop: 32,
            auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32
        )
        precondition(macBook.hasNotch)
        precondition(macBook.width == 192 && macBook.height == 32)

        // This display's camera inset is 43.5 and the menu bar is 45.
        // The notch has to cover that extra point and a half.
        let menuBarTaller = IslandScreenGeometry(
            screenWidth: 2048, safeAreaTop: 43.5,
            auxiliaryLeftWidth: 898.5, auxiliaryRightWidth: 898.5, menuBarHeight: 45
        )
        precondition(menuBarTaller.hasNotch)
        precondition(menuBarTaller.width == 251)
        precondition(menuBarTaller.height == 45, "notch was \(menuBarTaller.height)")

        // Incomplete or invalid measurements use the notch fallback, not the screen.
        for auxiliaryWidth: CGFloat? in [nil, 0, 1000] {
            let geometry = IslandScreenGeometry(
                screenWidth: 1512, safeAreaTop: 32,
                auxiliaryLeftWidth: auxiliaryWidth, auxiliaryRightWidth: auxiliaryWidth,
                menuBarHeight: 32
            )
            precondition(geometry.width == 184 && geometry.height == 32)
        }
        // Compact/greeting destinations share the measured resting height.
        for height: CGFloat in [22, 24, 32, 38] {
            let compact = IslandRestingLayout(width: 240, height: height)
            precondition(compact.botCenterY == height / 2)
            precondition(compact.botDiameter == min(20, height - 6))
            precondition(compact.botCenterY - compact.botDiameter / 2 >= 3)
            precondition(compact.botCenterY + compact.botDiameter / 2 <= height - 3)
            precondition(compact.miniGridCenterX == 200)
            precondition(compact.miniGridScale * 28 <= height - 4)
        }
        // The camera housing is negative space. Readable Coucou information
        // starts underneath it, on launch and while something is running.
        let housing = NotchClearance(occludedHeight: 32)
        precondition(housing.occludes(y: 16), "the middle of the notch is covered")
        let center = housing.readableCenterY()
        precondition(center > 32, "running information sits below the housing")
        precondition(!housing.occludes(y: center))
        precondition(center - 16 >= 32, "a 32pt strip stays clear of the housing")
        precondition(housing.restingHeight(fallback: 32, showingInformation: true) == 32 + NotchClearance.visibleBand)
        precondition(housing.restingHeight(fallback: 32, showingInformation: false) == 32, "the idle dock stays the housing")
        precondition(housing.earCenterY() == 16, "idle face stays in the notch ears")
        precondition(housing.earCenterY() + 10 <= 32, "the face fits the short dock")
        precondition(housing.expandedOffset == 32)
        precondition(housing.expandedHeight(252) == 284)
        precondition(housing.expandedHeight(150) == 182)

        let openDisplay = NotchClearance(occludedHeight: 0)
        precondition(!openDisplay.occludes(y: 0))
        precondition(!openDisplay.occludes(y: 12))
        precondition(openDisplay.readableCenterY(fallback: 24) == 12)
        precondition(openDisplay.earCenterY(fallback: 24) == 12)
        precondition(openDisplay.restingHeight(fallback: 24, showingInformation: true) == 24)
        precondition(openDisplay.expandedOffset == 0)
        precondition(openDisplay.expandedHeight(252) == 252)

        let mainChin = ActivityChin(
            physicalNotch: true, housingHeight: 32,
            chinHeight: 40, chinWidth: 240, openWidth: 340,
            fontSize: 13, showing: true
        )
        precondition(mainChin.drop == 40, "the main display drops a chin under the camera")
        precondition(mainChin.activityCenterY(fallback: 32) == 52, "the line sits under the housing")
        precondition(mainChin.activityCenterY(fallback: 32) > 32)
        precondition(mainChin.activityCenterY(fallback: 32, drawnHeight: 72) == 52, "a settled chin keeps the line under the camera")
        precondition(mainChin.activityCenterY(fallback: 32, drawnHeight: 52) == 42, "a growing chin carries the line with it")
        precondition(mainChin.activityCenterY(fallback: 32, drawnHeight: 400) == 52, "an open panel parks the line in the chin")
        precondition(mainChin.restingHeight(fallback: 32) == 72)
        precondition(mainChin.widthFloor == 240)
        precondition(ActivityChin.shown(enabled: true, physicalNotch: true, folded: false))
        precondition(!ActivityChin.shown(enabled: false, physicalNotch: true, folded: false), "chin off stays in the bar")
        precondition(!ActivityChin.shown(enabled: true, physicalNotch: true, folded: true), "a folded main chin stays in the bar")
        precondition(ActivityChin.shown(enabled: true, physicalNotch: false, folded: true), "a second display does not fold")
        precondition(!ActivityChin.shown(enabled: false, physicalNotch: false, folded: false), "chin off on a second display stays in the bar")

        let tallFace = ActivityChin(
            physicalNotch: true, housingHeight: 32,
            chinHeight: 28, chinWidth: 140, openWidth: 180,
            fontSize: 30, showing: true
        )
        precondition(tallFace.lineBox == 40, "a larger face grows the line")
        precondition(tallFace.drop == 40)
        precondition(tallFace.restingHeight(fallback: 32) >= 32 + tallFace.lineBox)
        precondition(tallFace.activityWidth == 240)

        let second = ActivityChin(
            physicalNotch: false, housingHeight: 24,
            chinHeight: 40, chinWidth: 240, openWidth: 340,
            fontSize: 13, showing: true
        )
        precondition(second.drop == 0, "a second display does not drop")
        precondition(second.activityCenterY(fallback: 24) == 12, "the line stays in the bar")
        precondition(second.restingHeight(fallback: 24) == ActivityChin.secondDisplayBar, "the second display bar holds the faces")
        precondition(second.widthFloor == second.activityWidth + ActivityChin.secondDisplayGutter * 2, "a second display can be wider")
        let bar: CGFloat = 548
        let face = ActivityChin.plainFaceCenter(width: bar)
        let wave = ActivityChin.plainWaveCenter(width: bar)
        precondition(wave > face, "the waveform stays to the right of the faces")
        precondition(bar - (wave + ActivityChin.shelfSpan / 2) >= ActivityChin.corner, "the waveform clears the corner")
        precondition(face + ActivityChin.faceReach + ActivityChin.clusterGap <= wave - ActivityChin.shelfSpan / 2, "the faces clear the waveform")
        precondition(ActivityChin.secondDisplayGutter >= ActivityChin.faceInset + ActivityChin.faceReach, "the line clears the faces")

        let secondTall = ActivityChin(
            physicalNotch: false, housingHeight: 24,
            chinHeight: 40, chinWidth: 240, openWidth: 180,
            fontSize: 26, showing: true
        )
        precondition(secondTall.drop == 0)
        precondition(secondTall.lineBox == 36)
        precondition(secondTall.restingHeight(fallback: 24) == max(secondTall.lineBox, ActivityChin.secondDisplayBar), "a taller face still fits the bar")
        precondition(secondTall.activityCenterY(fallback: 24) == 18)
        let tallBar = ActivityChin(
            physicalNotch: false, housingHeight: 24,
            chinHeight: 40, chinWidth: 240, openWidth: 340,
            barHeight: 90,
            fontSize: 13, showing: true
        )
        precondition(tallBar.drop == 0, "a taller second-display chin still does not drop")
        precondition(tallBar.restingHeight(fallback: 24) == 90, "the second-display height slider grows the bar")
        let shortBar = ActivityChin(
            physicalNotch: false, housingHeight: 44,
            chinHeight: 40, chinWidth: 240, openWidth: 340,
            barHeight: 22,
            fontSize: 13, showing: true
        )
        precondition(shortBar.restingHeight(fallback: 80) == shortBar.lineBox, "a short second-display chin is not held at the housing")
        precondition(shortBar.restingHeight(fallback: 80) < 48, "the second-display chin can sit under 48")
        precondition(ActivityChin.contentScale(barHeight: 58) == 1, "the default bar keeps full-size marks")
        precondition(ActivityChin.contentScale(barHeight: 120) == 1, "a taller bar does not grow the marks")
        precondition(ActivityChin.contentScale(barHeight: 30) < 1, "a shorter bar shrinks the marks")
        precondition(ActivityChin.contentScale(barHeight: 30) * ActivityChin.faceSpan <= 30 - 8 + 0.01, "the faces fit a 30pt bar")
        precondition(shortBar.contentScale < 1, "a 22pt second-display bar shrinks its marks")
        precondition(shortBar.contentScale * ActivityChin.faceSpan <= shortBar.lineBox, "the faces fit the shortest bar")
        let mainShort = ActivityChin(
            physicalNotch: true, housingHeight: 32,
            chinHeight: 28, chinWidth: 140, openWidth: 180,
            fontSize: 13, showing: true
        )
        precondition(mainShort.contentScale == 1, "the camera ears keep their size")

        let idle = ActivityChin(
            physicalNotch: true, housingHeight: 32,
            chinHeight: 40, chinWidth: 240, openWidth: 340,
            fontSize: 13, showing: false
        )
        precondition(idle.drop == 0)
        precondition(idle.widthFloor == 0)
        precondition(idle.restingHeight(fallback: 32) == 32, "an idle dock stays the housing")

        precondition(CoucouType.clamp(0.74) == 0.8)
        precondition(CoucouType.clamp(1.64) == 1.6)
        precondition(CoucouType.clamp(1.26) == 1.3)
        precondition(CoucouType.points(13, scale: 1) == 13)
        precondition(CoucouType.points(10, scale: 1.5) == 15)
        print("Island screen geometry and resting layout: 31 cases passed")
    }
}
