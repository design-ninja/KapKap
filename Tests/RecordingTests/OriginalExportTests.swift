import XCTest
import CaptureCore
@testable import KapKap

final class OriginalExportTests: XCTestCase {
    func testOriginalExportPreservesBytesAndReplacesDestination() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("original.mp4")
        let output = folder.appendingPathComponent("export.mp4")
        let bytes = Data((0..<65536).map { UInt8($0 % 251) })
        try bytes.write(to: input)
        try Data("old destination".utf8).write(to: output)
        let options = ExportOptions(format: .mp4, start: 0, end: 1, width: 100, fps: 30, muted: false)
        try await ExportService.export(input: input, destination: output, options: options, preserveOriginal: true)
        XCTAssertEqual(try Data(contentsOf: output), bytes)
        XCTAssertEqual(try Data(contentsOf: input), bytes)
    }
}
