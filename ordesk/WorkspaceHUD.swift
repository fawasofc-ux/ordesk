import SwiftUI
import AppKit

// MARK: - Workspace HUD View

/// A small floating overlay that shows the current workspace execution state.
/// Displays "Preparing Workspace…", "Launching Safari…", etc.
/// Auto-dismisses after completion.
struct WorkspaceHUD: View {
    let state: WorkspaceRunner.RunnerState
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Icon
            hudIcon
                .frame(width: 36, height: 36)

            // Message
            VStack(spacing: 4) {
                Text(hudTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.textPrimary)

                if let subtitle = hudSubtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(minWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
        )
        .onChange(of: state) { _, newState in
            if newState == .completed {
                // Auto-dismiss after 1 second
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    onDismiss()
                }
            }
        }
    }

    // MARK: - Icon

    @ViewBuilder
    private var hudIcon: some View {
        switch state {
        case .idle:
            EmptyView()

        case .preparingDesktop, .switchingDesktop:
            ProgressView()
                .controlSize(.regular)
                .scaleEffect(0.9)

        case .launchingApps:
            ProgressView()
                .controlSize(.regular)
                .scaleEffect(0.9)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(DesignSystem.runningGreen)
                .transition(.scale.combined(with: .opacity))

        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(DesignSystem.destructiveRed)
                .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Text

    private var hudTitle: String {
        switch state {
        case .idle:
            return ""
        case .preparingDesktop:
            return "Preparing Workspace…"
        case .switchingDesktop:
            return "Switching Desktop…"
        case .launchingApps(let current, _, _):
            return "Launching \(current)…"
        case .completed:
            return "Workspace Ready"
        case .failed:
            return "Something went wrong"
        }
    }

    private var hudSubtitle: String? {
        switch state {
        case .launchingApps(_, let index, let total):
            return "\(index + 1) of \(total)"
        case .failed(let message):
            return message
        default:
            return nil
        }
    }
}

// MARK: - HUD Window Controller

/// Manages the floating HUD window lifecycle.
/// Shows a centered overlay during workspace execution, auto-dismisses on completion.
@MainActor
final class WorkspaceHUDController {

    private var hudWindow: NSWindow?

    /// Shows the HUD on screen.
    func show(state: WorkspaceRunner.RunnerState) {
        if hudWindow == nil {
            createWindow(state: state)
        } else {
            updateContent(state: state)
        }
    }

    /// Updates the HUD state.
    func update(state: WorkspaceRunner.RunnerState) {
        updateContent(state: state)
    }

    /// Dismisses the HUD window with a fade.
    func dismiss() {
        guard let window = hudWindow else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor [weak self] in
                self?.hudWindow?.orderOut(nil)
                self?.hudWindow = nil
            }
        }
    }

    // MARK: - Private

    private func createWindow(state: WorkspaceRunner.RunnerState) {
        guard let screen = NSScreen.main else { return }

        let hudView = WorkspaceHUD(
            state: state,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let hostingView = NSHostingController(rootView: hudView)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Center on screen
        let windowSize = NSSize(width: 260, height: 120)
        let origin = NSPoint(
            x: screen.frame.midX - windowSize.width / 2,
            y: screen.frame.midY - windowSize.height / 2 + 100
        )
        window.setFrameOrigin(origin)

        window.alphaValue = 0
        window.orderFrontRegardless()

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 1
        }

        hudWindow = window
    }

    private func updateContent(state: WorkspaceRunner.RunnerState) {
        guard hudWindow != nil else {
            createWindow(state: state)
            return
        }

        let hudView = WorkspaceHUD(
            state: state,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        hudWindow?.contentViewController = NSHostingController(rootView: hudView)
    }
}

// MARK: - Error Alert

/// Shows a native macOS alert for workspace runner failures.
@MainActor
func showWorkspaceRunnerErrorAlert(error: Error) {
    let alert = NSAlert()
    alert.messageText = "Workspace Failed"
    alert.informativeText = error.localizedDescription
        + "\n\n"
        + WorkspaceRunner.diagnosticMessage()
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "OK")

    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
        AccessibilityPermissionManager.openAccessibilitySettings()
    }
}
