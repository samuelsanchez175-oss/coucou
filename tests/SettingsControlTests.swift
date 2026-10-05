import CoreGraphics
import Foundation

@main
enum SettingsControlTests {
    static func main() {
        testSlidersStayInsideTheRangeTheKnobCanReach()
        testResetRestoresSliderDefaultsAndKeepsKeys()
        testTogglesMatchTheSettingsRows()
        testPickersRejectAnUnknownChoice()
        testCalendarButtons()
        testWidgetWidthAndTheComingSoonSwitch()
        testShowingTheFloorDoesNotRaiseAStoredWidth()
        testHapticsSwitchStoresTheOppositeFlag()
        testDaysSliderChangesWhichEventsShow()
        testTapTempoButtonKeepsTheLastReading()
        testChooseASongAcceptsOnlyASong()
        testAZeroSizeOpenPanelGetsARealFrame()
        testChooseASongListsSongsInAFolder()
        testAccessibilityButtonShowsOnlyWhenTheKeysAreBlocked()
        testSoundSlider()
        testKeyButtonsTrimAndReport()
        testHookCancelClearsThePreview()
        testIntegrationFilterButtons()
        testShortcutRecorderIgnoresAPlainKey()
        testInvertSwitchStaysOffUntilHorizontalGesturesAreOn()
        testVolumeAndBrightnessStayOffUntilTurnedOn()
        print("Settings controls: 21 cases passed")
    }

    /// A slider writes the number on the knob. A value past either end stops at that end.
    /// The production change that fails this: commit() returning the raw value.
    static func testSlidersStayInsideTheRangeTheKnobCanReach() {
        let samples: [(String, Double, Double)] = [
            ("contentPadding", 80, 32),
            ("contentPadding", -4, 0),
            ("contentPadding", 20.4, 20),
            ("notchWidthOffset", -40.8, -40),
            ("notchHeightOffset", 6.6, 7),
            ("handlerWidth", 10, 40),
            ("handlerHeight", 100, 64),
            ("inactivityTimeout", 25, 25),
            ("daysBehind", 3.2, 3),
            ("daysAhead", 14, 14),
            ("dropAreaWidth", 3, 4),
            ("trayWidth", 30.2, 30),
            ("trayIconSize", 10, 36),
            ("trayIconSize", 100.4, 100),
            ("trayIconSize", 200, 140),
            ("soundVolume", 1, 0.2),
            ("soundVolume", -0.1, 0),
            ("soundVolume", 0.12, 0.12),
        ]
        for (name, raw, expect) in samples {
            let committed = SettingsBoard.commit(slider: name, value: raw)
            precondition(committed == expect, "\(name) \(raw) landed on \(String(describing: committed)), expected \(expect)")
        }
        precondition(SettingsBoard.commit(slider: "not-a-slider", value: 5) == nil)
        precondition(Set(SettingsBoard.sliderNames) == [
            "contentPadding", "notchWidthOffset", "notchHeightOffset",
            "handlerWidth", "handlerHeight", "inactivityTimeout",
            "daysBehind", "daysAhead", "dropAreaWidth", "trayWidth", "trayIconSize", "soundVolume",
        ])
    }

    /// Reset puts every slider and switch back. The API key string is not one of those values.
    /// The production change that fails this: reset returning the edited slider value.
    static func testResetRestoresSliderDefaultsAndKeepsKeys() {
        precondition(SettingsBoard.defaultValue("contentPadding") == 14)
        precondition(SettingsBoard.defaultValue("notchWidthOffset") == 0)
        precondition(SettingsBoard.defaultValue("notchHeightOffset") == 0)
        precondition(SettingsBoard.defaultValue("handlerWidth") == 94)
        precondition(SettingsBoard.defaultValue("handlerHeight") == 31)
        precondition(SettingsBoard.defaultValue("inactivityTimeout") == 10)
        precondition(SettingsBoard.defaultValue("daysBehind") == 7)
        precondition(SettingsBoard.defaultValue("daysAhead") == 7)
        precondition(SettingsBoard.defaultValue("trayWidth") == 12)
        precondition(SettingsBoard.defaultValue("trayIconSize") == 100)
        precondition(SettingsBoard.defaultValue("dropAreaWidth") == 16)
        precondition(SettingsBoard.defaultValue("soundVolume") == 0.12)
        precondition(SettingsBoard.resetStatus == "Notch settings reset. API keys were kept.")
        precondition(SettingsBoard.resetClearsAPIKeys == false)
    }

