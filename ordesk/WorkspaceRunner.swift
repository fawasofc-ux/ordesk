import AppKit
import Foundation

// MARK: - Workspace Runner

/// Executes a workspace: launches apps, unminimizes them, and positions
/// their windows at the correct screen ratios based on cardSize/grid layout.
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
    ///   - onStateChange: Callback invoked on each state transition (for HUD updates).
    /// - Throws: `RunnerError` if any step fails.
    func run(workspace: Workspace, onStateChange: @escaping (RunnerState) -> Void) async throws {
        self.onStateChange = onStateChange

        // Step 0: Verify permissions
        guard AccessibilityPermissionManager.isTrusted() else {
            transition(to: .failed("Accessibility permission not granted."))
            throw RunnerError.accessibilityNotGranted
        }

        // Step 1: Launch / activate all apps
        let apps = workspace.apps
        print("[WorkspaceRunner] Launching \(apps.count) app(s)...")
        for (index, app) in apps.enumerated() {
            print("[WorkspaceRunner] [\(index+1)/\(apps.count)] \(app.name) -- \(app.bundleIdentifier)")
            transition(to: .launchingApps(current: app.name, index: index, total: apps.count))
            try await launchAndActivateApp(app)

            // Delay between launches to avoid macOS window race conditions
            if index < apps.count - 1 {
                try await Task.sleep(for: .milliseconds(600))
            }
        }

        // Step 2: Wait for all windows to settle
        try await Task.sleep(for: .milliseconds(500))

        // Step 3: Position all windows based on cardSize layout
        transition(to: .positioningWindows)
        await positionAllWindows(apps: apps)

        // Done
        transition(to: .completed)
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

            // Activate via AppleScript (brings window to current Desktop)
            let activateScript = """
            tell application id "\(app.bundleIdentifier)"
                activate
                if (count of windows) = 0 then
                    try
                        make new document
                    end try
                end if
            end tell
            """
            let result = executeAppleScript(activateScript)
            if let error = result.error {
                print("[WorkspaceRunner] AppleScript activate failed for \(app.name): \(error)")
                // Fallback: try NSRunningApplication.activate
                runningApp.activate()
            }

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

    // MARK: - Window Positioning

    /// Positions all app windows based on their cardSize and order in the workspace.
    /// Uses the grid layout logic from the editor to calculate screen ratios.
    private func positionAllWindows(apps: [AppInstance]) async {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame // accounts for menu bar + dock

        // Calculate window frames based on card sizes
        let frames = calculateWindowFrames(apps: apps, in: visibleFrame)

        for (index, app) in apps.enumerated() {
            guard index < frames.count else { continue }
            let targetFrame = frames[index]

            print("[WorkspaceRunner] Positioning \(app.name) at \(targetFrame)")

            // Find the running app
            guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == app.bundleIdentifier
            }) else {
                print("[WorkspaceRunner] \(app.name) not running, skipping position")
                continue
            }

            // Use AXUIElement to move and resize
            setWindowFrame(for: runningApp, frame: targetFrame)

            // Small delay between positioning
            if index < apps.count - 1 {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Calculates target frames for each app based on their cardSize.
    ///
    /// Layout logic:
    /// - Uses the same grid system as the WorkspaceEditor
    /// - `small` = 1 column, 1 row unit
    /// - `medium` = 2 columns, 1 row unit
    /// - `large` = 2 columns, 2 row units
    ///
    /// The algorithm walks through apps row by row, placing them in a grid,
    /// then maps grid cells to actual screen coordinates.
    private func calculateWindowFrames(apps: [AppInstance], in rect: CGRect) -> [CGRect] {
        let gridConfig = GridConfiguration.configuration(for: apps.count)
        let totalColumns = gridConfig.columns

        // Build a placement map: each app occupies cells in a virtual grid
        struct Placement {
            let col: Int
            let row: Int
            let colSpan: Int
            let rowSpan: Int
        }

        var placements: [Placement] = []
        var currentCol = 0
        var currentRow = 0
        var maxRow = 0

        // Grid occupancy tracker
        var occupied: Set<String> = [] // "col,row" keys
        func isOccupied(_ c: Int, _ r: Int) -> Bool { occupied.contains("\(c),\(r)") }
        func occupy(_ c: Int, _ r: Int) { occupied.insert("\(c),\(r)") }

        for app in apps {
            let colSpan = app.cardSize.gridColumns
            let rowSpan = app.cardSize.gridRows

            // Find next available position
            var placed = false
            for r in currentRow...currentRow + 10 { // safety limit
                for c in 0...(totalColumns - colSpan) {
                    // Check if all cells for this placement are free
                    var canPlace = true
                    for dc in 0..<colSpan {
                        for dr in 0..<rowSpan {
                            if isOccupied(c + dc, r + dr) {
                                canPlace = false
                                break
                            }
                        }
                        if !canPlace { break }
                    }

                    if canPlace {
                        // Place the app
                        for dc in 0..<colSpan {
                            for dr in 0..<rowSpan {
                                occupy(c + dc, r + dr)
                            }
                        }
                        placements.append(Placement(col: c, row: r, colSpan: colSpan, rowSpan: rowSpan))
                        maxRow = max(maxRow, r + rowSpan)
                        placed = true
                        break
                    }
                }
                if placed { break }
            }

            if !placed {
                // Fallback: place at origin
                placements.append(Placement(col: 0, row: maxRow, colSpan: min(colSpan, totalColumns), rowSpan: rowSpan))
                maxRow += rowSpan
            }
        }

        // Convert grid placements to screen coordinates
        let totalRows = max(maxRow, 1)
        let cellWidth = rect.width / CGFloat(totalColumns)
        let cellHeight = rect.height / CGFloat(totalRows)
        let padding: CGFloat = 4 // small gap between windows

        var frames: [CGRect] = []
        for placement in placements {
            let x = rect.minX + CGFloat(placement.col) * cellWidth + padding
            let y = rect.minY + rect.height - CGFloat(placement.row + placement.rowSpan) * cellHeight + padding
            let w = CGFloat(placement.colSpan) * cellWidth - padding * 2
            let h = CGFloat(placement.rowSpan) * cellHeight - padding * 2

            frames.append(CGRect(x: x, y: y, width: max(w, 200), height: max(h, 150)))
        }

        return frames
    }

    /// Sets the position and size of the frontmost window of a running application
    /// using the Accessibility API (AXUIElement).
    private func setWindowFrame(for runningApp: NSRunningApplication, frame: CGRect) {
        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success, let windows = windowsRef as? [AXUIElement], let window = windows.first else {
            print("[WorkspaceRunner] No AX windows found for \(runningApp.localizedName ?? "unknown")")
            return
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
}
