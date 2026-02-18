import SwiftUI

@main
struct ordeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar app — no main window needed.
        // The popover is managed by AppDelegate via NSStatusItem.
        Settings {
            EmptyView()
        }
    }
}
