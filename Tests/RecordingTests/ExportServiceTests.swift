import XCTest
import CaptureCore
@testable import KapKap

final class ExportServiceTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("KapKap-service-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    func testExportReplacesTheDestinationAndReportsProgress() async throws {
        let ffmpeg = try exportTool()
        let input = try source(seconds: 2, ffmpeg: ffmpeg)
        let destination = folder.appendingPathComponent("out.mp4")
        try Data("old".utf8).write(to: destination)
        let progress = Progress()
        try await ExportService.export(input: input, destination: destination,
            options: ExportOptions(format: .mp4, start: 0, end: 2, width: 160, fps: 15, muted: true),
            executable: ffmpeg) { progress.record($0) }
        XCTAssertGreaterThan(try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 1000)
        XCTAssertGreaterThan(progress.maximum, 0.5)
        XCTAssertEqual(try hiddenFiles(), [])
    }

    func testCancelledExportLeavesNothingBehind() async throws {
        let ffmpeg = try exportTool()
        let input = try source(seconds: 30, ffmpeg: ffmpeg)
        let destination = folder.appendingPathComponent("cancelled.webm")
        let task = Task {
            try await ExportService.export(input: input, destination: destination,
                options: ExportOptions(format: .webm, start: 0, end: 30, width: 640, fps: 30, muted: true, quality: .best),
                executable: ffmpeg)
        }
        try await Task.sleep(for: .milliseconds(400))
        task.cancel()
        do { try await task.value; XCTFail("The export should have been cancelled") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try hiddenFiles(), [])
    }

    func testLossyGIFIsSmallerAndNeedsGifsicle() async throws {
        let ffmpeg = try exportTool()
        let input = try source(seconds: 2, ffmpeg: ffmpeg)
        let bundled = ffmpeg.deletingLastPathComponent().appendingPathComponent("gifsicle")
        guard FileManager.default.isExecutableFile(atPath: bundled.path) else {
            throw XCTSkip("Rebuild the app bundle to include Gifsicle.")
        }
        func export(_ quality: ExportQuality, executable: URL = ffmpeg) async throws -> Int {
            let destination = folder.appendingPathComponent("\(quality.rawValue).gif")
            try await ExportService.export(input: input, destination: destination,
                options: ExportOptions(format: .gif, start: 0, end: 2, width: 320, fps: 15, muted: true, quality: quality),
                executable: executable)
            return try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        }
        let best = try await export(.best)
        let balanced = try await export(.balanced)
        XCTAssertGreaterThan(balanced, 1000)
        XCTAssertLessThan(balanced, best)
        XCTAssertEqual(try hiddenFiles(), [])

        // FFmpeg alone, with no Gifsicle beside it, cannot make a lossy GIF.
        let alone = folder.appendingPathComponent("tools", isDirectory: true)
        try FileManager.default.createDirectory(at: alone, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alone.appendingPathComponent("ffmpeg"), withDestinationURL: ffmpeg)
        do { _ = try await export(.smaller, executable: alone.appendingPathComponent("ffmpeg")); XCTFail("Gifsicle is missing") }
        catch { XCTAssertTrue("\(error)".contains("missing"), "\(error)") }
        let lossless = try await export(.best, executable: alone.appendingPathComponent("ffmpeg"))
        XCTAssertGreaterThan(lossless, 1000)
    }

    @MainActor func testEditorEstimateAppearsAfterLoadingAndTracksSettings() async throws {
        let ffmpeg = try exportTool()
        let input = try source(seconds: 1, ffmpeg: ffmpeg)
        let hardware = ExportPreferences.hardware
        defer { ExportPreferences.hardware = hardware }
        let model = EditorStore(url: input)
        model.hardware = false
        await model.load()
        XCTAssertTrue(model.loaded)
        XCTAssertNil(model.error)
        await model.estimateSize(executable: ffmpeg)
        XCTAssertGreaterThan(try XCTUnwrap(model.estimatedBytes), 1000)
        XCTAssertFalse(model.estimating)

        model.exporting = true
        XCTAssertNil(model.estimatedBytes)
        await model.estimateSize(executable: ffmpeg)
        XCTAssertFalse(model.estimating)
        model.exporting = false
        let previous = model.estimatedBytes
        await model.estimateSize(executable: nil)
        XCTAssertEqual(model.estimatedBytes, previous, "Reuse the completed estimate after exporting")

        model.setExportWidth(160)
        XCTAssertNil(model.estimatedBytes, "Hide the stale size as soon as settings change")
        await model.estimateSize(executable: ffmpeg)
        XCTAssertGreaterThan(try XCTUnwrap(model.estimatedBytes), 1000)
    }

    @MainActor func testCancelledEstimateResetsStateAndCanRestart() async throws {
        let ffmpeg = try exportTool()
        let input = try source(seconds: 1, ffmpeg: ffmpeg)
        let hardware = ExportPreferences.hardware
        defer { ExportPreferences.hardware = hardware }
        let model = EditorStore(url: input)
        model.hardware = false
        await model.load()
        let task = Task { await model.estimateSize(executable: ffmpeg) }
        await Task.yield()
        XCTAssertTrue(model.estimating)
        task.cancel()
        await task.value
        XCTAssertFalse(model.estimating)
        XCTAssertNil(model.estimatedBytes)
        await model.estimateSize(executable: ffmpeg)
        XCTAssertGreaterThan(try XCTUnwrap(model.estimatedBytes), 1000)
    }

    private func hiddenFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix(".KapKap-") }
    }

    private func source(seconds: Int, ffmpeg: URL) throws -> URL {
        let input = folder.appendingPathComponent("source.mp4")
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=30",
                             "-t", String(seconds), "-c:v", "libx264", "-preset", "ultrafast", input.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return input
    }

    private func exportTool() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let ffmpeg = ProcessInfo.processInfo.environment["KAPKAP_FFMPEG"].map(URL.init(fileURLWithPath:))
            ?? root.appendingPathComponent("dist/KapKap.app/Contents/Resources/ffmpeg")
        guard FileManager.default.isExecutableFile(atPath: ffmpeg.path) else {
            if ProcessInfo.processInfo.environment["KAPKAP_REQUIRE_EXPORT_TOOLS"] == "1" {
                throw NSError(domain: "KapKap.ExportTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bundled FFmpeg is missing."])
            }
            throw XCTSkip("Build the app bundle before running export integration tests.")
        }
        return ffmpeg
    }
}

private final class Progress: @unchecked Sendable {
    private let lock = NSLock()
    private var highest = 0.0
    var maximum: Double { lock.lock(); defer { lock.unlock() }; return highest }
    func record(_ value: Double) { lock.lock(); highest = max(highest, value); lock.unlock() }
}
