import SwiftUI
import AppKit

struct MenuBarPopover: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var showActiveDeleteAlert = false
    @State private var workspaceToDelete: Workspace?
    @State private var showingNameInput = false
    @State private var newWorkspaceName = ""

    var body: some View {
        @Bindable var store = store

        ZStack {
            VStack(spacing: 0) {
                // MARK: - Header
                headerSection

                Divider()
                    .opacity(0.5)

                // MARK: - Search
                searchSection

                // MARK: - Welcome Card (only when no workspaces at all)
                if store.workspaces.isEmpty && store.searchText.isEmpty {
                    welcomeCard
                }

                // MARK: - Workspace List or Empty State
                if store.filteredWorkspaces.isEmpty {
                    emptyState
                } else {
                    workspaceList
                }

                Divider()
                    .opacity(0.5)

                // MARK: - Footer
                footerSection

                // MARK: - Quit
                quitButton
            }

            // MARK: - Name Input Popup
            if showingNameInput {
                nameInputPopup
            }
        }
        .frame(width: DesignSystem.popoverWidth)
        .background(DesignSystem.surfaceBackground)
        .alert("Active Workspace", isPresented: $showActiveDeleteAlert) {
            Button("Close Windows & Delete", role: .destructive) {
                if let ws = workspaceToDelete {
                    closeWorkspaceApps(ws)
                    store.activeWorkspaceID = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.deleteWorkspace(ws)
                    }
                    workspaceToDelete = nil
                }
            }
            Button("Minimize & Delete") {
                if let ws = workspaceToDelete {
                    minimizeWorkspaceApps(ws)
                    store.activeWorkspaceID = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.deleteWorkspace(ws)
                    }
                    workspaceToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                workspaceToDelete = nil
            }
        } message: {
            Text("This workspace is currently running. Would you like to close or minimize all its active windows before deleting?")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            HStack(spacing: 8) {
                Image("32")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("Ordesk Workspaces")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
            }

            Spacer()

            HStack(spacing: 4) {
                ClearWorkspaceButton()
                SettingsButton()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Search

    private var searchSection: some View {
        @Bindable var store = store
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            TextField("Search workspaces...", text: $store.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.inputRadius)
                .fill(DesignSystem.elevatedSurface)
                .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Workspace List

    private var workspaceList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(store.filteredWorkspaces) { workspace in
                    WorkspaceRow(
                        workspace: workspace,
                        timeAgo: store.timeAgoString(from: workspace.lastUsed),
                        isActive: store.activeWorkspaceID == workspace.id,
                        onRun: {
                            store.workspaceToRun = workspace
                        },
                        onEdit: {
                            store.selectedWorkspace = workspace
                            store.showingEditor = true
                        },
                        onDelete: {
                            if store.activeWorkspaceID == workspace.id {
                                // Active workspace — show alert with close/minimize options
                                workspaceToDelete = workspace
                                showActiveDeleteAlert = true
                            } else {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    store.deleteWorkspace(workspace)
                                }
                            }
                        }
                    )
                    .onTapGesture {
                        store.selectedWorkspace = workspace
                        store.showingEditor = true
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 420)
    }

    // MARK: - Welcome Card

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [DesignSystem.primaryBlue, DesignSystem.primaryBlueHover],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

                Text("Welcome to Workspace Manager")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
            }

            VStack(alignment: .leading, spacing: 6) {
                welcomeFeatureRow(icon: "square.stack.3d.up", text: "Save your current apps and windows as a workspace")
                welcomeFeatureRow(icon: "bolt.fill", text: "Switch between workspaces instantly to stay focused")
                welcomeFeatureRow(icon: "gearshape", text: "Customize behavior in Settings")
            }
            .padding(.leading, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DesignSystem.primaryBlue.opacity(0.06))
                .stroke(DesignSystem.primaryBlue.opacity(0.12), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private func welcomeFeatureRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.primaryBlue)
                .frame(width: 16)

            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.textSecondary)
                .lineLimit(2)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)

            VStack(spacing: 6) {
                Text(store.searchText.isEmpty ? "No workspaces yet" : "No results")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.textSecondary)

                if store.searchText.isEmpty {
                    Button {
                        promptForNewWorkspace()
                    } label: {
                        Text("Create your first workspace")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.primaryBlue)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                } else {
                    Text("Try a different search term")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: store.workspaces.isEmpty ? 140 : 200)
    }

    // MARK: - Active Workspace Cleanup

    private func closeWorkspaceApps(_ workspace: Workspace) {
        for app in workspace.apps where !app.bundleIdentifier.isEmpty {
            if let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == app.bundleIdentifier
            }) {
                runningApp.forceTerminate()
            }
        }
    }

    private func minimizeWorkspaceApps(_ workspace: Workspace) {
        for app in workspace.apps where !app.bundleIdentifier.isEmpty {
            if let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == app.bundleIdentifier
            }) {
                let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
                var windowsRef: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(
                    appElement, kAXWindowsAttribute as CFString, &windowsRef
                )
                if result == .success, let windows = windowsRef as? [AXUIElement] {
                    for window in windows {
                        AXUIElementSetAttributeValue(
                            window, kAXMinimizedAttribute as CFString, true as CFTypeRef
                        )
                    }
                }
            }
        }
    }

    // MARK: - Create Empty Workspace

    private func promptForNewWorkspace() {
        newWorkspaceName = ""
        withAnimation(.easeInOut(duration: 0.15)) {
            showingNameInput = true
        }
    }

    private func createEmptyWorkspaceAndOpenEditor() {
        let name = newWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.isEmpty ? "New Workspace" : name
        let emptyWorkspace = Workspace(
            name: finalName,
            apps: [],
            displayMode: WindowDetectionService.autoDetectedDisplayMode()
        )
        store.selectedWorkspace = emptyWorkspace
        store.showingEditor = true
        withAnimation(.easeInOut(duration: 0.15)) {
            showingNameInput = false
        }
        newWorkspaceName = ""
    }

    // MARK: - Name Input Popup

    private var nameInputPopup: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showingNameInput = false
                    }
                    newWorkspaceName = ""
                }

            // Popup card
            VStack(spacing: 14) {
                Text("New Workspace")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.textPrimary)

                TextField("Workspace name", text: $newWorkspaceName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.inputRadius)
                            .fill(DesignSystem.elevatedSurface)
                            .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                    )
                    .onSubmit {
                        createEmptyWorkspaceAndOpenEditor()
                    }

                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showingNameInput = false
                        }
                        newWorkspaceName = ""
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.buttonRadius)
                                    .fill(DesignSystem.elevatedSurface)
                                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        createEmptyWorkspaceAndOpenEditor()
                    } label: {
                        Text("Create")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.buttonRadius)
                                    .fill(DesignSystem.primaryBlue)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(width: 260)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DesignSystem.surfaceBackground)
                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 4)
            )
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 8) {
            // Create New Workspace (name input → editor)
            Button {
                promptForNewWorkspace()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Create New")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(DesignSystem.primaryBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.buttonRadius)
                        .fill(DesignSystem.primaryBlue.opacity(0.1))
                        .stroke(DesignSystem.primaryBlue.opacity(0.25), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            // Save Current Workspace
            Button {
                store.showingCreateModal = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Save Current")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.buttonRadius)
                        .fill(DesignSystem.primaryBlue)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DesignSystem.elevatedSurface.opacity(0.5))
    }

    private var quitButton: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "power")
                    .font(.system(size: 10, weight: .medium))
                Text("Quit Ordesk")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(DesignSystem.textSecondary)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
        .padding(.top, 4)
    }
}

// MARK: - Clear Workspace Button

struct ClearWorkspaceButton: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var isHovered = false

    var body: some View {
        Button {
            store.showingClearWorkspace = true
        } label: {
            Image(systemName: "xmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(isHovered ? DesignSystem.textPrimary : DesignSystem.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? DesignSystem.hoverBackground : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .help("Clear / organize open apps")
    }
}

// MARK: - Settings Button

struct SettingsButton: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var isHovered = false

    var body: some View {
        Button {
            store.showingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14))
                .foregroundStyle(isHovered ? DesignSystem.textPrimary : DesignSystem.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? DesignSystem.hoverBackground : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    MenuBarPopover()
        .environment(WorkspaceStore())
}