    /// Each checkbox on Live Activities, Gestures, Nook, and Drop Area has a default.
    /// The production change that fails this: defaultToggle returning nil for a row the page shows.
    static func testTogglesMatchTheSettingsRows() {
        let page = LiveActivityBehavior.settingsPage
        let names = page.general.filter { !$0.showsValue }.map(\.preference)
        precondition(names == [
            "liveActivitiesEnabled", "hudReplacement", "hideActivitiesOnNoNotch",
            "interactiveActivities", "quickPeek", "unhideAutomatically", "showSongChange",
        ])
        for name in names {
            precondition(SettingsBoard.defaultToggle(name) != nil, "\(name) has no stored switch")
        }
        precondition(SettingsBoard.defaultToggle("hudReplacement") == false)
        precondition(SettingsBoard.defaultToggle("showSongChange") == false)
        precondition(SettingsBoard.defaultToggle("liveActivitiesEnabled") == true)
        precondition(SettingsBoard.defaultToggle("not-a-toggle") == nil)

        precondition(SettingsBoard.defaultToggle("preferRoundButtons") == true)
        precondition(SettingsBoard.defaultToggle("translucentNotch") == false)
        precondition(SettingsBoard.defaultToggle("alwaysOpenOnHover") == false)
        precondition(SettingsBoard.defaultToggle("preventCloseOnMouseLeave") == false)
        precondition(SettingsBoard.defaultToggle("lockWhileTyping") == true)
        precondition(SettingsBoard.defaultToggle("handlerEnabled") == true)
        precondition(SettingsBoard.defaultToggle("handlerTransparent") == false)
        precondition(SettingsBoard.defaultToggle("demoMode") == false)
        precondition(SettingsBoard.defaultToggle("gesturesWhileHovering") == true)
        precondition(SettingsBoard.defaultToggle("verticalGestures") == true)
        precondition(SettingsBoard.defaultToggle("horizontalMediaGestures") == false)
        precondition(SettingsBoard.defaultToggle("invertMediaGestures") == false)
        precondition(SettingsBoard.defaultToggle("nookEnabled") == true)
        precondition(SettingsBoard.defaultToggle("widgetDividers") == true)
        precondition(SettingsBoard.defaultToggle("showPastEvents") == false)
        precondition(SettingsBoard.defaultToggle("showAllDayEvents") == false)
        precondition(SettingsBoard.defaultToggle("showMultiDayEvents") == false)
        precondition(SettingsBoard.defaultToggle("splitSongsIntoStems") == true)
        precondition(SettingsBoard.defaultToggle("soundEnabled") == true)
        precondition(SettingsBoard.defaultToggle("hotkeyEnabled") == false)
    }

    /// Show in fullscreen and Media source only keep the choices on the picker.
    /// The production change that fails this: commitChoice returning the unknown word.
    static func testPickersRejectAnUnknownChoice() {
        precondition(SettingsBoard.commitChoice("showInFullscreen", "always") == "always")
        precondition(SettingsBoard.commitChoice("showInFullscreen", "never") == "never")
        precondition(SettingsBoard.commitChoice("showInFullscreen", "banana") == "notched")
        precondition(SettingsBoard.commitChoice("mediaSource", "spotify") == "spotify")
        precondition(SettingsBoard.commitChoice("mediaSource", "music") == "music")
        precondition(SettingsBoard.commitChoice("mediaSource", "youtube") == "system")
    }

    /// Select All shows every calendar. Clear shows none. One box removes that calendar from the list.
    /// The production change that fails this: setCalendar leaving the selection unchanged.
    static func testCalendarButtons() {
        precondition(SettingsBoard.selectAllCalendars() == nil)
        precondition(SettingsBoard.clearCalendars().isEmpty)
        let withoutHome = SettingsBoard.setCalendar("home", on: false, selection: nil, known: ["home", "work"])
        precondition(withoutHome == ["work"])
        let both = SettingsBoard.setCalendar("home", on: true, selection: withoutHome, known: ["home", "work"])
        precondition(both.sorted() == ["home", "work"])
        let none = SettingsBoard.setCalendar("work", on: false, selection: ["work"], known: ["home", "work"])
        precondition(none.isEmpty)
    }

