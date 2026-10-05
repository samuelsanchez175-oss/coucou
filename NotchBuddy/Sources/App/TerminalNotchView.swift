import AppKit
import SwiftUI

/// The four colored terminal faces and the prompt that used to be the integration grid.
struct TerminalClusterView: View {
    @ObservedObject private var desk = TerminalDesk.shared

    private let columns = [
        GridItem(.fixed(TerminalBehavior.faceColumn), spacing: TerminalBehavior.faceColumnGap, alignment: .center),
        GridItem(.fixed(TerminalBehavior.faceColumn), spacing: TerminalBehavior.faceColumnGap, alignment: .center)
    ]

    var body: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(desk.slots) { slot in
                    TerminalFaceButton(slot: slot, desk: desk)
                        .frame(width: TerminalBehavior.faceColumn, alignment: .center)
                }
            }
            .frame(width: TerminalBehavior.faceGridWidth, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
            AttachBlobButton(desk: desk)
            if let askingID = desk.askingID {
                AttachAskList(desk: desk, slotID: askingID)
            } else {
                VStack(spacing: 6) {
                    TerminalPromptField(
                        text: $desk.draft,
                        ghost: desk.ghost,
                        placeholder: placeholder,
                        onSubmit: { desk.send() },
                        onAcceptWord: { desk.acceptNextWord() },
                        onAcceptAll: { desk.acceptAll() },
                        onWake: { desk.wakeCotypist() },
                        onEscape: { _ = desk.consumeEscape() },
                        onFocus: { desk.promptFocused = $0 }
                    )
                    .frame(height: desk.draft.contains("\n") ? 44 : 24)
                    if desk.accessibilityOff {
                        Button("Accessibility is off") { desk.askForAccessibility() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "#F5A524"))
                            .help("Opens Accessibility settings so Coucou can read Terminal and type into it.")
                    } else if desk.sendFailed {
                        Text("Could not send")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: "#F4505E"))
                    } else if let note = desk.selected.flatMap({ desk.notes[$0.id] }) {
                        Text(note)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: "#A7ABB3"))
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                TerminalPageLockButton(desk: desk)
                BatterySpeedLine()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholder: String {
        let name = desk.selected.map { desk.displayName($0.id) } ?? "Terminal 1"
        return "Write to \(TerminalBehavior.shortTitle(name, fallback: "Terminal"))"
    }
}

struct TerminalFaceButton: View {
    let slot: TerminalSlot
    @ObservedObject var desk: TerminalDesk

