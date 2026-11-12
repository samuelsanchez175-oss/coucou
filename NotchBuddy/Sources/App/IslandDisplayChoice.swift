import Foundation

/// Which screen hosts the island. Persisted in UserDefaults as `storageValue`.
enum IslandDisplayChoice: Equatable, Hashable {
    /// Default: the built-in screen with a notch, else the main screen.
    case notch
    /// The screen that carries the menu bar (first in `NSScreen.screens`).
    case menuBar
    /// The island moves to the screen under the cursor while it is not open.
    case followMouse
    /// A specific screen, identified by its display UUID (stable across reboots).
    case display(uuid: String)

    private static let displayPrefix = "display:"

    init(storageValue: String) {
        switch storageValue {
        case "menuBar":     self = .menuBar
        case "followMouse": self = .followMouse
        default:
            if storageValue.hasPrefix(Self.displayPrefix) {
                let uuid = String(storageValue.dropFirst(Self.displayPrefix.count))
                self = uuid.isEmpty ? .notch : .display(uuid: uuid)
            } else {
                self = .notch
            }
        }
    }

    var storageValue: String {
        switch self {
        case .notch:             return "notch"
        case .menuBar:           return "menuBar"
        case .followMouse:       return "followMouse"
        case .display(let uuid): return Self.displayPrefix + uuid
        }
    }
}

/// What the resolver needs to know about a connected screen, in `NSScreen.screens` order.
struct IslandDisplayCandidate {
    let uuid: String?
    let hasNotch: Bool
    let containsMouse: Bool
}

/// One connected screen, in `NSScreen.screens` order.
struct DisplaySettingScreen: Equatable {
    var uuid: String?
    var name: String
    var hasNotch: Bool
}

/// One row in the General tab's Display picker.
struct DisplaySettingOption: Equatable, Identifiable {
    var id: String
    var title: String
}

enum DisplaySettingList {
    /// Main display is the notched screen Coucou uses now. Every other screen is its own row.
    static func options(screens: [DisplaySettingScreen]) -> [DisplaySettingOption] {
        let mainIndex = screens.firstIndex { $0.hasNotch } ?? (screens.isEmpty ? nil : 0)
        var options = [DisplaySettingOption(id: IslandDisplayChoice.notch.storageValue, title: "Main display")]
        var used: Set<String> = ["Main display"]
        for (index, screen) in screens.enumerated() where index != mainIndex {
            guard let uuid = screen.uuid, !uuid.isEmpty else { continue }
            let base = screen.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = freshTitle(base.isEmpty ? "Display" : base, used: &used)
            options.append(DisplaySettingOption(
                id: IslandDisplayChoice.display(uuid: uuid).storageValue,
                title: title
            ))
        }
        return options
    }

    private static func freshTitle(_ base: String, used: inout Set<String>) -> String {
        if used.insert(base).inserted { return base }
        var number = 2
        while true {
            let next = "\(base) \(number)"
            if used.insert(next).inserted { return next }
            number += 1
        }
    }
}

/// Extra screens that show Coucou at the same time as the main display.
enum IslandExtraDisplays {
    static func parse(_ raw: String?) -> Set<String> {
        guard let raw else { return [] }
        return Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func storageValue(_ uuids: Set<String>) -> String {
        uuids.sorted().joined(separator: ",")
    }

    /// Indexes of selected screens, skipping the screen that already hosts the main island.
    static func mirrorIndexes(selected: Set<String>,
                              primary: Int?,
                              candidates: [IslandDisplayCandidate]) -> [Int] {
        candidates.enumerated().compactMap { index, candidate in
            guard index != primary, let uuid = candidate.uuid, !uuid.isEmpty, selected.contains(uuid) else { return nil }
            return index
        }
    }
}

enum IslandDisplayResolver {
    /// Index of the screen that should host the island, or nil to use the default
    /// (notch screen, else main screen). A disconnected chosen screen falls back too.
    static func index(for choice: IslandDisplayChoice,
                      in candidates: [IslandDisplayCandidate]) -> Int? {
        guard !candidates.isEmpty else { return nil }
        let notchIndex = candidates.firstIndex { $0.hasNotch }
        switch choice {
        case .notch:
            return notchIndex
        case .menuBar:
            return 0
        case .followMouse:
            return candidates.firstIndex { $0.containsMouse } ?? notchIndex
        case .display(let uuid):
            return candidates.firstIndex { $0.uuid == uuid } ?? notchIndex
        }
    }
}
