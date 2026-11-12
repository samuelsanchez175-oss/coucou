import AppKit
import SwiftUI
import ServiceManagement
import EventKit
import UniformTypeIdentifiers

private struct CoucouSettingsFaceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True only inside the settings window. The notch stays on Font size alone.
    var coucouSettingsFace: Bool {
        get { self[CoucouSettingsFaceKey.self] }
        set { self[CoucouSettingsFaceKey.self] = newValue }
    }
}

/// One face for Coucou text. Font size always applies. Settings font applies on the settings page only.
private struct CoucouFace: ViewModifier {
    @ObservedObject private var prefs = NookPreferences.shared
    @Environment(\.coucouSettingsFace) private var settingsPage
    var base: CGFloat
    var weight: Font.Weight = .regular
    var design: Font.Design = .default

    func body(content: Content) -> some View {
        content.font(.system(
            size: faceSize,
            weight: weight,
            design: design
        ))
    }

    private var faceSize: CGFloat {
        let notch = CoucouType.points(base, scale: prefs.coucouFontScale)
        guard settingsPage else { return notch }
        return notch * CGFloat(CoucouType.clamp(prefs.settingsFontScale))
    }
}

extension View {
    /// Settings font size. Callers that own a fixed frame grow it with `CoucouType.points`.
    func coucouFont(_ base: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(CoucouFace(base: base, weight: weight, design: design))
    }
}

func coucouBox(_ base: CGFloat) -> CGFloat {
    MainActor.assumeIsolated {
        CoucouType.points(base, scale: NookPreferences.shared.coucouFontScale)
    }
}

/// Settings-page frames. The notch keeps `coucouBox`, which ignores Settings font.
func settingsBox(_ base: CGFloat) -> CGFloat {
    MainActor.assumeIsolated {
        let prefs = NookPreferences.shared
        return CoucouType.points(base, scale: prefs.coucouFontScale)
            * CGFloat(CoucouType.clamp(prefs.settingsFontScale))
    }
}

/// Adjustment scales stay a short track. The form itself uses the window width.
private enum SettingsPage {
    /// Keeps each adjustment scale off the side of the page.
    static let scaleInset: CGFloat = 28
    static let scaleTrack: CGFloat = 220
}

enum CoucouSettingsTab: String, CaseIterable, Identifiable {
    case general, gestures, activities, nook, tray, drop, keys, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .gestures: return "Gestures"
        case .activities: return "Live Activities"
        case .nook: return "Nook"
        case .tray: return "Tray"
        case .drop: return "Drop Area"
        case .keys: return "Keys"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .gestures: return "hand.point.up.left.fill"
        case .activities: return "gauge.with.dots.needle.67percent"
        case .nook: return "lamp.desk.fill"
        case .tray: return "square.dashed"
        case .drop: return "arrow.down.doc.fill"
        case .keys: return "key.fill"
        case .about: return "ellipsis.circle.fill"
        }
    }
}

struct CoucouSettingsShell: View {
    @State private var tab: CoucouSettingsTab = .general
    @ObservedObject private var prefs = NookPreferences.shared

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .zIndex(1)
                .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            fontSizeControl
            Group {
                switch tab {
                case .general: GeneralSettingsPane()
                case .gestures: GestureSettingsPane()
                case .activities: LiveActivitySettingsPane()
                case .nook: NookSettingsPane()
                case .tray: WidthSettingsPane(
                    title: "Width:",
                    value: settingsSlider("trayWidth", prefs, \.trayWidth),
                    range: 4...30,
                    iconValue: settingsSlider("trayIconSize", prefs, \.trayIconSize),
                    iconRange: 36...140
                )
                case .drop: DropAreaSettingsPane()
                case .keys: SettingsView()
                case .about: AboutSettingsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            Spacer(minLength: 0)
        }
        .frame(
            minWidth: 1080,
            idealWidth: 1480,
            maxWidth: .infinity,
            minHeight: 520,
            idealHeight: 900,
            maxHeight: .infinity,
            alignment: .top
        )
        .environment(\.coucouSettingsFace, true)
        .coucouFont(13)
        .environment(\.coucouSettingsFace, true)
        .preferredColorScheme(.dark)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { postNotchPreview(tab) }
        .onChange(of: tab) { _, newTab in postNotchPreview(newTab) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let win = note.object as? NSWindow, win.title.hasPrefix("Settings") else { return }
            postNotchPreview(tab)
        }
    }

    /// The open settings tab keeps the matching notch page on screen.
    private func postNotchPreview(_ tab: CoucouSettingsTab) {
        NotificationCenter.default.post(name: .settingsNotchPreview, object: tab.rawValue)
    }