    var body: some View {
        let selected = desk.selectedID == slot.id
        let face = desk.faces[slot.id] ?? .idle
        let reading = behaviorFace(face)
        let name = TerminalBehavior.shortTitle(desk.displayName(slot.id), fallback: slot.name)
        let phrase = TerminalBehavior.statusPhrase(for: reading)
        Button {
            switch TerminalBehavior.blobClick(slotID: slot.id, selectedID: desk.selectedID) {
            case .focus:
                desk.cancelAsk()
                desk.openOrFocus(slot.id)
            case .askAttach:
                desk.beginAsk(slot.id)
            }
        } label: {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let level = TerminalBehavior.heartbeatLevel(
                    seconds: context.date.timeIntervalSinceReferenceDate,
                    bpm: TerminalBehavior.heartbeatBPM(for: reading)
                )
                VStack(spacing: 2) {
                    MiniBotCanvasView(task: faceTask(slot, face))
                        .frame(width: 28 / 0.6, height: 28 / 0.6)
                        .frame(width: 28, height: 28)
                        .opacity(0.78 + 0.22 * level)
                        .overlay {
                            Circle()
                                .stroke(
                                    Color(hex: TerminalBehavior.blobLightHex(slotHex: slot.color, face: reading)),
                                    lineWidth: reading == .idle ? 0 : 2.5
                                )
                                .opacity(reading == .idle ? 0 : 0.45 + 0.55 * level)
                                .padding(1)
                        }
                        .overlay {
                            Circle()
                                .stroke(
                                    ringColor(selected: selected, asking: desk.askingID == slot.id, dropping: desk.dropSlotID == slot.id),
                                    lineWidth: desk.dropSlotID == slot.id ? 2.5 : 1.5
                                )
                                .padding(1)
                        }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: TerminalBehavior.statusColorHex(for: reading)))
                            .frame(width: 6, height: 6)
                            .scaleEffect(0.85 + 0.45 * level)
                            .opacity(0.75 + 0.25 * level)
                            .accessibilityHidden(true)
                        Text(name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(selected ? Color.white : Color(hex: "#C8CCD2"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .allowsTightening(true)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .help("\(name). \(phrase). Opens this terminal in the \(TerminalBehavior.cornerPhrase(slot.id)). Drop a file here to attach it to this chat.")
        .accessibilityLabel("\(name). \(phrase). Opens in the \(TerminalBehavior.cornerPhrase(slot.id)). Drop a file to attach it.")
    }

    private func ringColor(selected: Bool, asking: Bool, dropping: Bool) -> Color {
        if dropping { return Color(hex: slot.color) }
        if asking { return Color(hex: "#F5A524") }
        return Color.white.opacity(selected ? 0.9 : 0)
    }
}

/// Bottom of the terminal tile. While on, leaving the pointer does not close this page for 20 seconds.
struct TerminalPageLockButton: View {
    @ObservedObject var desk: TerminalDesk

    var body: some View {
        Group {
            if desk.pageLocked, desk.lockLeftAt != nil {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    control(amount: openAmount(at: context.date))
                }
            } else {
                control(amount: desk.pageLocked ? 0 : 1)
            }
        }
    }

    private func openAmount(at date: Date) -> Double {
        TerminalBehavior.lockOpenAmount(
            locked: desk.pageLocked,
            leftAt: desk.lockLeftAt?.timeIntervalSinceReferenceDate,
            now: date.timeIntervalSinceReferenceDate
        )
    }

    private func control(amount: Double) -> some View {
        let holding = desk.pageLocked
        return Button {
            desk.togglePageLock()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Image(systemName: "lock.fill")
                        .opacity(1 - amount)
                    Image(systemName: "lock.open.fill")
                        .opacity(amount)
                }
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
                Text(holding ? "Holding this page open" : "Hold this page open")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: holding ? "#F5F6F8" : "#C8CCD2"))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(holding
              ? "The pointer can leave for 20 seconds. The lock opens during the last 3 seconds, then this page can close."
              : "Keeps this page open for 20 seconds after the pointer leaves. Off until you turn it on.")
        .accessibilityLabel(holding ? "Holding this page open" : "Hold this page open")
        .accessibilityHint("Stays open for 20 seconds after the pointer leaves. The lock opens during the last 3 seconds.")
    }
}

/// Battery percentage and charging speed, trailing the lock on the right card.
struct BatterySpeedLine: View {
    @ObservedObject private var board = NookBoard.shared

    var body: some View {
        if let percent = board.batteryPercent {
            let shown = min(100, max(0, percent))
            let watts = NookLayout.displayedSpeedWatts(
                charging: board.batteryCharging,
                packWatts: board.batteryWatts,
                supplyWatts: board.supplyWatts
            )
            let speed = watts.flatMap(NookLayout.chargeSpeedText)
            let chargingNow = (watts ?? 0) > 0
            HStack(spacing: 4) {
                Image(systemName: NookLayout.batterySymbol(percent: shown, charging: chargingNow))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "#C8CCD2"))
                    .accessibilityHidden(true)
                Text("\(shown)%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "#F5F6F8"))
                    .monospacedDigit()
                if let watts, let speed {
                    Text(speed)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: NookLayout.chargeSpeedColorHex(watts: watts)))
                        .monospacedDigit()
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .help(speed == nil ? "Battery percentage." : "Battery percentage and charging speed.")
            .accessibilityElement(children: .combine)
            .accessibilityLabel(speed.map { "\(shown) percent, \($0)" } ?? "\(shown) percent")
        }
    }
}

/// Stays unselected. Asks which already-open terminal the next free color should wire to.
struct AttachBlobButton: View {
    @ObservedObject var desk: TerminalDesk

    var body: some View {
        Button {
            desk.beginAskForFreeSlot()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .stroke(Color.white.opacity(0.45), lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.9))
                    }
                Text("Attach to an open terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "#C8CCD2"))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 22)
        }
        .buttonStyle(.plain)
        .help("Asks which Terminal window that is already open this color should follow. The face then shows Idle, Working, or Waiting.")
        .accessibilityLabel("Attach to an open terminal")
    }
}

struct AttachAskList: View {
    @ObservedObject var desk: TerminalDesk
    let slotID: String

