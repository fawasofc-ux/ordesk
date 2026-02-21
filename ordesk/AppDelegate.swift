import SwiftUI
import AppKit

// MARK: - Borderless window that accepts keyboard input

private class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    let store = WorkspaceStore()
    private var eventMonitor: Any?
    private var editorWindow: NSWindow?
    private var createModalWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var storeObservation: Any?
    private let workspaceRunner = WorkspaceRunner()
    private let hudController = WorkspaceHUDController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupEventMonitor()
        observeStore()

        // Hide dock icon — menu bar only app
        NSApp.setActivationPolicy(.accessory)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Ordesk")
            button.image?.size = NSSize(width: 16, height: 16)
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 360, height: 520)
        popover?.behavior = .transient
        popover?.animates = true

        let contentView = MenuBarPopover()
            .environment(store)

        popover?.contentViewController = NSHostingController(rootView: contentView)
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }
    }

    private func observeStore() {
        func observeEditor() {
            withObservationTracking {
                _ = store.showingEditor
                _ = store.selectedWorkspace
            } onChange: { [weak self] in
                DispatchQueue.main.async {
                    self?.handleEditorToggle()
                    observeEditor()
                }
            }
        }

        func observeCreateModal() {
            withObservationTracking {
                _ = store.showingCreateModal
            } onChange: { [weak self] in
                DispatchQueue.main.async {
                    self?.handleCreateModalToggle()
                    observeCreateModal()
                }
            }
        }

        func observeSettings() {
            withObservationTracking {
                _ = store.showingSettings
            } onChange: { [weak self] in
                DispatchQueue.main.async {
                    self?.handleSettingsToggle()
                    observeSettings()
                }
            }
        }

        func observeRunWorkspace() {
            withObservationTracking {
                _ = store.workspaceToRun
            } onChange: { [weak self] in
                DispatchQueue.main.async {
                    self?.handleRunWorkspace()
                    observeRunWorkspace()
                }
            }
        }

        observeEditor()
        observeCreateModal()
        observeSettings()
        observeRunWorkspace()
    }

    private func handleEditorToggle() {
        if store.showingEditor, let workspace = store.selectedWorkspace {
            popover?.performClose(nil)
            openEditorWindow(for: workspace)
        } else {
            closeEditorWindow()
        }
    }

    private func handleSettingsToggle() {
        if store.showingSettings {
            popover?.performClose(nil)
            openSettingsWindow()
        } else {
            closeSettingsWindow()
        }
    }

    private func handleCreateModalToggle() {
        if store.showingCreateModal {
            popover?.performClose(nil)
            openCreateModalWindow()
        } else {
            closeCreateModalWindow()
        }
    }

    private func handleRunWorkspace() {
        guard let workspace = store.workspaceToRun else { return }
        store.workspaceToRun = nil

        // Close any open overlays
        popover?.performClose(nil)
        closeEditorWindow()

        // Show HUD
        hudController.show(state: .preparingDesktop)

        // Mark workspace as recently used
        store.touchWorkspace(workspace)

        // Run workspace asynchronously
        Task { @MainActor in
            do {
                try await workspaceRunner.run(workspace: workspace) { [weak self] state in
                    self?.hudController.update(state: state)
                }
                // HUD auto-dismisses on .completed via WorkspaceHUD's onChange
            } catch {
                hudController.update(state: .failed(error.localizedDescription))
                // Show error alert after a short delay so user sees the HUD first
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.hudController.dismiss()
                    showWorkspaceRunnerErrorAlert(error: error)
                }
            }
        }
    }

    func openEditorWindow(for workspace: Workspace) {
        // Close existing editor if any
        closeEditorWindow()

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        let editorView = WorkspaceEditor(
            workspace: workspace,
            onDismiss: { [weak self] in
                self?.store.showingEditor = false
                self?.store.selectedWorkspace = nil
                self?.closeEditorWindow()
            }
        )
        .environment(store)

        let hostingView = NSHostingController(rootView: editorView)

        let window = KeyableWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.setFrame(screen.frame, display: true)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Show app temporarily so the window can become key
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Hide dock icon again after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.setActivationPolicy(.accessory)
            window.makeKeyAndOrderFront(nil)
        }

        editorWindow = window
    }

    func closeEditorWindow() {
        editorWindow?.orderOut(nil)
        editorWindow = nil
    }

    func openCreateModalWindow() {
        closeCreateModalWindow()

        guard let screen = NSScreen.main else { return }

        let modalView = CreateWorkspaceModal(
            onDismiss: { [weak self] in
                self?.store.showingCreateModal = false
                self?.closeCreateModalWindow()
            }
        )
        .environment(store)

        let hostingView = NSHostingController(rootView: modalView)

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.setFrame(screen.frame, display: true)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.setActivationPolicy(.accessory)
            window.makeKeyAndOrderFront(nil)
        }

        createModalWindow = window
    }

    func closeCreateModalWindow() {
        createModalWindow?.orderOut(nil)
        createModalWindow = nil
    }

    func openSettingsWindow() {
        closeSettingsWindow()

        guard let screen = NSScreen.main else { return }

        let settingsView = SettingsView(
            onDismiss: { [weak self] in
                self?.store.showingSettings = false
                self?.closeSettingsWindow()
            }
        )
        .environment(store)

        let hostingView = NSHostingController(rootView: settingsView)

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.setFrame(screen.frame, display: true)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.setActivationPolicy(.accessory)
            window.makeKeyAndOrderFront(nil)
        }

        settingsWindow = window
    }

    func closeSettingsWindow() {
        settingsWindow?.orderOut(nil)
        settingsWindow = nil
    }

    @objc private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}
