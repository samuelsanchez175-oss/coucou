import CoreGraphics
import Foundation

/// What each Settings control writes. The panes call these so a slider or a button
/// cannot store a value the control itself cannot show.
enum SettingsBoard {
    static let resetStatus = "Notch settings reset. API keys were kept."
    static let resetClearsAPIKeys = false

    private struct SliderSpec {
        var range: ClosedRange<Double>
        var step: Double
        var defaultValue: Double
    }

    private static let sliders: [String: SliderSpec] = [
        "contentPadding": SliderSpec(range: 0...32, step: 1, defaultValue: 14),
        "notchWidthOffset": SliderSpec(range: -40...40, step: 1, defaultValue: 0),
        "notchHeightOffset": SliderSpec(range: -40...40, step: 1, defaultValue: 0),
        "handlerWidth": SliderSpec(range: 40...220, step: 1, defaultValue: 94),
        "handlerHeight": SliderSpec(range: 16...64, step: 1, defaultValue: 31),
        "inactivityTimeout": SliderSpec(range: 0...60, step: 1, defaultValue: 10),
        "daysBehind": SliderSpec(range: 0...30, step: 1, defaultValue: 7),
        "daysAhead": SliderSpec(range: 0...30, step: 1, defaultValue: 7),
        "dropAreaWidth": SliderSpec(range: 4...30, step: 1, defaultValue: 16),
        "trayWidth": SliderSpec(range: 4...30, step: 1, defaultValue: 12),
        "trayIconSize": SliderSpec(range: 36...140, step: 1, defaultValue: 100),
        "soundVolume": SliderSpec(range: 0...0.2, step: 0, defaultValue: 0.12),
    ]

    static var sliderNames: [String] { Array(sliders.keys) }

    static func defaultValue(_ name: String) -> Double? {
        sliders[name]?.defaultValue
    }

    /// The number a slider stores. Whole-step sliders land on a step. Volume stays continuous.
    static func commit(slider name: String, value: Double) -> Double? {
        guard let spec = sliders[name] else { return nil }
        let clamped = min(spec.range.upperBound, max(spec.range.lowerBound, value))
        guard spec.step > 0 else { return clamped }
        let steps = ((clamped - spec.range.lowerBound) / spec.step).rounded()
        let snapped = spec.range.lowerBound + steps * spec.step
        return min(spec.range.upperBound, max(spec.range.lowerBound, snapped))
    }

    static func soundPercent(_ value: Double) -> Int {
        let volume = commit(slider: "soundVolume", value: value) ?? 0
        return Int((volume / 0.2 * 100).rounded())
    }

    private static let toggles: [String: Bool] = [
        "preferRoundButtons": true,
        "translucentNotch": false,
        "alwaysOpenOnHover": false,
        "preventCloseOnMouseLeave": false,
        "lockWhileTyping": true,
        "handlerEnabled": true,
        "handlerTransparent": false,
        "demoMode": false,
        "gesturesWhileHovering": true,
        "verticalGestures": true,
        "horizontalMediaGestures": false,
        "invertMediaGestures": false,
        "liveActivitiesEnabled": true,
        "hudReplacement": false,
        "hideActivitiesOnNoNotch": false,
        "interactiveActivities": true,
        "quickPeek": true,
        "unhideAutomatically": true,
        "showSongChange": false,
        "nookEnabled": true,
        "widgetDividers": true,
        "showPastEvents": false,
        "showAllDayEvents": false,
        "showMultiDayEvents": false,
        "splitSongsIntoStems": true,
        "soundEnabled": true,
        "hotkeyEnabled": false,
    ]

    static func defaultToggle(_ name: String) -> Bool? { toggles[name] }

    private static let choices: [String: (options: [String], fallback: String)] = [
        "showInFullscreen": (["notched", "always", "never"], "notched"),
        "mediaSource": (["system", "music", "spotify"], "system"),
    ]

    static func commitChoice(_ name: String, _ value: String) -> String? {
        guard let choice = choices[name] else { return nil }
        return choice.options.contains(value) ? value : choice.fallback
    }

    static func hapticsOn(disableHaptics: Bool) -> Bool { !disableHaptics }

    static func disableHaptics(uiOn: Bool) -> Bool { !uiOn }

    static func invertGestureControlEnabled(horizontalOn: Bool) -> Bool { horizontalOn }

    static func showAccessibilitySettings(hudOn: Bool, keysCaptured: Bool, accessibilityOff: Bool) -> Bool {
        hudOn && !keysCaptured && accessibilityOff
    }

    /// Nil means every calendar. Clear stores an empty list, which shows none.
    static func selectAllCalendars() -> [String]? { nil }

    static func clearCalendars() -> [String] { [] }

    static func setCalendar(_ id: String, on: Bool, selection: [String]?, known: [String]) -> [String] {
        var ids = selection ?? known
        if on {
            if !ids.contains(id) { ids.append(id) }
        } else {
            ids.removeAll { $0 == id }
        }
        return ids
    }

    /// Quick Apps stays off. Every other widget takes the switch as it is.
    static func commitWidgetEnabled(id: String, on: Bool) -> Bool {
        guard id != "quickApps" else { return false }
        return on
    }

