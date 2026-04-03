import AppKit
import Foundation

// MARK: - Workspace Runner

/// Executes a workspace: launches apps, unminimizes them, and positions
/// their windows at the correct screen ratios based on displayIndex and
/// dynamic layout (apps fill the screen adaptively).
///
/// Uses AppleScript + AXUIElement for window management.
///
/// Requires:
///   - Accessibility permission (AXIsProcessTrusted)
///   - Automation permission for "System Events" (NSAppleEventsUsageDescription)
@MainActor
final class WorkspaceRunner {

    // MARK: - Error Types

    enum RunnerError: LocalizedError {
        case accessibilityNotGranted
        case appLaunchFailed(appName: String, reason: String)
        case windowPositionFailed(appName: String, reason: String)

        var errorDescription: String? {
            switch self {
            case .accessibilityNotGranted:
                return "Accessibility permission is required to manage windows."
            case .appLaunchFailed(let name, let reason):
                return "Failed to launch \(name): \(reason)"
            case .windowPositionFailed(let name, let reason):
                return "Failed to position \(name): \(reason)"
            }
        }
    }

    // MARK: - State

    enum RunnerState: Equatable {
        case idle
        case preparingDesktop
        case switchingDesktop
        case launchingApps(current: String, index: Int, total: Int)
        case positioningWindows
        case completed
        case failed(String)
    }

    /// Observable state for the HUD overlay.
    private(set) var state: RunnerState = .idle
    private var onStateChange: ((RunnerState) -> Void)?

    // MARK: - Public API

    /// Runs a workspace: launches/activates apps and positions their windows.
    /// - Parameters:
    ///   - workspace: The workspace to execute.
    ///   - minimizeOthers: If true, minimize apps with visible windows that are NOT in the workspace.
    ///   - onStateChange: Callback invoked on each state transition (for HUD updates).
    /// - Throws: `RunnerError` if any step fails.
    func run(workspace: Workspace, minimizeOthers: Bool = false, onStateChange: @escaping (RunnerState) -> Void) async throws {
        self.onStateChange = onStateChange

        // Step 0: Verify permissions
        guard AccessibilityPermissionManager.isTrusted() else {
            transition(to: .failed("Accessibility permission not granted."))
            throw RunnerError.accessibilityNotGranted
        }

        // Step 0.5: Minimize unselected visible apps if requested
        if minimizeOthers {
            minimizeAppsNotInWorkspace(workspace)
            try await Task.sleep(for: .milliseconds(300))
        }

        // Step 1: Launch / activate all apps
        let apps = workspace.apps
        print("[WorkspaceRunner] Launching \(apps.count) app(s)...")
        for (index, app) in apps.enumerated() {
            print("[WorkspaceRunner] [\(index+1)/\(apps.count)] \(app.name) -- \(app.bundleIdentifier) (display \(app.displayIndex))")
            transition(to: .launchingApps(current: app.name, index: index, total: apps.count))
            try await launchAndActivateApp(app)

            // Delay between launches to avoid macOS window race conditions
            if index < apps.count - 1 {
                try await Task.sleep(for: .milliseconds(600))
            }
        }

        // Step 2: Wait for all windows to settle
        try await Task.sleep(for: .milliseconds(500))

        // Step 3: Position all windows based on displayIndex + dynamic layout
        transition(to: .positioningWindows)
        await positionAllWindows(apps: apps)

        // Done
        transition(to: .completed)
    }

    // MARK: - Minimize Unselected Apps

    /// Minimizes all visible windows of apps NOT in the workspace.
    private func minimizeAppsNotInWorkspace(_ workspace: Workspace) {
        let workspaceBundleIDs = Set(workspace.apps.map(\.bundleIdentifier).filter { !$0.isEmpty })
        let ordeskBundleID = Bundle.main.bundleIdentifier ?? ""

        let visibleBundleIDs = WindowDetectionService.bundleIDsWithVisibleWindows()
        let toMinimize = visibleBundleIDs
            .subtracting(workspaceBundleIDs)
            .subtracting([ordeskBundleID])

        print("[WorkspaceRunner] Minimizing \(toMinimize.count) unselected app(s)...")

        for bundleID in toMinimize {
            guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == bundleID
            }) else { continue }

            // Minimize all windows via AXUIElement
            let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
            var windowsRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

