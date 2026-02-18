import SwiftUI
import Combine

@Observable
class WorkspaceStore {
    var workspaces: [Workspace] = []
    var selectedWorkspace: Workspace?
    var showingEditor = false
    var showingCreateModal = false
    var searchText = ""

    var filteredWorkspaces: [Workspace] {
        if searchText.isEmpty {
            return workspaces.sorted { $0.lastUsed > $1.lastUsed }
        }
        return workspaces
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.lastUsed > $1.lastUsed }
    }

    init() {
        loadSampleData()
    }

    func deleteWorkspace(_ workspace: Workspace) {
        workspaces.removeAll { $0.id == workspace.id }
    }

    func addWorkspace(_ workspace: Workspace) {
        workspaces.append(workspace)
    }

    func updateWorkspace(_ workspace: Workspace) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = workspace
        }
    }

    private func loadSampleData() {
        let freelanceApps: [AppInstance] = [
            AppInstance(name: "Chrome", icon: "globe", isRunning: true),
            AppInstance(name: "VS Code", icon: "chevron.left.forwardslash.chevron.right", isRunning: true),
            AppInstance(name: "Figma", icon: "paintpalette", isRunning: true),
            AppInstance(name: "Spotify", icon: "music.note", isRunning: true),
        ]

        let devApps: [AppInstance] = [
            AppInstance(name: "VS Code", icon: "chevron.left.forwardslash.chevron.right", isRunning: true),
            AppInstance(name: "Terminal", icon: "terminal", isRunning: true),
            AppInstance(name: "Chrome", icon: "globe", isRunning: true),
        ]

        workspaces = [
            Workspace(
                name: "Freelance Environment",
                apps: freelanceApps,
                lastUsed: Date().addingTimeInterval(-3 * 3600),
                createdAt: Date().addingTimeInterval(-7 * 86400)
            ),
            Workspace(
                name: "My Dev Space",
                apps: devApps,
                lastUsed: Date().addingTimeInterval(-19 * 3600),
                createdAt: Date().addingTimeInterval(-14 * 86400)
            ),
        ]
    }

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
