import XCTest
@testable import KapKap

final class SavedCaptureAreaTests: XCTestCase {
    func testRestoresSameAreaAfterRelaunchAndDisplayRepositioning() throws {
        let suite = "KapKap-area-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let screen = CGRect(x: -1512, y: 982, width: 1512, height: 982)
        let selected = CGRect(x: -1400, y: 1100, width: 800, height: 500)
        SavedCaptureArea(displayIdentifier: "display-A", selection: selected, screen: screen).save(defaults: defaults)
        let loaded = try XCTUnwrap(SavedCaptureArea.load(defaults: defaults))
        XCTAssertEqual(loaded.rect(on: "display-A", screen: screen), selected)
        XCTAssertEqual(loaded.rect(on: "display-A", screen: CGRect(x: 0, y: 0, width: 1512, height: 982)),
                       CGRect(x: 112, y: 118, width: 800, height: 500))
        XCTAssertNil(loaded.rect(on: "display-B", screen: screen))
        XCTAssertNil(loaded.rect(on: "display-A", screen: CGRect(x: 0, y: 0, width: 600, height: 400)))
    }
}
