import Testing
import Foundation
@testable import ordesk

// MARK: - AccessibilityPermissionManager Tests

/// Tests the permission manager's UserDefaults-based persistence logic.
/// Does NOT call AXIsProcessTrusted() — that requires system interaction.
struct AccessibilityPermissionTests {

    @Test func persistGrant_setsUserDefault() {
        let key = "accessibilityPermissionGranted"
        UserDefaults.standard.removeObject(forKey: key)
        #expect(AccessibilityPermissionManager.hasPersistedGrant() == false)

        AccessibilityPermissionManager.persistGrant()
        #expect(AccessibilityPermissionManager.hasPersistedGrant() == true)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test func clearGrant_removesUserDefault() {
        AccessibilityPermissionManager.persistGrant()
        #expect(AccessibilityPermissionManager.hasPersistedGrant() == true)

        AccessibilityPermissionManager.clearGrant()
        #expect(AccessibilityPermissionManager.hasPersistedGrant() == false)
    }

    @Test func hasPersistedGrant_defaultIsFalse() {
        let key = "accessibilityPermissionGranted"
        UserDefaults.standard.removeObject(forKey: key)
        #expect(AccessibilityPermissionManager.hasPersistedGrant() == false)
    }

    @Test func persistGrant_survivesClearAndReSet() {
        AccessibilityPermissionManager.persistGrant()
        AccessibilityPermissionManager.clearGrant()
        AccessibilityPermissionManager.persistGrant()
        #expect(AccessibilityPermissionManager.hasPersistedGrant() == true)

        // Cleanup
        AccessibilityPermissionManager.clearGrant()
    }
}
