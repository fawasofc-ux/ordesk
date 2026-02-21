import AppKit

struct RunningAppInfo: Identifiable {
    let id: String            // bundleIdentifier
    let name: String
    let icon: NSImage
    let bundleURL: URL?
    let isRunning: Bool
}

enum RunningAppsService {

    /// Apps to always exclude (system daemons, ourselves, invisible helpers)
    private static let excludedBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.SystemUIServer",
    ]

    /// Returns currently running regular (visible) apps, sorted alphabetically.
    static func runningApps() -> [RunningAppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningAppInfo? in
                guard let bundleID = app.bundleIdentifier,
                      !excludedBundleIDs.contains(bundleID),
                      let name = app.localizedName
                else { return nil }

                let icon = app.icon ?? NSWorkspace.shared.icon(forFile: app.bundleURL?.path ?? "")
                icon.size = NSSize(width: 32, height: 32)

                return RunningAppInfo(
                    id: bundleID,
                    name: name,
                    icon: icon,
                    bundleURL: app.bundleURL,
                    isRunning: true
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
