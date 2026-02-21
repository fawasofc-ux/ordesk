import SwiftUI

struct MenuBarPopover: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            // MARK: - Header
            headerSection

            Divider()
                .opacity(0.5)

            // MARK: - Search
            searchSection

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
        }
        .frame(width: DesignSystem.popoverWidth)
        .background(DesignSystem.surfaceBackground)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [DesignSystem.primaryBlue, DesignSystem.primaryBlueHover],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

                Text("Ordesk Workspaces")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
            }

            Spacer()

            SettingsButton()
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
                        onRun: {
                            store.workspaceToRun = workspace
                        },
                        onEdit: {
                            store.selectedWorkspace = workspace
                            store.showingEditor = true
                        },
                        onDelete: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                store.deleteWorkspace(workspace)
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)

            VStack(spacing: 4) {
                Text(store.searchText.isEmpty ? "No workspaces yet" : "No results")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.textSecondary)

                Text(store.searchText.isEmpty ? "Create your first workspace" : "Try a different search term")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }

    // MARK: - Footer

    private var footerSection: some View {
        Button {
            store.showingCreateModal = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("Save Current Workspace")
                    .font(.system(size: 13, weight: .medium))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DesignSystem.elevatedSurface.opacity(0.5))
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
