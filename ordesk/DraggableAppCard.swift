import SwiftUI

struct DraggableAppCard: View {
    let app: AppInstance
    @Binding var cardSize: AppCardSize
    var onRemove: () -> Void

    @State private var isHovered = false

    private var iconGradient: LinearGradient {
        let colors: [Color] = {
            switch app.icon {
            case "globe":
                return [.blue.opacity(0.15), .cyan.opacity(0.1)]
            case "chevron.left.forwardslash.chevron.right":
                return [.purple.opacity(0.15), .indigo.opacity(0.1)]
            case "paintpalette":
                return [.pink.opacity(0.15), .orange.opacity(0.1)]
            case "message":
                return [.green.opacity(0.15), .teal.opacity(0.1)]
            case "music.note":
                return [.green.opacity(0.15), .mint.opacity(0.1)]
            case "terminal":
                return [.gray.opacity(0.15), .gray.opacity(0.1)]
            case "doc.text":
                return [.yellow.opacity(0.15), .orange.opacity(0.1)]
            case "calendar":
                return [.red.opacity(0.15), .pink.opacity(0.1)]
            default:
                return [.blue.opacity(0.15), .cyan.opacity(0.1)]
            }
        }()
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var iconColor: Color {
        switch app.icon {
        case "globe": return .blue
        case "chevron.left.forwardslash.chevron.right": return .purple
        case "paintpalette": return .pink
        case "message": return .green
        case "music.note": return .green
        case "terminal": return .gray
        case "doc.text": return .orange
        case "calendar": return .red
        default: return .blue
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Card content
            VStack(spacing: 8) {
                // App icon in gradient circle
                Image(systemName: app.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(iconGradient)
                    )

                // App name + running indicator
                HStack(spacing: 4) {
                    Text(app.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.textPrimary)
                        .lineLimit(1)

                    if app.isRunning {
                        Circle()
                            .fill(DesignSystem.runningGreen)
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(DesignSystem.cardBackground)
                    .stroke(
                        isHovered ? DesignSystem.cardBorder : DesignSystem.subtleBorder,
                        lineWidth: 0.5
                    )
                    .shadow(color: .black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 6 : 2, y: isHovered ? 2 : 1)
            )

            // Hover controls
            if isHovered {
                // Remove button (top-left)
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(DesignSystem.destructiveRed)
                                .shadow(color: DesignSystem.destructiveRed.opacity(0.3), radius: 3, y: 1)
                        )
                }
                .buttonStyle(.plain)
                .offset(x: -4, y: -4)
                .transition(.scale.combined(with: .opacity))

                // Size selector (top-right)
                HStack(spacing: 0) {
                    ForEach(AppCardSize.allCases, id: \.self) { size in
                        SizePillButton(
                            label: size.label,
                            isActive: cardSize == size,
                            action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    cardSize = size
                                }
                            }
                        )
                    }
                }
                .padding(2)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .stroke(DesignSystem.subtleBorder, lineWidth: 0.5)
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Size Pill Button

struct SizePillButton: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isActive ? .white : .secondary)
                .frame(width: 24, height: 20)
                .background(
                    Capsule()
                        .fill(isActive ? DesignSystem.primaryBlue : (isHovered ? DesignSystem.hoverBackground : Color.clear))
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
    let app = AppInstance(name: "Chrome", icon: "globe", isRunning: true)
    DraggableAppCard(
        app: app,
        cardSize: .constant(.small),
        onRemove: {}
    )
    .frame(width: 160, height: 140)
    .padding(20)
}
