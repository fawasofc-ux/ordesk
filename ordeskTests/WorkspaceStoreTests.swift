import Testing
import Foundation
@testable import ordesk

// MARK: - WorkspaceStore Tests

/// Tests WorkspaceStore CRUD operations and persistence using a temporary directory.
/// These tests do NOT interact with the real app data — they test logic in isolation.
struct WorkspaceStoreTests {

    // MARK: - CRUD Operations

    @Test @MainActor func addWorkspace() {
        let store = WorkspaceStore()
        let initialCount = store.workspaces.count

        let ws = Workspace(name: "Test WS", apps: [
            AppInstance(name: "Safari", bundleIdentifier: "com.apple.Safari"),
        ])
        store.addWorkspace(ws)

        #expect(store.workspaces.count == initialCount + 1)
        #expect(store.workspaces.last?.name == "Test WS")
    }

    @Test @MainActor func updateWorkspace_existing() {
        let store = WorkspaceStore()
        let ws = Workspace(id: "update-test", name: "Original", apps: [])
        store.addWorkspace(ws)

        var updated = ws
        updated.name = "Updated"
        store.updateWorkspace(updated)

        let found = store.workspaces.first { $0.id == "update-test" }
        #expect(found?.name == "Updated")
    }

    @Test @MainActor func updateWorkspace_newInsertsIfNotFound() {
        let store = WorkspaceStore()
        let initialCount = store.workspaces.count

        let ws = Workspace(id: "brand-new", name: "New WS", apps: [])
        store.updateWorkspace(ws)

        #expect(store.workspaces.count == initialCount + 1)
        #expect(store.workspaces.contains { $0.id == "brand-new" })
    }

    @Test @MainActor func deleteWorkspace() {
        let store = WorkspaceStore()
        let ws = Workspace(id: "delete-me", name: "To Delete", apps: [])
        store.addWorkspace(ws)

        let countBefore = store.workspaces.count
        store.deleteWorkspace(ws)

        #expect(store.workspaces.count == countBefore - 1)
        #expect(!store.workspaces.contains { $0.id == "delete-me" })
    }

    @Test @MainActor func deleteWorkspace_nonExistentIsNoOp() {
        let store = WorkspaceStore()
        let countBefore = store.workspaces.count
        let ghost = Workspace(id: "ghost", name: "Ghost", apps: [])
        store.deleteWorkspace(ghost)
        #expect(store.workspaces.count == countBefore)
    }

    @Test @MainActor func clearAllWorkspaces() {
        let store = WorkspaceStore()
        store.addWorkspace(Workspace(name: "WS1", apps: []))
        store.addWorkspace(Workspace(name: "WS2", apps: []))
        store.addWorkspace(Workspace(name: "WS3", apps: []))

        store.clearAllWorkspaces()
        #expect(store.workspaces.isEmpty)
    }

    @Test @MainActor func touchWorkspace_updatesLastUsed() throws {
        let store = WorkspaceStore()
        let oldDate = Date(timeIntervalSince1970: 0)
        let ws = Workspace(id: "touch-test", name: "Touch Me", apps: [], lastUsed: oldDate)
        store.addWorkspace(ws)

        store.touchWorkspace(ws)

        let found = store.workspaces.first { $0.id == "touch-test" }
        #expect(found != nil)
        // lastUsed should now be recent (within last 5 seconds)
        let interval = Date().timeIntervalSince(found!.lastUsed)
        #expect(interval < 5)
    }

    // MARK: - Filtered Workspaces

    @Test @MainActor func filteredWorkspaces_noSearch() {
        let store = WorkspaceStore()
        store.clearAllWorkspaces()
        let ws1 = Workspace(name: "Alpha", apps: [], lastUsed: Date(timeIntervalSinceNow: -100))
        let ws2 = Workspace(name: "Beta", apps: [], lastUsed: Date(timeIntervalSinceNow: -50))
        let ws3 = Workspace(name: "Gamma", apps: [], lastUsed: Date())
        store.addWorkspace(ws1)
        store.addWorkspace(ws2)
        store.addWorkspace(ws3)

        store.searchText = ""
        let filtered = store.filteredWorkspaces

        // Should be sorted by lastUsed descending (most recent first)
        #expect(filtered.count == 3)
        #expect(filtered[0].name == "Gamma")
        #expect(filtered[1].name == "Beta")
        #expect(filtered[2].name == "Alpha")
    }

