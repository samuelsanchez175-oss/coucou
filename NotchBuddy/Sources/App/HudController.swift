import AppKit
import ApplicationServices
import AudioToolbox
import CoreAudio
import CoreGraphics
import Darwin
import SwiftUI

private final class HudTapBox: @unchecked Sendable {
    var port: CFMachPort?
}

private let hudTapBox = HudTapBox()

/// Session event tap. Runs on the main run loop, so the main actor is safe to assume.
private let hudEventCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = hudTapBox.port {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
    guard Thread.isMainThread else { return Unmanaged.passUnretained(event) }
    guard let ns = NSEvent(cgEvent: event),
          ns.type == .systemDefined,
          ns.subtype.rawValue == 8 else {
        return Unmanaged.passUnretained(event)
    }
    let data = Int(ns.data1)
    let code = (data & 0xFFFF0000) >> 16
    let keyState = (data & 0xFF00) >> 8
    let swallow = MainActor.assumeIsolated {
        HudController.shared.handleMediaKey(code: code, keyState: keyState)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

/// Shows a volume or brightness bar in the notch and handles those keys.
@MainActor
final class HudController: ObservableObject {
    static let shared = HudController()

    @Published private(set) var visible = false
    @Published private(set) var title = "Volume"
    @Published private(set) var symbol = "speaker.wave.2.fill"
    @Published private(set) var percent = "0%"
    @Published private(set) var fraction: Double = 0
    @Published private(set) var accessibilityOff = false
    @Published private(set) var keysCaptured = false

    private var level = HudLevel(volume: 0.5, muted: false, brightness: 1)
    private var hideWork: DispatchWorkItem?
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var started = false
    private var applying = false
    private var listenedDevice: AudioDeviceID = 0
    private var suppressKeyUp = false

    func start() {
        guard !started else { return }
        started = true
        refreshFromSystem()
        installDeviceListener()
        rebindVolumeListener()
        syncTap()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in HudController.shared.syncTap() }
        }
    }

    func preferenceChanged() {
        if NookPreferences.shared.hudReplacement {
            syncTap()
        } else {
            removeTap()
            visible = false
        }
    }

    /// Returns true when this process should keep the key, so the system banner stays hidden.
    func handleMediaKey(code: Int, keyState: Int) -> Bool {
        guard NookPreferences.shared.hudReplacement else { return false }
        guard let key = HudBehavior.key(code: code, keyState: keyState) else {
            if keyState == 0x0B, HudBehavior.key(code: code, keyState: 0x0A) != nil {
                let swallow = suppressKeyUp
                suppressKeyUp = false
                return swallow
            }
            return false
        }
        refreshFromSystem()
        let next = HudBehavior.next(level: level, key: key)
        guard commit(next.level, kind: next.kind) else {
            suppressKeyUp = false
            return false
        }
        suppressKeyUp = true
        present(kind: next.kind)
        return true
    }

    func volumeChangedOutside() {
        guard !applying, NookPreferences.shared.hudReplacement else { return }
        let (volume, muted) = SystemVolume.read()
        guard abs(volume - level.volume) > 0.02 || muted != level.muted else { return }
        level.volume = volume
        level.muted = muted
        present(kind: .volume)
    }

    private func commit(_ requested: HudLevel, kind: HudKind) -> Bool {
        switch kind {
        case .volume:
            applying = true
            let wrote = SystemVolume.write(volume: requested.volume, muted: requested.muted)
            applying = false
            guard wrote else { return false }
            let (volume, muted) = SystemVolume.read()
            guard muted == requested.muted, abs(volume - requested.volume) < 0.03 else { return false }
            level.volume = volume
            level.muted = muted
            return true
        case .brightness:
            guard SystemBrightness.canChange() else { return false }
            let before = level.brightness
            guard SystemBrightness.write(requested.brightness) else { return false }
            guard let actual = SystemBrightness.read() else {
                level.brightness = requested.brightness
                return true
            }
            let unchanged = abs(actual - before) < 0.01
            let missed = abs(actual - requested.brightness) > 0.03
            if unchanged && missed { return false }
            level.brightness = actual
            return true
        }
    }

    private func present(kind: HudKind) {
        let shown = HudBehavior.shownFraction(kind: kind, level: level)
        title = kind == .volume ? "Volume" : "Brightness"
        fraction = shown
        percent = HudBehavior.percent(shown)
        symbol = HudBehavior.symbol(kind: kind, value: level.volume, muted: level.muted)
        visible = true
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.visible = false }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + HudBehavior.visibleSeconds, execute: work)
    }

    private func refreshFromSystem() {
        let (volume, muted) = SystemVolume.read()
        level.volume = volume
        level.muted = muted
        if let brightness = SystemBrightness.read() {
            level.brightness = brightness
        }
    }

    private func syncTap() {
        guard NookPreferences.shared.hudReplacement else {
            removeTap()
            return
        }
        let trusted = AXIsProcessTrusted()
        accessibilityOff = !trusted
        guard trusted else {
            removeTap()
            accessibilityOff = true
            return
        }
        guard tap == nil else {
            keysCaptured = true
            return
        }
        let mask = CGEventMask(1 << 14)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hudEventCallback,
            userInfo: nil
        ) else {
            keysCaptured = false
            accessibilityOff = !AXIsProcessTrusted()
            return
        }
        hudTapBox.port = port
        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        keysCaptured = true
        accessibilityOff = false
    }

    private func removeTap() {
        if let source = tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        tap = nil
        tapSource = nil
        hudTapBox.port = nil
        keysCaptured = false
    }

    private func installDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { _, _ in
            MainActor.assumeIsolated {
                HudController.shared.rebindVolumeListener()
            }
        }
    }

    private func rebindVolumeListener() {
        let device = SystemVolume.defaultOutput()
        guard device != 0, device != listenedDevice else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main) { _, _ in
            MainActor.assumeIsolated {
                HudController.shared.volumeChangedOutside()
            }
        }
        address.mSelector = kAudioDevicePropertyMute
        AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main) { _, _ in
            MainActor.assumeIsolated {
                HudController.shared.volumeChangedOutside()
            }
        }
        listenedDevice = device
    }
}

