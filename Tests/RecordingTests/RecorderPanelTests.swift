import XCTest
import AppKit
import SwiftUI
@testable import KapKap

final class RecorderPanelTests: XCTestCase {
    @MainActor func testSelectionControlsResizeAroundTheExistingCenter() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("Needs a display.") }
        let suite = "KapKap-panel-transition-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = CaptureStore(defaults: defaults)
        let panel = RecorderPanel(store: store)
        panel.setFrameOrigin(CGPoint(x: screen.frame.midX - panel.frame.width / 2, y: screen.frame.midY))
        let original = panel.frame
        let resized = expectation(description: "Selection controls expand the panel")
        resized.assertForOverFulfill = false
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main) { _ in
                MainActor.assumeIsolated {
                    if panel.frame.width > original.width { resized.fulfill() }
                }
            }
        defer {
            NotificationCenter.default.removeObserver(observer)
            panel.close()
            defaults.removePersistentDomain(forName: suite)
        }

        store.phase = .selecting
        panel.contentView?.layoutSubtreeIfNeeded()
        await fulfillment(of: [resized], timeout: 2)

        XCTAssertGreaterThan(panel.frame.width, original.width)
        XCTAssertEqual(panel.frame.midX, original.midX, accuracy: 0.5)
    }

    @MainActor func testWidthChangesKeepThePanelsHorizontalCenter() throws {
        try withPanel { panel, screen in
            panel.setFrame(CGRect(x: screen.frame.midX - 150, y: screen.frame.midY,
                                  width: 300, height: 80), display: false)
            let original = panel.frame
            var expanded = original
            expanded.size.width += 120

            panel.setFrame(expanded, display: false)

            XCTAssertEqual(panel.frame.midX, original.midX, accuracy: 0.5)
            XCTAssertLessThan(panel.frame.minX, original.minX)
            XCTAssertGreaterThan(panel.frame.maxX, original.maxX)

            var contracted = panel.frame
            contracted.size.width = original.width
            panel.setFrame(contracted, display: false)

            XCTAssertEqual(panel.frame.midX, original.midX, accuracy: 0.5)
            XCTAssertEqual(panel.frame.width, original.width, accuracy: 0.5)
        }
    }

    @MainActor func testExpansionAtScreenEdgeStaysOnScreen() throws {
        try withPanel { panel, screen in
            panel.setFrameOrigin(CGPoint(x: screen.frame.minX, y: screen.frame.midY))
            var expanded = panel.frame
            expanded.size.width += 120

            panel.setFrame(expanded, display: false)

            XCTAssertGreaterThanOrEqual(panel.frame.minX, screen.frame.minX)
            XCTAssertLessThanOrEqual(panel.frame.maxX, screen.frame.maxX)
        }
    }

    @MainActor func testSystemHelpAndMenusAppearAboveRecorder() throws {
        try withPanel { panel, _ in
            XCTAssertLessThan(panel.level.rawValue, Int(CGWindowLevelForKey(.helpWindow)))
            XCTAssertLessThan(panel.level.rawValue, NSWindow.Level.popUpMenu.rawValue)
        }
    }

    @MainActor private func withPanel(_ check: (RecorderPanel, NSScreen) -> Void) throws {
        guard let screen = NSScreen.main else { throw XCTSkip("Needs a display.") }
        let suite = "KapKap-panel-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let panel = RecorderPanel(store: CaptureStore(defaults: defaults))
        defer {
            panel.close()
            defaults.removePersistentDomain(forName: suite)
        }
        check(panel, screen)
    }
}
