import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - Borderless window that accepts keyboard input

private class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Global Hotkey Handler

/// Registers a system-wide keyboard shortcut using Carbon's EventHotKey API.
/// This works even when the app is in the background and the menu bar icon is hidden.
private final class GlobalHotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let callback: () -> Void

    /// Registers Ctrl+Option+O as the global hotkey.
    init(callback: @escaping () -> Void) {
        self.callback = callback
        registerHotKey()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func registerHotKey() {
        // Store self in a static so the C callback can reach it
        GlobalHotKeyManager.current = self

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Install the event handler
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                GlobalHotKeyManager.current?.callback()
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        guard status == noErr else {
            print("[GlobalHotKey] Failed to install event handler: \(status)")
            return
        }

        // Register Ctrl+Option+O (keyCode 0x1F = "O")
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x4F524445), // "ORDE"
            id: 1
        )

        let modifiers = UInt32(optionKey | controlKey)
        let keyCode = UInt32(kVK_ANSI_O)

        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if regStatus != noErr {
            print("[GlobalHotKey] Failed to register hotkey: \(regStatus)")
        } else {
            print("[GlobalHotKey] Registered Ctrl+Option+O")
        }
    }

    // Static reference for the C callback to reach the instance
    private static var current: GlobalHotKeyManager?
}

// MARK: - App Delegate

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
    private var hotKeyManager: GlobalHotKeyManager?
    private var popoverWindow: NSWindow?  // Fallback window when status bar icon is hidden
    private var screenChangeObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupEventMonitor()
        setupGlobalHotKey()
        setupScreenChangeMonitor()
        observeStore()

        // Hide dock icon — menu bar only app
        NSApp.setActivationPolicy(.accessory)

        // Show shortcut hint on first launch
        showLaunchHintIfNeeded()
    }

    /// Listens for display connect/disconnect events and re-centers any open windows.
    private func setupScreenChangeMonitor() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenChange()
        }
    }

    /// Re-centers open modal/editor windows on the current main screen
    /// when displays are connected or disconnected.
    private func handleScreenChange() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame

        // Re-center the create modal window
        if let window = createModalWindow, window.isVisible {
            window.setFrame(frame, display: true)
        }

        // Re-center the editor window
        if let window = editorWindow, window.isVisible {
            window.setFrame(frame, display: true)
        }

        // Re-center the settings window
        if let window = settingsWindow, window.isVisible {
            window.setFrame(frame, display: true)
        }
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
            // Also dismiss the fallback popover window
            if self?.popoverWindow != nil {
                self?.closePopoverWindow()
            }
        }
    }

    private func setupGlobalHotKey() {
        hotKeyManager = GlobalHotKeyManager { [weak self] in
            DispatchQueue.main.async {
                self?.togglePopoverSmart()
            }
        }
    }

    // MARK: - Smart Popover Toggle

    /// Toggles the popover. If the status bar icon is visible, attaches to it.
    /// If the icon is hidden (crowded menu bar), shows a floating panel instead.
    private func togglePopoverSmart() {
        // If popover is already showing, close it
        if let popover = popover, popover.isShown {
            popover.performClose(nil)
            return
        }

        // If fallback window is showing, close it
        if popoverWindow != nil {
            closePopoverWindow()
            return
        }

        // Try to show attached to the status bar button
        if let button = statusItem?.button, isStatusItemVisible(button) {
            showPopoverAttached(to: button)
        } else {
            // Status bar icon is hidden — show as floating panel near top-right
            showPopoverAsWindow()
        }
    }

    /// Checks if the status bar button is actually visible on screen.
    private func isStatusItemVisible(_ button: NSStatusBarButton) -> Bool {
        guard let window = button.window else { return false }
        let buttonFrameInScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
        // Check if the button's frame is within any screen's visible area
        for screen in NSScreen.screens {
            if screen.frame.intersects(buttonFrameInScreen) {
                return true
            }
        }
        return false
    }

    /// Shows the popover attached to the status bar button (normal behavior).
    private func showPopoverAttached(to button: NSStatusBarButton) {
        guard let popover = popover else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Shows the popover content as a floating panel near the top-right of the screen.
    /// Used when the menu bar icon is hidden due to a crowded menu bar.
    private func showPopoverAsWindow() {
        closePopoverWindow()

        guard let screen = NSScreen.main else { return }

        let contentView = MenuBarPopover()
            .environment(store)

        let hostingView = NSHostingController(rootView: contentView)

        let panelWidth: CGFloat = 360
        let panelHeight: CGFloat = 520

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.collectionBehavior = [.fullScreenAuxiliary]

        // Position near top-right, below the menu bar
        let menuBarHeight: CGFloat = NSStatusBar.system.thickness
        let padding: CGFloat = 8
        let origin = NSPoint(
            x: screen.frame.maxX - panelWidth - padding,
            y: screen.frame.maxY - menuBarHeight - panelHeight - padding
        )
        window.setFrameOrigin(origin)

        // Fade in
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 1
        }

        popoverWindow = window
    }

    private func closePopoverWindow() {
        guard let window = popoverWindow else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor [weak self] in
                self?.popoverWindow?.orderOut(nil)
                self?.popoverWindow = nil
            }
        }
    }

    // MARK: - Launch Hint

    /// Shows a brief notification on first launch to tell the user about the shortcut.
    private func showLaunchHintIfNeeded() {
        let key = "hasShownShortcutHint"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        // Show after a short delay so the app is fully initialized
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.showShortcutHint()
        }
    }

    private func showShortcutHint() {
        guard let screen = NSScreen.main else { return }

        let hintView = ShortcutHintView()
        let hostingView = NSHostingController(rootView: hintView)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.ignoresMouseEvents = true

        let menuBarHeight: CGFloat = NSStatusBar.system.thickness
        let origin = NSPoint(
            x: screen.frame.midX - 150,
            y: screen.frame.maxY - menuBarHeight - 100
        )
        window.setFrameOrigin(origin)

        window.alphaValue = 0
        window.orderFrontRegardless()

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window.animator().alphaValue = 1
        }

        // Auto dismiss after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                window.animator().alphaValue = 0
            } completionHandler: {
                window.orderOut(nil)
            }
        }
    }

    // MARK: - Store Observation

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
        hudController.show(state: .launchingApps(current: workspace.apps.first?.name ?? "", index: 0, total: workspace.apps.count))

        // Mark workspace as recently used
        store.touchWorkspace(workspace)

        // Run workspace asynchronously
        Task { @MainActor in
            do {
                try await workspaceRunner.run(workspace: workspace) { [weak self] state in
                    self?.hudController.update(state: state)
                }
                // HUD auto-dismisses via WorkspaceHUDController.update(.completed)
            } catch {
                hudController.update(state: .failed(error.localizedDescription))
                // Show error alert after a short delay so user sees the HUD first
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
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
        togglePopoverSmart()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}

// MARK: - Shortcut Hint View

/// A small floating toast that shows on first launch to tell the user about the global shortcut.
private struct ShortcutHintView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 16))
                .foregroundStyle(DesignSystem.primaryBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Ordesk is running")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.textPrimary)

                HStack(spacing: 4) {
                    Text("Press")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.textSecondary)

                    HStack(spacing: 2) {
                        KeyCapView(text: "\u{2303}")
                        KeyCapView(text: "\u{2325}")
                        KeyCapView(text: "O")
                    }

                    Text("to open anytime")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
        )
    }
}

/// A small key cap badge.
private struct KeyCapView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(DesignSystem.textPrimary)
            .frame(minWidth: 18, minHeight: 16)
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(DesignSystem.elevatedSurface)
                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
            )
    }
}
