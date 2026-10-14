import Foundation

/// Resting island dimensions, using a physical notch only when the screen has one.
struct IslandScreenGeometry {
    static let fallbackNotchWidth: CGFloat = 184
    private static let noNotchWidth: CGFloat = 80
    private static let noNotchHeight: CGFloat = 24

    let hasNotch: Bool
    let width: CGFloat
    let height: CGFloat

    init(screenWidth: CGFloat, safeAreaTop: CGFloat,
         auxiliaryLeftWidth: CGFloat?, auxiliaryRightWidth: CGFloat?,
         menuBarHeight: CGFloat) {
        hasNotch = safeAreaTop > 0
        if hasNotch {
            if let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth {
                let measuredWidth = screenWidth - left - right
                width = measuredWidth > 0 && measuredWidth < screenWidth
                    ? measuredWidth : Self.fallbackNotchWidth
            } else {
                width = Self.fallbackNotchWidth
            }
            // The camera inset can sit a point or two inside the menu bar.
            // The resting shape has to reach the bar or a hairline shows under it.
            height = max(safeAreaTop, menuBarHeight)
        } else {
            width = Self.noNotchWidth
            height = min(Self.noNotchHeight, menuBarHeight)
        }
    }
}

/// The camera housing is empty. Information is placed in the open band under it.
struct NotchClearance: Equatable {
    /// Tall enough for a 28pt face and a 32pt volume strip, with a little air.
    static let visibleBand: CGFloat = 36

    var occludedHeight: CGFloat

    /// How far readable content moves down. Zero on a display with no notch.
    var expandedOffset: CGFloat { max(0, occludedHeight) }

    /// True when this y is inside the camera housing.
    func occludes(y: CGFloat) -> Bool {
        expandedOffset > 0 && y >= 0 && y < expandedOffset
    }

    /// The idle dock stays the housing. A volume bar, track, or live activity
    /// drops the open band underneath.
    func restingHeight(fallback: CGFloat, showingInformation: Bool) -> CGFloat {
        guard expandedOffset > 0, showingInformation else { return fallback }
        return expandedOffset + Self.visibleBand
    }

    /// Idle face and colored dots stay in the side ears, beside the camera.
    func earCenterY(fallback: CGFloat = 0) -> CGFloat {
        guard expandedOffset > 0 else { return fallback / 2 }
        return expandedOffset / 2
    }

    /// Center of the band that drops under the housing for a running item.
    func readableCenterY(fallback: CGFloat = 0) -> CGFloat {
        guard expandedOffset > 0 else { return fallback / 2 }
        return expandedOffset + Self.visibleBand / 2
    }

    /// Expanded island height so the downward shift does not clip the bottom.
    func expandedHeight(_ contentHeight: CGFloat) -> CGFloat {
        contentHeight + expandedOffset
    }
}

/// Shared by the compact view and the greeting's collapse destination.
struct IslandRestingLayout {
    let width: CGFloat
    let height: CGFloat

    var botDiameter: CGFloat { min(20, max(0, height - 6)) }
    var botCenterY: CGFloat { height / 2 }
    var miniGridScale: CGFloat { min(1, max(0, height - 4) / 28) }
    var miniGridCenterX: CGFloat { width - 40 }
}
