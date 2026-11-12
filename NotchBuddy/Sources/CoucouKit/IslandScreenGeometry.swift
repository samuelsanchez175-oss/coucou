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

/// Live activity placement. The main display drops a chin under the camera.
/// A second display keeps the line in the bar and can make it wider.
struct ActivityChin: Equatable {
    var physicalNotch: Bool
    var housingHeight: CGFloat
    /// Points of black under the camera. The main display uses this.
    var chinHeight: CGFloat
    /// Banner width under the camera.
    var chinWidth: CGFloat
    /// Line width on a display with no camera.
    var openWidth: CGFloat
    /// Tallness of the chin on a display with no camera.
    var barHeight: CGFloat = Self.secondDisplayBar
    var fontSize: CGFloat
    var showing: Bool

    /// The face plus air, so a larger font is not cut off.
    var lineBox: CGFloat { max(22, fontSize + 10) }

    /// Extra height under the housing. Zero on a second display.
    var drop: CGFloat {
        guard physicalNotch, showing else { return 0 }
        return max(lineBox, chinHeight)
    }

    var activityWidth: CGFloat {
        let asked = physicalNotch ? chinWidth : openWidth
        return max(fontSize * 8, asked)
    }

    /// Black on each side of a second-display line.
    /// The faces and the waveform sit in that room, clear of the rounded corner.
    static let secondDisplayGutter: CGFloat = 104
    /// Collapsed bar on a display with no camera.
    /// Tall enough that the face grid clears the screen edge.
    static let secondDisplayBar: CGFloat = 58
    /// How far a closed face draws past the grid center, including the canvas past the cell.
    static let faceReach: CGFloat = 20
    /// Closed waveform width. The seven bars are this wide.
    static let shelfSpan: CGFloat = 28
    static let corner: CGFloat = 14
    static let cornerAir: CGFloat = 4
    static let clusterGap: CGFloat = 8

    /// Waveform center, measured from the right edge. The bars clear the corner.
    static var waveInset: CGFloat { corner + cornerAir + shelfSpan / 2 }
    /// Face-grid center, measured from the right edge. The grid sits left of the waveform.
    static var faceInset: CGFloat { waveInset + shelfSpan / 2 + clusterGap + faceReach }
    /// The closed face cluster, top to bottom, at full size. It is the tallest mark in the bar.
    static var faceSpan: CGFloat { faceReach * 2 }

    /// 1 when the bar holds the faces. A shorter bar shrinks Mochi, the line, the faces, and the waveform together.
    static func contentScale(barHeight: CGFloat) -> CGFloat {
        let air: CGFloat = 8
        let room = max(1, barHeight - air)
        return min(1, room / max(1, faceSpan))
    }

    /// The main display keeps the ear size. A second display follows its bar.
    var contentScale: CGFloat {
        guard !physicalNotch else { return 1 }
        return Self.contentScale(barHeight: max(lineBox, barHeight))
    }

    static func plainMochiCenter(width: CGFloat) -> CGFloat {
        min(max(0, width) / 2, 32)
    }

    static func plainFaceCenter(width: CGFloat) -> CGFloat {
        let span = max(0, width)
        return max(span / 2, span - faceInset)
    }

    static func plainWaveCenter(width: CGFloat) -> CGFloat {
        let span = max(0, width)
        return max(shelfSpan / 2, span - waveInset)
    }

    /// The closed island has to be at least this wide while an activity is up.
    var widthFloor: CGFloat {
        guard showing else { return 0 }
        if physicalNotch { return activityWidth }
        return activityWidth + Self.secondDisplayGutter * 2
    }

    func restingHeight(fallback: CGFloat) -> CGFloat {
        guard showing else { return fallback }
        if drop > 0 { return max(fallback, housingHeight + drop) }
        // A second display stays in the bar. The housing height does not hold it up.
        return max(lineBox, barHeight)
    }

    /// Off keeps the line in the bar. A folded main-display chin does the same.
    /// A second display does not fold, so `folded` only applies under a camera.
    static func shown(enabled: Bool, physicalNotch: Bool, folded: Bool) -> Bool {
        guard enabled else { return false }
        return !(physicalNotch && folded)
    }

    /// Under the camera on the main display. In the bar on a second display.
    /// `drawnHeight` is the shape on screen. Omit it for the settled chin.
    func activityCenterY(fallback: CGFloat, drawnHeight: CGFloat? = nil) -> CGFloat {
        guard physicalNotch, showing else {
            return max(lineBox / 2, (drawnHeight ?? fallback) / 2)
        }
        guard let drawnHeight else { return housingHeight + drop / 2 }
        let grown = max(0, drawnHeight - housingHeight)
        // An open panel is taller than any chin. The line stays in the settled chin
        // while that panel shrinks. A chin slider stays inside the chin, so the line rides it.
        let dropNow = grown > 100 ? drop : grown
        return housingHeight + dropNow / 2
    }
}

/// One scale for Coucou text. Frames that use `points` grow with the face.
enum CoucouType {
    static let minimum = 0.8
    static let maximum = 1.6

    static func clamp(_ scale: Double) -> Double {
        let clamped = min(maximum, max(minimum, scale))
        return (clamped * 10).rounded() / 10
    }

    static func points(_ base: CGFloat, scale: Double) -> CGFloat {
        base * CGFloat(clamp(scale))
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
