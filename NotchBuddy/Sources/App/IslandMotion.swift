import CoreGraphics
import Foundation

/// How the closed notch treats a playing track.
enum NotchShelf: Equatable {
    /// Colored terminal faces. Nothing is playing.
    case faces
    /// Artwork and a pause mark inside the resting notch. The title stays hidden.
    case artwork
    /// Retired. The closed notch no longer widens into a titled shelf.
    case peek
}

/// Open and close timing measured from the Coucou and NotchNook recordings.
enum IslandMotion {
    /// Words stay hidden while the black shape is still small.
    /// Coucou's 0.1s frame was overlapping type; NotchNook was still a blur.
    static let openHiddenUntil: Double = 0.18
    /// Content is fully sharp once the shape has settled, about 0.3s in.
    static let openSharpAt: Double = 0.32
    /// Close removes the words before the shape finishes shrinking,
    /// so they cannot ghost under the menu bar.
    static let closeGoneAt: Double = 0.08

    static func contentOpacity(opening: Bool, elapsed: Double) -> Double {
        let t = max(0, elapsed)
        if opening {
            if t <= openHiddenUntil { return 0 }
            if t >= openSharpAt { return 1 }
            return (t - openHiddenUntil) / (openSharpAt - openHiddenUntil)
        }
        if t >= closeGoneAt { return 0 }
        return 1 - (t / closeGoneAt)
    }

    /// A shape that is still smaller than the settled panel blurs its contents.
    /// A settled panel, including a small spring overshoot, stays sharp.
    static func blur(scale: Double) -> Double {
        let settled = min(1, max(0, scale))
        if settled >= 0.92 { return 0 }
        return (1 - settled) * 22
    }

    /// Playing keeps artwork and play. The closed notch never shows the title,
    /// including while the pointer rests on it.
    static func shelf(playing: Bool, pointerOnNotch: Bool) -> NotchShelf {
        guard playing else { return .faces }
        return pointerOnNotch ? .artwork : .artwork
    }

    /// A wing on one side adds the same width on the other.
    static func balancedWidth(side: CGFloat) -> CGFloat {
        max(0, side) * 2
    }

    /// Left edge of an island that stays centered in the panel.
    static func centeredOrigin(panelWidth: CGFloat, islandWidth: CGFloat) -> CGFloat {
        (panelWidth - islandWidth) / 2
    }

    /// Extra width past the hardware notch so the hover shelf can show the title.
    static func peekExtraWidth(title: String) -> CGFloat {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.isEmpty ? "Music" : trimmed
        let estimate = CGFloat(text.count) * 7 + 86
        return min(220, max(120, estimate))
    }
}

/// One drag of the white pull tab at the bottom of the open drawer.
struct DrawerDrag: Equatable {
    var extensionHeight: CGFloat
    var close: Bool
}

/// How the open notch meets the top of the screen, and how round the cards are.
enum IslandOutline {
    /// A positive radius would round the top outward into the menu bar. Zero stays flush.
    /// A negative radius is the closed notch's concave ear and is left alone.
    static func openTopRadius(requested: CGFloat) -> CGFloat {
        min(0, requested)
    }

    /// Top corners of the home cards. A wide radius fans the black out beside them.
    static let cardTopRadius: CGFloat = 4
    static let cardBottomRadius: CGFloat = 20
}

/// The bottom tab lengthens the drawer. Pushing it up closes the drawer.
enum DrawerPull {
    /// White bar, the same short pill the iPhone draws at the bottom of the screen.
    static let indicatorWidth: CGFloat = 134
    static let indicatorHeight: CGFloat = 5
    /// Empty band under the page. The pill lives inside it.
    static let contentClearance: CGFloat = 12
    /// Pill center, measured up from the bottom edge.
    static let tabCenterInset: CGFloat = 6
    /// Hit strip around the pill. It stays inside the band.
    static let grabHeight: CGFloat = 16
    /// An upward drag of this many points closes the drawer.
    static let closeTravel: CGFloat = 24
    /// Past this extra height, auto-close waits longer and watches a wider area.
    static let engagedTravel: CGFloat = 40
    static let standardCloseDelay: TimeInterval = 15

    /// `translationY` is positive when the finger moves down.
    static func drag(extensionHeight: CGFloat, translationY: CGFloat, maxExtension: CGFloat) -> DrawerDrag {
        if translationY <= -closeTravel {
            return DrawerDrag(extensionHeight: 0, close: true)
        }
        let cap = max(0, maxExtension)
        let next = min(cap, max(0, extensionHeight + translationY))
        return DrawerDrag(extensionHeight: next, close: false)
    }

    static func isExtended(_ extensionHeight: CGFloat) -> Bool {
        extensionHeight >= engagedTravel
    }

    /// A pulled-down drawer waits five times the usual auto-close time.
    static func autoCloseDelay(base: TimeInterval, extended: Bool) -> TimeInterval {
        let safe = base > 0 ? base : standardCloseDelay
        return extended ? safe * 5 : safe
    }

    /// How far the drawer may grow before it reaches the bottom of the screen.
    static func maxExtension(screenHeight: CGFloat, restingDrawerHeight: CGFloat, margin: CGFloat = 72) -> CGFloat {
        max(0, screenHeight - restingDrawerHeight - margin)
    }

    /// The black shape. A pull adds height and leaves the width alone.
    /// Closed, the shape is the notch: the pull does not leave a wide bar behind.
    static func drawnSize(
        open: Bool,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        openWidth: CGFloat,
        openHeight: CGFloat,
        extensionHeight: CGFloat
    ) -> (width: CGFloat, height: CGFloat) {
        if !open {
            return (max(0, notchWidth), max(0, notchHeight))
        }
        return (max(0, openWidth), max(0, openHeight) + max(0, extensionHeight))
    }

    /// Where the pointer may sit before the drawer starts closing.
    /// AppKit's origin is the bottom left, and the drawer is glued to the top of the screen.
    /// This rect is hover room only. It is never the drawn shape.
    static func keepOpenRect(island: CGRect, extended: Bool) -> CGRect {
        if !extended {
            return island.insetBy(dx: -6, dy: -6)
        }
        let linear = sqrt(5.0)
        let extraW = island.width * (linear - 1)
        let extraH = island.height * (linear - 1)
        return CGRect(
            x: island.minX - extraW / 2,
            y: island.minY - extraH,
            width: island.width * linear,
            height: island.height * linear
        )
    }
}

/// One step of the notch-edge haptic. The tick plays once per approach.
struct NotchHapticStep: Equatable {
    var play: Bool
    var wasOutside: Bool
}

/// A firm click as the pointer nears the notch. The settings switch can turn it off.
enum NotchHaptics {
    /// How close, in points, counts as nearing the edge.
    static let approachBand: CGFloat = 28

    /// Distance outside a rectangle. Zero means the point is inside.
    static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        guard !rect.isNull, !rect.isEmpty else { return .greatestFiniteMagnitude }
        let dx = max(rect.minX - point.x, point.x - rect.maxX, 0)
        let dy = max(rect.minY - point.y, point.y - rect.maxY, 0)
        return hypot(dx, dy)
    }

    /// `wasOutside` is true when the pointer was farther than `band` on the previous sample.
    static func approach(distance: CGFloat, band: CGFloat, wasOutside: Bool, enabled: Bool) -> NotchHapticStep {
        let outside = distance > band
        let play = enabled && wasOutside && !outside
        return NotchHapticStep(play: play, wasOutside: outside)
    }
}