private enum SystemVolume {
    static func defaultOutput() -> AudioDeviceID {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        return status == noErr ? device : 0
    }

    static func read() -> (Double, Bool) {
        let device = defaultOutput()
        guard device != 0 else { return (0, false) }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let volumeStatus = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyMute
        let muteStatus = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        let level = volumeStatus == noErr ? Double(min(1, max(0, volume))) : 0
        return (level, muteStatus == noErr && muted != 0)
    }

    static func write(volume: Double, muted: Bool) -> Bool {
        let device = defaultOutput()
        guard device != 0 else { return false }
        var volumeValue = Float32(min(1, max(0, volume)))
        let volumeSize = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let volumeStatus = AudioObjectSetPropertyData(device, &address, 0, nil, volumeSize, &volumeValue)
        var muteValue: UInt32 = muted ? 1 : 0
        let muteSize = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyMute
        let muteStatus = AudioObjectSetPropertyData(device, &address, 0, nil, muteSize, &muteValue)
        return volumeStatus == noErr && muteStatus == noErr
    }
}

private enum SystemBrightness {
    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32
    private typealias CanFn = @convention(c) (UInt32) -> Int32

    static func read() -> Double? {
        guard let get = load("DisplayServicesGetBrightness", as: GetFn.self) else { return nil }
        var value: Float = 0
        guard get(CGMainDisplayID(), &value) == 0 else { return nil }
        return Double(min(1, max(0, value)))
    }

    static func write(_ value: Double) -> Bool {
        guard let set = load("DisplayServicesSetBrightness", as: SetFn.self) else { return false }
        return set(CGMainDisplayID(), Float(min(1, max(0, value)))) == 0
    }

    static func canChange() -> Bool {
        guard let can = load("DisplayServicesCanChangeBrightness", as: CanFn.self) else { return false }
        return can(CGMainDisplayID()) != 0
    }

    private static func load<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY
        ), let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }
}

struct HudStrip: View {
    var title: String
    var symbol: String
    var percent: String
    var fraction: Double

    var body: some View {
        HStack(spacing: HudBehavior.rowSpacing) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: HudBehavior.iconWidth)
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .frame(width: HudBehavior.titleWidth, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule()
                    .fill(Color.white)
                    .frame(width: HudBehavior.fillWidth(fraction: fraction))
            }
            .frame(width: HudBehavior.trackWidth, height: 6)
            .animation(
                .spring(response: HudBehavior.fillSpringResponse, dampingFraction: HudBehavior.fillSpringDamping),
                value: fraction
            )
            Text(percent)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: HudBehavior.percentWidth, alignment: .trailing)
        }
        .padding(.horizontal, HudBehavior.rowInset)
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(percent)")
    }
}
