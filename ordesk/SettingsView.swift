import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(WorkspaceStore.self) private var store
    var onDismiss: () -> Void

    @State private var activeTab: SettingsTab = .general
    @State private var showClearConfirmation = false
    @State private var showResetPrefsConfirmation = false
    @State private var accessibilityGranted = false
    @State private var accessibilityPollTask: Task<Void, Never>?

    enum SettingsTab: String, CaseIterable {
        case general, shortcuts, advanced, about
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Settings Panel
            HStack(spacing: 0) {
                sidebar
                Divider()
                    .opacity(0.3)
                content
            }
            .frame(width: 600, height: 480)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.windowBackgroundColor))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
        }
        .onAppear {
            refreshAccessibilityStatus()
        }
        .onDisappear {
            accessibilityPollTask?.cancel()
            accessibilityPollTask = nil
        }
        .onChange(of: activeTab) { _, newTab in
            accessibilityPollTask?.cancel()
            accessibilityPollTask = nil
            if newTab == .advanced {
                refreshAccessibilityStatus()
                startAccessibilityPolling()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if activeTab == .advanced {
                refreshAccessibilityStatus()
            }
        }
        .alert("Clear All Workspaces?", isPresented: $showClearConfirmation) {
            Button("Delete All", role: .destructive) {
                store.clearAllWorkspaces()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(store.workspaces.count) saved workspace(s). This cannot be undone.")
        }
        .alert("Reset Preferences?", isPresented: $showResetPrefsConfirmation) {
            Button("Reset", role: .destructive) {
                store.preferences = Preferences()
                store.savePreferences()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore all settings to their default values.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            tabButton(.general, icon: "slider.horizontal.3", label: "General")
            tabButton(.shortcuts, icon: "keyboard", label: "Shortcuts")
            tabButton(.advanced, icon: "square.3.layers.3d", label: "Advanced")
            tabButton(.about, icon: "questionmark.circle", label: "About")
            Spacer()

            // App info in sidebar footer
            VStack(alignment: .leading, spacing: 2) {
                Text("Ordesk")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.textSecondary)
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
        .padding(12)
        .frame(width: 180)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func tabButton(_ tab: SettingsTab, icon: String, label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                activeTab = tab
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(activeTab == tab ? Color(NSColor.controlBackgroundColor) : Color.clear)
                    .shadow(color: activeTab == tab ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
            )
            .foregroundStyle(activeTab == tab ? DesignSystem.textPrimary : DesignSystem.textSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(activeTab == .general ? "General" : activeTab == .shortcuts ? "Keyboard Shortcuts" : activeTab == .advanced ? "Advanced" : "About Ordesk")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.textPrimary)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignSystem.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider().opacity(0.3)

            // Body
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch activeTab {
                    case .general:
                        generalTab
                    case .shortcuts:
                        shortcutsTab
                    case .advanced:
                        advancedTab
                    case .about:
                        aboutTab
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Setting Row Helper

    private func settingRow(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.textSecondary)
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 10)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 0) {
            // Launch at Login
            settingRow(
                title: "Launch at login",
                subtitle: "Automatically start when you log in to macOS"
            ) {
                Toggle("", isOn: $store.preferences.launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: store.preferences.launchAtLogin) { _, newValue in
                        updateLoginItem(enabled: newValue)
                        store.savePreferences()
                    }
            }

            Divider().opacity(0.3).padding(.vertical, 4)

            // Open on Launch
            settingRow(
                title: "Open on launch",
                subtitle: "Show workspace popover when Ordesk starts"
            ) {
                Toggle("", isOn: $store.preferences.showPopoverOnLaunch)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: store.preferences.showPopoverOnLaunch) { _, _ in
                        store.savePreferences()
                    }
            }

            Divider().opacity(0.3).padding(.vertical, 4)

            // Minimize Others on Run
            settingRow(
                title: "Minimize other apps",
                subtitle: "Always minimize unselected apps when running a workspace"
            ) {
                Toggle("", isOn: $store.preferences.minimizeOthersOnRun)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: store.preferences.minimizeOthersOnRun) { _, _ in
                        store.savePreferences()
                    }
            }

            Divider().opacity(0.3).padding(.vertical, 4)

            // Window Padding
            settingRow(
                title: "Window padding",
                subtitle: "Gap between tiled windows (\(Int(store.preferences.windowPadding))px)"
            ) {
                Stepper("", value: $store.preferences.windowPadding, in: 0...20, step: 2)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: store.preferences.windowPadding) { _, _ in
                        store.savePreferences()
                    }
            }

            Divider().opacity(0.3).padding(.vertical, 4)

            // App Launch Delay
            settingRow(
                title: "App launch delay",
                subtitle: "Time between launching each app"
            ) {
                Picker("", selection: $store.preferences.appLaunchDelay) {
                    Text("200ms (Fast)").tag(200.0)
                    Text("400ms").tag(400.0)
                    Text("600ms (Default)").tag(600.0)
                    Text("800ms").tag(800.0)
                    Text("1000ms (Slow)").tag(1000.0)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 160)
                .onChange(of: store.preferences.appLaunchDelay) { _, _ in
                    store.savePreferences()
                }
            }
        }
    }

    // MARK: - Launch at Login

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[Settings] Failed to update login item: \(error)")
        }
    }

    // MARK: - Shortcuts Tab

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Global shortcut
            VStack(alignment: .leading, spacing: 10) {
                Text("Global Shortcut")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.textPrimary)

                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        keyCap("⌃")
                        keyCap("⌥")
                        keyCap("O")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                    )
                }

                Text("Open or close Ordesk from anywhere on your Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.textSecondary)
            }

            Divider().opacity(0.3).padding(.vertical, 16)

            // Shortcuts reference
            VStack(alignment: .leading, spacing: 10) {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.textPrimary)

                VStack(spacing: 0) {
                    shortcutRow(action: "Open / Close Ordesk", keys: "⌃⌥O")
                }
            }
        }
    }

    private func keyCap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(DesignSystem.textPrimary)
            .frame(minWidth: 24, minHeight: 22)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(DesignSystem.elevatedSurface)
                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            )
    }

    private func shortcutRow(action: String, keys: String) -> some View {
        HStack {
            Text(action)
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.textSecondary)
            Spacer()
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DesignSystem.textPrimary.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                )
        }
        .padding(.vertical, 8)
    }

    // MARK: - Advanced Tab

    private var advancedTab: some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 0) {
            // Accessibility Status (read-only indicator)
            VStack(alignment: .leading, spacing: 10) {
                Text("Accessibility")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.textPrimary)

                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(accessibilityGranted ? DesignSystem.runningGreen : DesignSystem.destructiveRed)

                        Text(accessibilityGranted ? "Permission granted" : "Permission required")
                            .font(.system(size: 13))
                            .foregroundStyle(DesignSystem.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                    )

                    Button {
                        AccessibilityPermissionManager.openAccessibilitySettings()
                    } label: {
                        Text("Open Settings")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.primaryBlue)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(DesignSystem.primaryBlue.opacity(0.1))
                                    .stroke(DesignSystem.primaryBlue.opacity(0.25), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Text("Required to detect, position, and minimize windows")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.textSecondary)
            }

            Divider().opacity(0.3).padding(.vertical, 16)

            // Confirm before clearing
            settingRow(
                title: "Confirm before clearing",
                subtitle: "Ask for confirmation before deleting all workspaces"
            ) {
                Toggle("", isOn: $store.preferences.confirmBeforeClear)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: store.preferences.confirmBeforeClear) { _, _ in
                        store.savePreferences()
                    }
            }

            Divider().opacity(0.3).padding(.vertical, 16)

            // Danger Zone
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.destructiveRed)
                    Text("Danger Zone")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignSystem.textPrimary)
                }

                HStack(spacing: 8) {
                    Button {
                        if store.preferences.confirmBeforeClear {
                            showClearConfirmation = true
                        } else {
                            store.clearAllWorkspaces()
                        }
                    } label: {
                        Text("Clear All Workspaces")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.destructiveRed)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(DesignSystem.destructiveRed.opacity(0.08))
                                    .stroke(DesignSystem.destructiveRed.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showResetPrefsConfirmation = true
                    } label: {
                        Text("Reset Preferences")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(NSColor.controlBackgroundColor))
                                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Text("\(store.workspaces.count) workspace(s) saved")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.textSecondary)
            }
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App identity
            HStack(spacing: 14) {
                Image("64")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Ordesk")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DesignSystem.textPrimary)

                    Text("Organize the workspaces, save them, reuse with ease")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.textSecondary)
                        .lineLimit(2)

                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 16)

            Divider().opacity(0.3).padding(.vertical, 8)

            // About description
            VStack(alignment: .leading, spacing: 10) {
                Text("About")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.textPrimary)

                Text("Ordesk is a lightweight macOS menu bar app designed to streamline your workflow. It lets you capture your current desktop setup \u{2014} including open apps and their positions across multiple displays \u{2014} and save it as a reusable workspace. Switch between workspaces instantly with a single click or a global keyboard shortcut.")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Whether you\u{2019}re a developer juggling coding and design tools, a freelancer switching between client projects, or anyone who wants a cleaner desktop \u{2014} Ordesk handles the heavy lifting. It automatically detects connected displays, positions windows using smart tiling layouts, and manages app states so you can focus on what matters.")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 8)

            Divider().opacity(0.3).padding(.vertical, 8)

            // Developer section
            VStack(alignment: .leading, spacing: 10) {
                Text("Developer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.textPrimary)

                VStack(alignment: .leading, spacing: 12) {
                    // Developer identity
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [DesignSystem.primaryBlue, DesignSystem.primaryBlueHover],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)

                            Image("fawaz_usmall")
                                .frame(width: 32, height: 32)
                                .cornerRadius(18)
                                .scaledToFit()
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fawaz Faiz")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(DesignSystem.textPrimary)

                            Text("Senior iOS Developer")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignSystem.textSecondary)
                        }
                    }

                    // Location
                    VStack(spacing: 6) {
                        developerInfoRow(icon: "mappin.circle.fill", text: "From Sri Lanka, Living in United Arab Emirates")
                        developerInfoRow(icon: "phone.circle.fill", text: "+971 52 394 2374")
                        developerInfoRow(icon: "envelope.circle.fill", text: "fawasofc@gmail.com")
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                )
            }
        }
    }

    private func developerInfoRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.primaryBlue)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.textSecondary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    // MARK: - Accessibility Status Helpers

    /// Re-checks accessibility permission off the main thread and updates the UI.
    private func refreshAccessibilityStatus() {
        Task {
            let trusted = await Task.detached {
                AccessibilityPermissionManager.isTrusted()
            }.value
            await MainActor.run {
                accessibilityGranted = trusted
                if trusted {
                    AccessibilityPermissionManager.persistGrant()
                }
            }
        }
    }

    /// Polls accessibility status every 2 seconds while the Advanced tab is visible.
    /// Automatically stops when the tab changes or the view disappears.
    private func startAccessibilityPolling() {
        accessibilityPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                let trusted = await Task.detached {
                    AccessibilityPermissionManager.isTrusted()
                }.value
                await MainActor.run {
                    accessibilityGranted = trusted
                    if trusted {
                        AccessibilityPermissionManager.persistGrant()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView(onDismiss: {})
        .environment(WorkspaceStore())
        .frame(width: 700, height: 550)
}
