import SwiftUI

struct WorkspaceRow: View {
    let workspace: Workspace
    let timeAgo: String
    var onRun: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            AppIconCluster(apps: workspace.apps)

            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.textPrimary)
                    .lineLimit(1)

                Text("\(timeAgo) \u{2022} \(workspace.apps.count) apps")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if isHovered {
                HStack(spacing: 4) {
                    ActionButton(icon: "play.fill", color: DesignSystem.primaryBlue, action: onRun)
                    ActionButton(icon: "pencil", color: .secondary, action: onEdit)
                    ActionButton(icon: "trash", color: DesignSystem.destructiveRed, action: onDelete)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 24)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? DesignSystem.hoverBackground : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contentShape(Rectangle())
    }
}

struct ActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? color.opacity(0.1) : Color.clear)
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

#Preview {
    WorkspaceRow(
        workspace: Workspace(
            name: "Freelance Environment",
            apps: [
                AppInstance(name: "Chrome", icon: "globe", isRunning: true),
                AppInstance(name: "VS Code", icon: "chevron.left.forwardslash.chevron.right", isRunning: true),
                AppInstance(name: "Figma", icon: "paintpalette", isRunning: true),
                AppInstance(name: "Spotify", icon: "music.note", isRunning: true),
            ],
            lastUsed: Date().addingTimeInterval(-3 * 3600)
        ),
        timeAgo: "about 3 hours ago",
        onRun: {},
        onEdit: {},
        onDelete: {}
    )
    .frame(width: 360)
    .padding()
}
