import Foundation

enum HudKind: String, Equatable {
    case volume
    case brightness
}

enum HudKey: Equatable {
    case volumeUp
    case volumeDown
    case mute
    case brightnessUp
    case brightnessDown
}

struct HudLevel: Equatable {
    var volume: Double
    var muted: Bool
    var brightness: Double
}

/// Pure volume and brightness HUD rules. System calls live elsewhere.
enum HudBehavior {
    static let steps = 16
    static let visibleSeconds: TimeInterval = 1.4
    static let stripHeight: CGFloat = 32
    /// The row beside the camera: inset, icon, name, track, percent.
    static let iconWidth: CGFloat = 16
    static let titleWidth: CGFloat = 78
    static let trackWidth: CGFloat = 72
    static let percentWidth: CGFloat = 40
    static let rowSpacing: CGFloat = 8
    static let rowInset: CGFloat = 10
    static let wing: CGFloat = 250
    static var contentWidth: CGFloat {
        rowInset * 2 + iconWidth + titleWidth + trackWidth + percentWidth + rowSpacing * 3
    }

    /// One menu-bar wing. The island adds this on both sides so the housing stays centered.
    static func wingWidth(showing: Bool) -> CGFloat {
        showing ? wing : 0
    }

    /// Center of the bar, in the right wing, clear of the camera.
    static func stripCenterX(islandWidth: CGFloat, wing: CGFloat) -> CGFloat {
        let span = max(36, wing)
        return max(span / 2, islandWidth - span / 2)
    }

    /// Width of the white fill. Zero is an empty track, so mute does not leave a stuck nub.
    static func fillWidth(fraction: Double) -> CGFloat {
        let clamped = min(1, max(0, fraction))
        return trackWidth * clamped
    }

    /// The bar appears once the black shape has cleared the camera. It hides as soon as it is dismissed.
    static let revealAt: Double = 0.92
    static let fillSpringResponse: Double = 0.28
    static let fillSpringDamping: Double = 0.86

    static func stripShown(showing: Bool, shapeWidth: CGFloat, restingWidth: CGFloat, openWidth: CGFloat) -> Bool {
        guard showing else { return false }
        let span = openWidth - restingWidth
        guard span > 1 else { return true }
        let grown = (shapeWidth - restingWidth) / span
        return grown >= revealAt
    }

    /// A press is key state 0x0A. Key-up and unrelated media keys are ignored.
    static func key(code: Int, keyState: Int) -> HudKey? {
        guard keyState == 0x0A else { return nil }
        switch code {
        case 0: return .volumeUp
        case 1: return .volumeDown
        case 7: return .mute
        case 2: return .brightnessUp
        case 3: return .brightnessDown
        default: return nil
        }
    }

    static func next(level: HudLevel, key: HudKey) -> (kind: HudKind, level: HudLevel) {
        var level = level
        switch key {
        case .volumeUp:
            level.muted = false
            level.volume = step(level.volume, by: 1)
            return (.volume, level)
        case .volumeDown:
            level.muted = false
            level.volume = step(level.volume, by: -1)
            if level.volume <= 0 { level.muted = true }
            return (.volume, level)
        case .mute:
            level.muted.toggle()
            return (.volume, level)
        case .brightnessUp:
            level.brightness = step(level.brightness, by: 1)
            return (.brightness, level)
        case .brightnessDown:
            level.brightness = step(level.brightness, by: -1)
            return (.brightness, level)
        }
    }

    static func shownFraction(kind: HudKind, level: HudLevel) -> Double {
        switch kind {
        case .volume: return level.muted ? 0 : level.volume
        case .brightness: return level.brightness
        }
    }

    static func percent(_ value: Double) -> String {
        let clamped = min(1, max(0, value))
        return "\(Int((clamped * 100).rounded()))%"
    }

    static func symbol(kind: HudKind, value: Double, muted: Bool) -> String {
        switch kind {
        case .brightness:
            return "sun.max.fill"
        case .volume:
            if muted || value <= 0 { return "speaker.slash.fill" }
            if value < 0.34 { return "speaker.fill" }
            if value < 0.67 { return "speaker.wave.1.fill" }
            return "speaker.wave.2.fill"
        }
    }

    private static func step(_ value: Double, by delta: Int) -> Double {
        let clamped = min(1, max(0, value))
        let current = Int((clamped * Double(steps)).rounded())
        let next = min(steps, max(0, current + delta))
        return Double(next) / Double(steps)
    }
}
