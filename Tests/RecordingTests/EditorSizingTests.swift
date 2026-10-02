import XCTest
@testable import KapKap

final class EditorSizingTests: XCTestCase {
    @MainActor func testGIFAndVideoRememberTheirOwnQuality() {
        let defaults = UserDefaults.standard
        let keys = ["exportFormat", "exportQuality", "gifExportQuality"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        keys.forEach(defaults.removeObject(forKey:))

        let model = EditorStore(url: URL(fileURLWithPath: "/tmp/editor-quality-test.mp4"))
        model.format = .mp4
        model.quality = .best
        model.format = .gif
        XCTAssertEqual(model.quality, .balanced, "GIF starts from its own default")
        model.quality = .smaller
        model.format = .webm
        XCTAssertEqual(model.quality, .best, "Video formats share one quality")
        model.format = .gif
        XCTAssertEqual(model.quality, .smaller)

        let next = EditorStore(url: URL(fileURLWithPath: "/tmp/editor-quality-test.mp4"))
        XCTAssertEqual(next.format, .gif)
        XCTAssertEqual(next.quality, .smaller, "The next editor opens with the last format's quality")
    }

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
