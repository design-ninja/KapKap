import XCTest
@testable import CaptureCore

final class WindowSnappingTests: XCTestCase {
    func testFiveAnchorsOnOffsetDisplay() {
        let frame = CGRect(x: -1200, y: 40, width: 1200, height: 800)
        let size = CGSize(width: 320, height: 80)
        let anchors = [CGPoint(x: -760, y: 400), CGPoint(x: -760, y: 40),
                       CGPoint(x: -760, y: 760), CGPoint(x: -1200, y: 400),
                       CGPoint(x: -320, y: 400)]
        for anchor in anchors {
            var snap = WindowSnapping()
            XCTAssertEqual(snap.origin(for: CGPoint(x: anchor.x + 8, y: anchor.y + 4),
                                       size: size, visibleFrame: frame), anchor)
        }
    }

    func testCenterHasWiderCaptureRadiusThanEdges() {
        var snap = WindowSnapping()
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 320, height: 80)
        XCTAssertEqual(snap.origin(for: CGPoint(x: 365, y: 360), size: size, visibleFrame: frame), CGPoint(x: 340, y: 360))
        snap.reset()
        XCTAssertEqual(snap.origin(for: CGPoint(x: 365, y: 0), size: size, visibleFrame: frame), CGPoint(x: 365, y: 0))
        XCTAssertNil(snap.anchor)
    }

    func testStickyThresholdAndRelease() {
        var snap = WindowSnapping()
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 320, height: 80)
        XCTAssertEqual(snap.origin(for: CGPoint(x: 350, y: 360), size: size, visibleFrame: frame), CGPoint(x: 340, y: 360))
        XCTAssertEqual(snap.origin(for: CGPoint(x: 370, y: 360), size: size, visibleFrame: frame), CGPoint(x: 340, y: 360))
        XCTAssertEqual(snap.origin(for: CGPoint(x: 385, y: 360), size: size, visibleFrame: frame), CGPoint(x: 385, y: 360))
        XCTAssertNil(snap.anchor)
        XCTAssertEqual(snap.origin(for: CGPoint(x: 400, y: 200), size: size, visibleFrame: frame), CGPoint(x: 400, y: 200))
    }
}
