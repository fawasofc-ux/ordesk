import Testing
import Foundation
@testable import ordesk

// MARK: - AppInstance Tests

struct AppInstanceTests {

    @Test func initWithDefaults() {
        let app = AppInstance(name: "Safari")
        #expect(app.name == "Safari")
        #expect(app.bundleIdentifier == "")
        #expect(app.icon == "app")
        #expect(app.isRunning == false)
        #expect(app.position == nil)
        #expect(app.size == nil)
        #expect(app.cardSize == .small)
        #expect(app.displayIndex == 0)
    }

    @Test func initWithAllParameters() {
        let app = AppInstance(
            id: "test-id",
            name: "Chrome",
            bundleIdentifier: "com.google.Chrome",
            icon: "globe",
            isRunning: true,
            position: CGPoint(x: 100, y: 200),
            size: CGSize(width: 800, height: 600),
            cardSize: .medium,
            displayIndex: 1
        )
        #expect(app.id == "test-id")
        #expect(app.name == "Chrome")
        #expect(app.bundleIdentifier == "com.google.Chrome")
        #expect(app.icon == "globe")
        #expect(app.isRunning == true)
        #expect(app.position == CGPoint(x: 100, y: 200))
        #expect(app.size == CGSize(width: 800, height: 600))
        #expect(app.cardSize == .medium)
        #expect(app.displayIndex == 1)
    }

    @Test func equatable() {
        let app1 = AppInstance(id: "same", name: "Safari", bundleIdentifier: "com.apple.Safari")
        let app2 = AppInstance(id: "same", name: "Safari", bundleIdentifier: "com.apple.Safari")
        let app3 = AppInstance(id: "different", name: "Safari", bundleIdentifier: "com.apple.Safari")
        #expect(app1 == app2)
        #expect(app1 != app3)
    }

    @Test func codableRoundTrip() throws {
        let app = AppInstance(
            name: "VS Code",
            bundleIdentifier: "com.microsoft.VSCode",
            icon: "chevron.left.forwardslash.chevron.right",
            isRunning: false,
            displayIndex: 2
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(app)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AppInstance.self, from: data)
        #expect(decoded.name == "VS Code")
        #expect(decoded.bundleIdentifier == "com.microsoft.VSCode")
        #expect(decoded.displayIndex == 2)
    }