    /// Font size changes the notch and this page. Settings font changes this page only.
    private var fontSizeControl: some View {
        HStack(spacing: 8) {
            Text("Font size")
                .coucouFont(12, weight: .semibold)
            Button {
                stepFont(-0.1)
            } label: {
                Text("A−")
                    .coucouFont(14, weight: .semibold)
            }
            .buttonStyle(.bordered)
            .help("Smaller text")
            Text(fontSizePercent)
                .coucouFont(12, design: .monospaced)
                .frame(minWidth: settingsBox(48))
            Button {
                stepFont(0.1)
            } label: {
                Text("A+")
                    .coucouFont(18, weight: .semibold)
            }
            .buttonStyle(.bordered)
            .help("Larger text")
            Text("Settings font")
                .coucouFont(12, weight: .semibold)
                .padding(.leading, 16)
                .help("Only the settings page")
            Button {
                stepSettings(-0.1)
            } label: {
                Text("A−")
                    .coucouFont(14, weight: .semibold)
            }
            .buttonStyle(.bordered)
            .help("Smaller settings text")
            Text(settingsFontPercent)
                .coucouFont(12, design: .monospaced)
                .frame(minWidth: settingsBox(48))
            Button {
                stepSettings(0.1)
            } label: {
                Text("A+")
                    .coucouFont(18, weight: .semibold)
            }
            .buttonStyle(.bordered)
            .help("Larger settings text")
            Spacer(minLength: 16)
            LaunchAtLoginToggle()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fontSizePercent: String {
        "\(Int((prefs.coucouFontScale * 100).rounded()))%"
    }

    private var settingsFontPercent: String {
        "\(Int((prefs.settingsFontScale * 100).rounded()))%"
    }

    private func stepFont(_ delta: Double) {
        prefs.coucouFontScale = SettingsBoard.fontScale(prefs.coucouFontScale + delta)
        prefs.persist()
    }

    private func stepSettings(_ delta: Double) {
        prefs.settingsFontScale = SettingsBoard.fontScale(prefs.settingsFontScale + delta)
        prefs.persist()
    }

    private var tabBar: some View {
        ViewThatFits(in: .horizontal) {
            tabRow(Array(CoucouSettingsTab.allCases))
            VStack(alignment: .leading, spacing: settingsBox(4)) {
                tabRow(Array(CoucouSettingsTab.allCases.prefix(4)))
                tabRow(Array(CoucouSettingsTab.allCases.suffix(4)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// Each tile shares the window width. A second row appears when eight minimum tiles no longer fit.
    private func tabRow(_ items: [CoucouSettingsTab]) -> some View {
        HStack(spacing: settingsBox(4)) {
            ForEach(items) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: settingsBox(4)) {
                        Image(systemName: item.symbol)
                            .coucouFont(16)
                        Text(item.title)
                            .coucouFont(10)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, settingsBox(6))
                    .padding(.vertical, settingsBox(8))
                    .foregroundStyle(tab == item ? Color.accentColor : Color.secondary)
                    .background(tab == item ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(.interaction, RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .frame(minWidth: settingsBox(84), maxWidth: .infinity)
                .help(item.title)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func bind<T>(_ path: ReferenceWritableKeyPath<NookPreferences, T>) -> Binding<T> {
        Binding(get: { prefs[keyPath: path] }, set: { prefs[keyPath: path] = $0; prefs.persist() })
    }
}

// MARK: - General

private struct LaunchAtLoginToggle: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var status = ""

    var body: some View {
        HStack(spacing: 8) {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, on in setLaunch(on) }
            if !status.isEmpty {
                Text(status)
                    .coucouFont(11)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func setLaunch(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            status = ""
        } catch {
            status = error.localizedDescription
            launchAtLogin = !on
        }
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject private var prefs = NookPreferences.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    SettingsSection("Display") {
                        DisplayPicker()
                        Text("Show Coucou on each display you turn on. Turn the main display off to keep Coucou on the other screens only.")
                            .coucouFont(11)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    SettingsSection("Screens without a notch") {
                        Toggle("Show a handler", isOn: bind(\.handlerEnabled))
                        Text("A stand-in notch on a screen with no camera housing.")
                            .coucouFont(11)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        compactSlider("Width", value: settingsSlider("handlerWidth", prefs, \.handlerWidth), range: 40...220)
                        compactSlider("Height", value: settingsSlider("handlerHeight", prefs, \.handlerHeight), range: 16...64)
                        checkRow(title: "", "Transparent handler", bind(\.handlerTransparent),
                                 caption: "Will only show up on mouse hover.")
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                TerminalSettingsSection()
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

                HStack(alignment: .top, spacing: 16) {
                    SettingsSection("Notch") {
                        compactChoice("Show in fullscreen", selection: settingsChoice("showInFullscreen", prefs, \.showInFullscreen)) {
                            Text("On notched screens").tag("notched")
                            Text("Always").tag("always")
                            Text("Never").tag("never")
                        }
                        checkRow(title: "", "Prefer round buttons", bind(\.preferRoundButtons),
                                 caption: "Use capsules instead of rounded rectangles for buttons.")
                        checkRow(title: "", "Translucent notch background (experimental)", bind(\.translucentNotch), caption: nil)
                        checkRow(title: "", "Demo mode", bind(\.demoMode),
                                 caption: "Prevents Coucou from hiding when idle. Useful for screen recordings (this has no effect on non-notched screens).")
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSection("Notch size") {
                            Text("Fine tune the guess so it matches your notch.")
                                .coucouFont(11)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            compactSlider("Content padding", value: settingsSlider("contentPadding", prefs, \.contentPadding), range: 0...32)
                            compactSlider("Width", value: settingsSlider("notchWidthOffset", prefs, \.notchWidthOffset), range: -40...40)
                            compactSlider("Height", value: settingsSlider("notchHeightOffset", prefs, \.notchHeightOffset), range: -40...40)
                        }
                        NotchBehaviorSettings()
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func bind<T>(_ path: ReferenceWritableKeyPath<NookPreferences, T>) -> Binding<T> {
        Binding(get: { prefs[keyPath: path] }, set: { prefs[keyPath: path] = $0; prefs.persist() })
    }
}

private struct DisplayPicker: View {
    @ObservedObject private var state = AppState.shared

    private var options: [DisplaySettingOption] {
        DisplaySettingList.options(screens: NSScreen.screens.map { screen in
            DisplaySettingScreen(
                uuid: IslandWindowController.displayUUID(screen),
                name: screen.localizedName,
                hasNotch: screen.safeAreaInsets.top > 0
            )
        })
    }

    private var extras: [DisplaySettingOption] {
        Array(options.dropFirst())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Main display", isOn: Binding(
                get: { state.showOnMainDisplay },
                set: { state.showOnMainDisplay = $0 }
            ))
                .toggleStyle(.switch)
            ForEach(extras) { option in
                Toggle(option.title, isOn: extraBinding(option.id))
                    .toggleStyle(.switch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func extraBinding(_ id: String) -> Binding<Bool> {
        let uuid = String(id.dropFirst("display:".count))
        return Binding(
            get: { state.extraDisplays.contains(uuid) },
            set: { state.setExtraDisplay(uuid, on: $0) }
        )
    }
}

// MARK: - Gestures

private struct GestureSettingsPane: View {
    @ObservedObject private var prefs = NookPreferences.shared

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                SettingsSection("Notch") {
                    Toggle("Allow gestures when hovering the notch", isOn: bind(\.gesturesWhileHovering))
                    Toggle("Open/close notch with vertical gestures", isOn: bind(\.verticalGestures))
                    checkRow(title: "", "Always open on hover", bind(\.alwaysOpenOnHover),
                             caption: "This will disable some of Coucou's gestures.")
                    checkRow(
                        title: "",
                        "Haptic feedback",
                        hapticsOn,
                        caption: "A firm click when the pointer nears the edge of the notch. On by default."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSection("Media") {
                        Toggle("Control media with horizontal gestures", isOn: bind(\.horizontalMediaGestures))
                        Toggle("Invert media gestures actions", isOn: bind(\.invertMediaGestures))
                            .disabled(!SettingsBoard.invertGestureControlEnabled(horizontalOn: prefs.horizontalMediaGestures))
                        Text("If on, a left swipe will start the next song, if off, the previous one.")
                            .coucouFont(11)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    SettingsSection("Typing") {
                        checkRow(title: "", "Prevent from closing on mouse leave", bind(\.preventCloseOnMouseLeave), caption: nil)
                        checkRow(title: "", "Lock while typing", bind(\.lockWhileTyping), caption: nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var hapticsOn: Binding<Bool> {
        Binding(
            get: { SettingsBoard.hapticsOn(disableHaptics: prefs.disableHaptics) },
            set: { prefs.disableHaptics = SettingsBoard.disableHaptics(uiOn: $0); prefs.persist() }
        )
    }

    private func bind<T>(_ path: ReferenceWritableKeyPath<NookPreferences, T>) -> Binding<T> {
        Binding(get: { prefs[keyPath: path] }, set: { prefs[keyPath: path] = $0; prefs.persist() })
    }
}

// MARK: - Live activities

private struct LiveActivitySettingsPane: View {
    @ObservedObject private var prefs = NookPreferences.shared
    @ObservedObject private var hud = HudController.shared
    @State private var page = 0

    private var layout: LiveActivitySettingsPage { LiveActivityBehavior.settingsPage }

    var body: some View {
        SettingsScroller {
            liveActivityPage
        }
    }

    private var liveActivityPage: some View {
        VStack(spacing: 12) {
            Picker("Live activities", selection: $page) {
                Text(layout.pages[0]).tag(0)
                Text(layout.pages[1]).tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
            .fixedSize(horizontal: false, vertical: true)

            if page == 0 {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        SettingsSection("Show in the notch") {
                            ForEach(rowsBeforeTiming) { generalRow($0) }
                        }
                        SettingsSection("How long they stay") {
                            ForEach(timingRows) { generalRow($0) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    VStack(spacing: 16) {
                        SettingsSection("Interactivity") {
                            ForEach(rowsAfterTiming) { generalRow($0, showColumnTitle: false) }
                        }
                        SettingsSection("Media source") {
                            compactChoice("Media source", selection: settingsChoice("mediaSource", prefs, \.mediaSource)) {
                                Text("System").tag("system")
                                Text("Music").tag("music")
                                Text("Spotify").tag("spotify")
                            }
                        }
                        SettingsSection(layout.fullscreenTitle.trimmingCharacters(in: CharacterSet(charactersIn: ":"))) {
                            ForEach(layout.fullscreen) { item in
                                Toggle(isOn: fullscreenBinding(item.id)) {
                                    Label(item.title, systemImage: item.symbol ?? "circle")
                                }
                                .toggleStyle(.checkbox)
                            }
                            Text(layout.fullscreenCaption)
                                .coucouFont(11)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Chin", isOn: bind(\.chinEnabled))
                        .toggleStyle(.switch)
                    Text("The live activity drops under the notch. Off keeps the line in the bar on every display.")
                        .coucouFont(11)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 16) {
                        SettingsSection("Chin") {
                            secondChinColumn(
                                "Chin height",
                                value: settingsSlider("activityChinHeight", prefs, \.activityChinHeight),
                                range: 28...80,
                                caption: "On the main display, how far the live activity drops under the MacBook notch."
                            )
                            secondChinColumn(
                                "Chin width",
                                value: settingsSlider("activityChinWidth", prefs, \.activityChinWidth),
                                range: 140...360,
                                caption: "How wide that line is under the notch."
                            )
                        }
                        .disabled(!prefs.chinEnabled)
                        .frame(maxWidth: .infinity, alignment: .top)
                        SettingsSection("Second display") {
                            secondChinColumn(
                                "Chin height",
                                value: settingsSlider("activitySecondHeight", prefs, \.activitySecondHeight),
                                range: 22...120,
                                caption: "How tall the chin is on a display with no camera. The line stays in the bar."
                            )
                            secondChinColumn(
                                "Chin width",
                                value: settingsSlider("activityOpenWidth", prefs, \.activityOpenWidth),
                                range: 180...480,
                                caption: "How wide that chin is. It does not drop under a camera."
                            )
                        }
                        .disabled(!prefs.chinEnabled)
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            } else {
                SettingsSection("Activities") {
                    Text(layout.customizeCaption)
                        .coucouFont(11)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(layout.customize) { item in
                        Toggle(isOn: enabledBinding(item.id)) {
                            Label(item.title, systemImage: item.symbol ?? "circle")
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var rowsBeforeTiming: [LiveActivitySettingsRow] {
        guard let index = layout.general.firstIndex(where: \.showsValue) else { return layout.general }
        return Array(layout.general[..<index])
    }

    private var timingRows: [LiveActivitySettingsRow] {
        layout.general.filter(\.showsValue)
    }

    private var rowsAfterTiming: [LiveActivitySettingsRow] {
        guard let index = layout.general.firstIndex(where: \.showsValue) else { return [] }
        return Array(layout.general[layout.general.index(after: index)...])
    }

    @ViewBuilder
    private func generalRow(_ row: LiveActivitySettingsRow, showColumnTitle: Bool = true) -> some View {
        if row.showsValue {
            sliderRow(
                row.title,
                value: settingsSlider("inactivityTimeout", prefs, \.inactivityTimeout),
                range: 0...60,
                caption: row.caption
            )
        } else {
            VStack(alignment: HorizontalAlignment.leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if showColumnTitle, !row.title.isEmpty {
                        Text(row.title)
                            .frame(width: layout.labelColumn, alignment: .trailing)
                    }
                    Toggle(row.label, isOn: boolPreference(row.preference))
                        .toggleStyle(.checkbox)
                    Spacer(minLength: 0)
                }
                if let caption = row.caption {
                    indentedCaption(caption, underTitle: showColumnTitle && !row.title.isEmpty)
                }
                if row.preference == "hudReplacement" { hudNote }
            }
        }
    }

    @ViewBuilder
    private var hudNote: some View {
        if prefs.hudReplacement && !hud.keysCaptured {
            indentedCaption(hud.accessibilityOff
                ? "Accessibility is off, so the system banner still appears. Turn Accessibility on for Coucou, then the notch can replace it."
                : "The volume keys could not be captured, so the system banner still appears.")
            if SettingsBoard.showAccessibilitySettings(
                hudOn: prefs.hudReplacement,
                keysCaptured: hud.keysCaptured,
                accessibilityOff: hud.accessibilityOff
            ) {
                Button("Open Accessibility Settings") {
                    TerminalDesk.shared.askForAccessibility()
                }
                .padding(.leading, layout.labelColumn + 12)
            }
        }
    }

    private func indentedCaption(_ text: String, underTitle: Bool = false) -> some View {
        Text(text)
            .coucouFont(11)
            .foregroundStyle(.secondary)
            .padding(.leading, underTitle ? layout.labelColumn + 12 : 22)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func boolPreference(_ name: String) -> Binding<Bool> {
        switch name {
        case "liveActivitiesEnabled": return bind(\.liveActivitiesEnabled)
        case "hudReplacement": return bind(\.hudReplacement)
        case "hideActivitiesOnNoNotch": return bind(\.hideActivitiesOnNoNotch)
        case "interactiveActivities": return bind(\.interactiveActivities)
        case "quickPeek": return bind(\.quickPeek)
        case "unhideAutomatically": return bind(\.unhideAutomatically)
        case "showSongChange": return bind(\.showSongChange)
        default: return .constant(false)
        }
    }

    private func fullscreenBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { prefs.activities.first { $0.id == id }?.showInFullscreen ?? false },
            set: { prefs.setActivity(id: id, showInFullscreen: $0) }
        )
    }

    private func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { prefs.activities.first { $0.id == id }?.enabled ?? false },
            set: { prefs.setActivity(id: id, enabled: $0) }
        )
    }

    private func bind<T>(_ path: ReferenceWritableKeyPath<NookPreferences, T>) -> Binding<T> {
        Binding(get: { prefs[keyPath: path] }, set: { prefs[keyPath: path] = $0; prefs.persist() })
    }
}

// MARK: - Nook

private struct NookSettingsPane: View {
    @ObservedObject private var prefs = NookPreferences.shared
    @State private var selected = "calendar"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 20) {
                Toggle("Enable nook", isOn: bind(\.nookEnabled))
                Toggle("Show dividers between widgets", isOn: bind(\.widgetDividers))
                Spacer(minLength: 12)
                ActivePillsSettings()
            }
            caption("If disabled, clicking on the notch won't do anything.")
            widgetEditor
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var widgetEditor: some View {
        HStack(alignment: .top, spacing: 16) {
            List(selection: $selected) {
                ForEach(prefs.widgets) { widget in
                    HStack(spacing: 8) {
                        Image(systemName: NookWidgetInfo.symbol(widget.id))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(NookWidgetInfo.title(widget.id))
                            Text(NookWidgetInfo.comingSoon(widget.id) ? "Coming soon..." : "\(Int(nookWidthReadout(id: widget.id, stored: widget.cells, contentPadding: prefs.contentPadding))) cells")
                                .coucouFont(11)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: enabledBinding(widget.id))
                            .labelsHidden()
                            .disabled(NookWidgetInfo.comingSoon(widget.id))
                    }
                    .tag(widget.id)
                }
                .onMove { prefs.moveWidgets(from: $0, to: $1) }
            }
            .frame(width: 230)
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                enabledPreview
                GeometryReader { geo in
                    HStack(alignment: .top, spacing: 16) {
                        ScrollView {
                            widgetChoices
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: geo.size.height, alignment: .topLeading)
                        widgetAdjustments
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The pick list scrolls. The sliders stay in the column on the right.
    @ViewBuilder
    private var widgetChoices: some View {
        if selected == "calendar" {
            CalendarPickSettings()
        } else if let widget = prefs.widget(selected) {
            Text(NookWidgetInfo.title(widget.id))
                .coucouFont(14, weight: .semibold)
            if NookWidgetInfo.comingSoon(widget.id) {
                Text("Coming soon.")
                    .foregroundStyle(.secondary)
            } else if widget.id == "shortcuts" {
                ShortcutPickSettings()
            } else if widget.id == "quickApps" {
                QuickAppPickSettings()
            }
        }
    }

    @ViewBuilder
    private var widgetAdjustments: some View {
        let showsSliders = selected == "calendar"
            || (prefs.widget(selected).map { !NookWidgetInfo.comingSoon($0.id) } ?? false)
        if showsSliders {
            VStack(alignment: .leading, spacing: 12) {
                if selected == "calendar" {
                    CalendarWidgetSettings()
                } else if let widget = prefs.widget(selected) {
                    nookAdjustSlider(
                        "Width:",
                        value: cellsBinding(widget.id),
                        range: nookWidthRange(id: widget.id, contentPadding: prefs.contentPadding)
                    )
                    Text(nookWidthCaption)
                        .coucouFont(11)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(width: 320, alignment: .topLeading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var enabledPreview: some View {
        HStack(spacing: 8) {
            ForEach(prefs.widgets.filter(\.enabled)) { widget in
                VStack(spacing: 4) {
                    Image(systemName: NookWidgetInfo.symbol(widget.id))
                    Text(NookWidgetInfo.title(widget.id))
                        .coucouFont(11)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(widget.id == selected ? 0.14 : 0.06)))
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.35), lineWidth: 3))
    }

    private func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { prefs.widget(id)?.enabled ?? false },
            set: { prefs.setWidget(id: id, enabled: $0) }
        )
    }

    private func cellsBinding(_ id: String) -> Binding<Double> {
        Binding(
            get: { nookWidthReadout(id: id, stored: prefs.widget(id)?.cells ?? 1, contentPadding: prefs.contentPadding) },
            set: { proposed in
                let stored = prefs.widget(id)?.cells ?? 1
                guard let next = SettingsBoard.cellsFromSlider(
                    id: id, stored: stored, proposed: proposed, contentPadding: prefs.contentPadding
                ) else { return }
                prefs.setWidget(id: id, cells: next)
            }
        )
    }

    private func bind<T>(_ path: ReferenceWritableKeyPath<NookPreferences, T>) -> Binding<T> {
        Binding(get: { prefs[keyPath: path] }, set: { prefs[keyPath: path] = $0; prefs.persist() })
    }
}

private struct ShortcutPickSettings: View {
    @ObservedObject private var prefs = NookPreferences.shared
    @ObservedObject private var board = NookBoard.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shortcuts to show")
                .coucouFont(13, weight: .semibold)
            Text("Only the shortcuts you turn on appear in the notch. None are on until you choose them.")
                .coucouFont(11, weight: .regular)
                .foregroundStyle(Color.primary.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Refresh list") { Task { await board.refreshShortcutCatalog() } }
                Button("Select all") {
                    prefs.setShortcutPicks(NookShortcuts.selectAll(board.shortcutCatalog))
                }
                Button("Clear") { prefs.setShortcutPicks([]) }
            }
            if board.shortcutCatalog.isEmpty {
                Text(board.shortcutNote == NookShortcuts.loadFailed
                     ? NookShortcuts.loadFailed
                     : "No shortcuts on this Mac yet.")
                    .coucouFont(11, weight: .regular)
                    .foregroundStyle(Color.primary.opacity(0.82))
            }
            ForEach(NookShortcuts.sections(board.shortcutCatalog)) { section in
                if let title = section.title {
                    Text(title)
                        .coucouFont(12, weight: .semibold)
                }
                ForEach(section.shortcuts) { shortcut in
                    Toggle(shortcut.name, isOn: pickBinding(shortcut.identifier))
                }
            }
        }
        .task { await board.refreshShortcutCatalog() }
    }

    private func pickBinding(_ identifier: String) -> Binding<Bool> {
        Binding(
            get: { prefs.shortcutPicks.contains(identifier) },
            set: { on in
                prefs.setShortcutPicks(NookShortcuts.setPick(identifier, on: on, picks: prefs.shortcutPicks))
            }
        )
    }
}

private struct CalendarWidgetSettings: View {
    @ObservedObject private var prefs = NookPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let widget = prefs.widget("calendar") {
                nookAdjustSlider("Width:", value: Binding(
                    get: { nookWidthReadout(id: "calendar", stored: widget.cells, contentPadding: prefs.contentPadding) },
                    set: { proposed in
                        guard let next = SettingsBoard.cellsFromSlider(
                            id: "calendar", stored: widget.cells, proposed: proposed, contentPadding: prefs.contentPadding
                        ) else { return }
                        prefs.setWidget(id: "calendar", cells: next)
                    }
                ), range: nookWidthRange(id: "calendar", contentPadding: prefs.contentPadding))
                Text(nookWidthCaption)
                    .coucouFont(11)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            nookAdjustSlider(
                "Number of days behind:",
                value: settingsSlider("daysBehind", prefs, \.daysBehind),
                range: 0...30
            )
            nookAdjustSlider(
                "Number of days ahead:",
                value: settingsSlider("daysAhead", prefs, \.daysAhead),
                range: 0...30
            )
            Toggle("Show today's past events", isOn: bind(\.showPastEvents))
            Toggle("Show all-day events", isOn: bind(\.showAllDayEvents))
            Toggle("Show multi-day events", isOn: bind(\.showMultiDayEvents))
        }
    }

    private func bind<T>(_ path: ReferenceWritableKeyPath<NookPreferences, T>) -> Binding<T> {
        Binding(get: { prefs[keyPath: path] }, set: { prefs[keyPath: path] = $0; prefs.persist() })
    }
}

private struct QuickAppPickSettings: View {
    @ObservedObject private var prefs = NookPreferences.shared
    @ObservedObject private var board = NookBoard.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apps to show")
                .coucouFont(13, weight: .semibold)
            Text("Only the apps you turn on appear in the notch. None are on until you choose them.")
                .coucouFont(11, weight: .regular)
                .foregroundStyle(Color.primary.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Refresh list") { Task { await board.refreshQuickAppCatalog() } }
                Button("Select all") {
                    prefs.setQuickAppPicks(NookQuickApps.selectAll(board.quickAppCatalog))
                }
                Button("Clear") { prefs.setQuickAppPicks([]) }
            }
            if board.quickAppCatalog.isEmpty {
                Text(board.quickAppNote == NookQuickApps.loadFailed
                     ? NookQuickApps.loadFailed
                     : "No apps in Applications yet.")
                    .coucouFont(11, weight: .regular)
                    .foregroundStyle(Color.primary.opacity(0.82))
            }
            ForEach(board.quickAppCatalog) { app in
                Toggle(app.name, isOn: pickBinding(app.bundleID))
            }
        }
        .task { await board.refreshQuickAppCatalog() }
    }

    private func pickBinding(_ bundleID: String) -> Binding<Bool> {
        Binding(
            get: { prefs.quickAppPicks.contains(bundleID) },
            set: { on in
                prefs.setQuickAppPicks(NookQuickApps.setPick(bundleID, on: on, picks: prefs.quickAppPicks))
            }
        )
    }
}

@MainActor
private final class CalendarListModel: ObservableObject {
    struct Item: Identifiable {
        let id: String
        let title: String
        let color: Color
    }

    @Published var calendars: [Item] = []
    @Published var message = ""
    private let store = EKEventStore()

    func load() async {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            calendars = []
            message = CalendarBehavior.message
            return
        }
        let listed = store.calendars(for: .event).map { calendar in
            Item(id: calendar.calendarIdentifier, title: calendar.title, color: Color(cgColor: calendar.cgColor))
        }
        calendars = listed
        message = listed.isEmpty ? "No calendars found." : ""
    }
}

private struct CalendarPickSettings: View {
    @ObservedObject private var prefs = NookPreferences.shared
    @StateObject private var model = CalendarListModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendars to show:")
                .coucouFont(13, weight: .semibold)
            HStack {
                Button("Select All") {
                    prefs.enabledCalendarIDs = SettingsBoard.selectAllCalendars()
                    prefs.persist()
                }
                Button("Clear") {
                    prefs.enabledCalendarIDs = SettingsBoard.clearCalendars()
                    prefs.persist()
                }
            }
            if model.message == CalendarBehavior.message {
                Button(model.message) {
                    Task {
                        if await NookBoard.shared.askForCalendar() {
                            await model.load()
                        }
                    }
                }
                .buttonStyle(.plain)
                .coucouFont(11)
                .foregroundStyle(.secondary)
            } else if !model.message.isEmpty {
                Text(model.message).coucouFont(11).foregroundStyle(.secondary)
            }
            ForEach(model.calendars) { item in
                Toggle(isOn: calendarBinding(item.id)) {
                    HStack(spacing: 6) {
                        Circle().fill(item.color).frame(width: 8, height: 8)
                        Text(item.title)
                    }
                }
            }
        }
        .task { await model.load() }
    }

    private func calendarBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: {
                guard let chosen = prefs.enabledCalendarIDs else { return true }
                return chosen.contains(id)
            },
            set: { on in
                prefs.enabledCalendarIDs = SettingsBoard.setCalendar(
                    id, on: on, selection: prefs.enabledCalendarIDs, known: model.calendars.map(\.id)
                )
                prefs.persist()
            }
        )
    }
}

// MARK: - Drop area

private struct DropAreaSettingsPane: View {
    @ObservedObject private var prefs = NookPreferences.shared
    @State private var tempoButton = TapTempo.Button()
    @State private var songReadout: SongReadout?
    @State private var songName = ""
    @State private var songNote = ""
    @State private var readingSong = false
    @State private var songTargeted = false
    @State private var readGeneration = 0
    @State private var songChoices: [URL] = []
    @State private var showingChoices = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsSection("Drop width") {
                    sliderRow(
                        "Width:",
                        value: settingsSlider("dropAreaWidth", prefs, \.dropAreaWidth),
                        range: 4...30,
                        caption: "How wide the drop area is beside the notch. A higher number makes it wider. 16 by default."
                    )
                }
                HStack(alignment: .top, spacing: 16) {
                    SettingsSection("Music") {
                        checkRow(
                            title: "",
                            "Split songs into stems",
                            bind(\.splitSongsIntoStems),
                            caption: "A song dropped on the tray is added to the open Logic Pro project and split into vocals, drums, bass, guitar, piano, and the other instruments. On by default. Logic Pro has to be installed. The project that is already open stays open. Other files stay in the tray. Drag a file onto AirDrop to send it."
                        )
                        Text("The plus tab still sends a file to Mochi.")
                            .coucouFont(12)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSection("Tempo") {
                            tempoRow
                        }
                        SettingsSection("Song info") {
                            songInfoRow
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var tempoRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: registerTap) {
                Text(tempoButton.shown.map { "\($0) BPM" } ?? "Tap tempo")
                    .monospacedDigit()
                    .frame(minWidth: 92)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(tempoButton.shown.map { "Tap tempo, \($0) BPM" } ?? "Tap tempo")
            Text("Tap along with the song. The tempo shows on the button after two taps. A pause starts the count over, and the last tempo stays until the next one.")
                .coucouFont(11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var songInfoRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            songDropBox
            if let songReadout {
                readoutStrip(songReadout)
            }
            if !songName.isEmpty {
                Text(songName)
                    .coucouFont(11)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !songNote.isEmpty {
                Text(songNote)
                    .coucouFont(11)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Drop a song on this box, or choose one. BPM, key, Camelot code, and energy show here. Nothing opens in a browser.")
                .coucouFont(11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var songDropBox: some View {
        VStack(spacing: 8) {
            if readingSong {
                Text("Reading the song…")
                    .coucouFont(13)
            } else {
                Text("Drop a song here")
                    .coucouFont(13, weight: .medium)
                Button(showingChoices ? "Hide songs" : "Choose a song") {
                    if showingChoices {
                        showingChoices = false
                    } else {
                        songChoices = SongChooser.songs(in: SongChooser.defaultFolders())
                        showingChoices = true
                    }
                }
                .buttonStyle(.bordered)
                if showingChoices {
                    if songChoices.isEmpty {
                        Text("No songs in Music, Downloads, or the Desktop.")
                            .coucouFont(12)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(songChoices, id: \.path) { url in
                            Button(url.deletingPathExtension().lastPathComponent) {
                                showingChoices = false
                                acceptSong(url)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(songTargeted ? Color.accentColor : Color.secondary.opacity(0.7))
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            acceptSong(url)
            return true
        } isTargeted: { songTargeted = $0 }
    }

    private func readoutStrip(_ readout: SongReadout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                fact(readout.bpm.map(String.init) ?? "Unavailable", "BPM")
                fact(readout.keyName, "Key", colorHex: SongFacts.keyColorHex(keyName: readout.keyName))
                fact(readout.camelot, "Camelot")
                fact("\(readout.energy)", "Energy")
            }
            scaleNotes(SongFacts.scaleNotes(keyName: readout.keyName))
        }
    }

    private func fact(_ value: String, _ label: String, colorHex: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .coucouFont(17, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(colorHex.map { Color(hex: $0) } ?? Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .coucouFont(11)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func scaleNotes(_ notes: [String]) -> some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .coucouFont(17, weight: .semibold, design: .rounded)
                            .foregroundStyle(Color(hex: SongFacts.noteColorHex(note)))
                            .lineLimit(1)
                    }
                }
                Text("Scale")
                    .coucouFont(11)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func registerTap() {
        _ = tempoButton.tap(at: Date().timeIntervalSinceReferenceDate)
    }

    private func acceptSong(_ url: URL) {
        readGeneration += 1
        let generation = readGeneration
        guard SongChooser.accepted(ok: true, path: url.path) != nil else {
            readingSong = false
            songReadout = nil
            songName = ""
            songNote = SongChooser.rejectionNote(path: url.path) ?? ""
            return
        }
        readingSong = true
        songNote = ""
        songName = url.deletingPathExtension().lastPathComponent
        let captured = url
        let accessing = url.startAccessingSecurityScopedResource()
        Task {
            let readout = await Task.detached(priority: .userInitiated) {
                SongFacts.read(url: captured)
            }.value
            if accessing { captured.stopAccessingSecurityScopedResource() }
            guard generation == readGeneration else { return }
            readingSong = false
            if let readout {
                songReadout = readout
                songNote = ""
            } else {
                songReadout = nil
                songNote = "That song could not be read."
            }
        }
    }

    private func bind<T>(_ path: ReferenceWritableKeyPath<NookPreferences, T>) -> Binding<T> {
        Binding(get: { prefs[keyPath: path] }, set: { prefs[keyPath: path] = $0; prefs.persist() })
    }
}

private struct WidthSettingsPane: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    @Binding var iconValue: Double
    let iconRange: ClosedRange<Double>

    var body: some View {
        SettingsScroller {
            HStack(alignment: .top, spacing: 16) {
                SettingsSection("Tray width") {
                    fillingScale(
                        title,
                        value: $value,
                        range: range,
                        caption: "How wide the tray is beside the notch. A higher number makes the tray wider. 12 by default."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .top)
                SettingsSection("Icon size") {
                    fillingScale(
                        "Icon size:",
                        value: $iconValue,
                        range: iconRange,
                        caption: "How large each file icon is in the tray. A higher number makes the icon bigger. 100 by default."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The scale uses the column. A fixed track overflowed the window as the settings font changed.
    private func fillingScale(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>, caption: String
    ) -> some View {
        let snapped = Binding<Double>(
            get: { value.wrappedValue },
            set: { value.wrappedValue = $0.rounded() }
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .coucouFont(13)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text("\(Int(value.wrappedValue.rounded()))")
                    .coucouFont(12, design: .monospaced)
                    .lineLimit(1)
            }
            Slider(value: snapped, in: range)
                .frame(maxWidth: .infinity)
            Text(caption)
                .coucouFont(11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct AboutMaintenance: View {
    @ObservedObject private var prefs = NookPreferences.shared
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Reset all settings") {
                prefs.reset()
                status = "Notch settings reset. API keys were kept."
            }
            .buttonStyle(.bordered)
            Text("This will reset the notch, gestures, activities, nook, tray, and drop area. API keys stay.")
                .coucouFont(11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Quit Coucou") { NSApp.terminate(nil) }
                .buttonStyle(.bordered)
            Text("You can also right click the menu bar icon.")
                .coucouFont(11)
                .foregroundStyle(.secondary)
            if !status.isEmpty {
                Text(status).coucouFont(11).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }
}

private struct AboutSettingsPane: View {
    @ObservedObject private var board = NookBoard.shared

    var body: some View {
        let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        VStack(alignment: .leading, spacing: 8) {
            Text("Coucou")
                .coucouFont(18, weight: .semibold)
            Text("Version \(installed)")
                .foregroundStyle(.secondary)
            Text("Notch companion. The notch, gesture, activity, nook, tray, and drop settings on the other tabs follow the same adjustments as NotchNook. Chat keys live under Keys.")
                .coucouFont(12)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(LiveActivityBehavior.updateSentence(
                installed: installed,
                offered: board.offeredVersion,
                checked: board.updateChecked,
                checking: board.updateChecking
            ))
            .coucouFont(11)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Button("Check for a newer version") { board.checkForUpdate() }
                .disabled(board.updateChecking)
            if LiveActivityBehavior.updateIsAvailable(installed: installed, offered: board.offeredVersion) {
                Button("Open the release page") { board.openReleasePage() }
            }
            Text("Looks up the published Coucou release and does not download it. Coucou checks once when it opens, and again when you press this.")
                .coucouFont(11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            AboutMaintenance()
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Rows

private func compactChoice<Content: View>(
    _ title: String, selection: Binding<String>, @ViewBuilder content: () -> Content
) -> some View where Content: View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .coucouFont(12)
        Picker(title, selection: selection, content: content)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func compactSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
    let snapped = Binding<Double>(
        get: { value.wrappedValue },
        set: { value.wrappedValue = $0.rounded() }
    )
    return HStack(spacing: 8) {
        Text(title)
            .coucouFont(12)
            .lineLimit(2)
            .frame(width: max(88, settingsBox(108)), alignment: .leading)
        Slider(value: snapped, in: range)
        Text("\(Int(value.wrappedValue.rounded()))")
            .coucouFont(12, design: .monospaced)
            .lineLimit(1)
            .frame(width: max(32, settingsBox(36)), alignment: .trailing)
    }
}

private func labeledRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(title)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: max(160, settingsBox(210)), alignment: .trailing)
        content()
        Spacer(minLength: 0)
    }
}

private func checkRow(title: String, _ label: String, _ isOn: Binding<Bool>, caption: String?) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: max(160, settingsBox(210)), alignment: .trailing)
            }
            Toggle(label, isOn: isOn)
            Spacer(minLength: 0)
        }
        if let caption {
            Text(caption)
                .coucouFont(11)
                .foregroundStyle(.secondary)
                .padding(.leading, title.isEmpty ? 22 : max(160, settingsBox(210)) + 12)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private let nookWidthCaption = "Width is measured in cells. One cell is one step on the nook grid. Turning on another widget makes the nook wider. That width stays up until a widget is turned off."

private func nookWidthRange(id: String, contentPadding: Double) -> ClosedRange<Double> {
    let floor = NookLayout.fittedCells(id: id, cells: 1, contentPadding: CGFloat(contentPadding))
    let lower = min(16, max(1, floor))
    return Double(lower)...16
}

private func nookWidthReadout(id: String, stored: Int, contentPadding: Double) -> Double {
    Double(NookLayout.fittedCells(id: id, cells: stored, contentPadding: CGFloat(contentPadding)))
}

private func settingsSlider(
    _ name: String, _ prefs: NookPreferences, _ path: ReferenceWritableKeyPath<NookPreferences, Double>
) -> Binding<Double> {
    Binding(
        get: { prefs[keyPath: path] },
        set: {
            prefs[keyPath: path] = SettingsBoard.commit(slider: name, value: $0) ?? $0
            prefs.persist()
        }
    )
}

private func settingsChoice(
    _ name: String, _ prefs: NookPreferences, _ path: ReferenceWritableKeyPath<NookPreferences, String>
) -> Binding<String> {
    Binding(
        get: { prefs[keyPath: path] },
        set: {
            let current = prefs[keyPath: path]
            prefs[keyPath: path] = SettingsBoard.commitChoice(name, $0) ?? current
            prefs.persist()
        }
    )
}

/// One chin scale. It fills the column it sits in.
private func secondChinColumn(
    _ title: String, value: Binding<Double>, range: ClosedRange<Double>, caption: String
) -> some View {
    let snapped = Binding<Double>(
        get: { value.wrappedValue },
        set: { value.wrappedValue = $0.rounded() }
    )
    return VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
            Text(title)
                .coucouFont(13)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(Int(value.wrappedValue.rounded()))")
                .coucouFont(12, design: .monospaced)
                .lineLimit(1)
        }
        Slider(value: snapped, in: range)
        Text(caption)
            .coucouFont(11)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .top)
}

/// A slider that fits the Nook adjustment column. The label and value share one line.
private func nookAdjustSlider(
    _ title: String, value: Binding<Double>, range: ClosedRange<Double>
) -> some View {
    let snapped = Binding<Double>(
        get: { value.wrappedValue },
        set: { value.wrappedValue = $0.rounded() }
    )
    return VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
            Text(title)
                .coucouFont(13)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text("\(Int(value.wrappedValue.rounded()))")
                .coucouFont(12, design: .monospaced)
                .lineLimit(1)
        }
        Slider(value: snapped, in: range)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private func sliderRow(
    _ title: String, value: Binding<Double>, range: ClosedRange<Double>, caption: String? = nil
) -> some View {
    let snapped = Binding<Double>(
        get: { value.wrappedValue },
        set: { value.wrappedValue = $0.rounded() }
    )
    let labelWidth = max(140, settingsBox(180))
    let valueWidth = max(36, settingsBox(36))
    return VStack(spacing: 4) {
        HStack(spacing: 12) {
            Spacer(minLength: SettingsPage.scaleInset)
            Text(title)
                .coucouFont(13)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: labelWidth, alignment: .trailing)
            Color.clear
                .frame(width: SettingsPage.scaleTrack, height: max(28, settingsBox(28)))
                .overlay {
                    Slider(value: snapped, in: range)
                }
                .clipped()
            Text("\(Int(value.wrappedValue.rounded()))")
                .coucouFont(12, design: .monospaced)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: valueWidth, alignment: .trailing)
            Spacer(minLength: SettingsPage.scaleInset)
        }
        if let caption {
            HStack(spacing: 12) {
                Spacer(minLength: SettingsPage.scaleInset)
                Color.clear.frame(width: labelWidth)
                Text(caption)
                    .coucouFont(11)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: SettingsPage.scaleTrack)
                    .fixedSize(horizontal: false, vertical: true)
                Color.clear.frame(width: valueWidth)
                Spacer(minLength: SettingsPage.scaleInset)
            }
        }
    }
    .fixedSize(horizontal: false, vertical: true)
}

/// Long settings pages scroll. A short page stays at the top of the window.
private struct SettingsScroller<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
        }
        .defaultScrollAnchor(.top)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    private let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .coucouFont(13, weight: .semibold)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private func caption(_ text: String) -> some View {
    Text(text)
        .coucouFont(11)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
}
