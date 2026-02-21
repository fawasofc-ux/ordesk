import AppKit
import Foundation

// MARK: - Workspace Runner

/// Executes a workspace by creating a new macOS Desktop (Space),
/// switching into it, and launching the workspace's apps in order.
///
/// Uses AppleScript + System Events to automate Mission Control
/// (no private CGS APIs — App Store safe).
///
/// Requires:
///   • Accessibility permission (AXIsProcessTrusted)
///   • Automation permission for "System Events" (NSAppleEventsUsageDescription)
@MainActor
final class WorkspaceRunner {

    // MARK: - Error Types

    enum RunnerError: LocalizedError {
        case accessibilityNotGranted
        case missionControlFailed(String)
        case desktopCreationFailed(String)
        case desktopSwitchFailed(String)
        case appLaunchFailed(appName: String, reason: String)

        var errorDescription: String? {
            switch self {
            case .accessibilityNotGranted:
                return "Accessibility permission is required to create new Desktops."
            case .missionControlFailed(let detail):
                return "Unable to open Mission Control. \(detail)"
            case .desktopCreationFailed(let detail):
                return "Unable to create a new Desktop. \(detail)"
            case .desktopSwitchFailed(let detail):
                return "Unable to switch to the new Desktop. \(detail)"
            case .appLaunchFailed(let name, let reason):
                return "Failed to launch \(name): \(reason)"
            }
        }
    }

    // MARK: - State

    enum RunnerState: Equatable {
        case idle
        case preparingDesktop
        case switchingDesktop
        case launchingApps(current: String, index: Int, total: Int)
        case completed
        case failed(String)
    }

    /// Observable state for the HUD overlay.
    private(set) var state: RunnerState = .idle
    private var onStateChange: ((RunnerState) -> Void)?

    // MARK: - Public API

    /// Runs a workspace: creates a new Desktop, switches to it, launches apps.
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

        // Step 1: Create new Desktop
        transition(to: .preparingDesktop)
        try await createNewDesktop()

        // Step 2: Switch to the new Desktop
        transition(to: .switchingDesktop)
        try await switchToNewDesktop()

        // Wait for the Space transition animation to complete
        try await Task.sleep(for: .milliseconds(800))

        // Step 3+4: Launch apps in order
        let apps = workspace.apps
        print("[WorkspaceRunner] Launching \(apps.count) app(s)…")
        for (index, app) in apps.enumerated() {
            print("[WorkspaceRunner] [\(index+1)/\(apps.count)] \(app.name) — \(app.bundleIdentifier)")
            transition(to: .launchingApps(current: app.name, index: index, total: apps.count))
            try await launchApplication(app)

            // Delay between launches to avoid macOS window race conditions
            if index < apps.count - 1 {
                try await Task.sleep(for: .milliseconds(500))
            }
        }

