import Foundation

@main
enum LiveActivityTests {
    static func main() {
        testFirstSettingsTapOpensTheFullWindow()
        testSettingsPageLinesUp()
        testEachActivityCanLead()
        testPausedMediaDoesNotLead()
        testUpdateAppearsOnlyForANewerOffer()
        testChargeLineShowsTheSpeed()
        testChargeSpeedWearsAColor()
        testSettingsKeepsTheMatchingNotchOpen()
        print("Live activities: 8 cases passed")
    }

    /// The header gear opens the full settings window. It does not stop on the notch page.
    static func testFirstSettingsTapOpensTheFullWindow() {
        precondition(LiveActivityBehavior.settingsDestination() == .fullWindow,
                     "the first settings tap opens the full window")
        let header = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "struct IslandHeader",
            until: "struct TabButton"
        )
        precondition(header.contains("LiveActivityBehavior.settingsDestination"),
                     "the gear uses the settings tap decision")
        precondition(header.contains("openFullSettings"),
                     "the gear posts the full settings window")
        precondition(!header.contains("state.view = .settings"),
                     "the gear does not open the notch settings page first")
    }

    /// Live Activities uses the same label column, checkboxes, and slider value as the other panes.
    static func testSettingsPageLinesUp() {
        let page = LiveActivityBehavior.settingsPage
        precondition(page.pages == ["General", "Customize activities"])
        precondition(page.labelColumn == 210)
        precondition(page.controlStyle == "checkbox")

        let labels = page.general.map(\.label)
        precondition(labels.contains("Enable live activities"))
        precondition(labels.contains("Show volume and brightness in the notch"))
        precondition(labels.contains("Hide in non notched screens"))
        precondition(labels.contains("Enable interactive activities"))
        precondition(labels.contains("Enable Quick Peek"))
        precondition(labels.contains("Unhide Automatically"))
        precondition(labels.contains("Show song change"))

        let timeout = page.general.first { $0.id == "timeout" }
        precondition(timeout?.title == "Inactivity timeout:")
        precondition(timeout?.showsValue == true)
        precondition(timeout?.caption?.contains("seconds") == true)

        let interactivity = page.general.first { $0.id == "interactive" }
        precondition(interactivity?.title == "Interactivity:")
        precondition(interactivity?.caption?.isEmpty == false)

        precondition(page.fullscreen.map(\.id) == [
            "media", "tray", "calendar", "update", "bluetooth", "battery", "timerEnded"
        ])
        for item in page.fullscreen {
            precondition(item.title != item.id, "\(item.id) needs a plain title")
            precondition(item.title == LiveActivityBehavior.activityTitle(item.id))
            precondition(item.symbol == LiveActivityBehavior.activitySymbol(item.id))
            precondition(!(item.symbol ?? "").isEmpty)
        }
        precondition(page.customize.map(\.id) == page.fullscreen.map(\.id))
        precondition(page.customize.map(\.title) == page.fullscreen.map(\.title))

        let pane = sourceSlice(
            file: "NotchBuddy/Sources/App/CoucouSettingsShell.swift",
            from: "struct LiveActivitySettingsPane",
            until: "struct NookSettingsPane"
        )
        precondition(pane.contains("LiveActivityBehavior.settingsPage"),
                     "the pane draws the tested rows")
        precondition(pane.contains("toggleStyle(.checkbox)"),
                     "live activity choices are checkboxes")
        precondition(pane.contains("sliderRow("),
                     "the timeout uses the labeled slider")
        precondition(!pane.contains("List(prefs.activities)"),
                     "customize is not a nested list")
        precondition(pane.contains("Spacer(minLength: 0)"),
                     "extra space sits under the form")
        precondition(!pane.contains("ScrollView"),
                     "the form is not centered in a scroll view")
        precondition(!pane.contains("maxHeight: .infinity"),
                     "the form stays its own height")
        precondition(!pane.contains("alignment: .leading)"),
                     "a short list stays under the segmented control")
        precondition(pane.contains(".frame(width: 280)\n            .fixedSize(horizontal: false, vertical: true)"),
                     "the segmented control stays its own height")
        let shell = sourceSlice(
            file: "NotchBuddy/Sources/App/CoucouSettingsShell.swift",
            from: "struct CoucouSettingsShell",
            until: "struct GeneralSettingsPane"
        )
        precondition(shell.contains("Spacer(minLength: 0)"),
                     "a short page sits under the tab bar")
        precondition(shell.contains("SettingsPage.columnWidth"),
                     "settings sit in one centered column")
        precondition(shell.contains("alignment: .top"),
                     "the column stays under the tab bar, in the middle of the window")
        precondition(!shell.contains("alignment: .topLeading"),
                     "the page is not stuck to the left edge")
        precondition(shell.contains("contentShape(.interaction, RoundedRectangle(cornerRadius: 8))"),
                     "the settings tab square is the click target")
        let scales = sourceSlice(
            file: "NotchBuddy/Sources/App/CoucouSettingsShell.swift",
            from: "private func sliderRow",
            until: "private struct SettingsSection"
        )
        precondition(scales.contains("SettingsPage.scaleInset"),
                     "adjustment scales stay in from the page edge")
        precondition(scales.contains("SettingsPage.scaleTrack"),
                     "an adjustment scale stays a short track")
        let open = sourceSlice(
            file: "NotchBuddy/Sources/App/AppDelegate.swift",
            from: "func openSettings",
            until: "func placeBelowIsland"
        )
        precondition(open.contains("standardBounds"),
                     "settings lays out in the window bounds")
    }

    static func testEachActivityCanLead() {
        let enabled: Set<String> = [
            "media", "tray", "calendar", "update", "bluetooth", "battery", "timerEnded"
        ]
        var facts = quiet()
        facts.timerEnded = true
        facts.mediaTitle = "Blue"
        facts.mediaArtist = "Ada"
        facts.nextEventTitle = "Standup"
        facts.batteryPercent = 15
        facts.bluetoothIsNews = true
        facts.bluetoothName = "Pods"
        facts.trayCount = 2
        facts.updateAvailable = true
        precondition(lead(facts, enabled)?.id == "timerEnded")
        precondition(lead(facts, enabled)?.text == "Timer ended")

        facts.timerEnded = false
        precondition(lead(facts, enabled)?.id == "media")
        precondition(lead(facts, enabled)?.text == "Blue · Ada")

        facts.mediaTitle = nil
        precondition(lead(facts, enabled)?.id == "calendar")
        precondition(lead(facts, enabled)?.text == "Standup")

        facts.nextEventTitle = nil
        precondition(lead(facts, enabled)?.id == "battery")
        precondition(lead(facts, enabled)?.text == "15% battery")

        facts.batteryPercent = 40
        facts.batteryCharging = true
        facts.chargingWatts = 46.6
        let charging = lead(facts, enabled)
        precondition(charging?.text == "40% 47W", "charge line was \(charging?.text ?? "missing")")
        precondition(charging?.symbol == "battery.50.bolt", "indicator was \(charging?.symbol ?? "missing")")

        facts.batteryCharging = false
        facts.batteryPercent = 80
        precondition(lead(facts, enabled)?.id == "bluetooth")
        precondition(lead(facts, enabled)?.text == "Pods")

        facts.bluetoothIsNews = false
        precondition(lead(facts, enabled)?.id == "update")
        precondition(lead(facts, enabled)?.text == "Update available")
        precondition(lead(facts, enabled)?.symbol == "arrow.down.circle")

        facts.updateAvailable = false
        facts.trayCount = 1
        precondition(lead(facts, enabled)?.text == "1 file in the tray")
        facts.trayCount = 3
        precondition(lead(facts, enabled)?.text == "3 files in the tray")
        facts.trayCount = 0
        precondition(lead(facts, enabled) == nil)

        facts.trayCount = 4
        precondition(lead(facts, []) == nil, "a turned-off activity stays hidden")
        facts.bluetoothIsNews = true
        facts.bluetoothName = "   "
        precondition(lead(facts, ["bluetooth"]) == nil, "a blank device name stays hidden")

        var steady = quiet()
        steady.bluetoothName = "Pods"
        steady.bluetoothIsNews = false
        precondition(lead(steady, ["bluetooth"]) == nil, "a steady Bluetooth connection stays hidden")

        var healthy = quiet()
        healthy.batteryPercent = 21
        precondition(lead(healthy, ["battery"]) == nil, "a healthy battery stays hidden")
        precondition(lead(facts, enabled, revealed: false) == nil)
    }

    static func testUpdateAppearsOnlyForANewerOffer() {
        precondition(LiveActivityBehavior.updateIsAvailable(installed: "0.1.1", offered: nil) == false)
        precondition(LiveActivityBehavior.updateIsAvailable(installed: "0.1.1", offered: "0.1.1") == false)
        precondition(LiveActivityBehavior.updateIsAvailable(installed: "0.1.1", offered: "0.1.0") == false)
        precondition(LiveActivityBehavior.updateIsAvailable(installed: "0.1.1", offered: "0.1.2") == true)
        precondition(LiveActivityBehavior.updateIsAvailable(installed: "0.1.1", offered: "0.2") == true)
    }

    /// Charging shows the battery icon, the percentage, and the watts. The word charging stays off.
    static func testChargeLineShowsTheSpeed() {
        precondition(NookLayout.batteryLine(percent: 40, charging: true, watts: 46.6) == "40% 47W")
        precondition(NookLayout.batteryLine(percent: 40, charging: true, watts: 2.44) == "40% 2.4W")
        let unknown = NookLayout.batteryLine(percent: 40, charging: true, watts: nil)
        precondition(unknown == "40%", "missing speed was \(unknown)")
        precondition(!unknown.contains("charging"))
        precondition(NookLayout.batteryLine(percent: 15, charging: false, watts: 30) == "15% battery")
        precondition(NookLayout.batterySymbol(percent: 15, charging: false) == "battery.25")
        precondition(NookLayout.batterySymbol(percent: 96, charging: true) == "battery.100.bolt")
        let intoBattery = NookLayout.chargingWatts(milliamps: 2400, millivolts: 12000, charging: true)
        precondition(
            NookLayout.batteryLine(percent: 80, charging: true, watts: intoBattery) == "80% 29W",
            "2400 mA at 12000 mV was \(intoBattery ?? -1)"
        )
        let flipped = NookLayout.chargingWatts(milliamps: -2400, millivolts: 12000, charging: true)
        precondition(NookLayout.batteryLine(percent: 80, charging: true, watts: flipped) == "80% 29W")
        precondition(NookLayout.chargingWatts(milliamps: -2546, millivolts: 11839, charging: false) == nil)
    }

    /// The home card on the right shows the percentage and a colored charging speed.
    static func testChargeSpeedWearsAColor() {
        precondition(NookLayout.chargeSpeedText(0) == "0W")
        precondition(NookLayout.chargeSpeedText(4.2) == "4.2W")
        precondition(NookLayout.chargeSpeedText(29) == "29W")
        precondition(NookLayout.chargeSpeedText(67.2) == "67W")
        let finishing = NookLayout.measuredChargeWatts(
            batteryPowerMilliwatts: 4318,
            milliamps: 338,
            millivolts: 12695,
            charging: true
        )
        precondition(
            finishing.map(NookLayout.chargeSpeedText) == "4.3W",
            "a finishing charge of 4318 mW was \(finishing.map { String($0) } ?? "nil")"
        )
        let negativeInflow = NookLayout.measuredChargeWatts(
            batteryPowerMilliwatts: -46600,
            milliamps: nil,
            millivolts: nil,
            charging: true
        )
        precondition(negativeInflow.map { ($0 * 10).rounded() / 10 } == 46.6)
        precondition(NookLayout.measuredChargeWatts(
            batteryPowerMilliwatts: 4500,
            milliamps: 360,
            millivolts: 12500,
            charging: false
        ) == 0, "discharge is not a charge rate")
        precondition(NookLayout.measuredChargeWatts(
            batteryPowerMilliwatts: nil,
            milliamps: nil,
            millivolts: nil,
            charging: true
        ) == nil)
        let fromCurrent = NookLayout.measuredChargeWatts(
            batteryPowerMilliwatts: 0,
            milliamps: 338,
            millivolts: 12695,
            charging: true
        )
        precondition(
            fromCurrent.map(NookLayout.chargeSpeedText) == "4.3W",
            "a zero power sample must fall back to current times voltage, was \(fromCurrent.map { String($0) } ?? "nil")"
        )
        precondition(NookLayout.measuredChargeWatts(
            batteryPowerMilliwatts: nil,
            milliamps: 65535,
            millivolts: 12695,
            charging: true
        ) == nil, "a wrapped current is not a charge rate")
        precondition(NookLayout.chargeSpeedColorHex(watts: 4.2) == "#F5A524", "a slow charge stays amber")
        precondition(NookLayout.chargeSpeedColorHex(watts: 14.9) == "#F5A524")
        precondition(NookLayout.chargeSpeedColorHex(watts: 15) == "#3DDC84", "a normal charge stays green")
        precondition(NookLayout.chargeSpeedColorHex(watts: 44.9) == "#3DDC84")
        precondition(NookLayout.chargeSpeedColorHex(watts: 45) == "#64D2FF", "a fast charge stays blue")
        precondition(NookLayout.chargeSpeedColorHex(watts: 96) == "#64D2FF")
        precondition(NookLayout.displayedSpeedWatts(charging: true, packWatts: 46.6, supplyWatts: 60) == 46.6)
        precondition(NookLayout.displayedSpeedWatts(charging: true, packWatts: 4.318, supplyWatts: 60) == 4.318, "the adapter contract is not the charge rate")
        precondition(NookLayout.displayedSpeedWatts(charging: true, packWatts: 4.318, supplyWatts: 26.763) == 4.318, "system draw is not the charge rate")
        precondition(NookLayout.displayedSpeedWatts(charging: false, packWatts: 0, supplyWatts: 60) == 0)
        precondition(NookLayout.displayedSpeedWatts(charging: false, packWatts: nil, supplyWatts: 60) == nil, "a missing reading must not become the adapter contract")
        precondition(NookLayout.displayedSpeedWatts(charging: false, packWatts: nil, supplyWatts: nil) == nil)
        precondition(NookLayout.chargingWatts(milliamps: 65535, millivolts: 12000, charging: true) == nil)
        let cluster = sourceSlice(
            file: "NotchBuddy/Sources/App/TerminalNotchView.swift",
            from: "struct TerminalClusterView",
            until: "struct TerminalFaceButton"
        )
        precondition(cluster.contains("BatterySpeedLine"), "the right card has no battery line")
        let line = sourceSlice(
            file: "NotchBuddy/Sources/App/TerminalNotchView.swift",
            from: "struct BatterySpeedLine",
            until: "struct AttachBlobButton"
        )
        precondition(line.contains("chargeSpeedColorHex"), "the wattage has no color")
        precondition(line.contains("displayedSpeedWatts"), "the card shows the measured charge rate")
        let probe = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "private static func powerSample",
            until: "private static func adapterWatts"
        )
        precondition(probe.contains("BatteryPower"), "the charge rate comes from battery power")
        precondition(probe.contains("measuredChargeWatts"), "battery power is converted in milliwatts")
        precondition(!probe.contains("SystemPowerIn"), "system draw is not the charge rate")
        precondition(!probe.contains("\"Watts\""), "the adapter contract is not the charge rate")
        precondition(line.contains("chargeSpeedText"), "the wattage is a different string")
        precondition(line.contains("batterySymbol"), "the battery indicator is missing")
    }

    /// Each settings tab keeps the notch on the area that tab edits.
    static func testSettingsKeepsTheMatchingNotchOpen() {
        precondition(SettingsNotchPreview.page(for: "general") == .home)
        precondition(SettingsNotchPreview.page(for: "gestures") == .home)
        precondition(SettingsNotchPreview.page(for: "activities") == .activities)
        precondition(SettingsNotchPreview.page(for: "nook") == .nook)
        precondition(SettingsNotchPreview.page(for: "tray") == .tray)
        precondition(SettingsNotchPreview.page(for: "drop") == .drop)
        precondition(SettingsNotchPreview.page(for: "keys") == .none)
        precondition(SettingsNotchPreview.page(for: "about") == .none)
        precondition(SettingsNotchPreview.page(for: "closed") == .none)
        precondition(SettingsNotchPreview.staysOpen(.nook))
        precondition(SettingsNotchPreview.staysOpen(.tray))
        precondition(SettingsNotchPreview.staysOpen(.drop))
        precondition(SettingsNotchPreview.staysOpen(.activities))
        precondition(SettingsNotchPreview.staysOpen(.home))
        precondition(!SettingsNotchPreview.staysOpen(.none))

        let shell = sourceSlice(
            file: "NotchBuddy/Sources/App/CoucouSettingsShell.swift",
            from: "struct CoucouSettingsShell",
            until: "struct GeneralSettingsPane"
        )
        precondition(shell.contains("settingsNotchPreview"), "changing settings tells the notch which page to show")
        let general = sourceSlice(
            file: "NotchBuddy/Sources/App/CoucouSettingsShell.swift",
            from: "struct GeneralSettingsPane",
            until: "struct GestureSettingsPane"
        )
        precondition(general.contains("Haptic feedback"), "settings has a haptic switch")
        precondition(general.contains("nears the edge of the notch"), "the switch says what the click is for")
        let opener = sourceSlice(
            file: "NotchBuddy/Sources/App/AppDelegate.swift",
            from: "private func openSettings",
            until: "private func placeBelowIsland"
        )
        precondition(!opener.contains("collapse()"), "opening settings must not fold the notch")
        let hover = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "private func pollFrame",
            until: "private var lastMouse"
        )
        precondition(hover.contains("NotchHaptics.approach"), "the pointer tick uses the edge rule")
        precondition(hover.contains(".levelChange"), "the edge click is a firm tick")
        precondition(!hover.contains(".alignment"), "the edge click was the light tick")
        precondition(hover.contains("disableHaptics"), "the settings switch can turn the tick off")
        precondition(hover.contains("settingsPreview"), "an open settings page keeps its notch up")
        let preview = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "private func keepSettingsPreview",
            until: "private func presentExpanded"
        )
        precondition(preview.contains("refreshChrome()"), "the drop wing and activity line resize as soon as that page opens")
        let board = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "func refreshChrome",
            until: "private func considerHide"
        )
        precondition(board.contains("publish()"), "refreshChrome redraws the side width")
    }

    static func testPausedMediaDoesNotLead() {
        precondition(NookLayout.publishedMediaTitle(isPlaying: false, title: "Blue") == nil)
        precondition(NookLayout.publishedMediaTitle(isPlaying: true, title: "  ") == nil)
        precondition(NookLayout.publishedMediaTitle(isPlaying: true, title: "Blue") == "Blue")
    }

    static func quiet() -> NookActivityFacts {
        NookActivityFacts(
            mediaTitle: nil, mediaArtist: nil, trayCount: 0, nextEventTitle: nil,
            bluetoothName: nil, bluetoothIsNews: false, batteryPercent: nil,
            batteryCharging: false, timerEnded: false, updateAvailable: false
        )
    }

    static func lead(_ facts: NookActivityFacts, _ enabled: Set<String>, revealed: Bool = true) -> NookHeadline? {
        NookLayout.headline(facts: facts, enabled: enabled, revealed: revealed)
    }

    static func sourceSlice(file: String, from start: String, until end: String) -> String {
        let text: String
        do {
            text = try String(contentsOfFile: file, encoding: .utf8)
        } catch {
            preconditionFailure("could not read \(file)")
        }
        guard let startRange = text.range(of: start), let endRange = text.range(of: end) else {
            preconditionFailure("could not find \(start) in \(file)")
        }
        return String(text[startRange.lowerBound..<endRange.lowerBound])
    }
}
