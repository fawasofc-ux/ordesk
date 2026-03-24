import Testing
import Foundation
@testable import ordesk

// MARK: - JSON Persistence Tests

/// Tests that workspace and preference data survives encode/decode cycles,
/// handles corruption gracefully, and maintains backward compatibility.
struct PersistenceTests {

    // MARK: - Workspace JSON Round-Trip

    @Test func workspaceArray_encodeDecodeRoundTrip() throws {
        let workspaces = [
            Workspace(name: "Dev", apps: [
                AppInstance(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", displayIndex: 0),
                AppInstance(name: "Terminal", bundleIdentifier: "com.apple.Terminal", displayIndex: 0),
            ], displayMode: .single),
            Workspace(name: "Design", apps: [
                AppInstance(name: "Figma", bundleIdentifier: "com.figma.Desktop", displayIndex: 0),
                AppInstance(name: "Safari", bundleIdentifier: "com.apple.Safari", displayIndex: 1),
            ], displayMode: .dual),
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(workspaces)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([Workspace].self, from: data)

        #expect(decoded.count == 2)
        #expect(decoded[0].name == "Dev")
        #expect(decoded[0].apps.count == 2)
        #expect(decoded[0].apps[0].bundleIdentifier == "com.apple.dt.Xcode")
        #expect(decoded[1].name == "Design")
        #expect(decoded[1].displayMode == .dual)
        #expect(decoded[1].apps[1].displayIndex == 1)
    }

    @Test func emptyWorkspaceArray_roundTrip() throws {
        let workspaces: [Workspace] = []
        let data = try JSONEncoder().encode(workspaces)
        let decoded = try JSONDecoder().decode([Workspace].self, from: data)
        #expect(decoded.isEmpty)
    }

    @Test func workspaceWithEmptyApps_roundTrip() throws {
        let ws = Workspace(name: "Empty", apps: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(ws)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Workspace.self, from: data)
        #expect(decoded.apps.isEmpty)
        #expect(decoded.name == "Empty")
    }

    // MARK: - Corrupt JSON Handling

    @Test func corruptJSON_doesNotCrash() {
        let corruptData = "{ this is not valid json }}}".data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try? decoder.decode([Workspace].self, from: corruptData)
        #expect(result == nil) // Should fail gracefully, not crash
    }

    @Test func emptyData_doesNotCrash() {
        let emptyData = Data()
        let result = try? JSONDecoder().decode([Workspace].self, from: emptyData)
        #expect(result == nil)
    }

    @Test func corruptPreferences_doesNotCrash() {
        let corruptData = "not json".data(using: .utf8)!
        let result = try? JSONDecoder().decode(Preferences.self, from: corruptData)
        #expect(result == nil)
    }

    // MARK: - Backward Compatibility

    @Test func oldWorkspace_missingDisplayIndex_defaultsToZero() throws {
        let json = """
        {
            "id": "legacy-ws",
            "name": "Legacy",
            "apps": [
                {
                    "id": "app1",
                    "name": "Safari",
                    "bundleIdentifier": "com.apple.Safari",
                    "icon": "globe",
                    "isRunning": false,
                    "cardSize": "small"
                }
            ],
            "lastUsed": "2024-01-01T00:00:00Z",
            "createdAt": "2024-01-01T00:00:00Z",
            "restoreWindowLayout": true,
            "reuseOpenApps": true,
            "displayMode": "single"
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let ws = try decoder.decode(Workspace.self, from: data)
        #expect(ws.apps[0].displayIndex == 0)
        #expect(ws.name == "Legacy")
    }

    @Test func oldPreferences_missingNewFields_usesDefaults() throws {
        let json = """
        {
            "launchAtLogin": false,
            "defaultRestoreBehavior": "reuse-existing",
            "quickSwitchShortcut": "⌃⌥O"
        }
        """
        let data = json.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(prefs.windowPadding == 4)
        #expect(prefs.appLaunchDelay == 600)
        #expect(prefs.confirmBeforeClear == true)
        #expect(prefs.minimizeOthersOnRun == false)
        #expect(prefs.showPopoverOnLaunch == true)
    }

    // MARK: - Date Encoding

    @Test func dates_iso8601_roundTrip() throws {
        let now = Date()
        let ws = Workspace(name: "Date Test", apps: [], lastUsed: now, createdAt: now)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(ws)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Workspace.self, from: data)

        // ISO 8601 loses sub-second precision, so compare within 1 second
        #expect(abs(decoded.lastUsed.timeIntervalSince(now)) < 1)
        #expect(abs(decoded.createdAt.timeIntervalSince(now)) < 1)
    }

    // MARK: - File Persistence (using temp directory)

    @Test func writeAndReadJSON_tempFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_workspaces_\(UUID().uuidString).json")

        defer { try? FileManager.default.removeItem(at: tempFile) }

        let workspaces = [
            Workspace(name: "Temp Test", apps: [
                AppInstance(name: "Safari", bundleIdentifier: "com.apple.Safari"),
            ]),
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(workspaces)
        try data.write(to: tempFile, options: .atomic)

        let readData = try Data(contentsOf: tempFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([Workspace].self, from: readData)

        #expect(decoded.count == 1)
        #expect(decoded[0].name == "Temp Test")
    }

    @Test func atomicWrite_doesNotCorrupt() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("atomic_test_\(UUID().uuidString).json")

        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Write multiple times rapidly
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        for i in 0..<10 {
            let ws = [Workspace(name: "Iteration \(i)", apps: [])]
            let data = try encoder.encode(ws)
            try data.write(to: tempFile, options: .atomic)
        }

        // Final read should be valid
        let readData = try Data(contentsOf: tempFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([Workspace].self, from: readData)
        #expect(decoded[0].name == "Iteration 9")
    }
}