    var body: some View {
        let name = desk.slots.first { $0.id == slotID }?.name ?? "Terminal"
        let windows = desk.windowsForAsk(slotID)
        VStack(alignment: .leading, spacing: 3) {
            Text("Attach \(name)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
            Text(windows.isEmpty ? "No terminal is open." : "Pick a terminal that is already open.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(hex: "#A7ABB3"))
                .lineLimit(1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(windows) { window in
                        let title = TerminalBehavior.choiceTitle(window.title)
                        Button(title) { desk.attachToOpenWindow(slotID, window.id) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                            .help(title)
                            .accessibilityLabel("Attach to \(title)")
                    }
                    Button("New window") { desk.attachNewWindow(slotID) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .help("Opens a new Terminal window for this color.")
                    Button("Cancel") { desk.cancelAsk() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: "#A7ABB3"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }
            }
            .frame(height: 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 64)
    }
}

struct CompactTerminalFaces: View {
    @ObservedObject private var desk = TerminalDesk.shared

    var body: some View {
        let cols = [GridItem(.fixed(12), spacing: 2), GridItem(.fixed(12), spacing: 2)]
        LazyVGrid(columns: cols, spacing: 3) {
            ForEach(desk.slots) { slot in
                let face = desk.faces[slot.id] ?? .idle
                let reading = behaviorFace(face)
                let name = TerminalBehavior.shortTitle(desk.displayName(slot.id), fallback: slot.name)
                let phrase = TerminalBehavior.statusPhrase(for: reading)
                Button {
                    desk.armSelection(slot.id)
                    switch TerminalBehavior.blobClick(slotID: slot.id, selectedID: desk.selectedID) {
                    case .focus:
                        desk.cancelAsk()
                        desk.openOrFocus(slot.id)
                    case .askAttach:
                        desk.beginAsk(slot.id)
                    }
                } label: {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        let level = TerminalBehavior.heartbeatLevel(
                            seconds: context.date.timeIntervalSinceReferenceDate,
                            bpm: TerminalBehavior.heartbeatBPM(for: reading)
                        )
                        MiniBotCanvasView(task: faceTask(slot, face))
                            .frame(width: 12 / 0.6, height: 12 / 0.6)
                            .frame(width: 12, height: 12)
                            .opacity(0.72 + 0.28 * level)
                            .overlay {
                                Circle()
                                    .stroke(
                                        Color(hex: TerminalBehavior.blobLightHex(slotHex: slot.color, face: reading)),
                                        lineWidth: reading == .idle ? 0 : 1.5
                                    )
                                    .opacity(reading == .idle ? 0 : 0.45 + 0.55 * level)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(Color(hex: TerminalBehavior.statusColorHex(for: reading)))
                                    .frame(width: TerminalBehavior.collapsedStatusLight, height: TerminalBehavior.collapsedStatusLight)
                                    .offset(x: TerminalBehavior.collapsedStatusShift, y: TerminalBehavior.collapsedStatusShift)
                                    .accessibilityHidden(true)
                            }
                    }
                }
                .buttonStyle(.plain)
                .help("\(name). \(phrase). Opens this terminal in the \(TerminalBehavior.cornerPhrase(slot.id)).")
                .accessibilityLabel("\(name). \(phrase). Opens in the \(TerminalBehavior.cornerPhrase(slot.id)).")
            }
        }
        .frame(width: TerminalBehavior.compactSide, height: TerminalBehavior.compactSide)
    }
}

struct TerminalSettingsSection: View {
    @ObservedObject private var desk = TerminalDesk.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Terminals")
                .font(.system(size: 13, weight: .semibold))
            Text("Green is the top left, yellow the top right, purple the bottom left, and red the bottom right. Each one opens in that corner, and the little cuddler matches that terminal. The name is two or three words from the terminal, short enough to read whole. The dot is orange when idle, blue when a new response is available, and purple when it needs your input. Hold this page open keeps it up for 20 seconds after the pointer leaves, and the lock opens during the last 3 seconds. Drop a file on a color to attach it to that chat. An empty folder uses your home folder.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(desk.slots) { slot in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: slot.color)).frame(width: 8, height: 8)
                        TextField("Name before a window is open", text: nameBinding(slot.id))
                            .textFieldStyle(.roundedBorder)
                    }
                    if let live = desk.titles[slot.id], !live.isEmpty {
                        Text("Window name: \(live)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 6) {
                        TextField("Starting folder", text: folderBinding(slot.id))
                            .textFieldStyle(.roundedBorder)
                        Button("Choose Folder") { desk.chooseFolder(slot.id) }
                    }
                    Picker("Open window", selection: windowBinding(slot.id)) {
                        Text("New window").tag(0)
                        ForEach(desk.openWindows, id: \.id) { window in
                            Text(window.title.isEmpty ? "Terminal" : window.title).tag(window.id)
                        }
                    }
                }
            }
        }
        .onAppear { desk.start() }
    }

    private func nameBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { desk.slots.first { $0.id == id }?.name ?? "" },
            set: { desk.setName(id, $0) }
        )
    }

    private func folderBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { desk.slots.first { $0.id == id }?.folder ?? "" },
            set: { desk.setFolder(id, $0) }
        )
    }

    private func windowBinding(_ id: String) -> Binding<Int> {
        Binding(
            get: { desk.slots.first { $0.id == id }?.windowID ?? 0 },
            set: { desk.setWindow(id, $0 == 0 ? nil : $0) }
        )
    }
}

