import Foundation
import CoreGraphics

// Widget-only stub so CoucouKit/IslandTypes.swift compiles inside the Mac
// widget target. The real `TerminalBehavior` lives in Sources/App and never
// ships to the widget; the widget only ever reads the usage snapshot, never
// IslandConst.viewLayouts, so these placeholder values are inert.
enum TerminalBehavior {
    static let overviewHeight: CGFloat = 150
    static let overviewBlobCenterY: CGFloat = 76
}
