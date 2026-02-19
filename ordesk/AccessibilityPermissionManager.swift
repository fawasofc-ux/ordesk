import ApplicationServices
import AppKit
import Foundation

struct AccessibilityPermissionManager {

    private static let grantedKey = "accessibilityPermissionGranted"

    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
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
        guard !isTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings → Privacy & Security → Accessibility.
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Registers the app in the Accessibility list, opens System Settings,
    /// then polls until the user toggles the permission on.
    /// Persists the grant so future launches skip the permission flow.
    static func waitUntilTrusted() async {
        guard !isTrusted() else {
            persistGrant()
            return
        }
        // This registers Ordesk in the Accessibility list
        requestIfNeeded()
        // Then open Settings so the user can toggle it on
        openAccessibilitySettings()
        while !isTrusted() {
            try? await Task.sleep(for: .milliseconds(500))
        }
        persistGrant()
    }
}
