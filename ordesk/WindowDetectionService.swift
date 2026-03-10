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

    /// Detects running apps with visible windows and groups them by screen index.
    ///
    /// Uses `CGWindowListCopyWindowInfo` as the primary detection method (works
    /// reliably under App Sandbox without Accessibility permission), with an
    /// AXUIElement-based fallback for older macOS versions or edge cases.
    ///
    /// Only includes apps that have at least one visible (non-minimized) window.
    /// De-duplicates: each app appears at most once per screen.
    static func appsWithVisibleWindows() -> [Int: [DetectedWindowInfo]] {
        // Primary: CGWindowList API — sandbox-compatible, no AX needed for detection
        let result = detectViaCGWindowList()
        if !result.isEmpty { return result }
        // Fallback: Accessibility-based detection
        return detectViaAccessibility()
    }

    // MARK: - CGWindowList-Based Detection (Primary)

    /// Detects visible windows using `CGWindowListCopyWindowInfo`.
    /// This Core Graphics API works reliably under App Sandbox without
    /// requiring Accessibility permission for basic window metadata.
    private static func detectViaCGWindowList() -> [Int: [DetectedWindowInfo]] {
        var result: [Int: [DetectedWindowInfo]] = [:]
        let screens = NSScreen.screens
        guard let mainScreen = NSScreen.main else { return result }
        let mainScreenHeight = mainScreen.frame.height

        // Get all on-screen windows (excludes desktop elements like wallpaper)
        guard let windowListInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return result
        }

        // Build PID → NSRunningApplication map (regular apps only)
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
        var appByPID: [pid_t: NSRunningApplication] = [:]
        for app in runningApps {
            appByPID[app.processIdentifier] = app
        }

        // Track which bundleIDs we've already added per screen
        var seenPerScreen: [Int: Set<String>] = [:]

        for windowInfo in windowListInfo {
            // Get owner PID
            guard let pidNumber = windowInfo[kCGWindowOwnerPID as String] as? Int else { continue }
            let pid = pid_t(pidNumber)

            // Only include regular apps (not system processes)
            guard let app = appByPID[pid] else { continue }
            guard let bundleID = app.bundleIdentifier,
                  !excludedBundleIDs.contains(bundleID),
                  bundleID != Bundle.main.bundleIdentifier,
                  let name = app.localizedName
            else { continue }

            // Only include normal window layer (layer 0 = standard app windows)
            if let layer = windowInfo[kCGWindowLayer as String] as? Int, layer != 0 {
                continue
            }

            // Get window bounds (CG coordinates: origin at top-left of main screen)
            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any] else { continue }
            var bounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict as CFDictionary, &bounds) else { continue }

            // Skip tiny windows (helper windows, status items, etc.)
            if bounds.width < 50 || bounds.height < 50 { continue }

            // Convert CG coordinates to Cocoa coordinates for screen matching
            // CG: y from top of main screen going down
            // Cocoa: y from bottom of main screen going up
            let cocoaY = mainScreenHeight - bounds.origin.y - bounds.height
            let cocoaRect = CGRect(
                x: bounds.origin.x, y: cocoaY,
                width: bounds.width, height: bounds.height
            )

            // Find which screen this window is on (largest intersection area)
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

            // De-duplicate: each app once per screen
            if seenPerScreen[bestScreenIndex, default: []].contains(bundleID) {
                continue
            }
            seenPerScreen[bestScreenIndex, default: []].insert(bundleID)

            let icon = app.icon ?? NSWorkspace.shared.icon(forFile: app.bundleURL?.path ?? "")
            icon.size = NSSize(width: 32, height: 32)

            result[bestScreenIndex, default: []].append(
                DetectedWindowInfo(
                    bundleIdentifier: bundleID,
                    appName: name,
                    icon: icon,
                    screenIndex: bestScreenIndex
                )
            )
        }

        return result
    }

    // MARK: - Accessibility-Based Detection (Fallback)

    /// Detects visible windows using AXUIElement API.
    /// Requires Accessibility permission. Used as fallback when CGWindowList
    /// doesn't return results.
    private static func detectViaAccessibility() -> [Int: [DetectedWindowInfo]] {
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
                  bundleID != Bundle.main.bundleIdentifier,
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