            if result == .success, let windows = windowsRef as? [AXUIElement] {
                for window in windows {
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, true as CFTypeRef)
                }
                print("[WorkspaceRunner] Minimized windows for \(runningApp.localizedName ?? bundleID)")
            }
        }
    }

    // MARK: - Launch & Activate Apps

    /// Launches an app if not running, or activates + unminimizes it if already running.
    /// Uses AppleScript to ensure the app is visible on the current Desktop.
    private func launchAndActivateApp(_ app: AppInstance) async throws {
        guard !app.bundleIdentifier.isEmpty else {
            throw RunnerError.appLaunchFailed(
                appName: app.name,
                reason: "No bundle identifier"
            )
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: app.bundleIdentifier
        ) else {
            throw RunnerError.appLaunchFailed(
                appName: app.name,
                reason: "Application not installed"
            )
        }

        // Check if app is already running
        let runningApp = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == app.bundleIdentifier
        }

        if let runningApp = runningApp {
            // App IS running -- unminimize + activate it
            print("[WorkspaceRunner] \(app.name) is already running, activating...")

            // First: unhide if hidden
            if runningApp.isHidden {
                runningApp.unhide()
                try await Task.sleep(for: .milliseconds(200))
            }

            // Use AXUIElement to unminimize any minimized windows
            unminimizeWindows(for: runningApp)
            try await Task.sleep(for: .milliseconds(150))

            // Activate the app — just a simple activate, no window counting
            // (many apps like Figma/Electron don't support AppleScript window commands)
            let activateScript = """
            tell application id "\(app.bundleIdentifier)" to activate
            """
            let result = executeAppleScript(activateScript)
            if let error = result.error {
                print("[WorkspaceRunner] AppleScript activate failed for \(app.name): \(error)")
                // Fallback: NSRunningApplication.activate
                runningApp.activate()
            }

            // Wait for the app to come to foreground
            try await Task.sleep(for: .milliseconds(400))
        } else {
            // App is NOT running -- launch fresh
            print("[WorkspaceRunner] \(app.name) is not running, launching...")

            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.addsToRecentItems = false

            do {
                try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            } catch {
                throw RunnerError.appLaunchFailed(
                    appName: app.name,
                    reason: error.localizedDescription
                )
            }

            // Wait for the app to fully launch and create its first window
            try await waitForAppWindow(bundleIdentifier: app.bundleIdentifier, timeout: 5.0)
        }
    }

    /// Waits until an app has at least one window, or until timeout.
    private func waitForAppWindow(bundleIdentifier: String, timeout: Double) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == bundleIdentifier
            }) {
                // Check via AX if the app has any windows
                let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
                var windowsRef: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
                if result == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty {
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        // Timeout is OK -- some apps don't create windows immediately (e.g. menu bar apps)
        print("[WorkspaceRunner] Timeout waiting for window: \(bundleIdentifier)")
    }

    /// Uses AXUIElement to find and unminimize any minimized windows for the given app.
    private func unminimizeWindows(for runningApp: NSRunningApplication) {
        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            print("[WorkspaceRunner] Could not get windows for \(runningApp.localizedName ?? "unknown")")
            return
        }

        for window in windows {
            var minimizedRef: CFTypeRef?
            let minResult = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
            if minResult == .success, let isMinimized = minimizedRef as? Bool, isMinimized {
                print("[WorkspaceRunner] Unminimizing window for \(runningApp.localizedName ?? "unknown")")
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            }
        }
    }

    // MARK: - Window Positioning (Multi-Display Aware)

    /// Positions all app windows grouped by displayIndex on the correct screen.
    /// Each display gets a dynamic layout based on how many apps are assigned to it.
    private func positionAllWindows(apps: [AppInstance]) async {
        let screens = NSScreen.screens
        guard let mainScreen = screens.first else { return }
        let mainScreenHeight = mainScreen.frame.height

        // Group apps by displayIndex
        var appsByDisplay: [Int: [AppInstance]] = [:]
        for app in apps {
            appsByDisplay[app.displayIndex, default: []].append(app)
        }

        // Position apps on each display
        for (displayIndex, displayApps) in appsByDisplay.sorted(by: { $0.key < $1.key }) {
            // Get the screen for this display index (fall back to main if unavailable)
            let screen = displayIndex < screens.count ? screens[displayIndex] : mainScreen
            let axRect = cocoaVisibleFrameToAX(screen: screen, mainScreenHeight: mainScreenHeight)

            print("[WorkspaceRunner] Display \(displayIndex) (\(screen.localizedName)): \(displayApps.count) app(s) → AX rect \(axRect)")

            await positionAppsOnScreen(displayApps, in: axRect)
        }
    }

    /// Converts a screen's visibleFrame from Cocoa coordinates (origin bottom-left, Y up)
    /// to AX coordinates (origin top-left of main screen, Y down).
    func cocoaVisibleFrameToAX(screen: NSScreen, mainScreenHeight: CGFloat) -> CGRect {
        let visibleFrame = screen.visibleFrame
        let axX = visibleFrame.origin.x
        let axY = mainScreenHeight - visibleFrame.origin.y - visibleFrame.height
        return CGRect(x: axX, y: axY, width: visibleFrame.width, height: visibleFrame.height)
    }

    /// Positions a group of apps on a single screen using dynamic layout.
    private func positionAppsOnScreen(_ apps: [AppInstance], in axRect: CGRect) async {
        let frames = dynamicLayoutFrames(count: apps.count, in: axRect)

        for (index, app) in apps.enumerated() {
            guard index < frames.count else { continue }
            let targetFrame = frames[index]

            print("[WorkspaceRunner] Positioning \(app.name) at \(targetFrame)")

            guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == app.bundleIdentifier
            }) else {
                print("[WorkspaceRunner] \(app.name) not running, skipping position")
                continue
            }

            setWindowFrame(for: runningApp, frame: targetFrame)

            if index < apps.count - 1 {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Dynamic layout: apps automatically fill the available space.
    ///
    /// - 1 app  → full screen
    /// - 2 apps → side by side (left | right)
    /// - 3 apps → 2 on top, 1 full-width on bottom
    /// - 4 apps → 2×2 grid
    func dynamicLayoutFrames(count: Int, in rect: CGRect) -> [CGRect] {
        let padding: CGFloat = 4

        switch count {
        case 0:
            return []

        case 1:
            // Full screen
            return [
                CGRect(
                    x: rect.minX + padding,
                    y: rect.minY + padding,
                    width: rect.width - padding * 2,
                    height: rect.height - padding * 2
                )
            ]

        case 2:
            // Side by side
            let halfW = rect.width / 2
            return [
                CGRect(
                    x: rect.minX + padding,
                    y: rect.minY + padding,
                    width: halfW - padding * 2,
                    height: rect.height - padding * 2
                ),
                CGRect(
                    x: rect.minX + halfW + padding,
                    y: rect.minY + padding,
                    width: halfW - padding * 2,
                    height: rect.height - padding * 2
                )
            ]

        case 3:
            // 2 on top row, 1 full-width on bottom row
            let halfW = rect.width / 2
            let halfH = rect.height / 2
            return [
                CGRect(
                    x: rect.minX + padding,
                    y: rect.minY + padding,
                    width: halfW - padding * 2,
                    height: halfH - padding * 2
                ),
                CGRect(
                    x: rect.minX + halfW + padding,
                    y: rect.minY + padding,
                    width: halfW - padding * 2,
                    height: halfH - padding * 2
                ),
                CGRect(
                    x: rect.minX + padding,
                    y: rect.minY + halfH + padding,
                    width: rect.width - padding * 2,
                    height: halfH - padding * 2
                )
            ]

        case 4:
            // 2×2 grid
            let halfW = rect.width / 2
            let halfH = rect.height / 2
            return [
                CGRect(x: rect.minX + padding, y: rect.minY + padding,
                        width: halfW - padding * 2, height: halfH - padding * 2),
                CGRect(x: rect.minX + halfW + padding, y: rect.minY + padding,
                        width: halfW - padding * 2, height: halfH - padding * 2),
                CGRect(x: rect.minX + padding, y: rect.minY + halfH + padding,
                        width: halfW - padding * 2, height: halfH - padding * 2),
                CGRect(x: rect.minX + halfW + padding, y: rect.minY + halfH + padding,
                        width: halfW - padding * 2, height: halfH - padding * 2)
            ]

        default:
            // Fallback: 2-column grid for > 4 apps
            let cols = 2
            let rows = Int(ceil(Double(count) / Double(cols)))
            let cellW = rect.width / CGFloat(cols)
            let cellH = rect.height / CGFloat(rows)
            var frames: [CGRect] = []
            for i in 0..<count {
                let col = i % cols
                let row = i / cols
                frames.append(CGRect(
                    x: rect.minX + CGFloat(col) * cellW + padding,
                    y: rect.minY + CGFloat(row) * cellH + padding,
                    width: cellW - padding * 2,
                    height: cellH - padding * 2
                ))
            }
            return frames
        }
    }

    /// Sets the position and size of the frontmost window of a running application
    /// using the Accessibility API (AXUIElement).
    private func setWindowFrame(for runningApp: NSRunningApplication, frame: CGRect) {
        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            print("[WorkspaceRunner] No AX windows found for \(runningApp.localizedName ?? "unknown")")
            return
        }

        // Use the main (frontmost/last active) window — fall back to first if unavailable
        var mainWindowRef: CFTypeRef?
        let mainResult = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowRef)
        let window: AXUIElement
        if mainResult == .success, let mainWindow = mainWindowRef as! AXUIElement? {
            window = mainWindow
        } else {
            window = windows[0]
        }

        // Minimize all other windows so they don't clutter the layout
        for other in windows where other != window {
            var minimizedRef: CFTypeRef?
            let canCheck = AXUIElementCopyAttributeValue(other, kAXMinimizedAttribute as CFString, &minimizedRef)
            if canCheck == .success {
                AXUIElementSetAttributeValue(other, kAXMinimizedAttribute as CFString, true as CFTypeRef)
            }
        }

        // Set position
        var position = CGPoint(x: frame.origin.x, y: frame.origin.y)
        if let posValue = AXValueCreate(.cgPoint, &position) {
            let posResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
            if posResult != .success {
                print("[WorkspaceRunner] Failed to set position for \(runningApp.localizedName ?? "unknown"): \(posResult.rawValue)")
            }
        }

        // Set size
        var size = CGSize(width: frame.size.width, height: frame.size.height)
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            if sizeResult != .success {
                print("[WorkspaceRunner] Failed to set size for \(runningApp.localizedName ?? "unknown"): \(sizeResult.rawValue)")
            }
        }
    }

    // MARK: - AppleScript Execution

    private struct ScriptResult {
        let output: String?
        let error: String?
    }

    /// Executes an AppleScript string synchronously and returns the result.
    private func executeAppleScript(_ source: String) -> ScriptResult {
        var errorDict: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&errorDict)

        if let errorDict = errorDict {
            let message = errorDict[NSAppleScript.errorMessage] as? String
                ?? "Unknown AppleScript error"
            return ScriptResult(output: nil, error: message)
        }

        return ScriptResult(output: result?.stringValue, error: nil)
    }

    // MARK: - State Machine

    private func transition(to newState: RunnerState) {
        state = newState
        onStateChange?(newState)
    }

    // MARK: - Diagnostics

    /// Checks if "Displays have separate Spaces" is enabled.
    static func separateSpacesEnabled() -> Bool {
        let defaults = UserDefaults(suiteName: "com.apple.spaces")
        let spansDisplays = defaults?.bool(forKey: "spans-displays") ?? false
        return !spansDisplays
    }

    /// Returns a user-facing error message for common failure scenarios.
    static func diagnosticMessage() -> String {
        var issues: [String] = []

        if !AccessibilityPermissionManager.isTrusted() {
            issues.append("Grant Accessibility permission in System Settings -> Privacy & Security -> Accessibility")
        }

        if issues.isEmpty {
            return "All required permissions are configured correctly."
        }

        return "Unable to run workspace. Please ensure:\n\n" + issues.joined(separator: "\n")
    }

    // MARK: - Test Helpers

    /// Exposes dynamicLayoutFrames for unit testing.
    func testDynamicLayoutFrames(count: Int, in rect: CGRect) -> [CGRect] {
        dynamicLayoutFrames(count: count, in: rect)
    }

    /// Exposes coordinate conversion for unit testing (without needing an NSScreen).
    func testCocoaVisibleFrameToAX(visibleFrame: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        let axX = visibleFrame.origin.x
        let axY = mainScreenHeight - visibleFrame.origin.y - visibleFrame.height
        return CGRect(x: axX, y: axY, width: visibleFrame.width, height: visibleFrame.height)
    }
}
