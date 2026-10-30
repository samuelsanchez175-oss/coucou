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

    struct PublishedRelease: Equatable, Sendable {
        var version: String
        var page: String
        /// Direct Coucou.zip on the published GitHub release. Nil when that asset is missing.
        var download: String?
    }

    /// What the check-for-update button does after it reads the release. None of these install it.
    enum UpdateLookup: Equatable {
        /// Installed is current, or the check failed. Do not download.
        case current
        /// A newer release has no Coucou.zip. Do not invent a download.
        case missingZip(version: String)
        /// A newer Coucou.zip is not on disk yet. Download it, then ask.
        case download(version: String, url: String)
        /// That zip is already saved. Ask again. Do not download it again.
        case ask(version: String)
    }

    /// The prompt after a download. Save for later leaves Coucou as it is.
    enum UpdatePromptChoice: Equatable {
        case update
        case saveForLater
    }

    /// Latest published release. The app reads this once, not on every notch tick.
    static let releaseAPI = "https://api.github.com/repos/Louis-CFM/coucou/releases/latest"
    static let releasesPage = "https://github.com/Louis-CFM/coucou/releases/latest"

    /// A newer offered version is the only New Update signal. The same or an older offer stays quiet.
    static func updateIsAvailable(installed: String, offered: String?) -> Bool {
        guard let offered else { return false }
        return versionParts(offered).lexicographicallyPrecedes(versionParts(installed)) == false
            && versionParts(offered) != versionParts(installed)
    }

    /// Reads tag_name and html_url. A missing tag, a tag with no number, or a bad body is no offer.
    static func publishedRelease(json: Data) -> PublishedRelease? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let version = version(fromTag: object["tag_name"] as? String) else { return nil }
        return PublishedRelease(
            version: version,
            page: releasePage(object["html_url"] as? String),
            download: macZipURL(object)
        )
    }

    /// Download only when the offer is newer. A saved zip asks again and does not install.
    static func lookup(installed: String, offer: PublishedRelease?, savedFileExists: Bool) -> UpdateLookup {
        guard let offer, updateIsAvailable(installed: installed, offered: offer.version) else {
            return .current
        }
        if savedFileExists {
            return .ask(version: offer.version)
        }
        guard let download = offer.download else {
            return .missingZip(version: offer.version)
        }
        return .download(version: offer.version, url: download)
    }

    /// The original branch. The downloaded zip is that release's app, not this Mac's copy.
    static let originalBranch = "https://github.com/Louis-CFM/coucou.git"

    /// Update asks Grok to compare. Save for later does not.
    static func asksGrok(_ choice: UpdatePromptChoice) -> Bool {
        choice == .update
    }

    /// Neither choice installs the downloaded app over this Mac's Coucou.
    static func installsDownloadedApp(_ choice: UpdatePromptChoice) -> Bool {
        false
    }

    /// Samuel's local tree. The running app is built from this folder.
    static func localTree(home: URL) -> URL {
        home.appendingPathComponent("dev").appendingPathComponent("coucou")
    }

    /// The Grok CLI that reviews a release against the local tree.
    static func grokExecutable(home: URL) -> URL {
        home.appendingPathComponent(".grok").appendingPathComponent("bin").appendingPathComponent("grok")
    }

    /// What Grok is told. The zip stays a download. The local tree stays as it is.
    static func reviewBrief(version: String, zipPath: String) -> String {
        """
        The local Coucou in this folder is different from the original branch on GitHub.

        Original branch: \(originalBranch)
        Downloaded release zip: \(zipPath)
        Offered version: \(version)

        This zip is the original app. It must not be installed over the Coucou on this Mac.
        Do not regress the local Coucou in this folder.

        Do not replace /Applications/Coucou.app.
        Do not unzip that zip over the app.
        Do not discard uncommitted work in this folder.
        Do not push.
        Do not merge, reset, checkout, or clean.

        Fetch the original branch and compare it with this folder. Say what the original branch has that this copy does not, and what this copy has that the original branch does not. Then stop and wait.
        """
    }

    /// One shell argument. A quote inside the brief stays inside the argument.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Opens Grok in plan mode on the local tree. This command does not install the zip.
    static func reviewCommand(repo: String, grok: String, brief: String) -> String {
        let pathExport = #"export PATH="$HOME/.grok/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH""#
        return """
        \(pathExport); cd \(shellQuote(repo)) && exec \(shellQuote(grok)) --permission-mode plan --no-subagents --cwd \(shellQuote(repo)) --verbatim \(shellQuote(brief))
        """
    }

    /// The Mac zip on this repo. Any other asset, host, or path is ignored.
    static func macZipURL(_ object: [String: Any]) -> String? {
        guard let assets = object["assets"] as? [[String: Any]] else { return nil }
        for asset in assets {
            guard (asset["name"] as? String) == "Coucou.zip" else { continue }
            if let url = allowedDownloadURL(asset["browser_download_url"] as? String) {
                return url
            }
        }
        return nil
    }

    /// https://github.com/Louis-CFM/coucou/releases/download/<tag>/Coucou.zip
    static func allowedDownloadURL(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(".."),
              let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com" else { return nil }
        let path = url.path
        guard path.hasPrefix("/Louis-CFM/coucou/releases/download/"),
              path.hasSuffix("/Coucou.zip") else { return nil }
        return url.absoluteString
    }

    /// The GitHub download redirects to its asset host. Other hosts are refused.
    static func allowsReleaseRedirect(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        if host == "github.com" {
            return allowedDownloadURL(url.absoluteString) != nil
        }
        switch host {
        case "release-assets.githubusercontent.com",
             "objects.githubusercontent.com",
             "github-releases.githubusercontent.com":
            return true
        default:
            return false
        }
    }

    static func isZipHeader(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[data.startIndex] == 0x50
            && data[data.startIndex + 1] == 0x4B
            && data[data.startIndex + 2] == 0x03
            && data[data.startIndex + 3] == 0x04
    }

    static func isZipFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return isZipHeader(handle.readData(ofLength: 4))
    }

    /// Drops one leading v. "latest" and a blank tag are not versions.
    static func version(fromTag tag: String?) -> String? {
        guard var text = tag?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let first = text.first, first == "v" || first == "V" {
            let rest = text.dropFirst()
            if rest.first?.isNumber == true {
                text = String(rest)
            }
        }
        guard text.contains(where: { $0.isNumber }) else { return nil }
        return text
    }

    static func updateSentence(installed: String, offered: String?, checked: Bool, checking: Bool) -> String {
        if checking { return "Checking for a newer version." }
        if !checked { return "Coucou has not checked yet." }
        guard let offered else { return "Coucou could not check for a newer version." }
        if updateIsAvailable(installed: installed, offered: offered) {
            return "Version \(offered) is available."
        }
        return "This is the latest version."
    }

    /// Keeps a GitHub release page for this repo. Anything else uses the published releases page.
    private static func releasePage(_ raw: String?) -> String {
        guard let raw else { return releasesPage }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("https://github.com/Louis-CFM/coucou/") else { return releasesPage }
        return trimmed
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

    /// The open notch panel is taller than the drawn island and sits above the
    /// settings window. While settings is open, only the drawn island takes the
    /// press, so the eight tabs underneath stay clickable.
    static func panelTakesThePress(settingsOpen: Bool, overDrawnIsland: Bool, overPanel: Bool) -> Bool {
        if settingsOpen { return overDrawnIsland }
        return overDrawnIsland || overPanel
    }
}
