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
        settings.systemAudio = false
        settings.highlightClicks = false
        settings.fps = 30
        let sink = try SampleWriter(url: file, width: 160, height: 120, settings: settings) { error in
            XCTFail(error.localizedDescription)
        }
        let origin = CMTime(seconds: 100, preferredTimescale: 60_000)
        let sample = try testCaptureFrame(at: origin)
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
        settings.systemAudio = false
        settings.highlightClicks = false
        let sink = try SampleWriter(url: file, width: 160, height: 120, settings: settings) { _ in }
        do {
            try await sink.finish(at: CMTime(seconds: 10, preferredTimescale: 600))
            XCTFail("An empty recording must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("No video frames")) }
    }

    func testClickAnimationFinishesOnAStaticScreen() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("KapKap-click-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: file) }
        var settings = RecordingSettings()
        settings.microphone = false
        settings.systemAudio = false
        settings.highlightClicks = true
        settings.fps = 30
        let sink = try SampleWriter(url: file, width: 160, height: 120, settings: settings) { error in
            XCTFail(error.localizedDescription)
        }
        let origin = CMClockGetTime(CMClockGetHostTimeClock())
        let sample = try testCaptureFrame(at: origin)
        sink.queue.sync { sink.consume(sample, type: .screen) }
        sink.highlightClick(at: CGPoint(x: 0.5, y: 0.5), time: CMClockGetTime(CMClockGetHostTimeClock()))
        try await Task.sleep(for: .milliseconds(650))
        try await sink.finish(at: CMClockGetTime(CMClockGetHostTimeClock()))

        let frames = try await decodedFrames(file)
        XCTAssertGreaterThan(frames.times.count, 7)
        XCTAssertTrue(zip(frames.times, frames.times.dropFirst()).allSatisfy { $0 < $1 })
        XCTAssertEqual(frames.highlighted.first, false)
        XCTAssertTrue(frames.highlighted.contains(true))
        XCTAssertEqual(frames.highlighted.last, false)
    }

    func testPauseClearsClickHighlightsAndExcludesPausedTime() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("KapKap-pause-click-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: file) }
        var settings = RecordingSettings()
        settings.microphone = false
        settings.systemAudio = false
        settings.highlightClicks = true
        settings.fps = 30
        let sink = try SampleWriter(url: file, width: 160, height: 120, settings: settings) { error in
            XCTFail(error.localizedDescription)
        }
        let origin = CMClockGetTime(CMClockGetHostTimeClock())
        let sample = try testCaptureFrame(at: origin)
        sink.queue.sync { sink.consume(sample, type: .screen) }
        sink.highlightClick(at: CGPoint(x: 0.5, y: 0.5), time: CMClockGetTime(CMClockGetHostTimeClock()))
        try await Task.sleep(for: .milliseconds(100))
        await sink.setPaused(true)
        sink.highlightClick(at: CGPoint(x: 0.5, y: 0.5), time: CMClockGetTime(CMClockGetHostTimeClock()))
        try await Task.sleep(for: .milliseconds(350))
        await sink.setPaused(false)
        try await Task.sleep(for: .milliseconds(140))
        try await sink.finish(at: CMClockGetTime(CMClockGetHostTimeClock()))
        let duration = try await AVURLAsset(url: file).load(.duration)
        XCTAssertEqual(duration.seconds, 0.24, accuracy: 0.08)
        let frames = try await decodedFrames(file)
        XCTAssertTrue(frames.highlighted.contains(true))
        XCTAssertEqual(frames.highlighted.last, false)
        XCTAssertTrue(zip(frames.times, frames.times.dropFirst()).allSatisfy { $0 < $1 })
    }

    private func decodedFrames(_ file: URL) async throws -> (times: [CMTime], highlighted: [Bool]) {
        let asset = AVURLAsset(url: file)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var times: [CMTime] = []
        var highlighted: [Bool] = []
        while let frame = output.copyNextSampleBuffer() {
            times.append(frame.presentationTimeStamp)
            let pixel = try XCTUnwrap(frame.imageBuffer)
            CVPixelBufferLockBaseAddress(pixel, .readOnly)
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixel)).assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pixel)
            var found = false
            for y in 30..<90 {
                for x in 50..<110 {
                    let index = y * stride + x * 4
                    if Int(base[index]) - Int(base[index + 2]) > 12 { found = true }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixel, .readOnly)
            highlighted.append(found)
        }
        XCTAssertEqual(reader.status, .completed)
        return (times, highlighted)
    }
}
