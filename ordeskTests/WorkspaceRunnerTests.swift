import Testing
import Foundation
import CoreGraphics
@testable import ordesk

// MARK: - WorkspaceRunner Layout Tests

/// Tests the window layout logic (pure geometry — no system APIs needed).
/// These validate that dynamicLayoutFrames produces correct rects for 0–5+ apps.
struct WorkspaceRunnerLayoutTests {

    // Access dynamicLayoutFrames via a testable wrapper
    private let runner = WorkspaceRunner()
    private let testRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    // MARK: - Dynamic Layout Frames

    @Test @MainActor func layout_zeroApps() {
        let frames = runner.testDynamicLayoutFrames(count: 0, in: testRect)
        #expect(frames.isEmpty)
    }

    @Test @MainActor func layout_oneApp_fullScreen() {
        let frames = runner.testDynamicLayoutFrames(count: 1, in: testRect)
        #expect(frames.count == 1)
        let f = frames[0]
        // Should fill nearly the entire rect (minus padding)
        #expect(f.width > 1900)
        #expect(f.height > 1070)
        #expect(f.minX >= 0)
        #expect(f.minY >= 0)
    }

    @Test @MainActor func layout_twoApps_sideBySide() {
        let frames = runner.testDynamicLayoutFrames(count: 2, in: testRect)
        #expect(frames.count == 2)
        // Left and right should not overlap
        #expect(frames[0].maxX <= frames[1].minX + 10) // allow small padding gap
        // Both should be roughly half width
        #expect(abs(frames[0].width - frames[1].width) < 1)
        // Both should be full height (minus padding)
        #expect(frames[0].height > 1070)
        #expect(frames[1].height > 1070)
    }

    @Test @MainActor func layout_threeApps_twoTopOneBottom() {
        let frames = runner.testDynamicLayoutFrames(count: 3, in: testRect)
        #expect(frames.count == 3)
        // Top row: 2 apps side by side
        #expect(frames[0].minY == frames[1].minY) // same Y
        #expect(frames[0].maxX <= frames[1].minX + 10)
        // Bottom: full width
        #expect(frames[2].width > frames[0].width) // bottom is wider than each top
        // Bottom is below top row
        #expect(frames[2].minY > frames[0].minY)
    }

    @Test @MainActor func layout_fourApps_twoByTwoGrid() {
        let frames = runner.testDynamicLayoutFrames(count: 4, in: testRect)
        #expect(frames.count == 4)
        // Top-left and top-right should be at same Y
        #expect(frames[0].minY == frames[1].minY)
        // Bottom-left and bottom-right should be at same Y
        #expect(frames[2].minY == frames[3].minY)
        // Top row above bottom row
        #expect(frames[0].maxY <= frames[2].minY + 10)
        // All roughly same size
        let widths = frames.map(\.width)
        let heights = frames.map(\.height)
        #expect(widths.max()! - widths.min()! < 1)
        #expect(heights.max()! - heights.min()! < 1)
    }

    @Test @MainActor func layout_fiveApps_fallbackGrid() {
        let frames = runner.testDynamicLayoutFrames(count: 5, in: testRect)
        #expect(frames.count == 5)
        // All frames should be within the test rect
        for f in frames {
            #expect(f.minX >= testRect.minX)
            #expect(f.minY >= testRect.minY)
            #expect(f.maxX <= testRect.maxX + 1) // allow rounding
            #expect(f.maxY <= testRect.maxY + 1)
        }
    }

    @Test @MainActor func layout_framesNeverOverlap() {
        // For each count 1–6, no two frames should overlap significantly
        for count in 1...6 {
            let frames = runner.testDynamicLayoutFrames(count: count, in: testRect)
            for i in 0..<frames.count {
                for j in (i+1)..<frames.count {
                    let intersection = frames[i].intersection(frames[j])
                    // Allow tiny overlap from padding math (< 10px)
                    #expect(intersection.width < 10 || intersection.height < 10,
                           "Frames \(i) and \(j) overlap for count=\(count)")
                }
            }
        }
    }

    @Test @MainActor func layout_padding_appliedCorrectly() {
        let frames = runner.testDynamicLayoutFrames(count: 1, in: testRect)
        let f = frames[0]
        // With default 4px padding, the frame should be inset by 4px from each edge
        #expect(f.minX == 4)
        #expect(f.minY == 4)
        #expect(f.maxX == testRect.maxX - 4)
        #expect(f.maxY == testRect.maxY - 4)
    }

    @Test @MainActor func layout_nonStandardRect() {
        // Test with a non-origin rect (like a secondary display)
        let secondaryRect = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let frames = runner.testDynamicLayoutFrames(count: 2, in: secondaryRect)
        #expect(frames.count == 2)
        // Both frames should be within the secondary rect
        for f in frames {
            #expect(f.minX >= secondaryRect.minX)
            #expect(f.maxX <= secondaryRect.maxX + 1)
        }
    }

    // MARK: - Coordinate Conversion

    @Test @MainActor func cocoaToAX_mainScreen() {
        // For the main screen, AX origin = (0, 0) at top-left
        // Cocoa visibleFrame origin is at bottom-left
        let mainScreenHeight: CGFloat = 1080
        let cocoaFrame = CGRect(x: 0, y: 25, width: 1920, height: 1055) // typical with menu bar
        let axRect = runner.testCocoaVisibleFrameToAX(
            visibleFrame: cocoaFrame,
            mainScreenHeight: mainScreenHeight
        )
        #expect(axRect.origin.x == 0)
        #expect(axRect.origin.y == 0) // top of visible area in AX coords
        #expect(axRect.width == 1920)
        #expect(axRect.height == 1055)
    }

    // MARK: - Error Types

    @Test func runnerError_accessibilityNotGranted() {
        let error = WorkspaceRunner.RunnerError.accessibilityNotGranted
        #expect(error.errorDescription?.contains("Accessibility") == true)
    }

    @Test func runnerError_appLaunchFailed() {
        let error = WorkspaceRunner.RunnerError.appLaunchFailed(appName: "Safari", reason: "Not installed")
        #expect(error.errorDescription?.contains("Safari") == true)
        #expect(error.errorDescription?.contains("Not installed") == true)
    }

    @Test func runnerError_windowPositionFailed() {
        let error = WorkspaceRunner.RunnerError.windowPositionFailed(appName: "Chrome", reason: "No window")
        #expect(error.errorDescription?.contains("Chrome") == true)
    }

    // MARK: - State Machine

    @Test func runnerState_equatable() {
        #expect(WorkspaceRunner.RunnerState.idle == .idle)
        #expect(WorkspaceRunner.RunnerState.completed == .completed)
        #expect(WorkspaceRunner.RunnerState.failed("x") == .failed("x"))
        #expect(WorkspaceRunner.RunnerState.failed("x") != .failed("y"))
        #expect(WorkspaceRunner.RunnerState.launchingApps(current: "A", index: 0, total: 3)
                == .launchingApps(current: "A", index: 0, total: 3))
        #expect(WorkspaceRunner.RunnerState.launchingApps(current: "A", index: 0, total: 3)
                != .launchingApps(current: "B", index: 0, total: 3))
    }

    @Test @MainActor func runnerState_initiallyIdle() {
        let runner = WorkspaceRunner()
        #expect(runner.state == .idle)
    }
}
