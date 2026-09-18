import Foundation
import CaptureCore

enum ExportService {
    static var executable: URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources.appendingPathComponent("ffmpeg")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static func export(input: URL, destination: URL, options: ExportOptions, preserveOriginal: Bool = false) async throws {
        let working = destination.deletingLastPathComponent().appendingPathComponent(".KapKap-\(UUID().uuidString).\(options.format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: working) }
        if preserveOriginal {
            try Task.checkCancellation()
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.copyItem(at: input, to: working)
            }.value
        } else {
            guard let executable else {
                throw CaptureError.message("The ARM export tools are missing from this build. Rebuild using script/build_and_run.sh.")
            }
            let arguments = try options.arguments(input: input, output: working)
            let process = ExportProcess()
            try await withTaskCancellationHandler {
                try await process.run(executable: executable, arguments: arguments)
            } onCancel: { process.cancel() }
        }
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: working)
        } else { try FileManager.default.moveItem(at: working, to: destination) }
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

    func run(executable: URL, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = executable
                    process.arguments = arguments
                    process.standardInput = FileHandle.nullDevice
                    process.standardOutput = FileHandle.nullDevice
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
