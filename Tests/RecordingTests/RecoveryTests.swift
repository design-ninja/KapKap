import XCTest
import AVFoundation
@testable import KapKap

final class RecoveryTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("KapKap-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    /// A stream the system ended keeps everything recorded before it instead of deleting the file.
    func testInterruptedStreamIsSavedUpToItsLastFrame() async throws {
        let file = folder.appendingPathComponent("interrupted.mp4")
        var settings = RecordingSettings()
        settings.microphone = false
        settings.systemAudio = false
        settings.highlightClicks = false
        settings.fps = 30
        let reported = LockedCount()
        let sink = try SampleWriter(url: file, width: 160, height: 120, settings: settings) { _ in reported.increment() }
        let origin = CMTime(seconds: 100, preferredTimescale: 60_000)
        for frame in 0..<30 {
            let sample = try testCaptureFrame(at: origin + CMTime(value: CMTimeValue(frame), timescale: 30))
            sink.queue.sync { sink.consume(sample, type: .screen) }
        }
        sink.queue.sync {
            sink.interrupt(NSError(domain: "SCStreamErrorDomain", code: -3817))
            sink.interrupt(NSError(domain: "SCStreamErrorDomain", code: -3817))
        }
        let late = try testCaptureFrame(at: origin + CMTime(seconds: 3, preferredTimescale: 600))
        sink.queue.sync { sink.consume(late, type: .screen) }
        try await sink.finish(at: origin + CMTime(seconds: 10, preferredTimescale: 600))
        XCTAssertEqual(reported.value, 1)
        let duration = try await AVURLAsset(url: file).load(.duration)
        XCTAssertEqual(duration.seconds, 1, accuracy: 0.05)
    }

    func testPendingRecordingThatPlaysIsRecoveredAndBrokenOneStaysHidden() async throws {
        let playable = folder.appendingPathComponent(".KapKap playable.mp4")
        try await writeRecording(to: playable)
        let broken = folder.appendingPathComponent(".KapKap broken.mp4")
        try Data("not a movie".utf8).write(to: broken)
        let recent = folder.appendingPathComponent(".KapKap recent.mp4")
        try await writeRecording(to: recent)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: playable.path)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: broken.path)

        let recovered = await RecordingLibrary.recoverPending(in: folder, olderThan: 60)
        XCTAssertEqual(recovered.map(\.lastPathComponent), ["KapKap playable.mp4"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("KapKap playable.mp4").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: broken.path), "an unplayable file is kept for diagnosis")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path), "a file written moments ago may still be recording")
    }

    func testScratchExportsKeepOnlyWhatCanStillBeNeeded() throws {
        func export() throws -> URL {
            let url = try ScratchExports.newDestination(in: ScratchExports.clipboard, fileName: "clip.mp4", root: folder)
            try Data([1]).write(to: url)
            return url
        }
        let old = try export(), previous = try export(), current = try export()
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast],
                                              ofItemAtPath: old.deletingLastPathComponent().path)
        ScratchExports.prune(ScratchExports.clipboard, keeping: current, olderThan: 60, root: folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previous.path), "younger than the age limit")
        ScratchExports.prune(ScratchExports.clipboard, keeping: current, root: folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: previous.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.path))
    }

    private func writeRecording(to url: URL) async throws {
        var settings = RecordingSettings()
        settings.microphone = false
        settings.systemAudio = false
        settings.highlightClicks = false
        let sink = try SampleWriter(url: url, width: 160, height: 120, settings: settings) { _ in }
        let origin = CMTime(seconds: 5, preferredTimescale: 600)
        let sample = try testCaptureFrame(at: origin)
        sink.queue.sync { sink.consume(sample, type: .screen) }
        try await sink.finish(at: origin + CMTime(seconds: 1, preferredTimescale: 600))
    }
}

private final class LockedCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}
