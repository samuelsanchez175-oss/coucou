import Foundation

@main
enum IslandDisplayChoiceTests {
    static func main() {
        // Storage round-trip, unknown values fall back to the notch default.
        for choice: IslandDisplayChoice in [.notch, .menuBar, .followMouse, .display(uuid: "ABC-123")] {
            precondition(IslandDisplayChoice(storageValue: choice.storageValue) == choice)
        }
        precondition(IslandDisplayChoice(storageValue: "") == .notch)
        precondition(IslandDisplayChoice(storageValue: "garbage") == .notch)
        precondition(IslandDisplayChoice(storageValue: "display:") == .notch)

        // External screen holds the menu bar, MacBook (with notch) is second, mouse on the third.
        let screens = [
            IslandDisplayCandidate(uuid: "EXT-1", hasNotch: false, containsMouse: false),
            IslandDisplayCandidate(uuid: "MBP",   hasNotch: true,  containsMouse: false),
            IslandDisplayCandidate(uuid: "EXT-2", hasNotch: false, containsMouse: true),
        ]
        precondition(IslandDisplayResolver.index(for: .notch, in: screens) == 1)
        precondition(IslandDisplayResolver.index(for: .menuBar, in: screens) == 0)
        precondition(IslandDisplayResolver.index(for: .followMouse, in: screens) == 2)
        precondition(IslandDisplayResolver.index(for: .display(uuid: "EXT-2"), in: screens) == 2)

        // A disconnected chosen screen falls back to the notch screen.
        precondition(IslandDisplayResolver.index(for: .display(uuid: "GONE"), in: screens) == 1)

        // No notch anywhere (lid closed): nil means "use the main screen".
        let desk = [
            IslandDisplayCandidate(uuid: "EXT-1", hasNotch: false, containsMouse: false),
            IslandDisplayCandidate(uuid: "EXT-2", hasNotch: false, containsMouse: false),
        ]
        precondition(IslandDisplayResolver.index(for: .notch, in: desk) == nil)
        precondition(IslandDisplayResolver.index(for: .display(uuid: "GONE"), in: desk) == nil)
        // Mouse between screens (rounding at an edge): keep the default.
        precondition(IslandDisplayResolver.index(for: .followMouse, in: desk) == nil)

        precondition(IslandDisplayResolver.index(for: .menuBar, in: []) == nil)

        let connected = [
            DisplaySettingScreen(uuid: "MBP", name: "Built-in Retina Display", hasNotch: true),
            DisplaySettingScreen(uuid: "LEFT", name: "DELL", hasNotch: false),
            DisplaySettingScreen(uuid: "RIGHT", name: "DELL", hasNotch: false),
        ]
        let rows = DisplaySettingList.options(screens: connected)
        precondition(rows.map(\.id) == ["notch", "display:LEFT", "display:RIGHT"])
        precondition(rows.map(\.title) == ["Main display", "DELL", "DELL 2"])
        precondition(rows.first?.title == "Main display", "the current screen stays Main display")

        let deskScreens = [
            DisplaySettingScreen(uuid: "A", name: "Studio Display", hasNotch: false),
            DisplaySettingScreen(uuid: "B", name: "Cinema", hasNotch: false),
        ]
        let deskRows = DisplaySettingList.options(screens: deskScreens)
        precondition(deskRows.map(\.title) == ["Main display", "Cinema"])
        precondition(deskRows.map(\.id) == ["notch", "display:B"])

        let unnamed = [DisplaySettingScreen(uuid: "X", name: "  ", hasNotch: false)]
        precondition(DisplaySettingList.options(screens: unnamed).map(\.title) == ["Main display"])

        precondition(IslandExtraDisplays.parse(nil).isEmpty)
        precondition(IslandExtraDisplays.parse("").isEmpty)
        precondition(IslandExtraDisplays.parse(" LEFT, RIGHT,LEFT ") == ["LEFT", "RIGHT"])
        precondition(IslandExtraDisplays.storageValue(["RIGHT", "LEFT"]) == "LEFT,RIGHT")
        let mirrorScreens = [
            IslandDisplayCandidate(uuid: "MBP", hasNotch: true, containsMouse: false),
            IslandDisplayCandidate(uuid: "LEFT", hasNotch: false, containsMouse: false),
            IslandDisplayCandidate(uuid: "RIGHT", hasNotch: false, containsMouse: false),
        ]
        precondition(
            IslandExtraDisplays.mirrorIndexes(selected: ["LEFT", "MBP", "GONE"], primary: 0, candidates: mirrorScreens) == [1]
        )
        precondition(
            IslandExtraDisplays.mirrorIndexes(selected: ["LEFT", "RIGHT"], primary: 0, candidates: mirrorScreens) == [1, 2]
        )
        precondition(IslandExtraDisplays.mirrorIndexes(selected: [], primary: 0, candidates: mirrorScreens).isEmpty)

        let general = (try? String(contentsOfFile: "NotchBuddy/Sources/App/CoucouSettingsShell.swift", encoding: .utf8)) ?? ""
        precondition(general.contains("SettingsSection(\"Display\")"), "the general tab has a Display setting")
        precondition(general.contains("Show Coucou on each display you turn on. Turn the main display off to keep Coucou on the other screens only."))
        precondition(general.contains("DisplayPicker"))
        precondition(general.contains("Toggle(\"Main display\""))
        precondition(general.contains("showOnMainDisplay"))
        precondition(!general.contains(".constant(true)"))
        precondition(!general.contains(".disabled(true)"))
        precondition(general.contains("Toggle(\"Chin\""))
        precondition(general.contains("chinEnabled"))
        let list = (try? String(contentsOfFile: "NotchBuddy/Sources/App/IslandDisplayChoice.swift", encoding: .utf8)) ?? ""
        precondition(list.contains("\"Main display\""))

        print("IslandDisplayChoice tests passed")
    }
}
