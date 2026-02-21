import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WorkspaceEditor: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var editingWorkspace: Workspace
    @State private var showTemplatesPopup = false
    @State private var draggedAppID: String?

    var onDismiss: () -> Void

    init(workspace: Workspace, onDismiss: @escaping () -> Void) {
        // Load from persisted workspace — refresh running states at init
        var ws = workspace
        ws.refreshRunningStates()
        self._editingWorkspace = State(initialValue: ws)
        self.onDismiss = onDismiss
    }

    /// Dynamic column count based on the number of apps
    private var gridConfig: GridConfiguration {
        GridConfiguration.configuration(for: editingWorkspace.apps.count)
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Modal
            VStack(spacing: 0) {
                editorHeader
                Divider().opacity(0.3)
                editorContent
                dockBar
            }
            .frame(maxWidth: 900)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(DesignSystem.surfaceBackground)
                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                    .shadow(color: .black.opacity(0.2), radius: 40, y: 10)
            )
            .padding(.horizontal, 40)
            .padding(.vertical, 40)
        }
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(editingWorkspace.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignSystem.textPrimary)

                Text("Arrange your workspace layout")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.textSecondary)
            }

            Spacer()

            HStack(spacing: 8) {
                // Save button
                Button {
                    saveAndDismiss()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12))
                        Text("Save")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(DesignSystem.primaryBlue)
                }
                .buttonStyle(.plain)

                // Close button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(DesignSystem.hoverBackground)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Grid Content

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Info bar
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("\(editingWorkspace.apps.count) apps \u{2022} \(gridConfig.description) \u{2022} Drag to reorder, hover for resize")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)

            // App grid
            ScrollView {
                appGrid
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
        }
        .padding(.top, 12)
    }

    private var appGrid: some View {
        let columnCount = gridConfig.columns
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount)

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(editingWorkspace.apps) { app in
                let size = app.cardSize

                DraggableAppCard(
                    app: app,
                    cardSize: Binding(
                        get: { cardSizeFor(app) },
                        set: { setCardSize($0, for: app) }
                    ),
                    onRemove: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            editingWorkspace.apps.removeAll { $0.id == app.id }
                        }
                    }
                )
                .frame(height: size.gridRows == 2 ? 292 : 140)
                .gridCellColumns(size.gridColumns)
                // MARK: Drag & Drop
                .onDrag {
                    draggedAppID = app.id
                    return NSItemProvider(object: app.id as NSString)
                }
                .onDrop(of: [UTType.text], delegate: AppDropDelegate(
                    targetAppID: app.id,
                    apps: $editingWorkspace.apps,
                    draggedAppID: $draggedAppID
                ))
            }
        }
    }

    // MARK: - Card Size Helpers

    private func cardSizeFor(_ app: AppInstance) -> AppCardSize {
        app.cardSize
    }

    private func setCardSize(_ size: AppCardSize, for app: AppInstance) {
        if let index = editingWorkspace.apps.firstIndex(where: { $0.id == app.id }) {
            editingWorkspace.apps[index].cardSize = size
        }
    }

    // MARK: - Save

    private func saveAndDismiss() {
        store.updateWorkspace(editingWorkspace)
        onDismiss()
    }

    // MARK: - Dock Bar

    private var dockBar: some View {
        ZStack {
            // Frosted glass
            Rectangle()
                .fill(.ultraThinMaterial)

            HStack(spacing: 12) {
                // Templates button
                ZStack(alignment: .top) {
                    DockPillButton(
                        icon: "rectangle.grid.2x2",
                        label: "Templates",
                        action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showTemplatesPopup.toggle()
                            }
                        }
                    )

                    // Templates popup
                    if showTemplatesPopup {
                        TemplatesPopup(
                            onSelect: { template in
                                applyTemplate(template)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showTemplatesPopup = false
                                }
                            }
                        )
                        .offset(y: -140)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                    }
                }

                // Display mode selector
                DisplayModeSelector(
                    selectedMode: Binding(
                        get: { editingWorkspace.displayMode },
                        set: { editingWorkspace.displayMode = $0 }
                    )
                )

                // Run Workspace button
                RunWorkspaceButton {
                    store.updateWorkspace(editingWorkspace)
                    onDismiss()
                }

                // Saved Layouts button
                DockPillButton(
                    icon: "sparkles",
                    label: "Saved Layouts",
                    action: {}
                )
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 72)
        .overlay(alignment: .top) {
            Divider().opacity(0.3)
        }
    }

    // MARK: - Template Logic

    private func applyTemplate(_ template: LayoutTemplate) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            switch template {
            case .grid:
                for i in editingWorkspace.apps.indices {
                    editingWorkspace.apps[i].cardSize = .small
                }
            case .sidebar:
                guard !editingWorkspace.apps.isEmpty else { return }
                editingWorkspace.apps[0].cardSize = .large
                for i in editingWorkspace.apps.indices.dropFirst() {
                    editingWorkspace.apps[i].cardSize = .small
                }
            case .focus:
                guard !editingWorkspace.apps.isEmpty else { return }
                editingWorkspace.apps[0].cardSize = .large
                for i in editingWorkspace.apps.indices.dropFirst() {
                    editingWorkspace.apps[i].cardSize = .medium
                }
            }
        }
    }
}

