import SwiftUI
import AppKit

// MARK: - Detected App (local model for the create flow)

struct DetectedApp: Identifiable {
    let id: String
    let name: String
    let icon: String           // SF Symbol fallback
    let appIcon: NSImage?      // Real app icon from system
    let bundleID: String?
    let isRunning: Bool
    var isSelected: Bool
    let screenIndex: Int       // Which display this app's window is on (0 = main)

    init(id: String = UUID().uuidString, name: String, icon: String = "app", appIcon: NSImage? = nil, bundleID: String? = nil, isRunning: Bool = false, isSelected: Bool = false, screenIndex: Int = 0) {
        self.id = id
        self.name = name
        self.icon = icon
        self.appIcon = appIcon
        self.bundleID = bundleID
        self.isRunning = isRunning
        self.isSelected = isSelected
        self.screenIndex = screenIndex
    }
}

// MARK: - Create Workspace Modal

struct CreateWorkspaceModal: View {
    @Environment(WorkspaceStore.self) private var store

    @State private var workspaceName = ""
    @State private var restoreWindowLayout = true
    @State private var reuseOpenApps = true
    @State private var displayMode: DisplayMode = .single
    @State private var detectedApps: [DetectedApp] = []
    @State private var detectedDisplays: [DisplayInfo] = []
    @State private var isLoadingApps = true
    @State private var needsPermission = false

    var onDismiss: () -> Void

    private var selectedCount: Int {
        detectedApps.filter(\.isSelected).count
    }

    private var totalCount: Int {
        detectedApps.count
    }

    private var maxApps: Int {
        displayMode.maxApps
    }

    private var minApps: Int {
        displayMode.minApps
    }

    private var canSave: Bool {
        let nameValid = !workspaceName.trimmingCharacters(in: .whitespaces).isEmpty
        let meetsMin = selectedCount >= minApps
        let withinMax = selectedCount <= maxApps
        return nameValid && meetsMin && withinMax
    }

