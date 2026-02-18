import SwiftUI
import Foundation

// MARK: - Data Models

struct AppInstance: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var icon: String
    var isRunning: Bool
    var position: CGPoint?
    var size: CGSize?

    init(id: String = UUID().uuidString, name: String, icon: String, isRunning: Bool = false, position: CGPoint? = nil, size: CGSize? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isRunning = isRunning
        self.position = position
        self.size = size
    }
}

struct Workspace: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var apps: [AppInstance]
    var lastUsed: Date
    var createdAt: Date
    var restoreWindowLayout: Bool
    var reuseOpenApps: Bool
    var displayMode: DisplayMode

    init(id: String = UUID().uuidString, name: String, apps: [AppInstance], lastUsed: Date = Date(), createdAt: Date = Date(), restoreWindowLayout: Bool = true, reuseOpenApps: Bool = true, displayMode: DisplayMode = .single) {
        self.id = id
        self.name = name
        self.apps = apps
        self.lastUsed = lastUsed
        self.createdAt = createdAt
        self.restoreWindowLayout = restoreWindowLayout
        self.reuseOpenApps = reuseOpenApps
        self.displayMode = displayMode
    }
}

enum DisplayMode: String, Codable, CaseIterable {
    case single, dual, triple

    var label: String {
        switch self {
        case .single: return "Single"
        case .dual: return "Dual"
        case .triple: return "Triple"
        }
    }

    var icon: String {
        switch self {
        case .single: return "display"
        case .dual: return "display.2"
        case .triple: return "display.2"
        }
    }
}

enum AppCardSize: String, CaseIterable {
    case small, medium, large

    var label: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        }
    }

    var gridColumns: Int {
        switch self {
        case .small: return 1
        case .medium: return 2
        case .large: return 2
        }
    }

    var gridRows: Int {
        switch self {
        case .small: return 1
        case .medium: return 1
        case .large: return 2
        }
    }
}

struct Preferences: Codable {
    var launchAtLogin: Bool
    var defaultRestoreBehavior: RestoreBehavior
    var quickSwitchShortcut: String
}

enum RestoreBehavior: String, Codable {
    case openNew = "open-new"
    case reuseExisting = "reuse-existing"
}

// MARK: - Design System

enum DesignSystem {
    static let primaryBlue = Color(red: 37/255, green: 99/255, blue: 235/255)       // #2563EB
    static let primaryBlueHover = Color(red: 29/255, green: 78/255, blue: 216/255)  // #1D4ED8
    static let destructiveRed = Color(red: 239/255, green: 68/255, blue: 68/255)    // #EF4444
    static let runningGreen = Color(red: 34/255, green: 197/255, blue: 94/255)      // #22C55E
    static let textPrimary = Color(NSColor.labelColor)
    static let textSecondary = Color(NSColor.secondaryLabelColor)
    static let cardBackground = Color.white
    static let cardBorder = Color.black.opacity(0.08)
    static let hoverBackground = Color.black.opacity(0.03)

    static let popoverWidth: CGFloat = 360
    static let cornerRadius: CGFloat = 12
    static let buttonRadius: CGFloat = 8
    static let inputRadius: CGFloat = 6
}

// MARK: - App Icon Mapping

enum AppIconMapper {
    static func sfSymbol(for appName: String) -> String {
        switch appName.lowercased() {
        case "chrome", "safari", "firefox", "browser":
            return "globe"
        case "vs code", "vscode", "code":
            return "chevron.left.forwardslash.chevron.right"
        case "figma":
            return "paintpalette"
        case "slack":
            return "message"
        case "spotify":
            return "music.note"
        case "terminal", "iterm":
            return "terminal"
        case "notes":
            return "doc.text"
        case "calendar":
            return "calendar"
        default:
            return "app"
        }
    }
}
