import SwiftUI

struct SettingsView: View {
    @Environment(WorkspaceStore.self) private var store
    var onDismiss: () -> Void

    @State private var activeTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general, shortcuts, advanced
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
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            tabButton(.general, icon: "slider.horizontal.3", label: "General")
            tabButton(.shortcuts, icon: "keyboard", label: "Shortcuts")
            tabButton(.advanced, icon: "square.3.layers.3d", label: "Advanced")
            Spacer()
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
                Text(activeTab == .general ? "General" : activeTab == .shortcuts ? "Keyboard Shortcuts" : "Advanced")
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
                .onHover { isHovered in
                    // Hover handled by system
                }
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
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 0) {
            // Launch at login
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Launch at login")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text("Automatically start when you log in to macOS")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.textSecondary)
                }
                Spacer()
                Toggle("", isOn: $store.preferences.launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.vertical, 12)

            Divider().opacity(0.3).padding(.vertical, 8)

            // Default restore behavior
            VStack(alignment: .leading, spacing: 10) {
                Text("Default restore behavior")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.textPrimary)

                Picker("", selection: $store.preferences.defaultRestoreBehavior) {
                    Text("Reuse already open apps").tag(RestoreBehavior.reuseExisting)
                    Text("Always open new instances").tag(RestoreBehavior.openNew)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Choose how apps should be opened when restoring a workspace")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.textSecondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Shortcuts Tab

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Quick Switch
            VStack(alignment: .leading, spacing: 10) {
                Text("Quick Switch")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.textPrimary)

                HStack(spacing: 10) {
                    Text(store.preferences.quickSwitchShortcut)
                        .font(.system(size: 13))
                        .foregroundStyle(DesignSystem.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                        )

                    Button("Record") {}
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(DesignSystem.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                        )
                }

                Text("Open the workspace switcher from anywhere")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.textSecondary)
            }

            Divider().opacity(0.3).padding(.vertical, 16)

            // All Shortcuts
            VStack(alignment: .leading, spacing: 10) {
                Text("All Shortcuts")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.textPrimary)

                VStack(spacing: 0) {
                    shortcutRow(action: "Open Workspace Switcher", keys: "⌘⇧W")
                    shortcutRow(action: "Save Current Workspace", keys: "⌘⇧S")
                    shortcutRow(action: "Open Settings", keys: "⌘,")
                }
            }
        }
    }

    private func shortcutRow(action: String, keys: String) -> some View {
        HStack {
            Text(action)
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.textSecondary)
            Spacer()
            Text(keys)
                .font(.system(size: 11, design: .rounded))
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
        VStack(alignment: .leading, spacing: 0) {
            // Permissions
            VStack(alignment: .leading, spacing: 10) {
                Text("Permissions")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.textPrimary)

                Button {
                    // Reset accessibility permissions
                } label: {
                    Text("Reset Accessibility Permissions")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignSystem.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)

                Text("This app requires Accessibility permissions to detect and restore windows")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.textSecondary)
            }

            Divider().opacity(0.3).padding(.vertical, 16)

            // Danger Zone
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignSystem.destructiveRed)
                    Text("Danger Zone")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignSystem.textPrimary)
                }

                Button {
                    store.clearAllWorkspaces()
                } label: {
                    Text("Clear All Saved Workspaces")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignSystem.destructiveRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(DesignSystem.destructiveRed.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)

                Text("Permanently delete all saved workspace configurations")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.textSecondary)
            }
        }
    }
}

#Preview {
    SettingsView(onDismiss: {})
        .environment(WorkspaceStore())
        .frame(width: 700, height: 550)
}
