import SwiftUI

struct AppIconCluster: View {
    let apps: [AppInstance]
    let iconSize: CGFloat = 20
    let overlap: CGFloat = -6

    var body: some View {
        HStack(spacing: overlap) {
            ForEach(Array(apps.prefix(3).enumerated()), id: \.element.id) { index, app in
                AppMiniIcon(icon: app.icon)
                    .zIndex(Double(3 - index))
            }

            if apps.count > 3 {
                Text("+\(apps.count - 3)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: iconSize, height: iconSize)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(DesignSystem.cardBackground)
                            .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                    )
                    .zIndex(0)
            }
        }
    }
}

struct AppMiniIcon: View {
    let icon: String
    let size: CGFloat = 20

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(DesignSystem.cardBackground)
                    .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                    .shadow(color: .black.opacity(0.06), radius: 1, y: 0.5)
            )
    }
}

#Preview {
    AppIconCluster(apps: [
        AppInstance(name: "Chrome", icon: "globe", isRunning: true),
        AppInstance(name: "VS Code", icon: "chevron.left.forwardslash.chevron.right", isRunning: true),
        AppInstance(name: "Figma", icon: "paintpalette", isRunning: true),
        AppInstance(name: "Spotify", icon: "music.note", isRunning: true),
    ])
    .padding()
}