        // Done
        transition(to: .completed)
    }

    // MARK: - PART 1 — Create New Desktop via Mission Control

    /// Opens Mission Control, clicks the "+" button to add a new Desktop, then exits.
    private func createNewDesktop() async throws {
        // Phase 1: Open Mission Control (Ctrl + Up Arrow)
        let openMC = """
        tell application "System Events"
            key code 126 using control down
        end tell
        """
        let openResult = executeAppleScript(openMC)
        if let error = openResult.error {
            throw RunnerError.missionControlFailed(error)
        }

        // Wait for Mission Control animation
        try await Task.sleep(for: .milliseconds(700))

        // Phase 2: Click the "add desktop" button
        // Search resilliently by AXDescription to find the "+" button
        let addDesktop = """
        tell application "System Events"
            tell process "Dock"
                set mcGroup to group 2 of group 1 of group 1
                -- Find the "add desktop" button by searching AXDescription
                set addBtn to missing value
                try
                    set addBtn to button 1 of mcGroup
                end try
                if addBtn is not missing value then
                    click addBtn
                else
                    -- Fallback: search all buttons for "add desktop"
                    set allButtons to buttons of mcGroup
                    repeat with b in allButtons
                        try
                            if description of b contains "add" then
                                click b
                                exit repeat
                            end if
                        end try
                    end repeat
                end if
            end tell
        end tell
        """
        let addResult = executeAppleScript(addDesktop)
        if let error = addResult.error {
            // Try alternative approach: hover to reveal and click
            let fallbackAdd = """
            tell application "System Events"
                tell process "Dock"
                    -- Try clicking the add button in the spaces bar
                    try
                        set spacesList to list 1 of group 2 of group 1 of group 1
                        -- The + button is usually after the last space
                        click button 1 of group 2 of group 1 of group 1
                    end try
                end tell
            end tell
            """
            let fallbackResult = executeAppleScript(fallbackAdd)
            if let fallbackError = fallbackResult.error {
                // Exit Mission Control before throwing
                exitMissionControl()
                throw RunnerError.desktopCreationFailed(
                    "Could not find the 'add desktop' button. \(error) / \(fallbackError)"
                )
            }
        }

        // Wait for the new Space creation animation
        try await Task.sleep(for: .milliseconds(500))

        // Phase 3: Exit Mission Control
        exitMissionControl()

        // Wait for Mission Control to fully close
        try await Task.sleep(for: .milliseconds(400))
    }

    /// Sends Escape to exit Mission Control.
    private func exitMissionControl() {
        let script = """
        tell application "System Events"
            key code 53
        end tell
        """
        _ = executeAppleScript(script)
    }

    // MARK: - PART 2 — Switch to New Desktop

    /// Moves to the rightmost Desktop (the newly created one) using Ctrl+Right Arrow.
    private func switchToNewDesktop() async throws {
        let switchScript = """
        tell application "System Events"
            key code 124 using control down
        end tell
        """
        let result = executeAppleScript(switchScript)
        if let error = result.error {
            throw RunnerError.desktopSwitchFailed(error)
        }
    }

    // MARK: - PART 3+4 — Launch Applications

    /// Launches or activates a single application on the current Desktop.
    ///
    /// Strategy:
    /// 1. If the app is NOT running → launch it via NSWorkspace with `activates = true`
    ///    so it opens a new window on the current Desktop.
    /// 2. If the app IS already running → use AppleScript `tell application ... to activate`
    ///    which brings it to the foreground on the current Desktop (creating a new window if needed).
    /// 3. In both cases, follow up with an AppleScript activate to ensure visibility.
    private func launchApplication(_ app: AppInstance) async throws {
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
        let isAlreadyRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == app.bundleIdentifier
        }

        if !isAlreadyRunning {
            // Launch the app fresh — activates = true so it opens on the current Desktop
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

            // Give the app time to finish launching and create its window
            try await Task.sleep(for: .milliseconds(500))
        } else {
            // App is already running — use AppleScript to activate it on the current Desktop.
            // This tells macOS to bring the app to the foreground, which opens/moves
            // a window onto the active Space.
            let activateScript = """
            tell application id "\(app.bundleIdentifier)" to activate
            """
            let result = executeAppleScript(activateScript)
            if let error = result.error {
                // Fallback: try by name
                let fallbackScript = """
                tell application "\(app.name)" to activate
                """
                let fallbackResult = executeAppleScript(fallbackScript)
                if let fallbackError = fallbackResult.error {
                    print("[WorkspaceRunner] Failed to activate \(app.name): \(error) / \(fallbackError)")
                    // Don't throw — the app is running, it just might not move to this Desktop
                }
            }

            // Give the app time to move its window to the current Desktop
            try await Task.sleep(for: .milliseconds(300))
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

    // MARK: - PART 6 — Diagnostics

    /// Checks if "Displays have separate Spaces" is enabled.
    /// This setting is required for Space creation to work.
    /// Reads from com.apple.spaces preferences.
    static func separateSpacesEnabled() -> Bool {
        // CFPreferences for com.apple.spaces → "spans-displays"
        // When spans-displays == false (or missing), separate Spaces is ON (the default)
        // When spans-displays == true, separate Spaces is OFF
        let defaults = UserDefaults(suiteName: "com.apple.spaces")
        let spansDisplays = defaults?.bool(forKey: "spans-displays") ?? false
        return !spansDisplays
    }

    /// Returns a user-facing error message for common failure scenarios.
    static func diagnosticMessage() -> String {
        var issues: [String] = []

        if !AccessibilityPermissionManager.isTrusted() {
            issues.append("• Grant Accessibility permission in System Settings → Privacy & Security → Accessibility")
        }

        if !separateSpacesEnabled() {
            issues.append("• Enable \"Displays have separate Spaces\" in System Settings → Desktop & Dock")
        }

        if issues.isEmpty {
            return "All required permissions are configured correctly."
        }

        return "Unable to create a new Desktop. Please ensure:\n\n" + issues.joined(separator: "\n")
    }
}
