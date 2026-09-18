import XCTest
import AVFoundation
import ScreenCaptureKit
@testable import KapKap

final class SampleWriterTests: XCTestCase {
    func testStaticScreenHoldsItsLastFrameUntilStop() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("KapKap-writer-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: file) }
        var settings = RecordingSettings()
        settings.microphone = false
        settings.fps = 30
        let sink = try SampleWriter(url: file, width: 160, height: 120, settings: settings) { error in
            XCTFail(error.localizedDescription)
        }
        let origin = CMTime(seconds: 100, preferredTimescale: 60_000)
        let sample = try frame(at: origin)
        sink.queue.sync { sink.consume(sample, type: .screen) }
        try await sink.finish(at: origin + CMTime(seconds: 2, preferredTimescale: 60_000))
        let asset = AVURLAsset(url: file)
        let metadata = try await asset.load(.commonMetadata)
        let description = metadata.first { $0.commonKey == .commonKeyDescription }
        let recordedSettings = try await description?.load(.stringValue)
        XCTAssertEqual(recordedSettings, "KapKap recording fps=30")
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 2, accuracy: 0.04)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let size = try await tracks[0].load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 160, height: 120))
    }

    func testEmptyRecordingFailsInsteadOfReturningAnUnplayableFile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("KapKap-empty-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: file) }
        var settings = RecordingSettings()
        settings.microphone = false
        let sink = try SampleWriter(url: file, width: 160, height: 120, settings: settings) { _ in }
        do {
            try await sink.finish(at: CMTime(seconds: 10, preferredTimescale: 600))
            XCTFail("An empty recording must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("No video frames")) }
    }

    private func frame(at time: CMTime) throws -> CMSampleBuffer {
        var pixel: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 160, 120, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel), kCVReturnSuccess)
        let image = try XCTUnwrap(pixel)
        CVPixelBufferLockBaseAddress(image, [])
        memset(CVPixelBufferGetBaseAddress(image), 127, CVPixelBufferGetDataSize(image))
        CVPixelBufferUnlockBaseAddress(image, [])
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image, formatDescriptionOut: &format), noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image,
            formatDescription: try XCTUnwrap(format), sampleTiming: &timing, sampleBufferOut: &sample), noErr)
        let result = try XCTUnwrap(sample)
        let attachments = try XCTUnwrap(CMSampleBufferGetSampleAttachmentsArray(result, createIfNecessary: true))
        let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        let key = SCStreamFrameInfo.status.rawValue as NSString
        let value = NSNumber(value: SCFrameStatus.complete.rawValue)
        CFDictionarySetValue(dictionary, Unmanaged.passUnretained(key).toOpaque(), Unmanaged.passUnretained(value).toOpaque())
        return result
    }
}
