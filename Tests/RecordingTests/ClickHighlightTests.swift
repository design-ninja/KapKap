import XCTest
import AVFoundation
@testable import KapKap

final class ClickHighlightTests: XCTestCase {
    func testScreenCaptureColorMetadataMatchesTheCompositedFrame() throws {
        let time = CMTime(seconds: 100, preferredTimescale: 600)
        let sample = try testCaptureFrame(at: time, nonPropagatingGamma: 2.2)
        let renderer = try ClickHighlightRenderer(width: 160, height: 120, scale: 1)
        renderer.add(at: CGPoint(x: 0.5, y: 0.5), time: time)
        let rendered = try renderer.render(sample, at: time)
        XCTAssertTrue(CMVideoFormatDescriptionMatchesImageBuffer(try XCTUnwrap(rendered.formatDescription),
                                                                imageBuffer: try XCTUnwrap(rendered.imageBuffer)))
        let gamma = CMFormatDescriptionGetExtension(try XCTUnwrap(rendered.formatDescription),
                                                    extensionKey: kCMFormatDescriptionExtension_GammaLevel) as? NSNumber
        XCTAssertEqual(gamma?.doubleValue, 2.2)
    }

    func testPulseExpandsFadesAndDoesNotChangeTheSourceFrame() throws {
        let time = CMTime(seconds: 100, preferredTimescale: 60_000)
        let sample = try testCaptureFrame(at: time)
        let renderer = try ClickHighlightRenderer(width: 160, height: 120, scale: 1)
        renderer.add(at: CGPoint(x: 0.25, y: 0.25), time: time)
        let first = try renderer.render(sample, at: time)
        let middle = try renderer.render(sample, at: time + CMTime(seconds: 0.15, preferredTimescale: 60_000))
        let initial = try highlightedBounds(first)
        let expanded = try highlightedBounds(middle)
        XCTAssertEqual(initial.midX, 40, accuracy: 1)
        XCTAssertEqual(initial.midY, 30, accuracy: 1)
        XCTAssertGreaterThan(expanded.width, initial.width * 2)
        XCTAssertEqual(try highlightedBounds(sample), .zero)
        let expired = try renderer.render(sample, at: time + CMTime(seconds: 0.5, preferredTimescale: 60_000))
        XCTAssertTrue(expired.imageBuffer === sample.imageBuffer)
        XCTAssertFalse(renderer.hasPulses)
    }

    @MainActor
    func testCoordinatesForCroppedAreaAndWindowOnAnotherDisplay() {
        let area = CGRect(x: -1500, y: 100, width: 800, height: 600)
        XCTAssertEqual(RecordingClickMonitor.normalizedPoint(CGPoint(x: -1300, y: 550), in: area),
                       CGPoint(x: 0.25, y: 0.25))
        XCTAssertNil(RecordingClickMonitor.normalizedPoint(CGPoint(x: -1600, y: 500), in: area))
        let window = CaptureWindowGeometry.screenRect(CGRect(x: -1200, y: 100, width: 400, height: 300),
                                                      primary: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(RecordingClickMonitor.normalizedPoint(CGPoint(x: -1100, y: 905), in: window),
                       CGPoint(x: 0.25, y: 0.25))
    }

    func testClearingHighlightsLeavesACleanFrame() throws {
        let time = CMTime(seconds: 100, preferredTimescale: 600)
        let sample = try testCaptureFrame(at: time)
        let renderer = try ClickHighlightRenderer(width: 160, height: 120, scale: 1)
        renderer.add(at: CGPoint(x: 0.5, y: 0.5), time: time)
        renderer.clear()
        XCTAssertTrue(try renderer.render(sample, at: time).imageBuffer === sample.imageBuffer)
    }

    private func highlightedBounds(_ sample: CMSampleBuffer) throws -> CGRect {
        let pixel = try XCTUnwrap(sample.imageBuffer)
        CVPixelBufferLockBaseAddress(pixel, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixel)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixel)
        var bounds = CGRect.null
        for y in 0..<CVPixelBufferGetHeight(pixel) {
            for x in 0..<CVPixelBufferGetWidth(pixel) {
                let index = y * stride + x * 4
                if Int(base[index]) - Int(base[index + 2]) > 6 {
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return bounds.isNull ? .zero : bounds
    }
}
