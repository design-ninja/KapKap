import XCTest
@testable import KapKap

final class EditorSizingTests: XCTestCase {
    @MainActor func testDimensionEditsPreserveAspectRatioAndDoNotUpscale() {
        let model = EditorStore(url: URL(fileURLWithPath: "/tmp/editor-sizing-test.mp4"))
        model.sourceWidth = 1920; model.sourceHeight = 1080
        model.setExportWidth(1280)
        XCTAssertEqual(model.width, 1280)
        XCTAssertEqual(model.exportHeight, 720)
        model.setExportHeight(360)
        XCTAssertEqual(model.width, 640)
        XCTAssertEqual(model.exportHeight, 360)
        model.setExportWidth(4000)
        XCTAssertEqual(model.width, 1920)
        model.setExportWidth(-100)
        XCTAssertEqual(model.width, 2)
        XCTAssertGreaterThanOrEqual(model.exportHeight, 2)
        model.sourceWidth = 1080; model.sourceHeight = 1920
        model.setExportHeight(960)
        XCTAssertEqual(model.width, 540)
        XCTAssertEqual(model.exportHeight, 960)
    }
}
