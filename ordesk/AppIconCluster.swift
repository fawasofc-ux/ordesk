import SwiftUI
import AppKit

struct AppIconCluster: View {
    let apps: [AppInstance]
    let iconSize: CGFloat = 20
    let overlap: CGFloat = -6

    var body: some View {
        HStack(spacing: overlap) {
            ForEach(Array(apps.prefix(3).enumerated()), id: \.element.id) { index, app in
                AppMiniIcon(app: app)
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
    let app: AppInstance
    let size: CGFloat = 20

    var body: some View {
        Group {
            if let nsImage = app.resolvedIcon {
                // Real app icon
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                // SF Symbol fallback
                Image(systemName: app.icon)
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
    }
}

#Preview {
    AppIconCluster(apps: [
        AppInstance(name: "Safari", bundleIdentifier: "com.apple.Safari", icon: "globe", isRunning: true),
        AppInstance(name: "Finder", bundleIdentifier: "com.apple.finder", icon: "folder", isRunning: true),
        AppInstance(name: "Terminal", bundleIdentifier: "com.apple.Terminal", icon: "terminal", isRunning: true),
        AppInstance(name: "Notes", bundleIdentifier: "com.apple.Notes", icon: "doc.text", isRunning: true),
    ])
    .padding()
}