    /// Width is a whole cell count from the control floor through 16.
    static func commitCells(id: String, cells: Int, contentPadding: Double) -> Int {
        let floor = NookLayout.fittedCells(id: id, cells: 1, contentPadding: CGFloat(contentPadding))
        let lower = min(16, max(1, floor))
        return min(16, max(lower, cells))
    }

    /// The knob shows the fitted count. A write of that same number is the control drawing, not a new width.
    static func cellsFromSlider(id: String, stored: Int, proposed: Double, contentPadding: Double) -> Int? {
        let readout = NookLayout.fittedCells(id: id, cells: stored, contentPadding: CGFloat(contentPadding))
        let stepped = Int(proposed.rounded())
        guard stepped != readout else { return nil }
        return commitCells(id: id, cells: stepped, contentPadding: contentPadding)
    }

    static func keyToStore(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func grokKey(_ raw: String) -> SettingsKeySave {
        let stored = keyToStore(raw)
        let message = stored.isEmpty ? "✓ Grok key removed." : "✓ Grok key saved."
        return SettingsKeySave(stored: stored, message: message)
    }

    static func clearFilter() -> Set<String> { [] }

    /// An empty filter means every item is watched. Unchecking one keeps the others.
    static func toggleFilter(item: String, on: Bool, filter: Set<String>, items: [String]) -> Set<String> {
        var next = filter
        if on {
            next.insert(item)
            return next
        }
        if next.isEmpty { next = Set(items) }
        next.remove(item)
        return next
    }

    static func shortcut(hasModifier: Bool, flags: UInt, keyCode: UInt16) -> SettingsShortcut? {
        guard hasModifier else { return nil }
        return SettingsShortcut(flags: flags, keyCode: keyCode)
    }
}

struct SettingsKeySave: Equatable {
    var stored: String
    var message: String
}

struct SettingsShortcut: Equatable {
    var flags: UInt
    var keyCode: UInt16
}

struct HookDraft: Equatable {
    var showing: Bool
    var json: String

    static func cancel() -> HookDraft { HookDraft(showing: false, json: "") }
}

/// The song button on Customize pipelines. A cancelled panel or a non-song changes nothing.
enum SongChooser {
    static let message = "Choose a song. BPM, key, Camelot, and energy show on this page."

    static func accepted(ok: Bool, path: String?) -> String? {
        guard ok, let path, NookStemPipeline.isSong(path) else { return nil }
        return path
    }

    static func rejectionNote(path: String) -> String? {
        guard !NookStemPipeline.isSong(path) else { return nil }
        return "Drop a song. Other files stay where they are."
    }

    /// The open panel belongs on the Settings window. No Settings window means no panel.
    static func hostTitle(_ titles: [String]) -> String? {
        titles.first { $0.hasPrefix("Settings") }
    }

    /// Music, Downloads, and the Desktop. The system Open panel comes up with no size from this menu-bar app.
    static func defaultFolders() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Music", "Downloads", "Desktop"].map { home.appendingPathComponent($0) }
    }

    /// Song files in these folders, and one folder down. Packages and other files stay out.
    static func songs(in roots: [URL], limit: Int = 80) -> [URL] {
        var found: [URL] = []
        let manager = FileManager.default
        for root in roots {
            guard found.count < limit else { break }
            let children = (try? manager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let ordered = children.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            for url in ordered {
                guard found.count < limit else { break }
                if NookStemPipeline.isSong(url.path) {
                    found.append(url)
                    continue
                }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                guard values?.isDirectory == true else { continue }
                let ext = url.pathExtension.lowercased()
                guard ext != "app", ext != "logicx" else { continue }
                let nested = (try? manager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []
                for file in nested.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                    guard found.count < limit else { break }
                    guard NookStemPipeline.isSong(file.path) else { continue }
                    found.append(file)
                }
            }
        }
        return found
    }

    /// A menu-bar app can present the Open panel with no size. A panel that already has a size stays put.
    static func rescuedPanelFrame(width: CGFloat, height: CGFloat, screen: CGRect) -> CGRect? {
        guard width < 10 || height < 10 else { return nil }
        let panelWidth = min(720, screen.width - 80)
        let panelHeight = min(480, screen.height - 80)
        guard panelWidth > 100, panelHeight > 100 else { return nil }
        return CGRect(
            x: screen.midX - panelWidth / 2,
            y: screen.midY - panelHeight / 2,
            width: panelWidth,
            height: panelHeight
        )
    }
}

extension TapTempo {
    /// The Tap tempo button. A gap starts a new count and leaves the last BPM on the button.
    struct Button {
        var times: [TimeInterval] = []
        var shown: Int?

        mutating func tap(at time: TimeInterval) -> Int? {
            if let last = times.last, time - last > resetAfter {
                times = [time]
            } else {
                times.append(time)
                if times.count > 8 { times.removeFirst(times.count - 8) }
            }
            let reading = TapTempo.bpm(tapTimes: times)
            if let reading { shown = reading }
            return reading
        }
    }
}
