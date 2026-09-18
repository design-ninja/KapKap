import XCTest
import CoreMedia
@testable import CaptureCore

final class CaptureCoreTests: XCTestCase {
    func testFractionalSelectionHasOneToOnePixelMapping() {
        let display = CGRect(x: -1512, y: 982, width: 1512, height: 982)
        let selection = CGRect(x: -1511.75, y: 1068.2, width: 1511.5, height: 809.7)
        let source = CaptureGeometry.sourceRect(selection: selection, screen: display)
        for scale: CGFloat in [1, 2] {
            let aligned = CaptureGeometry.pixelAlignedRect(source, scale: scale)
            let pixels = CaptureGeometry.pixelSize(points: aligned.size, scale: scale)
            XCTAssertTrue(source.contains(aligned))
            XCTAssertEqual(aligned.width * scale, pixels.width)
            XCTAssertEqual(aligned.height * scale, pixels.height)
            XCTAssertEqual((aligned.minX * scale).truncatingRemainder(dividingBy: 2), 0)
            XCTAssertEqual((aligned.minY * scale).truncatingRemainder(dividingBy: 2), 0)
            XCTAssertLessThan(source.width - aligned.width, 4 / scale)
            XCTAssertLessThan(source.height - aligned.height, 4 / scale)
        }
    }

    func testAlignedDisplayIsUnchangedAndTinyCropIsRejected() {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(CaptureGeometry.pixelAlignedRect(display, scale: 2), display)
        XCTAssertEqual(CaptureGeometry.pixelAlignedRect(CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4), scale: 2), .zero)
        XCTAssertEqual(CaptureGeometry.pixelAlignedRect(.zero, scale: 2), .zero)
    }

    func testRetinaDisplayAboveAndLeftOfPrimary() {
        let display = CGRect(x: -1920, y: 1080, width: 1920, height: 1200)
        let selected = CGRect(x: -1820, y: 1880, width: 401, height: 201)
        XCTAssertEqual(CaptureGeometry.sourceRect(selection: selected, screen: display),
                       CGRect(x: 100, y: 199, width: 401, height: 201))
        XCTAssertEqual(CaptureGeometry.pixelSize(points: selected.size, scale: 2),
                       CGSize(width: 802, height: 402))
    }

    func testSelectionIsClippedAndEncoderDimensionsAreEven() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(CaptureGeometry.sourceRect(selection: CGRect(x: -20, y: 10, width: 70, height: 30), screen: display),
                       CGRect(x: 0, y: 60, width: 50, height: 30))
        XCTAssertEqual(CaptureGeometry.pixelSize(points: CGSize(width: 101, height: 77), scale: 1),
                       CGSize(width: 100, height: 76))
        XCTAssertEqual(CaptureGeometry.sourceRect(selection: CGRect(x: 200, y: 0, width: 20, height: 20), screen: display), .zero)
    }

    func testPauseRemovesTheSameGapFromAudioAndVideo() {
        var timeline = RecordingTimeline()
        timeline.begin(at: time(100))
        XCTAssertNil(timeline.presentationTime(for: time(99)))
        timeline.pause(at: time(102))
        XCTAssertNil(timeline.presentationTime(for: time(103)))
        XCTAssertEqual(timeline.duration(at: time(105)).seconds, 2, accuracy: 0.001)
        timeline.resume(at: time(107))
        XCTAssertNil(timeline.presentationTime(for: time(106.9)))
        XCTAssertEqual(timeline.presentationTime(for: time(107))!.seconds, 2, accuracy: 0.001)
        XCTAssertEqual(timeline.presentationTime(for: time(107.025))!.seconds, 2.025, accuracy: 0.001)
        timeline.pause(at: time(108))
        timeline.pause(at: time(109))
        timeline.resume(at: time(110))
        timeline.resume(at: time(111))
        XCTAssertEqual(timeline.presentationTime(for: time(111))!.seconds, 4, accuracy: 0.001)
        XCTAssertEqual(timeline.duration(at: time(111)).seconds, 4, accuracy: 0.001)
    }

    func testPauseBeforeFirstFrameDoesNotCreateNegativeTime() {
        var timeline = RecordingTimeline()
        timeline.pause(at: time(10))
        timeline.resume(at: time(12))
        timeline.begin(at: time(12.1))
        XCTAssertEqual(timeline.presentationTime(for: time(12.1))!.seconds, 0, accuracy: 0.001)
    }

    private func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 60_000) }
}
