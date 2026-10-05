import CoreGraphics
import Foundation

enum SettingsDestination: Equatable {
    case fullWindow
    case notchPage
}

struct LiveActivitySettingsRow: Equatable, Identifiable {
    var id: String
    var title: String
    var label: String
    var caption: String?
    var symbol: String?
    var showsValue: Bool
    var preference: String
}

struct LiveActivitySettingsPage: Equatable {
    var pages: [String]
    var labelColumn: CGFloat
    var controlStyle: String
    var general: [LiveActivitySettingsRow]
    var fullscreenTitle: String
    var fullscreenCaption: String
    var fullscreen: [LiveActivitySettingsRow]
    var customizeCaption: String
    var customize: [LiveActivitySettingsRow]
}

/// Which live activity leads the notch, and how the settings page lines those choices up.
enum LiveActivityBehavior {
    /// The header gear opens the full settings window on the first tap.
    static func settingsDestination() -> SettingsDestination { .fullWindow }

    /// A newer offered version is the only New Update signal. The same or an older offer stays quiet.
    static func updateIsAvailable(installed: String, offered: String?) -> Bool {
        guard let offered else { return false }
        return versionParts(offered).lexicographicallyPrecedes(versionParts(installed)) == false
            && versionParts(offered) != versionParts(installed)
    }

    private static func versionParts(_ value: String) -> [Int] {
        let parts = value.split(separator: ".").map { Int($0) ?? 0 }
        return parts.isEmpty ? [0] : parts
    }

    static func activityTitle(_ id: String) -> String {
        switch id {
        case "media": return "Media"
        case "tray": return "Files Tray"
        case "calendar": return "Calendar"
        case "update": return "New Update"
        case "bluetooth": return "Bluetooth"
        case "battery": return "Battery"
        case "timerEnded": return "Timer Ended"
        default: return id
        }
    }

    static func activitySymbol(_ id: String) -> String {
        switch id {
        case "media": return "music.note"
        case "tray": return "tray"
        case "calendar": return "calendar"
        case "update": return "arrow.down.circle"
        case "bluetooth": return "dot.radiowaves.left.and.right"
        case "battery": return "battery.100"
        case "timerEnded": return "timer"
        default: return "circle"
        }
    }

    static let activityOrder = ["media", "tray", "calendar", "update", "bluetooth", "battery", "timerEnded"]

    static let settingsPage = LiveActivitySettingsPage(
        pages: ["General", "Customize activities"],
        labelColumn: 210,
        controlStyle: "checkbox",
        general: [
            row("enable", "", "Enable live activities", nil, "liveActivitiesEnabled"),
            row("hud", "", "Show volume and brightness in the notch",
                "Off until you turn it on. The volume and brightness keys then draw a bar beside the notch instead of the system banner.",
                "hudReplacement"),
            row("hide", "", "Hide in non notched screens", nil, "hideActivitiesOnNoNotch"),
            LiveActivitySettingsRow(
                id: "timeout", title: "Inactivity timeout:", label: "",
                caption: "How long a live activity stays after it goes quiet, such as when the music pauses. 10 seconds by default.",
                symbol: nil, showsValue: true, preference: "inactivityTimeout"
            ),
            row("interactive", "Interactivity:", "Enable interactive activities",
                "Allow some activities to interact with mouse click.", "interactiveActivities"),
            row("peek", "", "Enable Quick Peek",
                "If enabled, some live activities will show a short info on mouse hover.", "quickPeek"),
            row("unhide", "", "Unhide Automatically",
                "If enabled, live activities that have been dismissed (by swiping up) will automatically return.",
                "unhideAutomatically"),
            row("song", "", "Show song change",
                "Show when a song changes while playing media via quick peek.", "showSongChange"),
        ],
        fullscreenTitle: "Show in fullscreen:",
        fullscreenCaption: "Choose which live activities remain visible when another app is in fullscreen mode.",
        fullscreen: activityOrder.map { activityRow($0) },
        customizeCaption: "Choose which live activities can appear in the notch.",
        customize: activityOrder.map { activityRow($0) }
    )

    private static func row(
        _ id: String, _ title: String, _ label: String, _ caption: String?, _ preference: String
    ) -> LiveActivitySettingsRow {
        LiveActivitySettingsRow(
            id: id, title: title, label: label, caption: caption,
            symbol: nil, showsValue: false, preference: preference
        )
    }

    private static func activityRow(_ id: String) -> LiveActivitySettingsRow {
        LiveActivitySettingsRow(
            id: id, title: activityTitle(id), label: activityTitle(id),
            caption: nil, symbol: activitySymbol(id), showsValue: false, preference: id
        )
    }
}

/// The notch page that matches the settings tab being edited.
enum SettingsNotchPage: Equatable {
    /// Open home, for general notch settings and gestures.
    case home
    /// Compact shelf, where live activities sit.
    case activities
    /// Open Nook widgets.
    case nook
    /// Open Tray.
    case tray
    /// Compact shelf with the drop wing showing.
    case drop
    /// Keys and About have no notch page.
    case none
}

/// While a settings tab is open, the notch stays on that tab's area.
enum SettingsNotchPreview {
    static func page(for tab: String) -> SettingsNotchPage {
        switch tab {
        case "general", "gestures": return .home
        case "activities": return .activities
        case "nook": return .nook
        case "tray": return .tray
        case "drop": return .drop
        default: return .none
        }
    }

    static func staysOpen(_ page: SettingsNotchPage) -> Bool {
        page != .none
    }
}
