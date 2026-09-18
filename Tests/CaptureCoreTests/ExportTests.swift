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
