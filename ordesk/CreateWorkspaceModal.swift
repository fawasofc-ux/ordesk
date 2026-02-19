import SwiftUI

// MARK: - Detected App (local model for the create flow)

struct DetectedApp: Identifiable {
    let id = UUID().uuidString
    let name: String
    let icon: String
    let isRunning: Bool
    var isSelected: Bool
}

// MARK: - Create Workspace Modal

struct CreateWorkspaceModal: View {
    @Environment(WorkspaceStore.self) private var store

    @State private var workspaceName = ""
    @State private var restoreWindowLayout = true
    @State private var reuseOpenApps = true
    @State private var displayMode: DisplayMode = .single
    @State private var detectedApps: [DetectedApp] = Self.sampleDetectedApps()

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
        let meetsMin = selectedCount >= minApps
        let withinMax = selectedCount <= maxApps
        return meetsMin && withinMax
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
                modalBody
                Divider().opacity(0.4)
                modalFooter
            }
            .frame(width: 420)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .fill(DesignSystem.surfaceBackground)
                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                    .shadow(color: .black.opacity(0.2), radius: 40, y: 16)
            )
            .onAppear {
                enforceMaxApps()
            }
        }
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

                // Display mode selector
                displayModeSection

                // Detected apps list
                detectedAppsSection

                // Options
                optionsSection
            }
            .padding(20)
        }
        .frame(maxHeight: 480)
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

    // MARK: - Display Mode

    private var displayModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display Setup")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.textSecondary)

            HStack(spacing: 0) {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            displayMode = mode
                            // Deselect excess apps when switching to a lower mode
                            enforceMaxApps()
                        }
                    } label: {
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
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                Capsule()
                    .fill(DesignSystem.elevatedSurface)
                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
            )

            Text("Max \(maxApps) apps • Min \(minApps) app\(minApps > 1 ? "s" : "") to save")
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.textSecondary)
        }
    }

    // MARK: - Detected Apps

    private var detectedAppsSection: some View {
        VStack(spacing: 8) {
            // Header row
            HStack {
                Text("Detected Apps")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.textSecondary)

                Spacer()

                Text("\(selectedCount)/\(maxApps) selected")
                    .font(.system(size: 11))
                    .foregroundStyle(isAtMaxApps ? DesignSystem.primaryBlue : DesignSystem.textSecondary)
            }

            // App list
            VStack(spacing: 0) {
                ForEach(Array(detectedApps.enumerated()), id: \.element.id) { index, app in
                    DetectedAppRow(
                        app: app,
                        isSelected: Binding(
                            get: { detectedApps[index].isSelected },
                            set: { newValue in
                                // Only allow selecting if under max, always allow deselecting
                                if newValue && isAtMaxApps { return }
                                detectedApps[index].isSelected = newValue
                            }
                        ),
                        isDisabled: !detectedApps[index].isSelected && isAtMaxApps
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DesignSystem.elevatedSurface)
                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
            )
        }
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

    // MARK: - Actions

    private func saveWorkspace() {
        let selectedApps = detectedApps
            .filter(\.isSelected)
            .map { detected in
                AppInstance(
                    name: detected.name,
                    icon: detected.icon,
                    isRunning: detected.isRunning
                )
            }

        // Use entered name or generate a default
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

        // Dismiss the create modal first, then open editor
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

    // MARK: - Sample Data

    static func sampleDetectedApps() -> [DetectedApp] {
        [
            DetectedApp(name: "Chrome", icon: "globe", isRunning: true, isSelected: true),
            DetectedApp(name: "VS Code", icon: "chevron.left.forwardslash.chevron.right", isRunning: true, isSelected: true),
            DetectedApp(name: "Figma", icon: "paintpalette", isRunning: true, isSelected: true),
            DetectedApp(name: "Slack", icon: "message", isRunning: true, isSelected: true),
            DetectedApp(name: "Spotify", icon: "music.note", isRunning: true, isSelected: true),
            DetectedApp(name: "Terminal", icon: "terminal", isRunning: true, isSelected: true),
            DetectedApp(name: "Notes", icon: "doc.text", isRunning: false, isSelected: false),
            DetectedApp(name: "Calendar", icon: "calendar", isRunning: false, isSelected: false),
        ]
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

                // App icon
                Image(systemName: app.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(DesignSystem.elevatedSurface)
                            .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                    )

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
