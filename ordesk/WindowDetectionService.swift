import AppKit
import ApplicationServices

// MARK: - Display Info

/// Describes a connected display.
struct DisplayInfo: Identifiable {
    let id: Int          // Index in NSScreen.screens (0 = main)
    let name: String     // e.g. "Built-in Retina Display"
    let frame: CGRect    // NSScreen.frame (Cocoa coordinates)
    let isMain: Bool
}

// MARK: - Detected Window Info

/// Describes a running app with a visible window and which screen it's on.
struct DetectedWindowInfo {
    let bundleIdentifier: String
    let appName: String
    let icon: NSImage
    let screenIndex: Int   // Which display the window is on
}

// MARK: - Window Detection Service

/// Detects connected displays and maps running app windows to their screens
/// using the Accessibility API (AXUIElement).
///
/// Requires Accessibility permission (AXIsProcessTrusted).
enum WindowDetectionService {

    /// Same exclusion list as RunningAppsService.
    private static let excludedBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.SystemUIServer",
    ]

    // MARK: - Connected Displays

    /// Returns all connected displays with human-readable names.
    static func connectedDisplays() -> [DisplayInfo] {
        NSScreen.screens.enumerated().map { index, screen in
            DisplayInfo(
                id: index,
                name: screen.localizedName,
                frame: screen.frame,
                isMain: screen == NSScreen.main
            )
        }
    }

    // MARK: - Auto Display Mode

    /// Detects the appropriate DisplayMode based on connected screen count.
    static func autoDetectedDisplayMode() -> DisplayMode {
        switch NSScreen.screens.count {
        case 1:      return .single
        case 2:      return .dual
        default:     return .triple
        }
    }

    // MARK: - Apps With Visible Windows Per Screen

    /// For each running app, inspects AX windows, reads their position,
    /// determines which screen each window is on, and returns results
    /// grouped by screen index.
    ///
    /// Only includes apps that have at least one visible (non-minimized) window.
    /// De-duplicates: each app appears at most once per screen.
    static func appsWithVisibleWindows() -> [Int: [DetectedWindowInfo]] {
        var result: [Int: [DetectedWindowInfo]] = [:]
        let screens = NSScreen.screens
        guard let mainScreen = NSScreen.main else { return result }

        let mainScreenHeight = mainScreen.frame.height

        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        // Track which bundleIDs we've already added per screen
        var seenPerScreen: [Int: Set<String>] = [:]

        for app in runningApps {
            guard let bundleID = app.bundleIdentifier,
                  !excludedBundleIDs.contains(bundleID),
                  let name = app.localizedName
            else { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            let axResult = AXUIElementCopyAttributeValue(
                appElement, kAXWindowsAttribute as CFString, &windowsRef
            )
            guard axResult == .success,
                  let windows = windowsRef as? [AXUIElement]
            else { continue }

            let icon = app.icon ?? NSWorkspace.shared.icon(forFile: app.bundleURL?.path ?? "")
            icon.size = NSSize(width: 32, height: 32)

            for window in windows {
                // Skip minimized windows
                var minimizedRef: CFTypeRef?
                let minResult = AXUIElementCopyAttributeValue(
                    window, kAXMinimizedAttribute as CFString, &minimizedRef
                )
                if minResult == .success, let isMinimized = minimizedRef as? Bool, isMinimized {
                    continue
                }

                // Read window position (AX coordinates: origin top-left, Y goes down)
                var posRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    window, kAXPositionAttribute as CFString, &posRef
                ) == .success, let posValue = posRef else { continue }

                var position = CGPoint.zero
                AXValueGetValue(posValue as! AXValue, .cgPoint, &position)

                // Read window size
                var sizeRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    window, kAXSizeAttribute as CFString, &sizeRef
                ) == .success, let sizeValue = sizeRef else { continue }

                var size = CGSize.zero
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

                // Skip tiny windows (likely hidden helper windows)
                if size.width < 50 || size.height < 50 { continue }

                // Convert AX position to Cocoa coordinates for screen matching
                // AX: y from top of main screen going down
                // Cocoa: y from bottom of main screen going up
                let cocoaY = mainScreenHeight - position.y - size.height
                let cocoaRect = CGRect(
                    x: position.x, y: cocoaY,
                    width: size.width, height: size.height
                )

                // Find which screen this window is on (by largest intersection area)
                var bestScreenIndex = 0
                var bestArea: CGFloat = 0
                for (idx, screen) in screens.enumerated() {
                    let intersection = screen.frame.intersection(cocoaRect)
                    if !intersection.isNull {
                        let area = intersection.width * intersection.height
                        if area > bestArea {
                            bestArea = area
                            bestScreenIndex = idx
                        }
                    }
                }

                // De-duplicate: only add each app once per screen
                if seenPerScreen[bestScreenIndex, default: []].contains(bundleID) {
                    continue
                }
                seenPerScreen[bestScreenIndex, default: []].insert(bundleID)

                result[bestScreenIndex, default: []].append(
                    DetectedWindowInfo(
                        bundleIdentifier: bundleID,
                        appName: name,
                        icon: icon,
                        screenIndex: bestScreenIndex
                    )
                )
            }
        }

        return result
    }

    /// Returns the set of all bundle identifiers that have at least one visible window.
    static func bundleIDsWithVisibleWindows() -> Set<String> {
        var ids: Set<String> = []
        for (_, infos) in appsWithVisibleWindows() {
            for info in infos {
                ids.insert(info.bundleIdentifier)
            }
        }
        return ids
    }
}
