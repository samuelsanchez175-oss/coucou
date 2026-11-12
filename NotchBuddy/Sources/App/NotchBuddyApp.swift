import SwiftUI
import AppKit

@main
struct NotchBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            CoucouSettingsShell()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .defaultSize(width: 1480, height: 900)
        .windowResizability(.contentMinSize)
    }
}