    /// Width stops at the cell count the widget's controls need, and at 16. Quick Apps stays off.
    /// The production change that fails this: commitCells returning the requested count unchanged.
    static func testWidgetWidthAndTheComingSoonSwitch() {
        precondition(SettingsBoard.commitCells(id: "media", cells: 5, contentPadding: 14) == 8)
        precondition(SettingsBoard.commitCells(id: "media", cells: 1, contentPadding: 0) == 7)
        precondition(SettingsBoard.commitCells(id: "calendar", cells: 6, contentPadding: 14) == 9)
        precondition(SettingsBoard.commitCells(id: "mirror", cells: 1, contentPadding: 14) == 5)
        precondition(SettingsBoard.commitCells(id: "shortcuts", cells: 14, contentPadding: 14) == 14)
        precondition(SettingsBoard.commitCells(id: "notes", cells: 20, contentPadding: 14) == 16)
        precondition(SettingsBoard.commitCells(id: "todos", cells: 4, contentPadding: 14) == 5)
        precondition(SettingsBoard.commitCells(id: "timer", cells: 4, contentPadding: 14) == 5)
        precondition(SettingsBoard.commitWidgetEnabled(id: "quickApps", on: true) == false)
        precondition(SettingsBoard.commitWidgetEnabled(id: "notes", on: true) == true)
        precondition(SettingsBoard.commitWidgetEnabled(id: "notes", on: false) == false)
    }

    /// The width knob shows the floor when the saved count is lower. Echoing that number must leave the saved count alone.
    /// A real move still saves. The production change that fails this: storing the floor whenever the knob is drawn.
    static func testShowingTheFloorDoesNotRaiseAStoredWidth() {
        precondition(SettingsBoard.cellsFromSlider(id: "calendar", stored: 6, proposed: 9, contentPadding: 14) == nil)
        precondition(SettingsBoard.cellsFromSlider(id: "todos", stored: 4, proposed: 5, contentPadding: 14) == nil)
        precondition(SettingsBoard.cellsFromSlider(id: "timer", stored: 4, proposed: 5, contentPadding: 14) == nil)
        precondition(SettingsBoard.cellsFromSlider(id: "calendar", stored: 6, proposed: 10, contentPadding: 14) == 10)
        precondition(SettingsBoard.cellsFromSlider(id: "media", stored: 8, proposed: 9, contentPadding: 14) == 9)
        precondition(SettingsBoard.cellsFromSlider(id: "media", stored: 9, proposed: 8, contentPadding: 14) == 8)
        precondition(SettingsBoard.cellsFromSlider(id: "shortcuts", stored: 14, proposed: 14, contentPadding: 14) == nil)
    }

    /// The Haptic feedback switch is on by default. The stored flag is the opposite.
    /// The production change that fails this: storing the switch position directly.
    static func testHapticsSwitchStoresTheOppositeFlag() {
        precondition(SettingsBoard.hapticsOn(disableHaptics: false) == true)
        precondition(SettingsBoard.hapticsOn(disableHaptics: true) == false)
        precondition(SettingsBoard.disableHaptics(uiOn: true) == false)
        precondition(SettingsBoard.disableHaptics(uiOn: false) == true)
    }