    private var isAtMaxApps: Bool {
        selectedCount >= maxApps
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Modal
            VStack(spacing: 0) {
                modalHeader
                Divider().opacity(0.4)

                if needsPermission {
                    permissionView
                } else {
                    modalBody
                    Divider().opacity(0.4)
                    modalFooter
                }
            }
            .frame(width: 420)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .fill(DesignSystem.surfaceBackground)
                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                    .shadow(color: .black.opacity(0.2), radius: 40, y: 16)
            )
            .onAppear {
                loadApps()
            }
            // Re-detect displays instantly when monitors are connected/disconnected
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                if !isLoadingApps && !needsPermission {
                    refreshDisplayDetection()
                }
            }
        }
    }

    /// Re-detects displays and rebuilds the app list when screens change
    /// (e.g. monitor plugged in or disconnected).
    private func refreshDisplayDetection() {
        let newDisplays = WindowDetectionService.connectedDisplays()
        let newMode = WindowDetectionService.autoDetectedDisplayMode()

        // Only refresh if display count actually changed
        guard newDisplays.count != detectedDisplays.count else { return }

        detectedDisplays = newDisplays
        displayMode = newMode

        // Re-detect which apps have visible windows on which screens
        let appsByScreen = WindowDetectionService.appsWithVisibleWindows()

        var visibleIDs: Set<String> = []
        for (_, windowInfos) in appsByScreen {
            for info in windowInfos {
                visibleIDs.insert(info.bundleIdentifier)
            }
        }
        visibleWindowBundleIDs = visibleIDs

        // Rebuild the detected apps list
        var apps: [DetectedApp] = []

        for screenIndex in newDisplays.map(\.id).sorted() {
            let windowInfos = appsByScreen[screenIndex] ?? []
            for info in windowInfos {
                apps.append(DetectedApp(
                    name: info.appName,
                    icon: AppIconMapper.sfSymbol(for: info.appName),
                    appIcon: info.icon,
                    bundleID: info.bundleIdentifier,
                    isRunning: true,
                    isSelected: true,
                    screenIndex: screenIndex
                ))
            }
        }

        let allRunning = RunningAppsService.runningApps()
        for runningApp in allRunning {
            if visibleIDs.contains(runningApp.id) { continue }
            apps.append(DetectedApp(
                name: runningApp.name,
                icon: AppIconMapper.sfSymbol(for: runningApp.name),
                appIcon: runningApp.icon,
                bundleID: runningApp.id,
                isRunning: runningApp.isRunning,
                isSelected: false,
                screenIndex: 0
            ))
        }

        detectedApps = apps
        enforceMaxApps()
    }

    // MARK: - Permission View

    private var permissionView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(DesignSystem.primaryBlue)

            VStack(spacing: 6) {
                Text("Accessibility Permission Required")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.textPrimary)

                Text("Ordesk needs Accessibility access to detect running apps and manage window positions.")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                Task { await grantPermissionAndLoad() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gear")
                        .font(.system(size: 12))
                    Text("Open System Settings")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.buttonRadius)
                        .fill(DesignSystem.primaryBlue)
                )
            }
            .buttonStyle(.plain)

            Text("Grant access in System Settings, then return here.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(height: 300)
        .padding(.horizontal, 20)
    }

    // MARK: - Header

    private var modalHeader: some View {
        HStack {
            Text("Save Current Workspace")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.textPrimary)

            Spacer()

            CloseButton(action: onDismiss)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Body

    private var modalBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Workspace name input
                nameInputSection

                // Display mode (auto-detected, non-interactive)
                displayModeSection

                // Detected apps list (per-display when multi-monitor)
                if isLoadingApps {
                    loadingView
                } else {
                    detectedAppsSection
                }

                // Options
                optionsSection
            }
            .padding(20)
        }
        .frame(maxHeight: 480)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Detecting windows and displays...")
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Name Input

    private var nameInputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Workspace Name")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.textSecondary)

            TextField("e.g., Design Work, Development, Writing", text: $workspaceName)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.inputRadius)
                        .fill(DesignSystem.elevatedSurface)
                        .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                )
        }
    }

    // MARK: - Display Mode (auto-detected, non-interactive)

    private var displayModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display Setup")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.textSecondary)

            HStack(spacing: 0) {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 10))
                        Text(mode.label)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(displayMode == mode ? .white : DesignSystem.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(displayMode == mode ? DesignSystem.primaryBlue : Color.clear)
                    )
                    .opacity(displayMode == mode ? 1.0 : 0.4)
                }
            }
            .padding(3)
            .background(
                Capsule()
                    .fill(DesignSystem.elevatedSurface)
                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
            )

            HStack(spacing: 4) {
                Image(systemName: "display")
                    .font(.system(size: 10))
                Text("\(detectedDisplays.count) display\(detectedDisplays.count != 1 ? "s" : "") detected")
                    .font(.system(size: 11))
            }
            .foregroundStyle(DesignSystem.textSecondary)
        }
    }

    // MARK: - Detected Apps (display-aware)

    private var detectedAppsSection: some View {
        VStack(spacing: 16) {
            if detectedDisplays.count <= 1 {
                // Single display: flat list
                singleDisplayAppList
            } else {
                // Multi-display: separate lists per display
                ForEach(detectedDisplays) { display in
                    displayAppList(for: display)
                }

                // Other running apps without visible windows
                let otherApps = detectedApps.filter { !hasVisibleWindow(bundleID: $0.bundleID) }
                if !otherApps.isEmpty {
                    otherRunningAppsList
                }
            }
        }
    }

    /// Single display: one flat list with header
    private var singleDisplayAppList: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Detected Apps")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.textSecondary)

                Spacer()

                Text("\(selectedCount)/\(maxApps) selected")
                    .font(.system(size: 11))
                    .foregroundStyle(isAtMaxApps ? DesignSystem.primaryBlue : DesignSystem.textSecondary)
            }

            appListView(apps: detectedApps)
        }
    }

    /// Per-display app list with display header
    private func displayAppList(for display: DisplayInfo) -> some View {
        let displayApps = detectedApps.filter { $0.screenIndex == display.id && hasVisibleWindow(bundleID: $0.bundleID) }

        return VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: display.isMain ? "laptopcomputer" : "display")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.primaryBlue)
                    Text(display.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignSystem.textSecondary)
                }

                Spacer()

                let displaySelected = displayApps.filter(\.isSelected).count
                Text("\(displaySelected) selected")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.textSecondary)
            }

            if displayApps.isEmpty {
                Text("No open windows on this display")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DesignSystem.elevatedSurface)
                            .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                    )
            } else {
                appListView(apps: displayApps)
            }
        }
    }

    /// Other running apps that have no visible windows
    private var otherRunningAppsList: some View {
        let otherApps = detectedApps.filter { !hasVisibleWindow(bundleID: $0.bundleID) }

        return VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("Other Running Apps")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }

            appListView(apps: otherApps)
        }
    }

    /// Reusable app list view
    private func appListView(apps: [DetectedApp]) -> some View {
        VStack(spacing: 0) {
            ForEach(apps) { app in
                if let index = detectedApps.firstIndex(where: { $0.id == app.id }) {
                    DetectedAppRow(
                        app: app,
                        isSelected: Binding(
                            get: { detectedApps[index].isSelected },
                            set: { newValue in
                                if newValue && isAtMaxApps { return }
                                detectedApps[index].isSelected = newValue
                            }
                        ),
                        isDisabled: !detectedApps[index].isSelected && isAtMaxApps
                    )
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignSystem.elevatedSurface)
                .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().opacity(0.3)

            CheckboxRow(
                isChecked: $restoreWindowLayout,
                label: "Restore window layout"
            )

            CheckboxRow(
                isChecked: $reuseOpenApps,
                label: "Reuse already open apps"
            )
        }
    }

    // MARK: - Footer

    private var modalFooter: some View {
        HStack {
            Spacer()

            // Cancel button
            Button(action: onDismiss) {
                Text("Cancel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            // Save & Edit button
            SaveButton(
                label: "Save & Edit",
                isEnabled: canSave,
                action: saveWorkspace
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(DesignSystem.elevatedSurface.opacity(0.3))
    }

    // MARK: - App Loading

    private func loadApps() {
        // Fast path: already trusted (live check)
        if AccessibilityPermissionManager.isTrusted() {
            AccessibilityPermissionManager.persistGrant()
            populateRealApps()
            return
        }
        // Previously granted but user revoked — clear stale grant
        if AccessibilityPermissionManager.hasPersistedGrant() {
            AccessibilityPermissionManager.clearGrant()
        }
        isLoadingApps = false
        needsPermission = true
    }

    private func grantPermissionAndLoad() async {
        await AccessibilityPermissionManager.waitUntilTrusted()
        await MainActor.run {
            needsPermission = false
            isLoadingApps = true
            populateRealApps()
        }
    }

    /// Tracks which bundleIDs had visible windows (set during populateRealApps)
    @State private var visibleWindowBundleIDs: Set<String> = []

    private func hasVisibleWindow(bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return visibleWindowBundleIDs.contains(id)
    }

    private func populateRealApps() {
        // 1. Auto-detect displays
        detectedDisplays = WindowDetectionService.connectedDisplays()
        displayMode = WindowDetectionService.autoDetectedDisplayMode()

        // 2. Get apps with visible windows, grouped by screen
        let appsByScreen = WindowDetectionService.appsWithVisibleWindows()

        // 3. Track which bundleIDs have visible windows
        var visibleIDs: Set<String> = []
        for (_, windowInfos) in appsByScreen {
            for info in windowInfos {
                visibleIDs.insert(info.bundleIdentifier)
            }
        }
        visibleWindowBundleIDs = visibleIDs

        // 4. Build detected apps list
        var apps: [DetectedApp] = []

        // First: apps with visible windows (pre-selected, assigned to their screen)
        for screenIndex in detectedDisplays.map(\.id).sorted() {
            let windowInfos = appsByScreen[screenIndex] ?? []
            for info in windowInfos {
                apps.append(DetectedApp(
                    name: info.appName,
                    icon: AppIconMapper.sfSymbol(for: info.appName),
                    appIcon: info.icon,
                    bundleID: info.bundleIdentifier,
                    isRunning: true,
                    isSelected: true,
                    screenIndex: screenIndex
                ))
            }
        }

        // Second: running apps WITHOUT visible windows (not selected, shown as "other")
        let allRunning = RunningAppsService.runningApps()
        for runningApp in allRunning {
            if visibleIDs.contains(runningApp.id) { continue }
            apps.append(DetectedApp(
                name: runningApp.name,
                icon: AppIconMapper.sfSymbol(for: runningApp.name),
                appIcon: runningApp.icon,
                bundleID: runningApp.id,
                isRunning: runningApp.isRunning,
                isSelected: false,
                screenIndex: 0
            ))
        }

        detectedApps = apps
        enforceMaxApps()
        isLoadingApps = false
    }

    // MARK: - Actions

    private func saveWorkspace() {
        // De-duplicate by bundleIdentifier (same app may appear on multiple screens)
        var seenBundleIDs: Set<String> = []
        let selectedApps = detectedApps
            .filter(\.isSelected)
            .compactMap { detected -> AppInstance? in
                guard let bundleID = detected.bundleID, !bundleID.isEmpty else { return nil }
                guard !seenBundleIDs.contains(bundleID) else { return nil }
                seenBundleIDs.insert(bundleID)
                return AppInstance(
                    name: detected.name,
                    bundleIdentifier: bundleID,
                    icon: detected.icon,
                    isRunning: detected.isRunning
                )
            }

        let trimmedName = workspaceName.trimmingCharacters(in: .whitespaces)
        let finalName = trimmedName.isEmpty ? "Workspace \(store.workspaces.count + 1)" : trimmedName

        let workspace = Workspace(
            name: finalName,
            apps: selectedApps,
            restoreWindowLayout: restoreWindowLayout,
            reuseOpenApps: reuseOpenApps,
            displayMode: displayMode
        )

        store.addWorkspace(workspace)

        store.showingCreateModal = false
        onDismiss()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            store.selectedWorkspace = workspace
            store.showingEditor = true
        }
    }

    private func enforceMaxApps() {
        var selectedSoFar = 0
        for i in detectedApps.indices {
            if detectedApps[i].isSelected {
                if selectedSoFar >= maxApps {
                    detectedApps[i].isSelected = false
                } else {
                    selectedSoFar += 1
                }
            }
        }
    }
}

// MARK: - Detected App Row

struct DetectedAppRow: View {
    let app: DetectedApp
    @Binding var isSelected: Bool
    var isDisabled: Bool = false
    @State private var isHovered = false

    var body: some View {
        Button {
            if !isDisabled {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isSelected.toggle()
                }
            }
        } label: {
            HStack(spacing: 10) {
                // Checkbox
                AppCheckbox(isChecked: isSelected)

                // App icon — real icon or SF Symbol fallback
                if let nsImage = app.appIcon {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: app.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(DesignSystem.elevatedSurface)
                                .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                        )
                }

                // App name
                Text(app.name)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.textPrimary)

                Spacer()

                // Running badge
                if app.isRunning {
                    Text("Running")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(DesignSystem.elevatedSurface)
                                .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .opacity(isDisabled ? 0.4 : 1.0)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered && !isDisabled ? DesignSystem.hoverBackground : Color.clear)
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

// MARK: - Checkbox

struct AppCheckbox: View {
    let isChecked: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(isChecked ? DesignSystem.primaryBlue : Color.clear)
                .stroke(isChecked ? DesignSystem.primaryBlue : DesignSystem.checkboxBorder, lineWidth: 1.5)
                .frame(width: 16, height: 16)

            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Checkbox Row (for options)

struct CheckboxRow: View {
    @Binding var isChecked: Bool
    let label: String

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isChecked.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                AppCheckbox(isChecked: isChecked)

                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.textPrimary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Save Button

struct SaveButton: View {
    var label: String = "Save"
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.buttonRadius)
                        .fill(
                            isEnabled
                                ? (isHovered ? DesignSystem.primaryBlueHover : DesignSystem.primaryBlue)
                                : DesignSystem.primaryBlue.opacity(0.4)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Close Button

struct CloseButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovered ? DesignSystem.textPrimary : DesignSystem.textSecondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isHovered ? DesignSystem.hoverBackground : DesignSystem.subtleOverlay)
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
    CreateWorkspaceModal(onDismiss: {})
        .environment(WorkspaceStore())
        .frame(width: 600, height: 700)
}