// MARK: - Drag & Drop Delegate

struct AppDropDelegate: DropDelegate {
    let targetAppID: String
    @Binding var apps: [AppInstance]
    @Binding var draggedAppID: String?

    func performDrop(info: DropInfo) -> Bool {
        draggedAppID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedAppID,
              draggedID != targetAppID,
              let fromIndex = apps.firstIndex(where: { $0.id == draggedID }),
              let toIndex = apps.firstIndex(where: { $0.id == targetAppID })
        else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            apps.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Layout Template

enum LayoutTemplate {
    case grid, sidebar, focus
}

// MARK: - Display Mode Selector

struct DisplayModeSelector: View {
    @Binding var selectedMode: DisplayMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DisplayMode.allCases, id: \.self) { mode in
                DisplayModeButton(
                    mode: mode,
                    isActive: selectedMode == mode,
                    action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedMode = mode
                        }
                    }
                )
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(DesignSystem.elevatedSurface)
                .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
        )
    }
}

struct DisplayModeButton: View {
    let mode: DisplayMode
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: 10))
                Text(mode.label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isActive ? .white : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? DesignSystem.primaryBlue : (isHovered ? DesignSystem.hoverBackground : Color.clear))
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

// MARK: - Run Workspace Button

struct RunWorkspaceButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 12))
                Text("Run Workspace")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 44)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [DesignSystem.primaryBlue, DesignSystem.primaryBlueHover],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: DesignSystem.primaryBlue.opacity(isHovered ? 0.4 : 0.2), radius: isHovered ? 12 : 6, y: isHovered ? 4 : 2)
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Dock Pill Button

struct DockPillButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isHovered ? DesignSystem.textPrimary : DesignSystem.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isHovered ? DesignSystem.cardBackground : DesignSystem.cardBackground.opacity(0.9))
                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                    .shadow(color: .black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 4 : 2, y: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Templates Popup (Screen 3)

struct TemplatesPopup: View {
    var onSelect: (LayoutTemplate) -> Void

    var body: some View {
        VStack(spacing: 0) {
            TemplateRow(
                icon: "square.grid.2x2",
                title: "Grid Layout",
                subtitle: "Equal sized tiles",
                action: { onSelect(.grid) }
            )

            Divider().padding(.horizontal, 8)

            TemplateRow(
                icon: "sidebar.left",
                title: "Sidebar Layout",
                subtitle: "Main + sidebar",
                action: { onSelect(.sidebar) }
            )

            Divider().padding(.horizontal, 8)

            TemplateRow(
                icon: "rectangle.center.inset.filled",
                title: "Focus Layout",
                subtitle: "One main app",
                action: { onSelect(.focus) }
            )
        }
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
        )
    }
}

struct TemplateRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.primaryBlue)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? DesignSystem.hoverBackground : Color.clear)
                    .padding(.horizontal, 4)
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

// MARK: - Preview

#Preview {
    WorkspaceEditor(
        workspace: Workspace(
            name: "Freelance Environment",
            apps: [
                AppInstance(name: "Safari", bundleIdentifier: "com.apple.Safari", icon: "globe", isRunning: true),
                AppInstance(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", icon: "chevron.left.forwardslash.chevron.right", isRunning: true),
                AppInstance(name: "Terminal", bundleIdentifier: "com.apple.Terminal", icon: "terminal", isRunning: true),
                AppInstance(name: "Notes", bundleIdentifier: "com.apple.Notes", icon: "doc.text", isRunning: false),
            ]
        ),
        onDismiss: {}
    )
    .environment(WorkspaceStore())
    .frame(width: 1000, height: 700)
}