    /// One day behind hides an event that ended two days ago. Three days behind shows it.
    /// The production change that fails this: the days slider not changing the window.
    static func testDaysSliderChangesWhichEventsShow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let end = now.addingTimeInterval(-2 * 86_400)
        let event = NookEventFact(
            calendarID: "home", title: "Session",
            start: end.addingTimeInterval(-3_600), end: end, isAllDay: false
        )
        let oneDay = Int(SettingsBoard.commit(slider: "daysBehind", value: 1.2) ?? -1)
        precondition(oneDay == 1)
        precondition(NookLayout.includeEvent(
            event, now: now, allowedCalendarIDs: nil,
            showPast: true, showAllDay: false, showMultiDay: false,
            daysBehind: oneDay, daysAhead: 7
        ) == false)
        let threeDays = Int(SettingsBoard.commit(slider: "daysBehind", value: 3) ?? -1)
        precondition(NookLayout.includeEvent(
            event, now: now, allowedCalendarIDs: nil,
            showPast: true, showAllDay: false, showMultiDay: false,
            daysBehind: threeDays, daysAhead: 7
        ) == true)
        precondition(SettingsBoard.defaultToggle("showAllDayEvents") == false)
    }

    /// Two taps at half a second read 120. A pause keeps that number until the next pair.
    /// The production change that fails this: clearing the shown tempo when the gap starts over.
    static func testTapTempoButtonKeepsTheLastReading() {
        var button = TapTempo.Button()
        precondition(button.tap(at: 0) == nil)
        precondition(button.tap(at: 0.5) == 120)
        precondition(button.shown == 120)
        precondition(button.tap(at: 2.8) == nil)
        precondition(button.shown == 120)
        precondition(button.tap(at: 3.3) == 120)
        precondition(button.shown == 120)
    }

    /// Choose a song reads a song file. A PDF and a cancelled panel leave the page as it was.
    /// The production change that fails this: accepted() returning a PDF path.
    static func testChooseASongAcceptsOnlyASong() {
        precondition(SongChooser.accepted(ok: true, path: "/tmp/song.wav") == "/tmp/song.wav")
        precondition(SongChooser.accepted(ok: false, path: "/tmp/song.wav") == nil)
        precondition(SongChooser.accepted(ok: true, path: "/tmp/notes.pdf") == nil)
        precondition(SongChooser.rejectionNote(path: "/tmp/notes.pdf") == "Drop a song. Other files stay where they are.")
        precondition(SongChooser.rejectionNote(path: "/tmp/song.wav") == nil)
        precondition(SongChooser.message == "Choose a song. BPM, key, Camelot, and energy show on this page.")
        precondition(SongChooser.hostTitle(["frank ocean", "Settings — Coucou"]) == "Settings — Coucou")
        precondition(SongChooser.hostTitle(["frank ocean"]) == nil)
    }

    /// Choose a song lists song files in a folder, including one folder down. A PDF is not a song.
    /// The production change that fails this: the list including notes.pdf, or skipping the nested mp3.
    static func testChooseASongListsSongsInAFolder() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("coucou-song-list-test")
        let nested = root.appendingPathComponent("album")
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root.appendingPathComponent("song.wav").path, contents: Data())
        FileManager.default.createFile(atPath: root.appendingPathComponent("notes.pdf").path, contents: Data())
        FileManager.default.createFile(atPath: nested.appendingPathComponent("track.mp3").path, contents: Data())
        let names = Set(SongChooser.songs(in: [root]).map(\.lastPathComponent))
        precondition(names == ["song.wav", "track.mp3"])
        precondition(SongChooser.songs(in: [root], limit: 1).count == 1)
        try? FileManager.default.removeItem(at: root)
    }

    /// A menu-bar app's Open panel can come up with no size. Give that one a frame the pointer can use.
    /// The production change that fails this: leaving a 0 by 0 panel where it appeared.
    static func testAZeroSizeOpenPanelGetsARealFrame() {
        let screen = CGRect(x: 0, y: 0, width: 2048, height: 1330)
        let frame = SongChooser.rescuedPanelFrame(width: 0, height: 0, screen: screen)
        precondition(frame == CGRect(x: 664, y: 425, width: 720, height: 480))
        precondition(SongChooser.rescuedPanelFrame(width: 800, height: 500, screen: screen) == nil)
    }

    /// Open Accessibility Settings is on screen only when the notch cannot take the keys.
    /// The production change that fails this: showing the button while Accessibility is already on.
    static func testAccessibilityButtonShowsOnlyWhenTheKeysAreBlocked() {
        precondition(SettingsBoard.showAccessibilitySettings(hudOn: true, keysCaptured: false, accessibilityOff: true))
        precondition(SettingsBoard.showAccessibilitySettings(hudOn: true, keysCaptured: false, accessibilityOff: false) == false)
        precondition(SettingsBoard.showAccessibilitySettings(hudOn: false, keysCaptured: false, accessibilityOff: true) == false)
        precondition(SettingsBoard.showAccessibilitySettings(hudOn: true, keysCaptured: true, accessibilityOff: true) == false)
    }

    /// Volume and brightness stay off until the switch is turned on.
    /// The production change that fails this: the switch defaulting to on, or the row still saying it is on by default.
    static func testVolumeAndBrightnessStayOffUntilTurnedOn() {
        precondition(SettingsBoard.defaultToggle("hudReplacement") == false,
                     "volume and brightness stay off until the switch is turned on")
        let row = LiveActivityBehavior.settingsPage.general.first { $0.preference == "hudReplacement" }
        let caption = row?.caption ?? ""
        precondition(row?.label == "Show volume and brightness in the notch")
        precondition(caption.contains("Off until you turn it on"),
                     "the row still says the bar starts on: \(caption)")
        precondition(!caption.lowercased().contains("on by default"))
        let prefs = sourceSlice(
            file: "NotchBuddy/Sources/App/NookPreferences.swift",
            from: "var hudReplacement: Bool",
            until: "didSet"
        )
        precondition(prefs.contains("= false"), "a new launch still turns the bar on")
    }

    static func sourceSlice(file: String, from start: String, until end: String) -> String {
        let text = try! String(contentsOfFile: file, encoding: .utf8)
        guard let from = text.range(of: start), let to = text.range(of: end, range: from.upperBound..<text.endIndex) else {
            preconditionFailure("missing \(start) in \(file)")
        }
        return String(text[from.lowerBound..<to.lowerBound])
    }

    /// Volume stays between silent and the top of this slider. The percent matches the knob.
    /// The production change that fails this: a volume of 1 staying 1, past the slider.
    static func testSoundSlider() {
        precondition(SettingsBoard.soundPercent(0) == 0)
        precondition(SettingsBoard.soundPercent(0.12) == 60)
        precondition(SettingsBoard.soundPercent(0.2) == 100)
        precondition(SettingsBoard.defaultToggle("soundEnabled") == true)
    }

    /// Save and Save Grok key store the key without surrounding spaces, and say what happened.
    /// The production change that fails this: storing the spaces, or a saved message for an empty key.
    static func testKeyButtonsTrimAndReport() {
        let saved = SettingsBoard.grokKey("  abc  ")
        precondition(saved.stored == "abc")
        precondition(saved.message == "✓ Grok key saved.")
        let removed = SettingsBoard.grokKey(" \n ")
        precondition(removed.stored == "")
        precondition(removed.message == "✓ Grok key removed.")
        precondition(SettingsBoard.keyToStore("  sk-ant-x  ") == "sk-ant-x")
    }

    /// Cancel closes the hook preview and drops the text that was about to be written.
    /// The production change that fails this: cancel leaving the preview on screen.
    static func testHookCancelClearsThePreview() {
        let draft = HookDraft.cancel()
        precondition(draft.showing == false)
        precondition(draft.json == "")
    }

    /// Clear watches every item again. Unchecking one while all are watched keeps the rest.
    /// The production change that fails this: unchecking one item clearing the whole list.
    static func testIntegrationFilterButtons() {
        precondition(SettingsBoard.clearFilter().isEmpty)
        let rest = SettingsBoard.toggleFilter(item: "a", on: false, filter: [], items: ["a", "b"])
        precondition(rest == ["b"])
        let both = SettingsBoard.toggleFilter(item: "a", on: true, filter: rest, items: ["a", "b"])
        precondition(both == ["a", "b"])
        let onlyB = SettingsBoard.toggleFilter(item: "a", on: false, filter: both, items: ["a", "b"])
        precondition(onlyB == ["b"])
    }

    /// The shortcut button takes a key only when a modifier is held.
    /// The production change that fails this: a plain N replacing the shortcut.
    static func testShortcutRecorderIgnoresAPlainKey() {
        precondition(SettingsBoard.shortcut(hasModifier: false, flags: 0, keyCode: 45) == nil)
        let taken = SettingsBoard.shortcut(hasModifier: true, flags: 1 << 20, keyCode: 45)
        precondition(taken?.keyCode == 45)
        precondition(taken?.flags == 1 << 20)
    }

    /// Invert media gestures does nothing until horizontal gestures are on.
    /// The production change that fails this: the invert switch accepting clicks while horizontal is off.
    static func testInvertSwitchStaysOffUntilHorizontalGesturesAreOn() {
        precondition(SettingsBoard.invertGestureControlEnabled(horizontalOn: false) == false)
        precondition(SettingsBoard.invertGestureControlEnabled(horizontalOn: true) == true)
    }
}
