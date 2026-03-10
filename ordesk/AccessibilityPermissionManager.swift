import ApplicationServices
import AppKit
import Foundation

struct AccessibilityPermissionManager {

    private static let grantedKey = "accessibilityPermissionGranted"

    /// Checks if Accessibility is actually working.
    /// Uses `AXIsProcessTrusted()` first, then falls back to a real AX operation
    /// to handle sandboxed apps where `AXIsProcessTrusted()` may return false
    /// even when the user has granted permission.
    static func isTrusted() -> Bool {
        // Fast path: standard API check
        if AXIsProcessTrusted() {
            return true
        }

        // Fallback: try an actual AX operation against a running app.
        // Under App Sandbox, AXIsProcessTrusted() can return false even
        // when the user has granted Accessibility permission. Testing a
        // real AX call is the reliable way to know.
        return canPerformAXOperation()
    }

    /// Attempts a real AXUIElement operation to see if Accessibility works.
    private static func canPerformAXOperation() -> Bool {
        // Try the frontmost app first, then fall back to any regular app
        let candidates: [NSRunningApplication] = {
            var apps: [NSRunningApplication] = []
            if let front = NSWorkspace.shared.frontmostApplication {
                apps.append(front)
            }
            // Add a couple of regular apps as backup (e.g. Finder is always running)
            apps.append(contentsOf: NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier
            }.prefix(2))
            return apps
        }()

        for app in candidates {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                appElement, kAXWindowsAttribute as CFString, &value
            )
            // .success = got windows, .noValue = app has no windows but AX works
            // Both mean we have Accessibility access
            if result == .success || result == .noValue {
                return true
            }
            // .apiDisabled or .notImplemented = AX is truly not granted
            // .cannotComplete = app may be unresponsive, try next candidate
            if result == .apiDisabled || result == .notImplemented {
                return false
            }
        }

        return false
    }

    /// Returns true if permission was previously granted and persisted.
    static func hasPersistedGrant() -> Bool {
        UserDefaults.standard.bool(forKey: grantedKey)
    }

    /// Persist that the user has granted accessibility permission.
    static func persistGrant() {
        UserDefaults.standard.set(true, forKey: grantedKey)
    }

    /// Clear persisted grant (e.g. if user revokes in System Settings).
    static func clearGrant() {
        UserDefaults.standard.removeObject(forKey: grantedKey)
    }

    /// Triggers the system prompt which registers the app in the Accessibility list.
    static func requestIfNeeded() {
        // Try the standard prompt first
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings → Privacy & Security → Accessibility.
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens System Settings and polls until Accessibility actually works.
    /// Persists the grant so future launches skip the permission flow.
    static func waitUntilTrusted() async {
        guard !isTrusted() else {
            persistGrant()
            return
        }
        // Register the app in the Accessibility list + show prompt
        requestIfNeeded()
        // Also open Settings so the user can toggle it on
        openAccessibilitySettings()
        // Poll until AX actually works
        while !isTrusted() {
            try? await Task.sleep(for: .milliseconds(500))
        }
        persistGrant()
    }
}