    @Test func backwardCompatibility_missingDisplayIndex() throws {
        // Simulate old JSON without displayIndex field
        let json = """
        {
            "id": "old-app",
            "name": "Safari",
            "bundleIdentifier": "com.apple.Safari",
            "icon": "globe",
            "isRunning": false,
            "cardSize": "small"
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppInstance.self, from: data)
        #expect(decoded.displayIndex == 0)
        #expect(decoded.name == "Safari")
    }
}

// MARK: - Workspace Tests

struct WorkspaceTests {

    @Test func initWithDefaults() {
        let ws = Workspace(name: "Dev Setup", apps: [])
        #expect(ws.name == "Dev Setup")
        #expect(ws.apps.isEmpty)
        #expect(ws.restoreWindowLayout == true)
        #expect(ws.reuseOpenApps == true)
        #expect(ws.displayMode == .single)
    }

    @Test func initWithApps() {
        let apps = [
            AppInstance(name: "Safari", bundleIdentifier: "com.apple.Safari"),
            AppInstance(name: "Chrome", bundleIdentifier: "com.google.Chrome"),
        ]
        let ws = Workspace(name: "Browsing", apps: apps, displayMode: .dual)
        #expect(ws.apps.count == 2)
        #expect(ws.displayMode == .dual)
    }

    @Test func codableRoundTrip() throws {
        let apps = [
            AppInstance(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", displayIndex: 0),
            AppInstance(name: "Figma", bundleIdentifier: "com.figma.Desktop", displayIndex: 1),
        ]
        let ws = Workspace(name: "Dev", apps: apps, displayMode: .dual)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(ws)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Workspace.self, from: data)

        #expect(decoded.name == "Dev")
        #expect(decoded.apps.count == 2)
        #expect(decoded.apps[0].displayIndex == 0)
        #expect(decoded.apps[1].displayIndex == 1)
        #expect(decoded.displayMode == .dual)
    }

    @Test func equatable() {
        let fixedDate = Date(timeIntervalSince1970: 1000)
        let ws1 = Workspace(id: "same", name: "WS", apps: [], lastUsed: fixedDate, createdAt: fixedDate)
        let ws2 = Workspace(id: "same", name: "WS", apps: [], lastUsed: fixedDate, createdAt: fixedDate)
        let ws3 = Workspace(id: "diff", name: "WS", apps: [], lastUsed: fixedDate, createdAt: fixedDate)
        #expect(ws1 == ws2)
        #expect(ws1 != ws3)
    }
}

// MARK: - DisplayMode Tests

struct DisplayModeTests {

    @Test func labels() {
        #expect(DisplayMode.single.label == "Single")
        #expect(DisplayMode.dual.label == "Dual")
        #expect(DisplayMode.triple.label == "Triple")
    }

    @Test func maxApps() {
        #expect(DisplayMode.single.maxApps == 4)
        #expect(DisplayMode.dual.maxApps == 8)
        #expect(DisplayMode.triple.maxApps == 12)
    }

    @Test func minApps() {
        #expect(DisplayMode.single.minApps == 1)
        #expect(DisplayMode.dual.minApps == 2)
        #expect(DisplayMode.triple.minApps == 3)
    }

    @Test func icons() {
        #expect(DisplayMode.single.icon == "display")
        #expect(DisplayMode.dual.icon == "display.2")
        #expect(DisplayMode.triple.icon == "display.2")
    }

    @Test func codableRawValues() {
        #expect(DisplayMode.single.rawValue == "single")
        #expect(DisplayMode.dual.rawValue == "dual")
        #expect(DisplayMode.triple.rawValue == "triple")
    }

    @Test func allCases() {
        #expect(DisplayMode.allCases.count == 3)
    }
}

// MARK: - AppCardSize Tests

struct AppCardSizeTests {

    @Test func labels() {
        #expect(AppCardSize.small.label == "S")
        #expect(AppCardSize.medium.label == "M")
        #expect(AppCardSize.large.label == "L")
    }

    @Test func gridDimensions() {
        #expect(AppCardSize.small.gridColumns == 1)
        #expect(AppCardSize.small.gridRows == 1)
        #expect(AppCardSize.medium.gridColumns == 2)
        #expect(AppCardSize.medium.gridRows == 1)
        #expect(AppCardSize.large.gridColumns == 2)
        #expect(AppCardSize.large.gridRows == 2)
    }
}

// MARK: - Preferences Tests

struct PreferencesTests {

    @Test func defaults() {
        let prefs = Preferences()
        #expect(prefs.launchAtLogin == false)
        #expect(prefs.defaultRestoreBehavior == .reuseExisting)
        #expect(prefs.quickSwitchShortcut == "⌃⌥O")
        #expect(prefs.showPopoverOnLaunch == true)
        #expect(prefs.minimizeOthersOnRun == false)
        #expect(prefs.windowPadding == 4)
        #expect(prefs.appLaunchDelay == 600)
        #expect(prefs.confirmBeforeClear == true)
    }

    @Test func codableRoundTrip() throws {
        var prefs = Preferences()
        prefs.launchAtLogin = true
        prefs.windowPadding = 10
        prefs.appLaunchDelay = 200
        prefs.minimizeOthersOnRun = true

        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)

        #expect(decoded.launchAtLogin == true)
        #expect(decoded.windowPadding == 10)
        #expect(decoded.appLaunchDelay == 200)
        #expect(decoded.minimizeOthersOnRun == true)
    }

    @Test func backwardCompatibility_missingFields() throws {
        // Simulate old JSON with only a few fields
        let json = """
        {
            "launchAtLogin": true,
            "defaultRestoreBehavior": "reuse-existing",
            "quickSwitchShortcut": "⌃⌥O"
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(decoded.launchAtLogin == true)
        #expect(decoded.showPopoverOnLaunch == true) // default
        #expect(decoded.minimizeOthersOnRun == false) // default
        #expect(decoded.windowPadding == 4) // default
        #expect(decoded.appLaunchDelay == 600) // default
        #expect(decoded.confirmBeforeClear == true) // default
    }
}

// MARK: - RestoreBehavior Tests

struct RestoreBehaviorTests {

