import Foundation

struct NookWidget: Identifiable, Codable, Equatable {
    var id: String
    var enabled: Bool
    var cells: Int
}

struct LiveActivityChoice: Identifiable, Codable, Equatable {
    var id: String
    var enabled: Bool
    var showInFullscreen: Bool
}

/// Notch adjustments copied from the NotchNook settings window.
/// Stored in UserDefaults. API keys are not part of this reset.
@MainActor
final class NookPreferences: ObservableObject {
    static let shared = NookPreferences()

    static let fullscreenChoices = ["notched", "always", "never"]
    static let mediaSources = ["system", "music", "spotify"]

    @Published var showInFullscreen: String = "notched"
    @Published var mediaSource: String = "system"
    @Published var preferRoundButtons: Bool = true
    @Published var translucentNotch: Bool = false
    @Published var alwaysOpenOnHover: Bool = false
    @Published var disableHaptics: Bool = false
    @Published var preventCloseOnMouseLeave: Bool = false
    @Published var lockWhileTyping: Bool = true
    @Published var contentPadding: Double = 14
    @Published var notchWidthOffset: Double = 0
    @Published var notchHeightOffset: Double = 0
    @Published var handlerEnabled: Bool = true
    @Published var handlerWidth: Double = 94
    @Published var handlerHeight: Double = 31
    @Published var handlerTransparent: Bool = false
    @Published var demoMode: Bool = false

    @Published var gesturesWhileHovering: Bool = true
    @Published var verticalGestures: Bool = true
    @Published var horizontalMediaGestures: Bool = false
    @Published var invertMediaGestures: Bool = false

    @Published var liveActivitiesEnabled: Bool = true
    @Published var hideActivitiesOnNoNotch: Bool = false
    @Published var inactivityTimeout: Double = 10
    @Published var interactiveActivities: Bool = true
    @Published var quickPeek: Bool = true
    @Published var unhideAutomatically: Bool = true
    @Published var showSongChange: Bool = false
    /// Volume and brightness keys draw in the notch. Off until the user turns it on.
    @Published var hudReplacement: Bool = false {
        didSet {
            guard ready else { return }
            HudController.shared.preferenceChanged()
        }
    }
    @Published var activities: [LiveActivityChoice] = NookPreferences.defaultActivities

    @Published var nookEnabled: Bool = true
    @Published var widgetDividers: Bool = true
    @Published var widgets: [NookWidget] = NookPreferences.defaultWidgets
    @Published var enabledCalendarIDs: [String]? = nil
    @Published var showPastEvents: Bool = false
    @Published var showAllDayEvents: Bool = false
    @Published var showMultiDayEvents: Bool = false
    @Published var daysBehind: Double = 7
    @Published var daysAhead: Double = 7

    @Published var trayWidth: Double = 12
    /// File-type icon size in the tray, in points. 100 fills most of the tile.
    @Published var trayIconSize: Double = 100
    @Published var dropAreaWidth: Double = 16
    /// A song dropped on the nook is split into stems in the open Logic Pro project.
    @Published var splitSongsIntoStems: Bool = true

    /// Set by the key monitor. True for a short time after a key press.
    @Published private(set) var typingLocked: Bool = false
    private var typingClear: DispatchWorkItem?

    private let defaults = UserDefaults.standard
    private var ready = false

    private init() {
        load()
        ready = true
        if fitEnabledWidgetWidths() { persist() }
    }

    func noteTyping() {
        guard lockWhileTyping else { return }
        typingLocked = true
        typingClear?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.typingLocked = false }
        typingClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    func widget(_ id: String) -> NookWidget? {
        widgets.first { $0.id == id }
    }

