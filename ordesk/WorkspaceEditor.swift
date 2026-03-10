import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WorkspaceEditor: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var editingWorkspace: Workspace
    @State private var detectedDisplays: [DisplayInfo] = []
    @State private var addingAppForDisplay: Int? = nil  // Which display index is showing the add popup
    @State private var showUnselectedAppsAlert = false
    @State private var unselectedAppNames: [String] = []
    @State private var draggingAppID: String?
    @State private var isEditingName = false

    var onDismiss: () -> Void

    private let maxAppsPerDisplay = 4

    init(workspace: Workspace, onDismiss: @escaping () -> Void) {
        var ws = workspace
        ws.refreshRunningStates()
        self._editingWorkspace = State(initialValue: ws)
        self.onDismiss = onDismiss
    }

    // MARK: - Computed Helpers

    private var displayCount: Int {
        max(1, detectedDisplays.count)
    }

    /// Apps assigned to a specific display
    private func appsForDisplay(_ displayIndex: Int) -> [AppInstance] {
        editingWorkspace.apps.filter { $0.displayIndex == displayIndex }
    }

    /// Number of empty slots on a display
    private func emptySlotCount(_ displayIndex: Int) -> Int {
        max(0, maxAppsPerDisplay - appsForDisplay(displayIndex).count)
    }

    /// Whether a display has room for more apps
    private func canAddToDisplay(_ displayIndex: Int) -> Bool {
        appsForDisplay(displayIndex).count < maxAppsPerDisplay
    }

    /// All bundle IDs already in the workspace
    private var usedBundleIDs: Set<String> {
        Set(editingWorkspace.apps.map(\.bundleIdentifier).filter { !$0.isEmpty })
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    if addingAppForDisplay != nil {
                        addingAppForDisplay = nil
                    } else {
                        onDismiss()
                    }
                }

            // Modal
            VStack(spacing: 0) {
                editorHeader
                Divider().opacity(0.3)
                displayModeBar
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

            // Add-app overlay
            if let targetDisplay = addingAppForDisplay {
                AddAppOverlay(
                    displayIndex: targetDisplay,
                    displayName: targetDisplay < detectedDisplays.count
                        ? detectedDisplays[targetDisplay].name
                        : "Display \(targetDisplay + 1)",
                    usedBundleIDs: usedBundleIDs,
                    onSelect: { appInfo in
                        addApp(appInfo, toDisplay: targetDisplay)
                        addingAppForDisplay = nil
                    },
                    onDismiss: { addingAppForDisplay = nil }
                )
            }
        }
        .onAppear { detectDisplays() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            detectDisplays()
        }
        .alert("Unselected Apps Detected", isPresented: $showUnselectedAppsAlert) {
            Button("Minimize & Run", role: .destructive) {
                store.updateWorkspace(editingWorkspace)
                store.minimizeOthersOnRun = true
                store.workspaceToRun = editingWorkspace
                onDismiss()
            }
            Button("Run Without Minimizing") {
                store.updateWorkspace(editingWorkspace)
                store.minimizeOthersOnRun = false
                store.workspaceToRun = editingWorkspace
                onDismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let names = unselectedAppNames.prefix(5).joined(separator: ", ")
            let suffix = unselectedAppNames.count > 5 ? " and \(unselectedAppNames.count - 5) more" : ""
            Text("The following apps are currently open but not included in this workspace: \(names)\(suffix). Would you like to minimize them for a cleaner workspace?")
        }
    }

    // MARK: - Display Detection

    private func detectDisplays() {
        detectedDisplays = WindowDetectionService.connectedDisplays()
        let newMode = WindowDetectionService.autoDetectedDisplayMode()
        editingWorkspace.displayMode = newMode

        // Reassign apps from disconnected displays to the last available display
        let maxDisplayIndex = max(0, detectedDisplays.count - 1)
        for i in editingWorkspace.apps.indices {
            if editingWorkspace.apps[i].displayIndex > maxDisplayIndex {
                editingWorkspace.apps[i].displayIndex = maxDisplayIndex
            }
        }
    }

    // MARK: - Add / Remove Helpers

    private func addApp(_ appInfo: RunningAppInfo, toDisplay displayIndex: Int) {
        guard canAddToDisplay(displayIndex) else { return }
        let app = AppInstance(
            name: appInfo.name,
            bundleIdentifier: appInfo.id,
            icon: AppIconMapper.sfSymbol(for: appInfo.name),
            isRunning: appInfo.isRunning,
            cardSize: .small,
            displayIndex: displayIndex
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            editingWorkspace.apps.append(app)
        }
    }

    private func removeApp(_ app: AppInstance) {
        withAnimation(.easeInOut(duration: 0.2)) {
            editingWorkspace.apps.removeAll { $0.id == app.id }
        }
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if isEditingName {
                        TextField("Workspace name", text: $editingWorkspace.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DesignSystem.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(DesignSystem.elevatedSurface)
                                    .stroke(DesignSystem.primaryBlue.opacity(0.4), lineWidth: 1)
                            )
                            .frame(maxWidth: 260)
                            .onSubmit {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isEditingName = false
                                }
                            }
                    } else {
                        Text(editingWorkspace.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DesignSystem.textPrimary)

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isEditingName = true
                            }
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DesignSystem.textSecondary)
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(DesignSystem.hoverBackground)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Rename workspace")
                    }
                }

                Text("Arrange your workspace layout")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.textSecondary)
            }

            Spacer()

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
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Display Mode Bar (auto-detected, non-interactive)

    private var displayModeBar: some View {
        HStack(spacing: 12) {
            // Display mode pills (non-interactive, same as CreateWorkspaceModal)
            HStack(spacing: 0) {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 10))
                        Text(mode.label)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(editingWorkspace.displayMode == mode ? .white : DesignSystem.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(editingWorkspace.displayMode == mode ? DesignSystem.primaryBlue : Color.clear)
                    )
                    .opacity(editingWorkspace.displayMode == mode ? 1.0 : 0.4)
                }
            }
            .padding(3)
            .background(
                Capsule()
                    .fill(DesignSystem.elevatedSurface)
                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
            )

            // Detected display count
            HStack(spacing: 4) {
                Image(systemName: "display")
                    .font(.system(size: 10))
                Text("\(detectedDisplays.count) display\(detectedDisplays.count != 1 ? "s" : "") detected")
                    .font(.system(size: 11))
            }
            .foregroundStyle(DesignSystem.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Editor Content (per-display grids)

    private var editorContent: some View {
        ScrollView {
            if displayCount <= 1 {
                // Single display: one centered grid
                singleDisplaySection
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            } else if displayCount == 2 {
                // Dual display: side-by-side grids with swap button
                HStack(alignment: .top, spacing: 0) {
                    multiDisplaySection(
                        displayIndex: 0,
                        display: detectedDisplays.indices.contains(0) ? detectedDisplays[0] : nil
                    )

                    // Swap button between the two displays
                    swapButton
                        .padding(.horizontal, 8)
                        .padding(.top, 60)

                    multiDisplaySection(
                        displayIndex: 1,
                        display: detectedDisplays.indices.contains(1) ? detectedDisplays[1] : nil
                    )
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            } else {
                // 3 displays: side-by-side grids (no swap)
                HStack(alignment: .top, spacing: 24) {
                    ForEach(0..<displayCount, id: \.self) { displayIndex in
                        let display = displayIndex < detectedDisplays.count ? detectedDisplays[displayIndex] : nil
                        multiDisplaySection(displayIndex: displayIndex, display: display)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Swap Button (dual display only)

    private var swapButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                for i in editingWorkspace.apps.indices {
                    let current = editingWorkspace.apps[i].displayIndex
                    if current == 0 {
                        editingWorkspace.apps[i].displayIndex = 1
                    } else if current == 1 {
                        editingWorkspace.apps[i].displayIndex = 0
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignSystem.primaryBlue)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DesignSystem.primaryBlue.opacity(0.1))
                        .stroke(DesignSystem.primaryBlue.opacity(0.25), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help("Swap apps between displays")
    }

    // MARK: - Single Display Section

    private var singleDisplaySection: some View {
        let apps = appsForDisplay(0)
        let empty = emptySlotCount(0)

        return VStack(alignment: .leading, spacing: 12) {
            // Info bar
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("\(apps.count) app\(apps.count != 1 ? "s" : "") \u{2022} 2×2 grid")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            // 2x2 grid
            displayAppGrid(displayIndex: 0, apps: apps, emptySlots: empty)
        }
    }

    // MARK: - Multi-Display Section

    private func multiDisplaySection(displayIndex: Int, display: DisplayInfo?) -> some View {
        let apps = appsForDisplay(displayIndex)
        let empty = emptySlotCount(displayIndex)

        return VStack(spacing: 12) {
            // Display header
            HStack(spacing: 6) {
                Image(systemName: display?.isMain == true ? "laptopcomputer" : "display")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.primaryBlue)
                Text(display?.name ?? "Display \(displayIndex + 1)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.textPrimary)

                Spacer()

                Text("\(apps.count)/\(maxAppsPerDisplay)")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.textSecondary)
            }

            // 2x2 grid
            displayAppGrid(displayIndex: displayIndex, apps: apps, emptySlots: empty)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 2×2 App Grid

    private func displayAppGrid(displayIndex: Int, apps: [AppInstance], emptySlots: Int) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            // Filled app cards (draggable + drop targets)
            ForEach(apps) { app in
                DraggableAppCard(
                    app: app,
                    onRemove: { removeApp(app) }
                )
                .frame(height: 140)
                .opacity(draggingAppID == app.id ? 0.4 : 1.0)
                .onDrag {
                    draggingAppID = app.id
                    return NSItemProvider(object: app.id as NSString)
                }
                .onDrop(of: [.text], delegate: AppReorderDropDelegate(
                    targetAppID: app.id,
                    targetDisplayIndex: displayIndex,
                    draggingAppID: $draggingAppID,
                    workspace: $editingWorkspace,
                    maxAppsPerDisplay: maxAppsPerDisplay
                ))
            }

            // Empty slot add buttons (drop targets only, not draggable)
            ForEach(0..<emptySlots, id: \.self) { _ in
                AddAppSlot {
                    addingAppForDisplay = displayIndex
                }
                .frame(height: 140)
                .onDrop(of: [.text], delegate: EmptySlotDropDelegate(
                    targetDisplayIndex: displayIndex,
                    draggingAppID: $draggingAppID,
                    workspace: $editingWorkspace,
                    maxAppsPerDisplay: maxAppsPerDisplay
                ))
            }
        }
    }

    // MARK: - Dock Bar

    private var dockBar: some View {
        ZStack {
            // Frosted glass
            Rectangle()
                .fill(.ultraThinMaterial)

            HStack(spacing: 12) {
                Spacer()

                // Run Workspace button
                RunWorkspaceButton {
                    checkAndRunWorkspace()
                }

                // Save Layout button
                DockPillButton(
                    icon: "square.and.arrow.down",
                    label: "Save Layout",
                    action: { saveAndDismiss() }
                )

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 72)
        .overlay(alignment: .top) {
            Divider().opacity(0.3)
        }
    }

    // MARK: - Run Workspace (with unselected app check)

    /// Checks for unselected visible apps before running, shows alert if found.
    private func checkAndRunWorkspace() {
        store.updateWorkspace(editingWorkspace)

        let workspaceBundleIDs = Set(
            editingWorkspace.apps.map(\.bundleIdentifier).filter { !$0.isEmpty }
        )
        let ordeskBundleID = Bundle.main.bundleIdentifier ?? ""

        // Find apps with visible windows that aren't in this workspace
        let visibleBundleIDs = WindowDetectionService.bundleIDsWithVisibleWindows()
        let unselectedIDs = visibleBundleIDs
            .subtracting(workspaceBundleIDs)
            .subtracting([ordeskBundleID])

        if unselectedIDs.isEmpty {
            // No unselected apps — run directly
            store.minimizeOthersOnRun = false
            store.workspaceToRun = editingWorkspace
            onDismiss()
        } else {
            // Get app names for the alert message
            unselectedAppNames = unselectedIDs.compactMap { bundleID in
                NSWorkspace.shared.runningApplications
                    .first(where: { $0.bundleIdentifier == bundleID })?
                    .localizedName
            }.sorted()
            showUnselectedAppsAlert = true
        }
    }

    // MARK: - Save

    private func saveAndDismiss() {
        store.updateWorkspace(editingWorkspace)
        onDismiss()
    }
}

// MARK: - Drag & Drop Delegates

/// Handles dropping an app card onto another app card — reorders within or across displays.
struct AppReorderDropDelegate: DropDelegate {
    let targetAppID: String
    let targetDisplayIndex: Int
    @Binding var draggingAppID: String?
    @Binding var workspace: Workspace
    let maxAppsPerDisplay: Int

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggingAppID, draggedID != targetAppID else { return }
        guard let fromIndex = workspace.apps.firstIndex(where: { $0.id == draggedID }),
              let toIndex = workspace.apps.firstIndex(where: { $0.id == targetAppID })
        else { return }

        let draggedDisplayIndex = workspace.apps[fromIndex].displayIndex
        let isCrossDisplay = draggedDisplayIndex != targetDisplayIndex

        // For cross-display moves, check if target display has room
        if isCrossDisplay {
            let targetCount = workspace.apps.filter { $0.displayIndex == targetDisplayIndex }.count
            guard targetCount < maxAppsPerDisplay else { return }
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            workspace.apps[fromIndex].displayIndex = targetDisplayIndex
            workspace.apps.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingAppID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

/// Handles dropping an app card onto an empty slot — moves the app to that display.
struct EmptySlotDropDelegate: DropDelegate {
    let targetDisplayIndex: Int
    @Binding var draggingAppID: String?
    @Binding var workspace: Workspace
    let maxAppsPerDisplay: Int

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedID = draggingAppID,
              let appIndex = workspace.apps.firstIndex(where: { $0.id == draggedID })
        else {
            draggingAppID = nil
            return false
        }

        let isAlreadyOnDisplay = workspace.apps[appIndex].displayIndex == targetDisplayIndex
        if !isAlreadyOnDisplay {
            let currentCount = workspace.apps.filter { $0.displayIndex == targetDisplayIndex }.count
            guard currentCount < maxAppsPerDisplay else {
                draggingAppID = nil
                return false
            }
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            workspace.apps[appIndex].displayIndex = targetDisplayIndex

            // Move to end of display's section in the array
            let app = workspace.apps.remove(at: appIndex)
            if let lastIndex = workspace.apps.lastIndex(where: { $0.displayIndex == targetDisplayIndex }) {
                workspace.apps.insert(app, at: lastIndex + 1)
            } else {
                workspace.apps.append(app)
            }
        }

        draggingAppID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Add App Overlay

/// A centered overlay panel showing available apps to add to a specific display.
struct AddAppOverlay: View {
    let displayIndex: Int
    let displayName: String
    let usedBundleIDs: Set<String>
    let onSelect: (RunningAppInfo) -> Void
    let onDismiss: () -> Void

    @State private var allApps: [AppListItem] = []
    @State private var searchText = ""
    @State private var isLoading = true

    /// Combined model for running + installed apps
    struct AppListItem: Identifiable {
        let id: String   // bundleIdentifier
        let name: String
        let icon: NSImage
        let isRunning: Bool
        let bundleURL: URL?

        var asRunningAppInfo: RunningAppInfo {
            RunningAppInfo(id: id, name: name, icon: icon, bundleURL: bundleURL, isRunning: isRunning)
        }
    }

    private var filteredApps: [AppListItem] {
        let available = allApps.filter { !usedBundleIDs.contains($0.id) }
        if searchText.isEmpty { return available }
        return available.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var runningApps: [AppListItem] {
        filteredApps.filter(\.isRunning)
    }

    private var installedApps: [AppListItem] {
        filteredApps.filter { !$0.isRunning }
    }

    var body: some View {
        ZStack {
            // Dim backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Panel
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add App")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DesignSystem.textPrimary)
                        Text(displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(DesignSystem.textSecondary)
                    }
                    Spacer()
                    CloseButton(action: onDismiss)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().opacity(0.3)

                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    TextField("Search apps...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.inputRadius)
                        .fill(DesignSystem.elevatedSurface)
                        .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider().opacity(0.3)

                // App list
                if isLoading {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Loading apps...")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignSystem.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else if filteredApps.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text(searchText.isEmpty ? "No available apps" : "No apps matching \"\(searchText)\"")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignSystem.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                            // Running apps section
                            if !runningApps.isEmpty {
                                Section {
                                    ForEach(runningApps) { app in
                                        appRow(app)
                                    }
                                } header: {
                                    sectionHeader(title: "Running Apps", icon: "circle.fill", color: DesignSystem.runningGreen)
                                }
                            }

                            // Installed apps section
                            if !installedApps.isEmpty {
                                Section {
                                    ForEach(installedApps) { app in
                                        appRow(app)
                                    }
                                } header: {
                                    sectionHeader(title: "Installed Apps", icon: "app", color: DesignSystem.textSecondary)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(width: 320)
            .frame(maxHeight: 450)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DesignSystem.surfaceBackground)
                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
            )
        }
        .onAppear { loadApps() }
    }

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(DesignSystem.surfaceBackground)
    }

    private func appRow(_ app: AppListItem) -> some View {
        AppRowButton(app: app, onSelect: {
            onSelect(app.asRunningAppInfo)
        })
    }

    private func loadApps() {
        isLoading = true

        // Running apps
        let running = RunningAppsService.runningApps().map {
            AppListItem(id: $0.id, name: $0.name, icon: $0.icon, isRunning: true, bundleURL: $0.bundleURL)
        }
        let runningIDs = Set(running.map(\.id))

        // Installed apps (excluding those already running)
        let installed = RunningAppsService.installedApps()
            .filter { !runningIDs.contains($0.id) }
            .map {
                AppListItem(id: $0.id, name: $0.name, icon: $0.icon, isRunning: false, bundleURL: $0.bundleURL)
            }

        allApps = running + installed
        isLoading = false
    }
}

// MARK: - App Row Button (used in AddAppOverlay)

private struct AppRowButton: View {
    let app: AddAppOverlay.AppListItem
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(app.name)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.textPrimary)
                    .lineLimit(1)

                Spacer()

                if app.isRunning {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DesignSystem.runningGreen)
                            .frame(width: 6, height: 6)
                        Text("Running")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DesignSystem.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? DesignSystem.hoverBackground : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Reusable Components (kept from previous version)

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

// MARK: - Preview

#Preview {
    WorkspaceEditor(
        workspace: Workspace(
            name: "Freelance Environment",
            apps: [
                AppInstance(name: "Safari", bundleIdentifier: "com.apple.Safari", icon: "globe", isRunning: true, displayIndex: 0),
                AppInstance(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", icon: "chevron.left.forwardslash.chevron.right", isRunning: true, displayIndex: 0),
                AppInstance(name: "Terminal", bundleIdentifier: "com.apple.Terminal", icon: "terminal", isRunning: true, displayIndex: 1),
                AppInstance(name: "Notes", bundleIdentifier: "com.apple.Notes", icon: "doc.text", isRunning: false, displayIndex: 1),
            ]
        ),
        onDismiss: {}
    )
    .environment(WorkspaceStore())
    .frame(width: 1000, height: 700)
}
