import SwiftUI
import AppKit

// MARK: - Clear Action

enum ClearAction: String, CaseIterable {
    case minimize
    case forceQuit

    var label: String {
        switch self {
        case .minimize: return "Minimize"
        case .forceQuit: return "Force Quit"
        }
    }

    var icon: String {
        switch self {
        case .minimize: return "minus.circle"
        case .forceQuit: return "xmark.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .minimize: return "Minimize all visible app windows"
        case .forceQuit: return "Force quit all visible apps"
        }
    }
}

// MARK: - Display Target

enum DisplayTarget: Hashable {
    case all
    case specific(index: Int, name: String)

    var label: String {
        switch self {
        case .all: return "All Displays"
        case .specific(_, let name): return name
        }
    }

    var icon: String {
        switch self {
        case .all: return "display.2"
        case .specific: return "display"
        }
    }
}

// MARK: - Clear Workspace View

struct ClearWorkspaceView: View {
    var onDismiss: () -> Void

    @State private var selectedAction: ClearAction = .minimize
    @State private var selectedTarget: DisplayTarget = .all
    @State private var detectedDisplays: [DisplayInfo] = []
    @State private var isExecuting = false

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isExecuting { onDismiss() }
                }

            // Modal card
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DesignSystem.primaryBlue)

                    Text("Clear Workspace")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignSystem.textPrimary)

                    Spacer()

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(DesignSystem.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(DesignSystem.hoverBackground)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                Divider().opacity(0.5)

                // Content
                VStack(alignment: .leading, spacing: 16) {
                    // Action selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Action")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DesignSystem.textSecondary)
                            .textCase(.uppercase)

                        ForEach(ClearAction.allCases, id: \.self) { action in
                            actionRadioButton(action)
                        }
                    }

                    // Display target selection (only show if multiple displays)
                    if detectedDisplays.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Target Display")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DesignSystem.textSecondary)
                                .textCase(.uppercase)

                            // "All Displays" option
                            displayRadioButton(.all)

                            // Individual display options
                            ForEach(detectedDisplays) { display in
                                displayRadioButton(.specific(index: display.id, name: display.name))
                            }
                        }
                    }

                    // Warning for force quit
                    if selectedAction == .forceQuit {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)

                            Text("Unsaved changes in open apps will be lost.")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignSystem.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orange.opacity(0.08))
                                .stroke(Color.orange.opacity(0.2), lineWidth: 0.5)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                Divider().opacity(0.5)

                // Action buttons
                HStack(spacing: 10) {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DesignSystem.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.buttonRadius)
                                    .fill(DesignSystem.elevatedSurface)
                                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        executeClearAction()
                    } label: {
                        HStack(spacing: 6) {
                            if isExecuting {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                            }
                            Text(selectedAction == .minimize ? "Minimize Apps" : "Force Quit Apps")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.buttonRadius)
                                .fill(selectedAction == .forceQuit
                                      ? DesignSystem.destructiveRed
                                      : DesignSystem.primaryBlue)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isExecuting)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .frame(width: 380)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .fill(DesignSystem.surfaceBackground)
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
            )
        }
        .onAppear {
            detectedDisplays = WindowDetectionService.connectedDisplays()
            // Default to "all" when multiple displays
            if detectedDisplays.count > 1 {
                selectedTarget = .all
            } else if let first = detectedDisplays.first {
                selectedTarget = .specific(index: first.id, name: first.name)
            }
        }
    }

    // MARK: - Radio Buttons

    private func actionRadioButton(_ action: ClearAction) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedAction = action
            }
        } label: {
            HStack(spacing: 10) {
                // Radio circle
                ZStack {
                    Circle()
                        .stroke(selectedAction == action
                                ? DesignSystem.primaryBlue
                                : DesignSystem.checkboxBorder,
                                lineWidth: 1.5)
                        .frame(width: 18, height: 18)

                    if selectedAction == action {
                        Circle()
                            .fill(DesignSystem.primaryBlue)
                            .frame(width: 10, height: 10)
                    }
                }

                Image(systemName: action.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(selectedAction == action
                                    ? DesignSystem.primaryBlue
                                    : DesignSystem.textSecondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(action.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignSystem.textPrimary)

                    Text(action.description)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedAction == action
                          ? DesignSystem.primaryBlue.opacity(0.06)
                          : Color.clear)
                    .stroke(selectedAction == action
                            ? DesignSystem.primaryBlue.opacity(0.2)
                            : Color.clear,
                            lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func displayRadioButton(_ target: DisplayTarget) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTarget = target
            }
        } label: {
            HStack(spacing: 10) {
                // Radio circle
                ZStack {
                    Circle()
                        .stroke(selectedTarget == target
                                ? DesignSystem.primaryBlue
                                : DesignSystem.checkboxBorder,
                                lineWidth: 1.5)
                        .frame(width: 18, height: 18)

                    if selectedTarget == target {
                        Circle()
                            .fill(DesignSystem.primaryBlue)
                            .frame(width: 10, height: 10)
                    }
                }

                Image(systemName: target.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(selectedTarget == target
                                    ? DesignSystem.primaryBlue
                                    : DesignSystem.textSecondary)
                    .frame(width: 20)

                Text(target.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTarget == target
                          ? DesignSystem.primaryBlue.opacity(0.06)
                          : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Execute

    private func executeClearAction() {
        isExecuting = true

        // Determine which screen indices to target
        let targetScreenIndices: Set<Int>
        switch selectedTarget {
        case .all:
            targetScreenIndices = Set(detectedDisplays.map(\.id))
        case .specific(let index, _):
            targetScreenIndices = [index]
        }

        // Get apps with visible windows grouped by screen
        let appsPerScreen = WindowDetectionService.appsWithVisibleWindows()
        let ordeskBundleID = Bundle.main.bundleIdentifier ?? ""

        // Collect bundle IDs to act on
        var bundleIDsToAct: Set<String> = []
        for (screenIndex, windowInfos) in appsPerScreen {
            if targetScreenIndices.contains(screenIndex) {
                for info in windowInfos {
                    if info.bundleIdentifier != ordeskBundleID {
                        bundleIDsToAct.insert(info.bundleIdentifier)
                    }
                }
            }
        }

        // Execute the action
        switch selectedAction {
        case .minimize:
            minimizeApps(bundleIDs: bundleIDsToAct)
        case .forceQuit:
            forceQuitApps(bundleIDs: bundleIDsToAct)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isExecuting = false
            onDismiss()
        }
    }

    private func minimizeApps(bundleIDs: Set<String>) {
        for bundleID in bundleIDs {
            guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == bundleID
            }) else { continue }

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
        print("[ClearWorkspace] Minimized \(bundleIDs.count) app(s)")
    }

    private func forceQuitApps(bundleIDs: Set<String>) {
        for bundleID in bundleIDs {
            guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == bundleID
            }) else { continue }

            runningApp.forceTerminate()
            print("[ClearWorkspace] Force quit \(runningApp.localizedName ?? bundleID)")
        }
        print("[ClearWorkspace] Force quit \(bundleIDs.count) app(s)")
    }
}

#Preview {
    ClearWorkspaceView(onDismiss: {})
}
