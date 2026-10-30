import Foundation

@main
enum LiveActivityTests {
    static func main() {
        testFirstSettingsTapOpensTheFullWindow()
        testSettingsPageLinesUp()
        testEachActivityCanLead()
        testPausedMediaDoesNotLead()
        testUpdateAppearsOnlyForANewerOffer()
        testReleaseTagBecomesTheUpdateOffer()
        testCheckForUpdateDownloadsThenAsks()
        testChargeLineShowsTheSpeed()
        testChargeSpeedWearsAColor()
        testSettingsKeepsTheMatchingNotchOpen()
        print("Live activities: 10 cases passed")
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

    /// A published release tag is the offered version. A bad body stays quiet.
    static func testReleaseTagBecomesTheUpdateOffer() {
        let newer = Data("""
        {"tag_name":"v0.1.2","html_url":"https://github.com/Louis-CFM/coucou/releases/tag/v0.1.2"}
        """.utf8)
        let offer = LiveActivityBehavior.publishedRelease(json: newer)
        precondition(offer?.version == "0.1.2", "the version keeps the numbers after v")
        precondition(offer?.page == "https://github.com/Louis-CFM/coucou/releases/tag/v0.1.2")
        precondition(LiveActivityBehavior.updateIsAvailable(installed: "0.1.1", offered: offer?.version) == true)

        let bare = Data(#"{"tag_name":"0.2.0"}"#.utf8)
        let missingPage = LiveActivityBehavior.publishedRelease(json: bare)
        precondition(missingPage?.version == "0.2.0")
        precondition(missingPage?.page == LiveActivityBehavior.releasesPage, "a missing page uses the published releases page")

        let elsewhere = Data(#"{"tag_name":"v9.0.0","html_url":"https://example.com/grab"}"#.utf8)
        precondition(LiveActivityBehavior.publishedRelease(json: elsewhere)?.page == LiveActivityBehavior.releasesPage)

        precondition(LiveActivityBehavior.publishedRelease(json: Data("not json".utf8)) == nil)
        precondition(LiveActivityBehavior.publishedRelease(json: Data(#"{"message":"Not Found"}"#.utf8)) == nil)
        precondition(LiveActivityBehavior.publishedRelease(json: Data(#"{"tag_name":"latest"}"#.utf8)) == nil)
        precondition(LiveActivityBehavior.version(fromTag: "  V1.4 ") == "1.4")
        precondition(LiveActivityBehavior.version(fromTag: "v") == nil)
        precondition(LiveActivityBehavior.version(fromTag: nil) == nil)

        precondition(LiveActivityBehavior.updateSentence(installed: "0.1.1", offered: nil, checked: false, checking: true) == "Checking for a newer version.")
        precondition(LiveActivityBehavior.updateSentence(installed: "0.1.1", offered: nil, checked: false, checking: false) == "Coucou has not checked yet.")
        precondition(LiveActivityBehavior.updateSentence(installed: "0.1.1", offered: nil, checked: true, checking: false) == "Coucou could not check for a newer version.")
        precondition(LiveActivityBehavior.updateSentence(installed: "0.1.1", offered: "0.1.1", checked: true, checking: false) == "This is the latest version.")
        precondition(LiveActivityBehavior.updateSentence(installed: "0.1.1", offered: "0.1.2", checked: true, checking: false) == "Version 0.1.2 is available.")

        let publish = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "private func publish()",
            until: "private func scheduleTrayNotice"
        )
        precondition(publish.contains("offered: offeredVersion"), "the live line uses the cached release")
        precondition(!publish.contains("offered: nil"), "the live line no longer ignores the published release")
        precondition(!publish.contains("URLSession"), "the two-second tick does not fetch a release")
        precondition(!publish.contains("releases/latest"), "the two-second tick does not fetch a release")
        precondition(!publish.contains("downloadZip"), "the two-second tick does not download a release")
        precondition(!publish.contains("lookForUpdate"), "the two-second tick does not look for an update")

        let start = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "func start()",
            until: "func notePointer"
        )
        precondition(start.contains("checkForUpdate()"), "Coucou checks once when it opens")

        let about = sourceSlice(
            file: "NotchBuddy/Sources/App/CoucouSettingsShell.swift",
            from: "struct AboutSettingsPane",
            until: "// MARK: - Rows"
        )
        precondition(about.contains("Check for a newer version"))
        precondition(about.contains("Open the release page"))
        precondition(about.contains("Looks up the published Coucou release"))
        precondition(about.contains("size: 11"))
        precondition(about.contains("updateSentence"))

        let pill = sourceSlice(
            file: "NotchBuddy/Sources/App/NookIslandView.swift",
            from: "struct LiveActivityPill",
            until: "// MARK: - Widget row"
        )
        precondition(pill.contains("headline.id == \"update\""), "only the update line opens the release")
        precondition(pill.contains("openReleasePage"))
        precondition(pill.contains("trayCollapsedText"))
        precondition(pill.contains("headline.symbol"))

        let activities = sourceSlice(
            file: "NotchBuddy/Sources/App/NookPreferences.swift",
            from: "static let defaultActivities",
            until: "private func applyDefaults"
        )
        precondition(activities.contains("id: \"update\", enabled: true"), "New Update stays available to turn on")
    }

    /// The header button downloads a newer Coucou.zip, then asks. Update asks Grok and does not install it.
    static func testCheckForUpdateDownloadsThenAsks() {
        let zip = "https://github.com/Louis-CFM/coucou/releases/download/v0.5.6/Coucou.zip"
        precondition(LiveActivityBehavior.allowedDownloadURL(zip) == zip)
        precondition(LiveActivityBehavior.allowedDownloadURL("https://example.com/Coucou.zip") == nil)
        precondition(LiveActivityBehavior.allowedDownloadURL("https://github.com/samuelsanchez175-oss/coucou/releases/download/v9/Coucou.zip") == nil)
        precondition(LiveActivityBehavior.allowedDownloadURL("http://github.com/Louis-CFM/coucou/releases/download/v0.5.6/Coucou.zip") == nil)
        precondition(LiveActivityBehavior.allowedDownloadURL("https://github.com/Louis-CFM/coucou/releases/download/v0.5.6/Other.zip") == nil)
        let cdn = URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/1")!
        precondition(LiveActivityBehavior.allowsReleaseRedirect(cdn))
        precondition(LiveActivityBehavior.allowsReleaseRedirect(URL(string: "https://example.com/Coucou.zip")!) == false)
        precondition(LiveActivityBehavior.isZipHeader(Data([0x50, 0x4B, 0x03, 0x04, 0x00])))
        precondition(LiveActivityBehavior.isZipHeader(Data("not a zip".utf8)) == false)

        let body = Data("""
        {"tag_name":"v0.5.6","html_url":"https://github.com/Louis-CFM/coucou/releases/tag/v0.5.6","assets":[
        {"name":"Other.zip","browser_download_url":"https://github.com/Louis-CFM/coucou/releases/download/v0.5.6/Other.zip"},
        {"name":"Coucou.zip","browser_download_url":"https://github.com/Louis-CFM/coucou/releases/download/v0.5.6/Coucou.zip"}]}
        """.utf8)
        let offer = LiveActivityBehavior.publishedRelease(json: body)
        precondition(offer?.version == "0.5.6")
        precondition(offer?.download == zip)
        precondition(LiveActivityBehavior.publishedRelease(json: Data(#"{"tag_name":"v0.1.2"}"#.utf8))?.download == nil)

        let fresh = LiveActivityBehavior.lookup(installed: "0.3.0", offer: offer, savedFileExists: false)
        guard case .download(let version, let url) = fresh else {
            preconditionFailure("a newer release downloads, got \(String(describing: fresh))")
        }
        precondition(version == "0.5.6")
        precondition(url == zip)

        let saved = LiveActivityBehavior.lookup(installed: "0.3.0", offer: offer, savedFileExists: true)
        guard case .ask(let asked) = saved else {
            preconditionFailure("a saved zip asks again and does not download, got \(String(describing: saved))")
        }
        precondition(asked == "0.5.6")

        let same = LiveActivityBehavior.lookup(installed: "0.5.6", offer: offer, savedFileExists: false)
        guard case .current = same else {
            preconditionFailure("the same version does not download")
        }
        let older = LiveActivityBehavior.PublishedRelease(version: "0.1.0", page: LiveActivityBehavior.releasesPage, download: zip)
        let behind = LiveActivityBehavior.lookup(installed: "0.3.0", offer: older, savedFileExists: false)
        guard case .current = behind else {
            preconditionFailure("an older release does not download")
        }
        let bare = LiveActivityBehavior.PublishedRelease(version: "0.9.0", page: LiveActivityBehavior.releasesPage, download: nil)
        let missing = LiveActivityBehavior.lookup(installed: "0.3.0", offer: bare, savedFileExists: false)
        guard case .missingZip = missing else {
            preconditionFailure("a newer release with no zip does not invent a download")
        }

        precondition(LiveActivityBehavior.asksGrok(.update))
        precondition(LiveActivityBehavior.asksGrok(.saveForLater) == false)
        precondition(LiveActivityBehavior.installsDownloadedApp(.update) == false)
        precondition(LiveActivityBehavior.installsDownloadedApp(.saveForLater) == false)
        let home = URL(fileURLWithPath: "/Users/samuel")
        precondition(LiveActivityBehavior.localTree(home: home).path == "/Users/samuel/dev/coucou")
        precondition(LiveActivityBehavior.grokExecutable(home: home).path == "/Users/samuel/.grok/bin/grok")
        let brief = LiveActivityBehavior.reviewBrief(version: "0.5.6", zipPath: "/tmp/Coucou-0.5.6.zip")
        precondition(brief.contains("original branch"))
        precondition(brief.contains(LiveActivityBehavior.originalBranch))
        precondition(brief.contains("/tmp/Coucou-0.5.6.zip"))
        precondition(brief.contains("Do not regress the local Coucou"))
        precondition(brief.contains("Do not replace /Applications/Coucou.app."))
        precondition(brief.contains("Do not push."))
        precondition(brief.contains("Then stop and wait."))
        precondition(!brief.contains("ditto"))
        let command = LiveActivityBehavior.reviewCommand(
            repo: "/Users/samuel/dev/coucou",
            grok: "/Users/samuel/.grok/bin/grok",
            brief: brief
        )
        precondition(command.contains("--permission-mode plan"))
        precondition(command.contains("--no-subagents"))
        precondition(command.contains("'/Users/samuel/.grok/bin/grok'"))
        precondition(command.contains("'/Users/samuel/dev/coucou'"))
        precondition(command.contains("--verbatim"))
        precondition(!command.contains("ditto"))
        precondition(!command.contains("git push"))
        precondition(!command.contains("git reset"))
        precondition(!command.contains("git merge"))
        precondition(!command.contains("git clean"))
        precondition(LiveActivityBehavior.shellQuote("/tmp/a b") == "'/tmp/a b'")
        precondition(LiveActivityBehavior.shellQuote("a'b") == "'a'\\''b'")

        let header = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "private var actions",
            until: "struct TabButton"
        )
        precondition(header.contains("speaker.wave.2"))
        precondition(header.contains("\"power\""))
        precondition(header.contains("NSApplication.shared.terminate"))
        precondition(header.contains("Quit"))
        precondition(header.contains("arrow.triangle.2.circlepath"))
        precondition(header.contains("lookForUpdate()"))
        precondition(header.contains("Check for update"))
        let speaker = header.range(of: "speaker.wave.2")
        let power = header.range(of: "\"power\"")
        let arrows = header.range(of: "arrow.triangle.2.circlepath")
        precondition(speaker != nil && power != nil && arrows != nil)
        precondition(speaker!.lowerBound < power!.lowerBound, "quit sits next to volume")
        precondition(power!.lowerBound < arrows!.lowerBound, "the two arrows sit beside quit")

        let look = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "func lookForUpdate()",
            until: "func askToApply"
        )
        precondition(look.contains("ReleaseProbe.latest"))
        precondition(look.contains("ReleaseProbe.downloadZip"))
        precondition(look.contains("askToApply"))
        precondition(!look.contains("applyDownloadedUpdate"), "finding the update does not install it")
        precondition(!look.contains("reviewDownloadedUpdate"), "finding the update does not open Grok")
        precondition(!look.contains("terminate"), "finding the update does not quit Coucou")
        precondition(!look.contains("ditto"), "finding the update does not unpack the zip")

        let ask = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "func askToApply",
            until: "func answerUpdatePrompt"
        )
        precondition(ask.contains("zipReady: true"))
        precondition(ask.contains("showUpdatePrompt"))
        precondition(ask.contains("original GitHub release"))
        precondition(ask.contains("asks Grok"))
        precondition(ask.contains("does not replace Coucou"))
        precondition(!ask.contains("replaces Coucou with this download"))
        precondition(!ask.contains("applyDownloadedUpdate"), "showing the prompt does not install the download")
        precondition(!ask.contains("reviewDownloadedUpdate"), "showing the prompt does not open Grok")
        precondition(!ask.contains("runModal"))
        precondition(!ask.contains("/Applications/Coucou.app"), "the prompt itself does not replace Coucou")
        precondition(!ask.contains("ditto"))

        let answer = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "func answerUpdatePrompt",
            until: "func reviewDownloadedUpdate"
        )
        precondition(answer.contains("asksGrok"))
        precondition(answer.contains("installsDownloadedApp"))
        let gate = answer.range(of: "asksGrok")
        let reviewCall = answer.range(of: "reviewDownloadedUpdate")
        precondition(gate != nil && reviewCall != nil)
        precondition(gate!.lowerBound < reviewCall!.lowerBound, "Update is chosen before Grok is opened")
        precondition(!answer.contains("applyDownloadedUpdate"))
        precondition(!answer.contains("ditto"))
        precondition(!answer.contains("terminate"))

        let card = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandRootView.swift",
            from: "struct UpdatePromptCard",
            until: "struct TabButton"
        )
        precondition(card.contains("\"Update\""))
        precondition(card.contains("\"Save for later\""))
        precondition(card.contains("answerUpdatePrompt(.update)"))
        precondition(card.contains("answerUpdatePrompt(.saveForLater)"))

        let installer = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "func reviewDownloadedUpdate",
            until: "func stagedZipURL"
        )
        precondition(installer.contains("reviewCommand"))
        precondition(installer.contains("do script"))
        precondition(installer.contains("Coucou was not replaced."))
        precondition(installer.contains("The download was not installed."))
        precondition(!installer.contains("ditto"))
        precondition(!installer.contains("terminate"))
        precondition(!installer.contains("/Applications/Coucou.app"))
        precondition(!installer.contains("applyDownloadedUpdate"))

        let hold = sourceSlice(
            file: "NotchBuddy/Sources/App/IslandWindowController.swift",
            from: "fsm.isHeldOpen",
            until: "voiceWoke"
        )
        precondition(hold.contains("updatePrompt"), "the update choice keeps the notch open")

        let check = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "func checkForUpdate()",
            until: "func openReleasePage"
        )
        precondition(!check.contains("downloadZip"), "opening Coucou does not download the release")
        precondition(!check.contains("askToApply"))

        let start = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "func start()",
            until: "func notePointer"
        )
        precondition(start.contains("checkForUpdate()"))
        precondition(!start.contains("lookForUpdate"), "opening Coucou does not download the release")
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
        let leaving = NookLayout.chargingWatts(milliamps: -2400, millivolts: 12000, charging: true)
        precondition(leaving == 0, "a negative current is the pack supplying the Mac, was \(leaving.map { String($0) } ?? "nil")")
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
        let discharging = NookLayout.measuredChargeWatts(
            batteryPowerMilliwatts: -3800,
            milliamps: nil,
            millivolts: nil,
            charging: true
        )
        precondition(discharging == 0, "a negative pack power is not a 3.8W charge")
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
        let packPower = NookLayout.measuredChargeWatts(
            batteryPowerMilliwatts: 27229,
            milliamps: 2148,
            millivolts: 12041,
            charging: true
        )
        precondition(
            packPower.map { Int(($0 * 1000).rounded()) } == 25864,
            "2148 mA at 12041 mV is the charge rate, not the 27229 mW telemetry, was \(packPower.map { String($0) } ?? "nil")"
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
        let fromTheCable = NookLayout.shownChargeWatts(inputMilliwatts: 13808, packWatts: 3.8)
        precondition(
            fromTheCable.map { Int(($0 * 1000).rounded()) } == 13808,
            "the corner shows the watts on the cable, not the 3.8W leaving the pack, was \(fromTheCable.map { String($0) } ?? "nil")"
        )
        precondition(NookLayout.shownChargeWatts(inputMilliwatts: nil, packWatts: 4.318) == 4.318, "a missing port reading keeps the pack watts")
        precondition(NookLayout.shownChargeWatts(inputMilliwatts: 0, packWatts: 4.3) == 4.3)
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
        precondition(probe.contains("IPDInputPower"), "the corner shows the watts coming in on the cable")
        precondition(probe.contains("shownChargeWatts"), "the cable watts are the number on the card")
        precondition(probe.contains("SystemPowerIn"), "the telemetry input is the fallback")
        precondition(probe.contains("BatteryPower"), "pack power remains the fallback")
        precondition(!probe.contains("\"Watts\""), "the adapter's rated watts are not the charge rate")
        precondition(line.contains("chargeSpeedText"), "the wattage is a different string")
        precondition(line.contains("batterySymbol"), "the battery indicator is missing")
        let clock = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "func startBatteryClock",
            until: "private func tick"
        )
        precondition(clock.contains("readBattery"), "the charge rate has its own read")
        precondition(clock.contains("10_000_000_000"), "the charge rate is read every 10 seconds")
        let tick = sourceSlice(
            file: "NotchBuddy/Sources/App/NookBoard.swift",
            from: "private func tick",
            until: "private func refreshMedia"
        )
        precondition(tick.contains("readBattery"), "a quiet notch tick still reads the charge rate sooner")
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
        precondition(
            SettingsNotchPreview.panelTakesThePress(settingsOpen: true, overDrawnIsland: false, overPanel: true) == false,
            "an open settings tab lets a click through the empty part of the notch"
        )
        precondition(
            SettingsNotchPreview.panelTakesThePress(settingsOpen: true, overDrawnIsland: true, overPanel: true),
            "the drawn notch still takes its own clicks while settings is open"
        )
        precondition(
            SettingsNotchPreview.panelTakesThePress(settingsOpen: false, overDrawnIsland: false, overPanel: true),
            "a closed settings window still lets the open notch take a press on the panel"
        )

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
        precondition(general.contains("HStack(alignment: .top"), "the lower settings sit in two columns")
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
        precondition(hover.contains("panelTakesThePress"), "the settings tabs stay clickable under the open notch")
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
