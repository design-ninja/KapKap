import XCTest
@testable import CaptureCore

final class ExportTests: XCTestCase {
    func testRejectsInvalidRanges() {
        let url = URL(fileURLWithPath: "/tmp/unused.mp4")
        for (start, end) in [(2.0, 1.0), (-1.0, 1.0), (.nan, 1.0), (0.0, .infinity)] {
            XCTAssertThrowsError(try ExportOptions(format: .mp4, start: start, end: end, width: 100, fps: 30, muted: false).arguments(input: url, output: url))
        }
    }

    func testTimesNeverUseExponentNotation() throws {
        let url = URL(fileURLWithPath: "/tmp/unused.mp4")
        // Three nudges forward and three back leave a trim handle at 2.8e-17, not at zero.
        let start = 0.1 + 0.1 + 0.1 - 0.1 - 0.1 - 0.1
        XCTAssertTrue(String(start).contains("e-"))
        let arguments = try ExportOptions(format: .mp4, start: start, end: 1, width: 100, fps: 30, muted: true)
            .arguments(input: url, output: url)
        XCTAssertFalse(arguments.contains { $0.contains("e-") }, "\(arguments)")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "-ss")! + 1], "0.000000")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "-t")! + 1], "1.000000")
    }

    func testHardwareEncodingUsesTheMediaEngineOnlyForMP4AndHEVC() throws {
        let url = URL(fileURLWithPath: "/tmp/unused.mp4")
        func encoder(_ format: ExportFormat, hardware: Bool) throws -> String {
            let arguments = try ExportOptions(format: format, start: 0, end: 1, width: 100, fps: 30, muted: true, hardware: hardware)
                .arguments(input: url, output: url)
            return arguments.firstIndex(of: "-c:v").map { arguments[$0 + 1] } ?? "none"
        }
        XCTAssertEqual(try encoder(.mp4, hardware: true), "h264_videotoolbox")
        XCTAssertEqual(try encoder(.hevc, hardware: true), "hevc_videotoolbox")
        XCTAssertEqual(try encoder(.mp4, hardware: false), "libx264")
        XCTAssertEqual(try encoder(.hevc, hardware: false), "libx265")
        XCTAssertEqual(try encoder(.webm, hardware: true), "libvpx-vp9")
        XCTAssertEqual(try encoder(.av1, hardware: true), "libsvtav1")
    }

    func testRecordingQualityBitRates() {
        // Standard keeps the previous formula, but 4K at 60 fps is no longer cut to 80 Mbps.
        XCTAssertEqual(RecordingQuality.standard.bitRate(width: 1920, height: 1080, fps: 60), 24_883_200)
        XCTAssertEqual(RecordingQuality.standard.bitRate(width: 3840, height: 2160, fps: 60), 99_532_800)
        XCTAssertEqual(RecordingQuality.high.bitRate(width: 1920, height: 1080, fps: 60), 49_766_400)
        XCTAssertEqual(RecordingQuality.high.bitRate(width: 3840, height: 2160, fps: 60), 199_065_600)
        XCTAssertEqual(RecordingQuality.standard.bitRate(width: 160, height: 120, fps: 30), 2_000_000)
        XCTAssertEqual(RecordingQuality.high.bitRate(width: 160, height: 120, fps: 30), 4_000_000)
        XCTAssertEqual(RecordingQuality.standard.bitRate(width: 6016, height: 3384, fps: 60), 100_000_000)
        XCTAssertEqual(RecordingQuality.high.bitRate(width: 6016, height: 3384, fps: 60), 200_000_000)
    }

    func testSmallerQualityMakesSmallerVideoFiles() throws {
        let ffmpeg = try bundledFFmpeg()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KapKap-quality-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("source.mp4")
        _ = try run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=30",
                             "-t", "1", "-c:v", "libx264", "-crf", "0", input.path])
        let encoders = ExportFormat.allCases.filter { $0 != .gif && $0 != .apng }.map { ($0, false) }
            + ExportFormat.allCases.filter(\.offersHardwareEncoding).map { ($0, true) }
        for (format, hardware) in encoders {
            let name = "\(format)\(hardware ? " (hardware)" : "")"
            let sizes = try ExportQuality.allCases.map { quality -> Int in
                let output = directory.appendingPathComponent("\(format.rawValue)-\(hardware)-\(quality.rawValue).\(format.fileExtension)")
                let options = ExportOptions(format: format, start: 0, end: 1, width: 320, fps: 30, muted: true,
                                            quality: quality, hardware: hardware)
                _ = try run(ffmpeg, options.arguments(input: input, output: output))
                return try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            }
            XCTAssertLessThan(sizes[0], sizes[1], "\(name): Smaller is not smaller than Balanced")
            XCTAssertLessThan(sizes[1], sizes[2], "\(name): Balanced is not smaller than Best")
        }
    }

    func testEveryFormatEncodesAndDecodesWithBundledARMTools() throws {
        let ffmpeg = try bundledFFmpeg()
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
        for format in ExportFormat.allCases where format.offersHardwareEncoding {
            let output = directory.appendingPathComponent("hardware-\(format.rawValue).\(format.fileExtension)")
            let options = ExportOptions(format: format, start: 0.2, end: 1.0, width: 160, fps: 15, muted: false, hardware: true)
            _ = try run(ffmpeg, options.arguments(input: input, output: output))
            let probe = try run(ffmpeg, ["-hide_banner", "-i", output.path, "-t", "1", "-f", "null", "-"])
            XCTAssertTrue(probe.contains(format == .hevc ? "Video: hevc" : "Video: h264"), "\(format) (hardware): wrong codec\n\(probe)")
            XCTAssertTrue(probe.contains("160x120"), "\(format) (hardware): unexpected dimensions\n\(probe)")
            XCTAssertTrue(probe.contains("Audio:"), "\(format) (hardware): missing audio")
            XCTAssertTrue(probe.contains("00:00:00.80") || probe.contains("00:00:00.81"), "\(format) (hardware): unexpected trimmed duration\n\(probe)")
        }
    }

    /// The point of hardware encoding: x265 took two minutes for a half-minute game clip. A full-HD
    /// clip at 60 fps must encode clearly faster on the media engine. x264 is already fast on a test
    /// pattern this easy, so H.264 only gains on busy footage (docs/export-quality.md).
    func testHardwareHEVCIsFasterThanX265() throws {
        let ffmpeg = try bundledFFmpeg()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KapKap-speed-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("source.mp4")
        _ = try run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=60",
                             "-t", "4", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "10", input.path])
        func seconds(hardware: Bool) throws -> Double {
            let output = directory.appendingPathComponent("hevc-\(hardware).mp4")
            let options = ExportOptions(format: .hevc, start: 0, end: 4, width: 1920, fps: 60, muted: true, hardware: hardware)
            let started = Date()
            _ = try run(ffmpeg, options.arguments(input: input, output: output))
            return Date().timeIntervalSince(started)
        }
        let software = try seconds(hardware: false)
        let hardware = try seconds(hardware: true)
        XCTAssertLessThan(hardware * 1.5, software, "x265 \(software) s, VideoToolbox \(hardware) s")
    }

    func testLoopSettingControlsGIFAndAPNGPlayback() throws {
        let ffmpeg = try bundledFFmpeg()
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
        let ffmpeg = try bundledFFmpeg()
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

/// The FFmpeg bundled by script/build_and_run.sh, or the one KAPKAP_FFMPEG names. Set
/// KAPKAP_REQUIRE_EXPORT_TOOLS=1 to fail instead of skip when it is missing, so a green run cannot
/// hide untested exports.
func bundledFFmpeg() throws -> URL {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let ffmpeg = ProcessInfo.processInfo.environment["KAPKAP_FFMPEG"].map(URL.init(fileURLWithPath:))
        ?? root.appendingPathComponent("dist/KapKap.app/Contents/Resources/ffmpeg")
    guard FileManager.default.isExecutableFile(atPath: ffmpeg.path) else {
        let message = "Build the app bundle (script/build_and_run.sh --build-only) before running export integration tests."
        if ProcessInfo.processInfo.environment["KAPKAP_REQUIRE_EXPORT_TOOLS"] == "1" {
            throw NSError(domain: "KapKap.ExportTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        throw XCTSkip(message)
    }
    return ffmpeg
}
