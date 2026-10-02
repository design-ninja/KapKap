import Foundation
import CaptureCore

enum ExportService {
    static var executable: URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources.appendingPathComponent("ffmpeg")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// `progress` receives the finished share, 0 to 1, from the encoder's own progress report. A GIF is
    /// then shrunk by the Gifsicle bundled next to `executable`, which takes the last part of the bar.
    static func export(input: URL, destination: URL, options: ExportOptions, executable: URL? = executable,
                       progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let folder = destination.deletingLastPathComponent()
        let working = folder.appendingPathComponent(".KapKap-\(UUID().uuidString).\(options.format.fileExtension)")
        let compressed = folder.appendingPathComponent(".KapKap-\(UUID().uuidString).\(options.format.fileExtension)")
        defer {
            try? FileManager.default.removeItem(at: working)
            try? FileManager.default.removeItem(at: compressed)
        }
        let missing = CaptureError.message("The ARM export tools are missing from this build. Rebuild using script/build_and_run.sh.")
        guard let executable else { throw missing }
        let arguments = try ["-progress", "pipe:1", "-nostats"] + options.arguments(input: input, output: working)
        let compression = options.compressionArguments(input: working, output: compressed)
        let gifsicle = executable.deletingLastPathComponent().appendingPathComponent("gifsicle")
        if compression != nil, !FileManager.default.isExecutableFile(atPath: gifsicle.path) { throw missing }
        // Gifsicle reports no progress and takes about a quarter of a GIF export.
        let encodingShare = compression == nil ? 1.0 : 0.75
        let process = ExportProcess()
        let length = options.end - options.start
        try await withTaskCancellationHandler {
            try await process.run(executable: executable, arguments: arguments) { seconds in
                progress?(min(1, max(0, seconds / length)) * encodingShare)
            }
            if let compression {
                try await process.run(executable: gifsicle, arguments: compression) { _ in }
                progress?(1)
            }
        } onCancel: { process.cancel() }
        try Task.checkCancellation()
        let result = compression == nil ? working : compressed
        var saved = destination
        if FileManager.default.fileExists(atPath: destination.path) {
            saved = try FileManager.default.replaceItemAt(destination, withItemAt: result) ?? destination
        } else { try FileManager.default.moveItem(at: result, to: destination) }
        // iCloud Drive flags dot-files as hidden and the flag survives the rename, which left exports
        // to an iCloud Desktop greyed out in Finder and missing from the Desktop itself.
        var visible = URLResourceValues()
        visible.isHidden = false
        try saved.setResourceValues(visible)
    }
}

private final class ExportProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }

    /// `encoded` receives how many seconds of output are done, read from `-progress pipe:1`.
    func run(executable: URL, arguments: [String], encoded: @escaping @Sendable (Double) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = executable
                    process.arguments = arguments
                    process.standardInput = FileHandle.nullDevice
                    let report = Pipe()
                    process.standardOutput = report
                    report.fileHandleForReading.readabilityHandler = { handle in
                        let chunk = String(decoding: handle.availableData, as: UTF8.self)
                        for line in chunk.split(separator: "\n") where line.hasPrefix("out_time_us=") {
                            if let micros = Double(line.dropFirst("out_time_us=".count)) { encoded(micros / 1_000_000) }
                        }
                    }
                    defer { report.fileHandleForReading.readabilityHandler = nil }
                    let errors = Pipe()
                    process.standardError = errors
                    self.lock.lock()
                    if self.cancelled { self.lock.unlock(); throw CancellationError() }
                    self.process = process
                    do { try process.run() } catch { self.lock.unlock(); throw error }
                    self.lock.unlock()
                    let data = errors.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    self.lock.lock()
                    let cancelled = self.cancelled
                    self.process = nil
                    self.lock.unlock()
                    if cancelled { throw CancellationError() }
                    guard process.terminationStatus == 0 else {
                        let message = String(data: data.suffix(6000), encoding: .utf8) ?? "Unknown encoder error"
                        throw CaptureError.message("Export failed (\(process.terminationStatus)).\n\(message)")
                    }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