    func setWidget(id: String, enabled: Bool) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        let on = SettingsBoard.commitWidgetEnabled(id: id, on: enabled)
        guard widgets[index].enabled != on else { return }
        widgets[index].enabled = on
        persist()
    }

    func setWidget(id: String, cells: Int) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        let fitted = SettingsBoard.commitCells(id: id, cells: cells, contentPadding: contentPadding)
        guard widgets[index].cells != fitted else { return }
        widgets[index].cells = fitted
        persist()
    }

    func moveWidgets(from offsets: IndexSet, to destination: Int) {
        widgets.move(fromOffsets: offsets, toOffset: destination)
        persist()
    }

    func setActivity(id: String, enabled: Bool) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].enabled = enabled
        persist()
    }

    func setActivity(id: String, showInFullscreen: Bool) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].showInFullscreen = showInFullscreen
        persist()
    }

    func reset() {
        ready = false
        applyDefaults()
        enabledCalendarIDs = nil
        ready = true
        persist()
    }

    /// Order matches the open notch: media, calendar, then Mirror.
    private static let legacyWidgetOrder = [
        "calendar", "media", "shortcuts", "mirror", "notes", "quickApps", "todos", "timer"
    ]

    static let defaultWidgets: [NookWidget] = [
        NookWidget(id: "media", enabled: true, cells: 5),
        NookWidget(id: "calendar", enabled: true, cells: 5),
        NookWidget(id: "mirror", enabled: true, cells: 2),
        NookWidget(id: "shortcuts", enabled: false, cells: 14),
        NookWidget(id: "notes", enabled: false, cells: 5),
        NookWidget(id: "quickApps", enabled: false, cells: 4),
        NookWidget(id: "todos", enabled: false, cells: 4),
        NookWidget(id: "timer", enabled: false, cells: 4),
    ]

    static let defaultActivities: [LiveActivityChoice] = [
        LiveActivityChoice(id: "media", enabled: true, showInFullscreen: true),
        LiveActivityChoice(id: "tray", enabled: true, showInFullscreen: true),
        LiveActivityChoice(id: "calendar", enabled: true, showInFullscreen: true),
        LiveActivityChoice(id: "update", enabled: true, showInFullscreen: true),
        LiveActivityChoice(id: "bluetooth", enabled: true, showInFullscreen: true),
        LiveActivityChoice(id: "battery", enabled: true, showInFullscreen: true),
        LiveActivityChoice(id: "timerEnded", enabled: true, showInFullscreen: true),
    ]

    private func applyDefaults() {
        showInFullscreen = SettingsBoard.commitChoice("showInFullscreen", "notched") ?? "notched"
        mediaSource = SettingsBoard.commitChoice("mediaSource", "system") ?? "system"
        preferRoundButtons = SettingsBoard.defaultToggle("preferRoundButtons") ?? true
        translucentNotch = SettingsBoard.defaultToggle("translucentNotch") ?? false
        alwaysOpenOnHover = SettingsBoard.defaultToggle("alwaysOpenOnHover") ?? false
        disableHaptics = false
        preventCloseOnMouseLeave = SettingsBoard.defaultToggle("preventCloseOnMouseLeave") ?? false
        lockWhileTyping = SettingsBoard.defaultToggle("lockWhileTyping") ?? true
        contentPadding = SettingsBoard.defaultValue("contentPadding") ?? 14
        notchWidthOffset = SettingsBoard.defaultValue("notchWidthOffset") ?? 0
        notchHeightOffset = SettingsBoard.defaultValue("notchHeightOffset") ?? 0
        handlerEnabled = SettingsBoard.defaultToggle("handlerEnabled") ?? true
        handlerWidth = SettingsBoard.defaultValue("handlerWidth") ?? 94
        handlerHeight = SettingsBoard.defaultValue("handlerHeight") ?? 31
        handlerTransparent = SettingsBoard.defaultToggle("handlerTransparent") ?? false
        demoMode = SettingsBoard.defaultToggle("demoMode") ?? false
        gesturesWhileHovering = SettingsBoard.defaultToggle("gesturesWhileHovering") ?? true
        verticalGestures = SettingsBoard.defaultToggle("verticalGestures") ?? true
        horizontalMediaGestures = SettingsBoard.defaultToggle("horizontalMediaGestures") ?? false
        invertMediaGestures = SettingsBoard.defaultToggle("invertMediaGestures") ?? false
        liveActivitiesEnabled = SettingsBoard.defaultToggle("liveActivitiesEnabled") ?? true
        hideActivitiesOnNoNotch = SettingsBoard.defaultToggle("hideActivitiesOnNoNotch") ?? false
        inactivityTimeout = SettingsBoard.defaultValue("inactivityTimeout") ?? 10
        interactiveActivities = SettingsBoard.defaultToggle("interactiveActivities") ?? true
        quickPeek = SettingsBoard.defaultToggle("quickPeek") ?? true
        unhideAutomatically = SettingsBoard.defaultToggle("unhideAutomatically") ?? true
        showSongChange = SettingsBoard.defaultToggle("showSongChange") ?? false
        hudReplacement = SettingsBoard.defaultToggle("hudReplacement") ?? false
        activities = Self.defaultActivities
        nookEnabled = SettingsBoard.defaultToggle("nookEnabled") ?? true
        widgetDividers = SettingsBoard.defaultToggle("widgetDividers") ?? true
        widgets = Self.defaultWidgets
        showPastEvents = SettingsBoard.defaultToggle("showPastEvents") ?? false
        showAllDayEvents = SettingsBoard.defaultToggle("showAllDayEvents") ?? false
        showMultiDayEvents = SettingsBoard.defaultToggle("showMultiDayEvents") ?? false
        daysBehind = SettingsBoard.defaultValue("daysBehind") ?? 7
        daysAhead = SettingsBoard.defaultValue("daysAhead") ?? 7
        trayWidth = SettingsBoard.defaultValue("trayWidth") ?? 12
        trayIconSize = SettingsBoard.defaultValue("trayIconSize") ?? 100
        dropAreaWidth = SettingsBoard.defaultValue("dropAreaWidth") ?? 16
        splitSongsIntoStems = SettingsBoard.defaultToggle("splitSongsIntoStems") ?? true
    }

    private func load() {
        applyDefaults()
        let d = defaults
        if let v = d.string(forKey: key("showInFullscreen")), Self.fullscreenChoices.contains(v) { showInFullscreen = v }
        if let v = d.string(forKey: key("mediaSource")), Self.mediaSources.contains(v) { mediaSource = v }
        loadBool("preferRoundButtons", &preferRoundButtons)
        loadBool("translucentNotch", &translucentNotch)
        loadBool("alwaysOpenOnHover", &alwaysOpenOnHover)
        loadBool("disableHaptics", &disableHaptics)
        loadBool("preventCloseOnMouseLeave", &preventCloseOnMouseLeave)
        loadBool("lockWhileTyping", &lockWhileTyping)
        loadDouble("contentPadding", &contentPadding)
        loadDouble("notchWidthOffset", &notchWidthOffset)
        loadDouble("notchHeightOffset", &notchHeightOffset)
        loadBool("handlerEnabled", &handlerEnabled)
        loadDouble("handlerWidth", &handlerWidth)
        loadDouble("handlerHeight", &handlerHeight)
        loadBool("handlerTransparent", &handlerTransparent)
        loadBool("demoMode", &demoMode)
        loadBool("gesturesWhileHovering", &gesturesWhileHovering)
        loadBool("verticalGestures", &verticalGestures)
        loadBool("horizontalMediaGestures", &horizontalMediaGestures)
        loadBool("invertMediaGestures", &invertMediaGestures)
        loadBool("liveActivitiesEnabled", &liveActivitiesEnabled)
        loadBool("hideActivitiesOnNoNotch", &hideActivitiesOnNoNotch)
        loadDouble("inactivityTimeout", &inactivityTimeout)
        loadBool("interactiveActivities", &interactiveActivities)
        loadBool("quickPeek", &quickPeek)
        loadBool("unhideAutomatically", &unhideAutomatically)
        loadBool("showSongChange", &showSongChange)
        loadBool("hudReplacement", &hudReplacement)
        if let data = d.data(forKey: key("activities")),
           let saved = try? JSONDecoder().decode([LiveActivityChoice].self, from: data),
           !saved.isEmpty {
            activities = Self.defaultActivities.map { item in
                saved.first { $0.id == item.id } ?? item
            }
        }
        loadBool("nookEnabled", &nookEnabled)
        loadBool("widgetDividers", &widgetDividers)
        if let data = d.data(forKey: key("widgets")),
           let saved = try? JSONDecoder().decode([NookWidget].self, from: data),
           !saved.isEmpty {
            var merged = saved.filter { item in Self.defaultWidgets.contains { $0.id == item.id } }
            for item in Self.defaultWidgets where !merged.contains(where: { $0.id == item.id }) {
                merged.append(item)
            }
            if merged.map(\.id) == Self.legacyWidgetOrder {
                let byID = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
                merged = Self.defaultWidgets.compactMap { byID[$0.id] }
            }
            widgets = merged
        }
        if d.object(forKey: key("enabledCalendarIDs")) != nil,
           let data = d.data(forKey: key("enabledCalendarIDs")),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            enabledCalendarIDs = ids
        }
        loadBool("showPastEvents", &showPastEvents)
        loadBool("showAllDayEvents", &showAllDayEvents)
        loadBool("showMultiDayEvents", &showMultiDayEvents)
        loadDouble("daysBehind", &daysBehind)
        loadDouble("daysAhead", &daysAhead)
        loadDouble("trayWidth", &trayWidth)
        loadDouble("trayIconSize", &trayIconSize)
        loadDouble("dropAreaWidth", &dropAreaWidth)
        loadBool("splitSongsIntoStems", &splitSongsIntoStems)
    }

    /// Raises each enabled widget to the cell count that fits its controls.
    /// A stored count above that floor stays. Disabled widgets are left alone.
    @discardableResult
    func fitEnabledWidgetWidths() -> Bool {
        var changed = false
        let pad = CGFloat(contentPadding)
        for index in widgets.indices where widgets[index].enabled {
            let fitted = NookLayout.fittedCells(
                id: widgets[index].id,
                cells: widgets[index].cells,
                contentPadding: pad
            )
            if fitted != widgets[index].cells {
                widgets[index].cells = fitted
                changed = true
            }
        }
        return changed
    }

    func persist() {
        guard ready else { return }
        fitEnabledWidgetWidths()
        let d = defaults
        d.set(showInFullscreen, forKey: key("showInFullscreen"))
        d.set(mediaSource, forKey: key("mediaSource"))
        d.set(preferRoundButtons, forKey: key("preferRoundButtons"))
        d.set(translucentNotch, forKey: key("translucentNotch"))
        d.set(alwaysOpenOnHover, forKey: key("alwaysOpenOnHover"))
        d.set(disableHaptics, forKey: key("disableHaptics"))
        d.set(preventCloseOnMouseLeave, forKey: key("preventCloseOnMouseLeave"))
        d.set(lockWhileTyping, forKey: key("lockWhileTyping"))
        d.set(contentPadding, forKey: key("contentPadding"))
        d.set(notchWidthOffset, forKey: key("notchWidthOffset"))
        d.set(notchHeightOffset, forKey: key("notchHeightOffset"))
        d.set(handlerEnabled, forKey: key("handlerEnabled"))
        d.set(handlerWidth, forKey: key("handlerWidth"))
        d.set(handlerHeight, forKey: key("handlerHeight"))
        d.set(handlerTransparent, forKey: key("handlerTransparent"))
        d.set(demoMode, forKey: key("demoMode"))
        d.set(gesturesWhileHovering, forKey: key("gesturesWhileHovering"))
        d.set(verticalGestures, forKey: key("verticalGestures"))
        d.set(horizontalMediaGestures, forKey: key("horizontalMediaGestures"))
        d.set(invertMediaGestures, forKey: key("invertMediaGestures"))
        d.set(liveActivitiesEnabled, forKey: key("liveActivitiesEnabled"))
        d.set(hideActivitiesOnNoNotch, forKey: key("hideActivitiesOnNoNotch"))
        d.set(inactivityTimeout, forKey: key("inactivityTimeout"))
        d.set(interactiveActivities, forKey: key("interactiveActivities"))
        d.set(quickPeek, forKey: key("quickPeek"))
        d.set(unhideAutomatically, forKey: key("unhideAutomatically"))
        d.set(showSongChange, forKey: key("showSongChange"))
        d.set(hudReplacement, forKey: key("hudReplacement"))
        if let data = try? JSONEncoder().encode(activities) { d.set(data, forKey: key("activities")) }
        d.set(nookEnabled, forKey: key("nookEnabled"))
        d.set(widgetDividers, forKey: key("widgetDividers"))
        if let data = try? JSONEncoder().encode(widgets) { d.set(data, forKey: key("widgets")) }
        if let ids = enabledCalendarIDs, let data = try? JSONEncoder().encode(ids) {
            d.set(data, forKey: key("enabledCalendarIDs"))
        } else {
            d.removeObject(forKey: key("enabledCalendarIDs"))
        }
        d.set(showPastEvents, forKey: key("showPastEvents"))
        d.set(showAllDayEvents, forKey: key("showAllDayEvents"))
        d.set(showMultiDayEvents, forKey: key("showMultiDayEvents"))
        d.set(daysBehind, forKey: key("daysBehind"))
        d.set(daysAhead, forKey: key("daysAhead"))
        d.set(trayWidth, forKey: key("trayWidth"))
        d.set(trayIconSize, forKey: key("trayIconSize"))
        d.set(dropAreaWidth, forKey: key("dropAreaWidth"))
        d.set(splitSongsIntoStems, forKey: key("splitSongsIntoStems"))
        NotificationCenter.default.post(name: .nookChromeChanged, object: nil)
    }

    private func loadBool(_ name: String, _ target: inout Bool) {
        if defaults.object(forKey: key(name)) != nil { target = defaults.bool(forKey: key(name)) }
    }

    private func loadDouble(_ name: String, _ target: inout Double) {
        guard defaults.object(forKey: key(name)) != nil else { return }
        let raw = defaults.double(forKey: key(name))
        target = SettingsBoard.commit(slider: name, value: raw) ?? raw
    }

    private func key(_ name: String) -> String { "nook.\(name)" }
}

extension Notification.Name {
    static let nookChromeChanged = Notification.Name("nookChromeChanged")
}

enum NookWidgetInfo {
    static func title(_ id: String) -> String {
        switch id {
        case "calendar": return "Calendar"
        case "media": return "Media Player"
        case "shortcuts": return "Shortcuts"
        case "mirror": return "Mirror"
        case "notes": return "Notes"
        case "quickApps": return "Quick Apps"
        case "todos": return "To-dos"
        case "timer": return "Timer"
        default: return id
        }
    }

    static func symbol(_ id: String) -> String {
        switch id {
        case "calendar": return "calendar"
        case "media": return "music.note"
        case "shortcuts": return "sparkles"
        case "mirror": return "person.crop.circle"
        case "notes": return "note.text"
        case "quickApps": return "square.grid.2x2"
        case "todos": return "checklist"
        case "timer": return "timer"
        default: return "square"
        }
    }

    static func comingSoon(_ id: String) -> Bool { id == "quickApps" }
}

enum LiveActivityInfo {
    static func title(_ id: String) -> String { LiveActivityBehavior.activityTitle(id) }
    static func symbol(_ id: String) -> String { LiveActivityBehavior.activitySymbol(id) }
}
