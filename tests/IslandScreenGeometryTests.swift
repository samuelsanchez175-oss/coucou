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
        print("Island screen geometry and resting layout: 31 cases passed")
    }
}