    @Test func rawValues() {
        #expect(RestoreBehavior.openNew.rawValue == "open-new")
        #expect(RestoreBehavior.reuseExisting.rawValue == "reuse-existing")
    }

    @Test func codable() throws {
        let encoded = try JSONEncoder().encode(RestoreBehavior.openNew)
        let decoded = try JSONDecoder().decode(RestoreBehavior.self, from: encoded)
        #expect(decoded == .openNew)
    }
}

// MARK: - GridConfiguration Tests

struct GridConfigurationTests {

    @Test func singleApp() {
        let config = GridConfiguration.configuration(for: 1)
        #expect(config.columns == 1)
        #expect(config.description == "Full screen")
    }

    @Test func twoApps() {
        let config = GridConfiguration.configuration(for: 2)
        #expect(config.columns == 2)
        #expect(config.description == "Side by side")
    }

    @Test func threeApps() {
        let config = GridConfiguration.configuration(for: 3)
        #expect(config.columns == 3)
    }

    @Test func fourApps() {
        let config = GridConfiguration.configuration(for: 4)
        #expect(config.columns == 2)
        #expect(config.description == "2×2 grid")
    }

    @Test func fiveToSixApps() {
        let config5 = GridConfiguration.configuration(for: 5)
        let config6 = GridConfiguration.configuration(for: 6)
        #expect(config5.columns == 3)
        #expect(config6.columns == 3)
    }

    @Test func tenPlusApps() {
        let config = GridConfiguration.configuration(for: 12)
        #expect(config.columns == 4)
    }

    @Test func zeroApps() {
        let config = GridConfiguration.configuration(for: 0)
        #expect(config.columns == 4) // falls to default
    }
}

// MARK: - AppIconMapper Tests

struct AppIconMapperTests {

    @Test func knownApps() {
        #expect(AppIconMapper.sfSymbol(for: "Safari") == "globe")
        #expect(AppIconMapper.sfSymbol(for: "chrome") == "globe")
        #expect(AppIconMapper.sfSymbol(for: "VS Code") == "chevron.left.forwardslash.chevron.right")
        #expect(AppIconMapper.sfSymbol(for: "Figma") == "paintpalette")
        #expect(AppIconMapper.sfSymbol(for: "Slack") == "message")
        #expect(AppIconMapper.sfSymbol(for: "Spotify") == "music.note")
        #expect(AppIconMapper.sfSymbol(for: "Terminal") == "terminal")
        #expect(AppIconMapper.sfSymbol(for: "Notes") == "doc.text")
        #expect(AppIconMapper.sfSymbol(for: "Calendar") == "calendar")
    }

    @Test func unknownAppReturnsFallback() {
        #expect(AppIconMapper.sfSymbol(for: "RandomApp") == "app")
        #expect(AppIconMapper.sfSymbol(for: "") == "app")
    }

    @Test func caseInsensitive() {
        #expect(AppIconMapper.sfSymbol(for: "SAFARI") == "globe")
        #expect(AppIconMapper.sfSymbol(for: "slack") == "message")
        #expect(AppIconMapper.sfSymbol(for: "TERMINAL") == "terminal")
    }
}