private func behaviorFace(_ face: TerminalFace) -> TerminalBehavior.Face {
    switch face {
    case .idle: return .idle
    case .working: return .working
    case .waiting: return .waiting
    }
}

private func faceTask(_ slot: TerminalSlot, _ face: TerminalFace) -> AgentTask {
    AgentTask(
        id: "terminal-\(slot.id)",
        name: slot.name,
        color: slot.color,
        state: face.botState,
        steps: [],
        source: .agent,
        isIntegration: true
    )
}

struct TerminalPromptField: NSViewRepresentable {
    @Binding var text: String
    var ghost: String
    var placeholder: String
    var onSubmit: () -> Void
    var onAcceptWord: () -> Void
    var onAcceptAll: () -> Void
    var onWake: () -> Void
    var onEscape: () -> Void
    var onFocus: (Bool) -> Void

    func makeNSView(context: Context) -> TerminalPromptNSTextView {
        let view = TerminalPromptNSTextView()
        view.delegate = context.coordinator
        view.handler = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.font = .systemFont(ofSize: 12)
        view.textColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        view.insertionPointColor = .white
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.textContainerInset = NSSize(width: 2, height: 3)
        view.string = text
        return view
    }

    func updateNSView(_ view: TerminalPromptNSTextView, context: Context) {
        context.coordinator.parent = self
        view.handler = context.coordinator
        if view.string != text {
            view.string = text
        }
        view.ghost = ghost
        view.placeholder = placeholder
        view.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TerminalPromptField
        init(_ parent: TerminalPromptField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            MainActor.assumeIsolated {
                guard let view = notification.object as? NSTextView else { return }
                parent.text = view.string
                parent.onFocus(true)
                TerminalDesk.shared.noteDraftChanged()
            }
        }

        func textDidBeginEditing(_ notification: Notification) {
            MainActor.assumeIsolated { parent.onFocus(true) }
        }
        func textDidEndEditing(_ notification: Notification) {
            MainActor.assumeIsolated { parent.onFocus(false) }
        }
    }
}

final class TerminalPromptNSTextView: NSTextView {
    weak var handler: TerminalPromptField.Coordinator?
    var ghost = ""
    var placeholder = ""

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36:
            if event.modifierFlags.contains(.shift) {
                insertText("\n", replacementRange: selectedRange())
            } else {
                MainActor.assumeIsolated { handler?.parent.onSubmit() }
            }
        case 48:
            MainActor.assumeIsolated { handler?.parent.onAcceptWord() }
        case 50:
            if event.modifierFlags.contains(.control) {
                MainActor.assumeIsolated { handler?.parent.onWake() }
            } else if !ghost.isEmpty {
                MainActor.assumeIsolated { handler?.parent.onAcceptAll() }
            } else {
                insertText("`", replacementRange: selectedRange())
            }
        case 53:
            MainActor.assumeIsolated { handler?.parent.onEscape() }
        default:
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? .systemFont(ofSize: 12),
                .foregroundColor: NSColor.white.withAlphaComponent(0.35)
            ]
            placeholder.draw(at: NSPoint(x: textContainerInset.width + 4, y: textContainerInset.height), withAttributes: attrs)
        }
        guard !ghost.isEmpty, let layout = layoutManager, let container = textContainer else { return }
        let end = string.utf16.count
        let rect = layout.boundingRect(forGlyphRange: NSRange(location: max(0, end - 1), length: min(1, end)), in: container)
        let point = NSPoint(x: rect.maxX + textContainerInset.width, y: textContainerInset.height)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: 12),
            .foregroundColor: NSColor.white.withAlphaComponent(0.38)
        ]
        ghost.draw(at: point, withAttributes: attrs)
    }
}
