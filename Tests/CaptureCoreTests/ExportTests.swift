import XCTest
@testable import CaptureCore

final class ExportTests: XCTestCase {
    func testRejectsInvalidRanges() {
        let url = URL(fileURLWithPath: "/tmp/unused.mp4")
        for (start, end) in [(2.0, 1.0), (-1.0, 1.0), (.nan, 1.0), (0.0, .infinity)] {
            XCTAssertThrowsError(try ExportOptions(format: .mp4, start: start, end: end, width: 100, fps: 30, muted: false).arguments(input: url, output: url))
        }
    }

    func testEveryFormatEncodesAndDecodesWithBundledARMTools() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let ffmpeg = root.appendingPathComponent("dist/KapKap.app/Contents/Resources/ffmpeg")
        guard FileManager.default.isExecutableFile(atPath: ffmpeg.path) else { throw XCTSkip("Build the app bundle before running export integration tests.") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KapKap-export-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("source.mp4")
        _ = try run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=30",
                             "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "1.5", "-c:v", "libx264", "-c:a", "aac", input.path])
        for format in ExportFormat.allCases {
            let output = directory.appendingPathComponent("export-\(format.rawValue).\(format.fileExtension)")
            let options = ExportOptions(format: format, start: 0.2, end: 1.0, width: 160, fps: 15, muted: false)
            _ = try run(ffmpeg, options.arguments(input: input, output: output))
            let probe = try run(ffmpeg, ["-hide_banner", "-i", output.path, "-t", "1", "-f", "null", "-"])
            XCTAssertTrue(probe.contains("160x120"), "\(format): unexpected dimensions\n\(probe)")
            XCTAssertTrue(probe.contains("Video:"), "\(format): no decodable video")
            if format != .gif && format != .apng {
                XCTAssertTrue(probe.contains("Audio:"), "\(format): missing audio")
                XCTAssertTrue(probe.contains("00:00:00.80") || probe.contains("00:00:00.81"), "\(format): unexpected trimmed duration\n\(probe)")
            }
        }
    }

    func testLoopSettingControlsGIFAndAPNGPlayback() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let ffmpeg = root.appendingPathComponent("dist/KapKap.app/Contents/Resources/ffmpeg")
        guard FileManager.default.isExecutableFile(atPath: ffmpeg.path) else { throw XCTSkip("Build the app bundle before running export integration tests.") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KapKap-loop-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("source.mp4")
        _ = try run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=160x120:rate=15",
                             "-t", "0.5", "-c:v", "libx264", input.path])
        func export(_ format: ExportFormat, loop: Bool) throws -> Data {
            let output = directory.appendingPathComponent("\(format.rawValue)-\(loop).\(format.fileExtension)")
            let options = ExportOptions(format: format, start: 0, end: 0.5, width: 80, fps: 10, muted: true, loop: loop)
            _ = try run(ffmpeg, options.arguments(input: input, output: output))
            return try Data(contentsOf: output)
        }
        // A GIF loops only if it carries the Netscape application extension.
        let netscape = Data("NETSCAPE2.0".utf8)
        XCTAssertNotNil(try export(.gif, loop: true).range(of: netscape))
        XCTAssertNil(try export(.gif, loop: false).range(of: netscape))
        // APNG stores its play count after the frame count in acTL; 0 means forever.
        func plays(_ data: Data) throws -> UInt32 {
            let chunk = try XCTUnwrap(data.range(of: Data("acTL".utf8)))
            return data[(chunk.upperBound + 4)..<(chunk.upperBound + 8)].reduce(0) { $0 << 8 | UInt32($1) }
        }
        XCTAssertEqual(try plays(export(.apng, loop: true)), 0)
        XCTAssertEqual(try plays(export(.apng, loop: false)), 1)
    }

    func testTwoAudioTracksAreMixedIntoOne() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let ffmpeg = root.appendingPathComponent("dist/KapKap.app/Contents/Resources/ffmpeg")
        guard FileManager.default.isExecutableFile(atPath: ffmpeg.path) else { throw XCTSkip("Build the app bundle before running export integration tests.") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KapKap-mix-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Like a recording with a microphone track (mono) and a system audio track (stereo).
        let input = directory.appendingPathComponent("source.mp4")
        _ = try run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=30",
                             "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
                             "-f", "lavfi", "-i", "sine=frequency=880:sample_rate=48000",
                             "-map", "0:v", "-map", "1:a", "-map", "2:a", "-ac:a:1", "2",
                             "-t", "1.5", "-c:v", "libx264", "-c:a", "aac", input.path])
        for format in [ExportFormat.mp4, .webm] {
            let output = directory.appendingPathComponent("mixed.\(format.fileExtension)")
            let options = ExportOptions(format: format, start: 0.2, end: 1.0, width: 160, fps: 15, muted: false, audioTracks: 2)
            _ = try run(ffmpeg, options.arguments(input: input, output: output))
            let probe = try run(ffmpeg, ["-hide_banner", "-i", output.path, "-f", "null", "-"])
            XCTAssertEqual(probe.components(separatedBy: "Audio:").count - 1, 2, "\(format): expected one audio stream in and one out\n\(probe)")
            XCTAssertTrue(probe.contains("160x120"), "\(format): video lost while mixing audio\n\(probe)")
            // Both tones must survive the mix: 440 Hz from the first track and 880 Hz from the second.
            for tone in [440, 880] {
                let band = try run(ffmpeg, ["-hide_banner", "-i", output.path, "-af",
                    "bandpass=f=\(tone):width_type=q:width=8,volumedetect", "-f", "null", "-"])
                let level = band.components(separatedBy: "mean_volume: ").last.flatMap { Double($0.prefix { "-.0123456789".contains($0) }) }
                XCTAssertGreaterThan(try XCTUnwrap(level, band), -40, "\(format): \(tone) Hz missing from the mix")
            }
        }
    }

    private func run(_ executable: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "KapKap.ExportTest", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: text])
        }
        return text
    }
}