    @Test @MainActor func filteredWorkspaces_withSearch() {
        let store = WorkspaceStore()
        store.clearAllWorkspaces()
        store.addWorkspace(Workspace(name: "Dev Setup", apps: []))
        store.addWorkspace(Workspace(name: "Design Work", apps: []))
        store.addWorkspace(Workspace(name: "Music", apps: []))

        store.searchText = "de"
        let filtered = store.filteredWorkspaces

        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.name.lowercased().contains("de") })
    }

    @Test @MainActor func filteredWorkspaces_caseInsensitive() {
        let store = WorkspaceStore()
        store.clearAllWorkspaces()
        store.addWorkspace(Workspace(name: "UPPERCASE", apps: []))

        store.searchText = "upper"
        #expect(store.filteredWorkspaces.count == 1)

        store.searchText = "UPPER"
        #expect(store.filteredWorkspaces.count == 1)
    }

    @Test @MainActor func filteredWorkspaces_noMatch() {
        let store = WorkspaceStore()
        store.clearAllWorkspaces()
        store.addWorkspace(Workspace(name: "Dev", apps: []))

        store.searchText = "zzzzz"
        #expect(store.filteredWorkspaces.isEmpty)
    }

    // MARK: - Time Ago

    @Test @MainActor func timeAgo_justNow() {
        let store = WorkspaceStore()
        let result = store.timeAgoString(from: Date())
        #expect(result == "just now")
    }

    @Test @MainActor func timeAgo_oneHour() {
        let store = WorkspaceStore()
        let result = store.timeAgoString(from: Date(timeIntervalSinceNow: -3600))
        #expect(result == "about 1 hour ago")
    }

    @Test @MainActor func timeAgo_multipleHours() {
        let store = WorkspaceStore()
        let result = store.timeAgoString(from: Date(timeIntervalSinceNow: -7200))
        #expect(result == "about 2 hours ago")
    }

    @Test @MainActor func timeAgo_oneDay() {
        let store = WorkspaceStore()
        let result = store.timeAgoString(from: Date(timeIntervalSinceNow: -86400))
        #expect(result == "about 1 day ago")
    }

    @Test @MainActor func timeAgo_multipleDays() {
        let store = WorkspaceStore()
        let result = store.timeAgoString(from: Date(timeIntervalSinceNow: -259200))
        #expect(result == "about 3 days ago")
    }

    @Test @MainActor func timeAgo_lessThanHour() {
        let store = WorkspaceStore()
        let result = store.timeAgoString(from: Date(timeIntervalSinceNow: -1800))
        #expect(result == "just now")
    }

    // MARK: - Active Workspace

    @Test @MainActor func activeWorkspaceID_initiallyNil() {
        let store = WorkspaceStore()
        #expect(store.activeWorkspaceID == nil)
    }

    @Test @MainActor func activeWorkspaceID_canBeSet() {
        let store = WorkspaceStore()
        store.activeWorkspaceID = "ws-123"
        #expect(store.activeWorkspaceID == "ws-123")
    }

    @Test @MainActor func activeWorkspaceID_canBeCleared() {
        let store = WorkspaceStore()
        store.activeWorkspaceID = "ws-123"
        store.activeWorkspaceID = nil
        #expect(store.activeWorkspaceID == nil)
    }

    // MARK: - UI State

    @Test @MainActor func uiState_defaults() {
        let store = WorkspaceStore()
        #expect(store.showingEditor == false)
        #expect(store.showingCreateModal == false)
        #expect(store.showingSettings == false)
        #expect(store.showingClearWorkspace == false)
        #expect(store.workspaceToRun == nil)
        #expect(store.minimizeOthersOnRun == false)
        #expect(store.searchText == "")
        #expect(store.selectedWorkspace == nil)
    }
}
