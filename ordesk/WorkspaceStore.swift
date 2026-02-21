import SwiftUI
import Foundation

// MARK: - Workspace Store (JSON-persisted)

@Observable
class WorkspaceStore {
    var workspaces: [Workspace] = []
    var selectedWorkspace: Workspace?
    var showingEditor = false
    var showingCreateModal = false
    var showingSettings = false
    var searchText = ""
    var preferences = Preferences(
        launchAtLogin: false,
        defaultRestoreBehavior: .reuseExisting,
        quickSwitchShortcut: "⌘⇧W"
    )

    // MARK: - Persistence paths

    private static let appSupportDir: URL = {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Ordesk", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var workspacesFileURL: URL {
        appSupportDir.appendingPathComponent("workspaces.json")
    }

    private static var preferencesFileURL: URL {
        appSupportDir.appendingPathComponent("preferences.json")
    }

    // MARK: - Computed

    var filteredWorkspaces: [Workspace] {
        if searchText.isEmpty {
            return workspaces.sorted { $0.lastUsed > $1.lastUsed }
        }
        return workspaces
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.lastUsed > $1.lastUsed }
    }

    // MARK: - Init

    init() {
        loadWorkspaces()
        loadPreferences()
    }

    // MARK: - CRUD

    func addWorkspace(_ workspace: Workspace) {
        workspaces.append(workspace)
        saveWorkspaces()
    }

    func updateWorkspace(_ workspace: Workspace) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = workspace
            saveWorkspaces()
        }
    }

    func deleteWorkspace(_ workspace: Workspace) {
        workspaces.removeAll { $0.id == workspace.id }
        saveWorkspaces()
    }

    func clearAllWorkspaces() {
        workspaces.removeAll()
        saveWorkspaces()
    }

    /// Marks a workspace as recently used (updates `lastUsed` timestamp).
    func touchWorkspace(_ workspace: Workspace) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index].lastUsed = Date()
            saveWorkspaces()
        }
    }

    // MARK: - Persistence — Workspaces

    private func saveWorkspaces() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(workspaces)
            try data.write(to: Self.workspacesFileURL, options: .atomic)
        } catch {
            print("[WorkspaceStore] Failed to save workspaces: \(error)")
        }
    }

    private func loadWorkspaces() {
        let url = Self.workspacesFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            workspaces = try decoder.decode([Workspace].self, from: data)
        } catch {
            print("[WorkspaceStore] Failed to load workspaces: \(error)")
        }
    }

    // MARK: - Persistence — Preferences

    func savePreferences() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(preferences)
            try data.write(to: Self.preferencesFileURL, options: .atomic)
        } catch {
            print("[WorkspaceStore] Failed to save preferences: \(error)")
        }
    }

    private func loadPreferences() {
        let url = Self.preferencesFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            preferences = try JSONDecoder().decode(Preferences.self, from: data)
        } catch {
            print("[WorkspaceStore] Failed to load preferences: \(error)")
        }
    }

    // MARK: - Helpers

    func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let hours = Int(interval / 3600)
        if hours < 1 { return "just now" }
        if hours == 1 { return "about 1 hour ago" }
        if hours < 24 { return "about \(hours) hours ago" }
        let days = hours / 24
        if days == 1 { return "about 1 day ago" }
        return "about \(days) days ago"
    }
}
