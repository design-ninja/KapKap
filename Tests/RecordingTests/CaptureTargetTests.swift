import XCTest
import AppKit
@testable import KapKap

final class CaptureTargetTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @MainActor func testWholeDisplayFollowsANewResolution() throws {
        let display = CaptureTarget(displayID: 1, screenFrame: screen, rect: screen, scale: 2, name: "Built-in")
        let larger = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let current = try CaptureStore.current(display, screenFrame: larger, scale: 2, name: "Built-in")
        XCTAssertEqual(current.rect, larger)
        XCTAssertEqual(current.screenFrame, larger)
    }

    @MainActor func testAreaMovesWithItsDisplayAndRejectsANewResolution() throws {
        let area = CaptureTarget(displayID: 1, screenFrame: screen, rect: CGRect(x: 100, y: 200, width: 400, height: 300),
                                 scale: 2, name: "Selected area")
        let moved = CGRect(x: -1512, y: 300, width: 1512, height: 982)
        XCTAssertEqual(try CaptureStore.current(area, screenFrame: moved, scale: 2, name: "Built-in").rect,
                       CGRect(x: -1412, y: 500, width: 400, height: 300))
        XCTAssertThrowsError(try CaptureStore.current(area, screenFrame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
                                                      scale: 2, name: "Built-in"))
    }

    @MainActor func testLastAreaIsRestoredOnLaunch() throws {
        guard let screen = NSScreen.screens.first, let displayID = screen.displayID,
              let identifier = SavedCaptureArea.identifier(for: displayID) else { throw XCTSkip("Needs a display.") }
        let suite = "KapKap-restore-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let selected = CGRect(x: screen.frame.minX + 40, y: screen.frame.minY + 60, width: 320, height: 200)
        SavedCaptureArea(displayIdentifier: identifier, selection: selected, screen: screen.frame).save(defaults: defaults)
        let store = CaptureStore(defaults: defaults)
        XCTAssertEqual(store.target?.rect, selected)
        XCTAssertTrue(store.hasSelectedArea)
        XCTAssertEqual(store.lastArea?.rect, selected)
    }
}
